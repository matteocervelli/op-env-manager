#!/usr/bin/env bash
# Convert .env files with op:// references to op-env-manager format
# Part of op-env-manager by Matteo Cervelli

set -eo pipefail

# Get script directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/logger.sh"
source "$LIB_DIR/error_helpers.sh"
source "$LIB_DIR/retry.sh"

# Global variables
ENV_FILE=""
VAULT=""
ITEM_NAME=""
SECTION=""
DRY_RUN=false
SAVE_TEMPLATE=false
TEMPLATE_OUTPUT=".env.op"

# Performance optimization: Item metadata cache (command-scoped)
declare -A ITEM_CACHE

# Show usage
usage() {
    cat << EOF
Usage: op-env-manager convert [options]

Convert .env files with op:// secret references to op-env-manager format.
This command reads a .env file containing 1Password secret references (op://...),
resolves those references to actual values, and pushes them to a new 1Password
item using op-env-manager's naming convention.

Options:
    --env-file=FILE        Path to .env file with op:// references (required)
    --vault=VAULT          Target 1Password vault name (required)
    --item=NAME            Target item name prefix (default: env-secrets)
    --section=SECTION      Environment section (e.g., dev, prod, staging)
    --template             Also generate .env.op template file with op:// references
    --template-output=FILE Output path for template file (default: .env.op)
    --dry-run              Preview what would be converted without actually pushing

Examples:
    # Convert legacy .env.template to op-env-manager format
    op-env-manager convert \\
      --env-file=.env.production.template \\
      --vault="app-cna-crm" \\
      --item="cna-crm"

    # Convert with section organization
    op-env-manager convert \\
      --env-file=.env.template \\
      --vault="Personal" \\
      --item="myapp" \\
      --section="prod"

    # Preview conversion without making changes
    op-env-manager convert \\
      --env-file=.env.template \\
      --vault="Personal" \\
      --dry-run

    # Convert and generate template file
    op-env-manager convert \\
      --env-file=.env.legacy \\
      --vault="Personal" \\
      --template

Notes:
    - Resolves op:// references using 'op read' command
    - Creates a single Secure Note item with all variables
    - Preserves variable names exactly as they appear in source file
    - Comments and empty lines are ignored
    - Non-secret lines (without op://) are included as-is
    - Useful for migrating from 'op run' workflow to op-env-manager

Workflow:
    1. Parse .env file line by line
    2. Detect op:// secret references
    3. Resolve references using 'op read'
    4. Push resolved values to new item structure
    5. No temporary plaintext files created

Secret Reference Format:
    Source format:  VAR_NAME=op://vault/item/field
    Resolves to:    VAR_NAME=actual_secret_value
    Stored as:      item-prefix (Secure Note with VAR_NAME field)

EOF
    exit 1
}

# Check if 1Password CLI is installed and authenticated
check_op_cli() {
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry-run mode: skipping 1Password authentication check"
        return 0
    fi

    # Use centralized diagnostics from error_helpers
    if ! diagnose_op_cli; then
        exit 1
    fi

    log_success "1Password CLI authenticated"
}

# Check if item exists with caching (optimization)
# Cache key format: "vault:item"
check_item_exists_cached() {
    local vault="$1"
    local item="$2"
    local cache_key="${vault}:${item}"

    # Check cache first
    if [ -n "${ITEM_CACHE[$cache_key]:-}" ]; then
        return "${ITEM_CACHE[$cache_key]}"
    fi

    # Not in cache, check with 1Password
    if retry_with_backoff "check if item exists" op item get "$item" --vault "$vault" &> /dev/null; then
        ITEM_CACHE[$cache_key]=0
        return 0
    else
        ITEM_CACHE[$cache_key]=1
        return 1
    fi
}

# Detect if a value contains op:// reference
has_op_reference() {
    local value="$1"
    if [[ "$value" =~ op:// ]]; then
        return 0
    else
        return 1
    fi
}

# Extract op:// reference from value
# Handles item names with spaces by matching until @ or end of line
extract_op_reference() {
    local value="$1"

    # op:// reference format: op://vault/item-name/field
    # Item names can contain spaces, so we need smart detection

    # Strategy: Look for the pattern and find where it ends
    # It ends at: @ (in URLs), end of string, or start of another protocol

    # Case 1: Reference embedded in URL before @ (most common)
    # Example: postgresql://user:op://vault/item name/field@host
    # Match everything from op:// until @
    if [[ "$value" =~ op://([^@]+)@ ]]; then
        # Extract the full reference including the op:// prefix
        local full_match="${BASH_REMATCH[0]}"
        # Remove the trailing @
        echo "${full_match%@}"
        return 0
    fi

    # Case 2: Reference is the entire value or standalone
    # Example: API_KEY=op://vault/item name/field
    # Match from op:// to end of string (allowing spaces)
    if [[ "$value" =~ op://(.+)$ ]]; then
        echo "op://${BASH_REMATCH[1]}"
        return 0
    fi

    # Case 3: Fallback - shouldn't reach here
    if [[ "$value" =~ (op://[^[:space:]]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
}

# Resolve op:// reference to actual value
resolve_op_reference() {
    local ref="$1"
    local value

    if [ "$DRY_RUN" = true ]; then
        echo "[RESOLVED:$ref]"
        return 0
    fi

    # Show progress (helps debug slow operations)
    log_info "Resolving: $ref" >&2

    # Use op read to resolve the reference (with retry for network errors)
    value=$(retry_with_backoff "resolve secret reference" op read "$ref" 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Failed to resolve reference: $ref" >&2
        echo "" >&2
        echo "$value" >&2

        # Check for common errors
        if echo "$value" | grep -qi "not found\|no item"; then
            echo "" >&2
            log_troubleshoot "The reference might be incorrect"
            suggest_op_reference_format
        elif echo "$value" | grep -qi "network\|timeout\|connection"; then
            suggest_network_check
        else
            echo "" >&2
            log_suggestion "Test the reference manually:"
            log_command "op read \"$ref\""
            echo "" >&2
        fi
        return 1
    fi

    echo "$value"
}

# Bulk resolve op:// references in parallel (optimization)
# Input: List of "key|op_ref" pairs (one per line)
# Output: List of "key|resolved_value" pairs
bulk_resolve_op_references() {
    local refs_input="$1"  # Format: "key|op_ref" per line

    if [ -z "$refs_input" ]; then
        return 0
    fi

    # Count references for progress
    local ref_count=$(echo "$refs_input" | wc -l | tr -d ' ')

    if [ "$DRY_RUN" = true ]; then
        # In dry-run, just echo mock resolutions
        while IFS='|' read -r key ref; do
            echo "$key|[RESOLVED:$ref]"
        done <<< "$refs_input"
        return 0
    fi

    log_info "Resolving $ref_count op:// references in parallel..." >&2

    # Create temporary directory for parallel results
    local temp_dir=$(mktemp -d)
    trap 'rm -rf "$temp_dir"' EXIT

    # Start parallel resolution jobs
    local pids=()
    local job_id=0

    while IFS='|' read -r key ref; do
        {
            local result_file="$temp_dir/result_${job_id}"
            local value
            value=$(retry_with_backoff "resolve secret reference" op read "$ref" 2>&1)
            if [ $? -eq 0 ]; then
                echo "$key|$value" > "$result_file"
            else
                echo "$key|ERROR:$value" > "$result_file"
            fi
        } &
        pids+=($!)
        job_id=$((job_id + 1))
    done <<< "$refs_input"

    # Wait for all parallel jobs
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # Collect results
    for result_file in "$temp_dir"/result_*; do
        if [ -f "$result_file" ]; then
            cat "$result_file"
        fi
    done
}

# Parse .env file and resolve op:// references (optimized with bulk resolution)
parse_and_resolve_env_file() {
    local env_file="$1"

    if [ ! -f "$env_file" ]; then
        log_error "Environment file not found: $env_file"
        suggest_file_check "$env_file"
        exit 1
    fi

    # First pass: Collect all op:// references and non-secret variables
    declare -A var_map          # All variables (key -> original_value)
    declare -A ref_map          # Variables with op:// refs (key -> op_ref)
    declare -A embedded_map     # Track if op:// is embedded in value (key -> original_value)
    local refs_to_resolve=""    # Bulk resolution input

    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
            continue
        fi

        # Parse KEY=VALUE
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"

            # Trim whitespace
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)

            # Remove surrounding quotes from value
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"

            if [ -n "$key" ]; then
                var_map["$key"]="$value"

                # Check if value contains op:// reference
                if has_op_reference "$value"; then
                    local op_ref
                    op_ref=$(extract_op_reference "$value")

                    if [ -n "$op_ref" ]; then
                        ref_map["$key"]="$op_ref"
                        embedded_map["$key"]="$value"
                        refs_to_resolve+="$key|$op_ref"$'\n'
                    fi
                fi
            fi
        fi
    done < "$env_file"

    # Second pass: Bulk resolve all op:// references in parallel
    declare -A resolved_map  # Resolved values (key -> resolved_value)
    local resolution_results=""

    if [ -n "$refs_to_resolve" ]; then
        resolution_results=$(bulk_resolve_op_references "$refs_to_resolve")

        # Parse resolution results
        while IFS='|' read -r key resolved_value; do
            if [ -n "$key" ]; then
                if [[ "$resolved_value" == ERROR:* ]]; then
                    log_warning "Skipping $key due to resolution failure: ${resolved_value#ERROR:}" >&2
                else
                    resolved_map["$key"]="$resolved_value"
                fi
            fi
        done <<< "$resolution_results"
    fi

    # Third pass: Output final variables
    for key in "${!var_map[@]}"; do
        if [ -n "${ref_map[$key]:-}" ]; then
            # Variable has op:// reference
            if [ -n "${resolved_map[$key]:-}" ]; then
                local original_value="${embedded_map[$key]}"
                local op_ref="${ref_map[$key]}"
                local resolved_value="${resolved_map[$key]}"

                # Replace op:// reference with resolved value
                local final_value="${original_value/$op_ref/$resolved_value}"
                echo "$key=$final_value"
            fi
            # If not resolved, skip (already warned in resolution phase)
        else
            # No op:// reference, output as-is
            echo "$key=${var_map[$key]}"
        fi
    done
}

# Convert and push to 1Password
convert_to_1password() {
    log_header "Converting Environment Variables to op-env-manager Format"
    echo ""

    if [ -z "$ENV_FILE" ]; then
        log_error "--env-file is required"
        echo "" >&2
        log_suggestion "Specify the .env file to convert:"
        log_command "op-env-manager convert --env-file=\".env.template\" --vault=\"VaultName\""
        echo "" >&2
        usage
    fi

    if [ -z "$VAULT" ]; then
        log_error "--vault is required"
        echo "" >&2
        log_suggestion "Specify target vault name:"
        log_command "op-env-manager convert --env-file=\"$ENV_FILE\" --vault=\"VaultName\""
        echo "" >&2
        suggest_vault_list
        usage
    fi

    if [ -z "$ITEM_NAME" ]; then
        ITEM_NAME="env-secrets"
        log_info "Using default item name prefix: $ITEM_NAME"
    fi

    check_op_cli

    log_step "Parsing and resolving: $ENV_FILE"
    local resolved_vars
    resolved_vars=$(parse_and_resolve_env_file "$ENV_FILE")

    if [ -z "$resolved_vars" ]; then
        log_error "No variables found or resolved in $ENV_FILE"
        echo "" >&2
        log_suggestion "Check your .env file:"
        log_command "cat \"$ENV_FILE\""
        echo "" >&2
        log_troubleshoot "Common issues:"
        echo "    1. File is empty or contains only comments" >&2
        echo "    2. All op:// references failed to resolve" >&2
        echo "    3. Variables don't follow KEY=value format" >&2
        echo "" >&2
        log_info "Example .env format for convert:"
        log_command "API_KEY=op://Personal/myapp-API_KEY/password"
        log_command "DATABASE_URL=postgresql://user:op://Personal/myapp-DB_PASS/password@host/db"
        exit 1
    fi

    local count=0
    local op_ref_count=0
    local item_title="$ITEM_NAME"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create/update item: $item_title"
        if [ -n "$SECTION" ]; then
            log_info "[DRY RUN] Section: $SECTION"
        fi
        echo ""

        while IFS= read -r line || [ -n "$line" ]; do
            # Skip empty lines
            [ -z "$line" ] && continue

            # Parse KEY=VALUE
            if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"

                if [ -n "$key" ]; then
                    if [ -n "$SECTION" ]; then
                        log_info "[DRY RUN] Would set: $SECTION.$key = ${value:0:20}..."
                    else
                        log_info "[DRY RUN] Would set: $key = ${value:0:20}..."
                    fi
                    if [[ "$value" == *"[RESOLVED:"* ]]; then
                        op_ref_count=$((op_ref_count + 1))
                    fi
                    count=$((count + 1))
                fi
            fi
        done <<< "$resolved_vars"
    else
        # Check if item exists (using cache for performance)
        local item_exists=false
        if check_item_exists_cached "$VAULT" "$item_title"; then
            item_exists=true
            log_info "Updating existing item: $item_title"
        else
            log_info "Creating new item: $item_title"
        fi
        echo ""

        # Build field assignments as a temporary file
        local temp_fields
        temp_fields=$(mktemp)
        trap 'rm -f "$temp_fields"' EXIT

        while IFS= read -r line; do
            # Skip empty lines
            [ -z "$line" ] && continue

            # Parse KEY=VALUE
            if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
                local key="${BASH_REMATCH[1]}"
                local value="${BASH_REMATCH[2]}"

                if [ -n "$key" ]; then
                    if [ -n "$SECTION" ]; then
                        echo "${SECTION}.${key}[password]=${value}" >> "$temp_fields"
                        log_success "Converted: $SECTION.$key"
                    else
                        echo "${key}[password]=${value}" >> "$temp_fields"
                        log_success "Converted: $key"
                    fi
                    count=$((count + 1))
                fi
            fi
        done <<< "$resolved_vars"

        # Read field assignments into array
        local field_args=()
        while IFS= read -r line; do
            field_args+=("$line")
        done < "$temp_fields"

        # Create or update the item with all fields
        local result
        if [ "$item_exists" = true ]; then
            # Update existing item
            result=$(retry_with_backoff "update item with fields" op item edit "$item_title" --vault "$VAULT" "${field_args[@]}" 2>&1)
            if [ $? -ne 0 ]; then
                echo ""
                log_error "Failed to update item in 1Password"
                echo "$result"
                exit 1
            fi
        else
            # Create new item
            log_info "Creating item..."
            result=$(retry_with_backoff "create new item" op item create --category="Secure Note" \
                --title="$item_title" \
                --vault="$VAULT" \
                --tags="op-env-manager" \
                "${field_args[0]}" < /dev/null 2>&1)
            if [ $? -ne 0 ]; then
                echo ""
                log_error "Failed to create item in 1Password"
                echo "$result"
                exit 1
            fi

            # Add remaining fields
            if [ ${#field_args[@]} -gt 1 ]; then
                log_info "Adding remaining fields..."
                local remaining_fields=("${field_args[@]:1}")
                result=$(retry_with_backoff "add remaining fields" op item edit "$item_title" --vault "$VAULT" "${remaining_fields[@]}" 2>&1)
                if [ $? -ne 0 ]; then
                    echo ""
                    log_error "Failed to add remaining fields to item"
                    echo "$result"
                    exit 1
                fi
            fi
        fi
    fi

    echo ""
    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN: No changes made. Remove --dry-run to convert for real."
        log_info "Would convert $count variables ($op_ref_count with op:// references)"
        if [ "$SAVE_TEMPLATE" = true ]; then
            log_info "Would also generate template file: $TEMPLATE_OUTPUT"
        fi
    else
        log_success "Successfully converted and pushed environment variables!"

        # Generate template file if requested
        if [ "$SAVE_TEMPLATE" = true ]; then
            echo ""
            log_step "Generating template file: $TEMPLATE_OUTPUT"

            # Source template generation functions
            source "$LIB_DIR/template.sh"

            # Collect field names from converted variables
            local field_names=()
            while IFS= read -r line; do
                # Skip empty lines
                [ -z "$line" ] && continue

                # Parse KEY=VALUE
                if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
                    local key="${BASH_REMATCH[1]}"
                    if [ -n "$key" ]; then
                        field_names+=("$key")
                    fi
                fi
            done <<< "$resolved_vars"

            # Generate template file
            generate_template_file "$VAULT" "$ITEM_NAME" "$SECTION" "$TEMPLATE_OUTPUT" "${field_names[@]}"
            log_success "Template file saved: $TEMPLATE_OUTPUT"
        fi

        echo ""
        log_info "To inject these back into your environment:"
        if [ -n "$SECTION" ]; then
            echo "  op-env-manager inject --vault=\"$VAULT\" --item=\"$ITEM_NAME\" --section=\"$SECTION\""
        else
            echo "  op-env-manager inject --vault=\"$VAULT\" --item=\"$ITEM_NAME\""
        fi

        if [ "$SAVE_TEMPLATE" = true ]; then
            echo ""
            log_info "Or use template file with op run:"
            if [ -n "$SECTION" ]; then
                echo "  export APP_ENV=\"$SECTION\""
            fi
            echo "  op run --env-file=$TEMPLATE_OUTPUT -- your-command"
        fi
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env-file=*)
                ENV_FILE="${1#*=}"
                shift
                ;;
            --env-file)
                ENV_FILE="$2"
                shift 2
                ;;
            --vault=*)
                VAULT="${1#*=}"
                shift
                ;;
            --vault)
                VAULT="$2"
                shift 2
                ;;
            --item=*)
                ITEM_NAME="${1#*=}"
                shift
                ;;
            --item)
                ITEM_NAME="$2"
                shift 2
                ;;
            --section=*)
                SECTION="${1#*=}"
                shift
                ;;
            --section)
                SECTION="$2"
                shift 2
                ;;
            --template)
                SAVE_TEMPLATE=true
                shift
                ;;
            --template-output=*)
                SAVE_TEMPLATE=true
                TEMPLATE_OUTPUT="${1#*=}"
                shift
                ;;
            --template-output)
                SAVE_TEMPLATE=true
                TEMPLATE_OUTPUT="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Main function
main() {
    parse_args "$@"
    convert_to_1password
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
