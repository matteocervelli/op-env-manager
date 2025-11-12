#!/usr/bin/env bash
# Convert .env files with op:// references to op-env-manager format
# Part of op-env-manager by Matteo Cervelli

set -eo pipefail

# Get script directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/logger.sh"

# Global variables
ENV_FILE=""
VAULT=""
ITEM_NAME=""
SECTION=""
DRY_RUN=false
SAVE_TEMPLATE=false
TEMPLATE_OUTPUT=".env.op"

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
    if ! command -v op &> /dev/null; then
        log_error "1Password CLI (op) is not installed"
        log_info "See installation guide: docs/1PASSWORD_SETUP.md"
        exit 1
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "Dry-run mode: skipping 1Password authentication check"
        return 0
    fi

    if ! op account list &> /dev/null; then
        log_error "Not signed in to 1Password CLI"
        log_info "Sign in with: op signin"
        exit 1
    fi

    log_success "1Password CLI authenticated"
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

    # Use op read to resolve the reference
    value=$(op read "$ref" 2>&1)
    local exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Failed to resolve reference: $ref" >&2
        echo "$value" >&2
        return 1
    fi

    echo "$value"
}

# Parse .env file and resolve op:// references
parse_and_resolve_env_file() {
    local env_file="$1"

    if [ ! -f "$env_file" ]; then
        log_error "Environment file not found: $env_file"
        exit 1
    fi

    # Parse .env file, ignore comments and empty lines
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
                # Check if value contains op:// reference
                if has_op_reference "$value"; then
                    local op_ref
                    op_ref=$(extract_op_reference "$value")

                    if [ -n "$op_ref" ]; then
                        # Resolve the reference
                        local resolved_value
                        resolved_value=$(resolve_op_reference "$op_ref")

                        if [ $? -eq 0 ]; then
                            # Replace the op:// reference with resolved value
                            # Handle cases where op:// is embedded in a larger string
                            value="${value/$op_ref/$resolved_value}"
                            echo "$key=$value"
                        else
                            log_warning "Skipping $key due to resolution failure"
                        fi
                    fi
                else
                    # No op:// reference, include as-is
                    echo "$key=$value"
                fi
            fi
        fi
    done < "$env_file"
}

# Convert and push to 1Password
convert_to_1password() {
    log_header "Converting Environment Variables to op-env-manager Format"
    echo ""

    if [ -z "$ENV_FILE" ]; then
        log_error "--env-file is required"
        usage
    fi

    if [ -z "$VAULT" ]; then
        log_error "--vault is required"
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
        # Check if item exists
        local item_exists=false
        if op item get "$item_title" --vault "$VAULT" &> /dev/null 2>&1; then
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
            result=$(op item edit "$item_title" --vault "$VAULT" "${field_args[@]}" 2>&1)
            if [ $? -ne 0 ]; then
                echo ""
                log_error "Failed to update item in 1Password"
                echo "$result"
                exit 1
            fi
        else
            # Create new item
            log_info "Creating item..."
            result=$(op item create --category="Secure Note" \
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
                result=$(op item edit "$item_title" --vault "$VAULT" "${remaining_fields[@]}" 2>&1)
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
