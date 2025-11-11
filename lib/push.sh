#!/usr/bin/env bash
# Push local .env file to 1Password vault
# Part of op-env-manager by Matteo Cervelli

set -eo pipefail

# Get script directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/logger.sh"

# Global variables
ENV_FILE=".env"
VAULT=""
ITEM_NAME=""
SECTION=""
DRY_RUN=false

# Show usage
usage() {
    cat << EOF
Usage: op-env-manager push [options]

Push local .env file variables to 1Password vault as individual password items.

Options:
    --env-file=FILE     Path to .env file (default: .env)
    --vault=VAULT       1Password vault name (required)
    --item=NAME         Item name prefix (default: env-secrets)
    --section=SECTION   Environment section (e.g., dev, prod, staging, demo)
    --dry-run           Preview what would be pushed without actually pushing

Examples:
    op-env-manager push --vault="Personal" --env-file=.env.production
    op-env-manager push --vault="Projects" --item="myapp" --section="dev" --env-file=.env.dev
    op-env-manager push --vault="Projects" --item="myapp" --section="prod" --env-file=.env.prod
    op-env-manager push --vault="Work" --item="myapp" --dry-run

Notes:
    - Creates a single Secure Note item in 1Password with all variables as fields
    - When --section is specified, variables are organized in named sections (e.g., dev, prod)
    - Enables secret references like: op://vault/item/\$APP_ENV/VAR_NAME
    - Existing items are updated with new/changed fields
    - Comments and empty lines in .env are ignored
    - Tagged with 'op-env-manager' for identification

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

# Parse .env file and extract variables
parse_env_file() {
    local env_file="$1"

    if [ ! -f "$env_file" ]; then
        log_error "Environment file not found: $env_file"
        exit 1
    fi

    # Parse .env file, ignore comments and empty lines
    grep -v '^\s*#' "$env_file" | grep -v '^\s*$' | while IFS='=' read -r key value; do
        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Remove quotes from value if present
        value="${value%\"}"
        value="${value#\"}"
        value="${value%\'}"
        value="${value#\'}"

        if [ -n "$key" ]; then
            echo "$key=$value"
        fi
    done
}

# Push variables to 1Password
push_to_1password() {
    log_header "Pushing Environment Variables to 1Password"
    echo ""

    if [ -z "$VAULT" ]; then
        log_error "--vault is required"
        usage
    fi

    if [ -z "$ITEM_NAME" ]; then
        ITEM_NAME="env-secrets"
        log_info "Using default item name prefix: $ITEM_NAME"
    fi

    check_op_cli

    log_step "Reading variables from: $ENV_FILE"
    local vars
    vars=$(parse_env_file "$ENV_FILE")

    if [ -z "$vars" ]; then
        log_error "No variables found in $ENV_FILE"
        exit 1
    fi

    local count=0
    local item_title="$ITEM_NAME"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would create/update item: $item_title"
        if [ -n "$SECTION" ]; then
            log_info "[DRY RUN] Section: $SECTION"
        fi
        echo ""
        while IFS='=' read -r key value; do
            if [ -n "$key" ]; then
                if [ -n "$SECTION" ]; then
                    log_info "[DRY RUN] Would set: $SECTION.$key[password]"
                else
                    log_info "[DRY RUN] Would set: $key[password]"
                fi
                ((count++))
            fi
        done <<< "$vars"
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

        # Build field assignments as a temporary file (to avoid shell escaping issues)
        local temp_fields
        temp_fields=$(mktemp)
        trap 'rm -f "$temp_fields"' EXIT

        while IFS='=' read -r key value; do
            if [ -n "$key" ]; then
                if [ -n "$SECTION" ]; then
                    echo "${SECTION}.${key}[password]=${value}" >> "$temp_fields"
                    log_success "Setting: $SECTION.$key"
                else
                    echo "${key}[password]=${value}" >> "$temp_fields"
                    log_success "Setting: $key"
                fi
                ((count++))
            fi
        done <<< "$vars"

        # Read field assignments into array
        local field_args=()
        while IFS= read -r line; do
            field_args+=("$line")
        done < "$temp_fields"

        # Create or update the item with all fields
        # Note: We process fields in batches to avoid command-line length limits
        local result
        if [ "$item_exists" = true ]; then
            # Update existing item - process all fields at once
            result=$(op item edit "$item_title" --vault "$VAULT" "${field_args[@]}" 2>&1)
            if [ $? -ne 0 ]; then
                echo ""
                log_error "Failed to update item in 1Password"
                echo "$result"
                exit 1
            fi
        else
            # Create new item with first field, then add rest with edit
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

            # Add remaining fields with edit
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
        log_warning "DRY RUN: No changes made. Remove --dry-run to push for real."
    else
        log_success "Successfully pushed environment variables to 1Password!"
        echo ""
        log_info "To inject these back into your environment:"
        if [ -n "$SECTION" ]; then
            echo "  op-env-manager inject --vault=\"$VAULT\" --item=\"$ITEM_NAME\" --section=\"$SECTION\""
            echo ""
            log_info "Or use with \$APP_ENV variable:"
            echo "  export APP_ENV=\"$SECTION\""
            echo "  op run --env-file=<(op-env-manager inject --vault=\"$VAULT\" --item=\"$ITEM_NAME\" --section=\"\$APP_ENV\") -- your-command"
        else
            echo "  op-env-manager inject --vault=\"$VAULT\" --item=\"$ITEM_NAME\""
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
    push_to_1password
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
