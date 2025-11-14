#!/usr/bin/env bash
# Inject secrets from 1Password vault into local .env file
# Part of op-env-manager by Matteo Cervelli

set -eo pipefail

# Get script directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/logger.sh"
source "$LIB_DIR/error_helpers.sh"
source "$LIB_DIR/retry.sh"
source "$LIB_DIR/progress.sh"

# Global variables
OUTPUT_FILE=".env"
VAULT=""
ITEM_NAME=""
SECTION=""
DRY_RUN=false
OVERWRITE=false

# Show usage
usage() {
    cat << EOF
Usage: op-env-manager inject [options]

Inject secrets from 1Password vault into local .env file.

Options:
    --vault=VAULT       1Password vault name (required)
    --item=NAME         Item name prefix (default: env-secrets)
    --section=SECTION   Environment section (e.g., dev, prod, staging, demo)
    --output=FILE       Output file path (default: .env)
    --overwrite         Overwrite existing file without prompting
    --dry-run           Preview what would be written without actually writing

Examples:
    op-env-manager inject --vault="Personal" --output=.env.local
    op-env-manager inject --vault="Projects" --item="myapp" --section="dev" --output=.env.dev
    op-env-manager inject --vault="Projects" --item="myapp" --section="prod" --output=.env.prod
    op-env-manager inject --vault="Work" --item="myapp" --dry-run

Notes:
    - Retrieves fields from specified item and section in 1Password
    - Creates .env file with KEY=value format
    - File permissions set to 600 (owner read/write only)
    - Prompts before overwriting existing files (unless --overwrite)
    - Use with --section to retrieve environment-specific secrets

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

# Retrieve fields from 1Password item/section
get_fields_from_item() {
    local vault="$1"
    local item_name="$2"
    local section="$3"

    log_step "Retrieving fields from vault: $vault, item: $item_name"
    if [ -n "$section" ]; then
        log_info "Section: $section"
    fi

    # Get the item
    local item_json
    local error_output
    error_output=$(mktemp)
    trap 'rm -f "$error_output"' EXIT

    item_json=$(retry_with_backoff "get item from vault" op item get "$item_name" --vault "$vault" --format json 2>"$error_output")

    if [ -z "$item_json" ]; then
        local error_msg
        error_msg=$(cat "$error_output")

        log_error "Item not found: $item_name in vault $vault"

        # Check for specific errors
        if echo "$error_msg" | grep -qi "vault.*not found"; then
            suggest_vault_list "$vault"
        else
            suggest_item_push "$vault" "$item_name"
            suggest_item_list "$vault" "$item_name"
        fi
        exit 1
    fi

    # Extract fields from the specified section (or all fields if no section)
    if [ -n "$section" ]; then
        # Get fields from specific section
        echo "$item_json" | jq -r ".fields[] | select(.section.label == \"$section\") | \"\(.label)=\(.value // \"\")\""
    else
        # Get all password/concealed fields without section
        echo "$item_json" | jq -r '.fields[] | select(.type == "CONCEALED" or .type == "STRING") | select(.section == null) | "\(.label)=\(.value // "")"'
    fi
}

# Inject secrets into .env file
inject_to_env_file() {
    log_header "Injecting Secrets from 1Password"
    echo ""

    if [ -z "$VAULT" ]; then
        log_error "--vault is required"
        echo "" >&2
        log_suggestion "Specify a vault name:"
        log_command "op-env-manager inject --vault=\"VaultName\" --item=\"item-name\""
        echo "" >&2
        suggest_vault_list
        usage
    fi

    if [ -z "$ITEM_NAME" ]; then
        ITEM_NAME="env-secrets"
        log_info "Using default item name prefix: $ITEM_NAME"
    fi

    check_op_cli

    # Check if output file exists
    if [ -f "$OUTPUT_FILE" ] && [ "$OVERWRITE" != true ] && [ "$DRY_RUN" != true ]; then
        log_warning "File already exists: $OUTPUT_FILE"
        read -rp "Overwrite? (y/n): " response
        if [ "$response" != "y" ]; then
            log_info "Cancelled"
            exit 0
        fi
    fi

    # Get fields from 1Password item
    local fields
    fields=$(get_fields_from_item "$VAULT" "$ITEM_NAME" "$SECTION")

    if [ -z "$fields" ]; then
        if [ -n "$SECTION" ]; then
            log_error "No fields found in section: $SECTION"
            suggest_section_check "$VAULT" "$ITEM_NAME" "$SECTION"

            echo "" >&2
            log_suggestion "Or push your environment to this section:"
            log_command "op-env-manager push --vault=\"$VAULT\" --item=\"$ITEM_NAME\" --section=\"$SECTION\" --env-file=\".env\""
        else
            log_error "No fields found in item: $ITEM_NAME"
            echo "" >&2
            suggest_item_push "$VAULT" "$ITEM_NAME"
        fi
        exit 1
    fi

    local count=0
    local temp_file
    temp_file=$(mktemp)
    trap 'rm -f "$temp_file"' EXIT

    # Header
    echo "# Generated by op-env-manager on $(date -u +"%Y-%m-%d %H:%M:%S UTC")" > "$temp_file"
    echo "# Vault: $VAULT" >> "$temp_file"
    echo "# Item: $ITEM_NAME" >> "$temp_file"
    if [ -n "$SECTION" ]; then
        echo "# Section: $SECTION" >> "$temp_file"
    fi
    echo "" >> "$temp_file"

    # Process each field
    log_step "Retrieving secrets..."
    echo ""

    # Count total fields for progress tracking
    local total_fields
    total_fields=$(echo "$fields" | grep -c '^[^[:space:]]' || true)

    # Initialize progress bar
    init_progress "$total_fields" "Injecting variables"

    while IFS='=' read -r key value; do
        if [ -n "$key" ]; then
            if [ "$DRY_RUN" = true ]; then
                log_info "[DRY RUN] Would inject: $key"
                echo "${key}=<secret-from-1password>" >> "$temp_file"
            else
                # Convert \n escape sequences back to actual newlines for multiline values
                # Use printf to interpret escape sequences
                local processed_value
                processed_value=$(printf '%b' "$value")

                # If value contains newlines, wrap in double quotes
                if [[ "$processed_value" == *$'\n'* ]]; then
                    echo "${key}=\"${processed_value}\"" >> "$temp_file"
                else
                    echo "${key}=${processed_value}" >> "$temp_file"
                fi
                log_success "Retrieved: $key"
            fi
            ((count++))
            update_progress "$count"
        fi
    done <<< "$fields"

    finish_progress

    echo ""

    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN: Preview of what would be written to $OUTPUT_FILE:"
        echo ""
        cat "$temp_file"
        echo ""
        log_info "Remove --dry-run to actually create the file"
    else
        # Write to output file
        cp "$temp_file" "$OUTPUT_FILE"
        chmod 600 "$OUTPUT_FILE"

        log_success "Successfully injected secrets to: $OUTPUT_FILE"
        echo ""
        log_info "File permissions set to 600 (owner read/write only)"
        echo ""
        log_warning "Security reminder:"
        echo "  - Never commit this file to version control"
        echo "  - Add '$OUTPUT_FILE' to your .gitignore"
        echo "  - Rotate secrets regularly in 1Password"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
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
            --output=*)
                OUTPUT_FILE="${1#*=}"
                shift
                ;;
            --output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --overwrite)
                OVERWRITE=true
                shift
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
    inject_to_env_file
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
