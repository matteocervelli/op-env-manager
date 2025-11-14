#!/usr/bin/env bash
# Compare local .env file with 1Password vault
# Part of op-env-manager by Matteo Cervelli

set -eo pipefail

# Get script directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/logger.sh"
source "$LIB_DIR/error_helpers.sh"
source "$LIB_DIR/retry.sh"

# Import parse_env_file from push.sh
source "$LIB_DIR/push.sh"

# Import get_fields_from_item from inject.sh
source "$LIB_DIR/inject.sh"

# Global variables
ENV_FILE=".env"
VAULT=""
ITEM_NAME="env-secrets"
SECTION=""
DRY_RUN=false

# Show usage
usage() {
    cat << EOF
Usage: op-env-manager diff [options]

Compare local .env file with 1Password vault and show differences.

Options:
    --env-file=FILE        Path to .env file (default: .env)
    --vault=VAULT          1Password vault name (required)
    --item=NAME            Item name prefix (default: env-secrets)
    --section=SECTION      Environment section (e.g., dev, prod, staging, demo)
    --dry-run              Preview operation without checking 1Password

Exit Codes:
    0                      Files are identical (no differences)
    1                      Differences found
    2                      Error occurred

Output Format:
    +  Variable added in 1Password (not in local)
    -  Variable removed (only in local, not in 1Password)
    ±  Variable modified (different values)

Examples:
    op-env-manager diff --vault="Personal" --env-file=.env
    op-env-manager diff --vault="Projects" --item="myapp" --section="dev" --env-file=.env.dev
    op-env-manager diff --vault="Work" --item="myapp" --dry-run

EOF
    exit 1
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

    # Validate required arguments
    if [ -z "$VAULT" ]; then
        log_error "--vault is required"
        echo "" >&2
        suggest_vault_list
        exit 2
    fi

    # Use default item name if not specified
    if [ -z "$ITEM_NAME" ]; then
        ITEM_NAME="env-secrets"
    fi
}

# Check if 1Password CLI is installed and authenticated
check_op_cli() {
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry-run mode: skipping 1Password authentication check"
        return 0
    fi

    # Use centralized diagnostics from error_helpers
    if ! diagnose_op_cli; then
        exit 2
    fi

    log_success "1Password CLI authenticated"
}

# Compare local and remote states
# Returns: JSON with additions, deletions, modifications
compare_states() {
    local local_vars="$1"   # KEY=value format
    local remote_vars="$2"  # KEY=value format

    # Convert to associative arrays
    declare -A local_map
    declare -A remote_map

    # Parse local variables
    while IFS='=' read -r key value; do
        # Skip empty lines
        if [ -n "$key" ]; then
            local_map["$key"]="$value"
        fi
    done <<< "$local_vars"

    # Parse remote variables
    while IFS='=' read -r key value; do
        # Skip empty lines
        if [ -n "$key" ]; then
            remote_map["$key"]="$value"
        fi
    done <<< "$remote_vars"

    # Find additions (only in remote)
    local additions=()
    for key in "${!remote_map[@]}"; do
        if [[ ! -v local_map["$key"] ]]; then
            additions+=("$key")
        fi
    done

    # Find deletions (only in local)
    local deletions=()
    for key in "${!local_map[@]}"; do
        if [[ ! -v remote_map["$key"] ]]; then
            deletions+=("$key")
        fi
    done

    # Find modifications (different values)
    local modifications=()
    for key in "${!local_map[@]}"; do
        if [[ -v remote_map["$key"] ]]; then
            if [[ "${local_map[$key]}" != "${remote_map[$key]}" ]]; then
                modifications+=("$key")
            fi
        fi
    done

    # Build JSON output (manually to avoid jq dependency issues)
    local json_additions=""
    for key in "${additions[@]}"; do
        if [ -z "$json_additions" ]; then
            json_additions="\"$key\""
        else
            json_additions="$json_additions,\"$key\""
        fi
    done

    local json_deletions=""
    for key in "${deletions[@]}"; do
        if [ -z "$json_deletions" ]; then
            json_deletions="\"$key\""
        else
            json_deletions="$json_deletions,\"$key\""
        fi
    done

    local json_modifications=""
    for key in "${modifications[@]}"; do
        if [ -z "$json_modifications" ]; then
            json_modifications="\"$key\""
        else
            json_modifications="$json_modifications,\"$key\""
        fi
    done

    echo "{\"additions\":[$json_additions],\"deletions\":[$json_deletions],\"modifications\":[$json_modifications]}"

    # Also export maps for display function
    export DIFF_LOCAL_MAP_KEYS="${!local_map[*]}"
    export DIFF_REMOTE_MAP_KEYS="${!remote_map[*]}"

    # Store values in temporary environment variables (limited to 128 KB total)
    for key in "${!local_map[@]}"; do
        export "DIFF_LOCAL_$key=${local_map[$key]}"
    done
    for key in "${!remote_map[@]}"; do
        export "DIFF_REMOTE_$key=${remote_map[$key]}"
    done
}

# Display differences with colorized output
display_diff() {
    local diff_json="$1"
    local item_name="$2"

    # Parse diff JSON
    local additions=$(echo "$diff_json" | jq -r '.additions[]' 2>/dev/null || true)
    local deletions=$(echo "$diff_json" | jq -r '.deletions[]' 2>/dev/null || true)
    local modifications=$(echo "$diff_json" | jq -r '.modifications[]' 2>/dev/null || true)

    # Count differences
    local add_count=$(echo "$additions" | grep -c "." || echo "0")
    local del_count=$(echo "$deletions" | grep -c "." || echo "0")
    local mod_count=$(echo "$modifications" | grep -c "." || echo "0")
    local total_diff=$((add_count + del_count + mod_count))

    if [ "$total_diff" -eq 0 ]; then
        log_success "No differences found - local and remote are identical"
        return 0
    fi

    log_header "Differences Found: $total_diff changes"
    echo ""

    # Show additions (only in 1Password)
    if [ "$add_count" -gt 0 ]; then
        log_info "Added in 1Password (not in local): $add_count"
        while IFS= read -r key; do
            [ -n "$key" ] && echo "  $(log_color_green "+") $(log_color_cyan "$key")"
        done <<< "$additions"
        echo ""
    fi

    # Show deletions (only in local)
    if [ "$del_count" -gt 0 ]; then
        log_info "Removed from 1Password (only in local): $del_count"
        while IFS= read -r key; do
            [ -n "$key" ] && echo "  $(log_color_red "-") $(log_color_cyan "$key")"
        done <<< "$deletions"
        echo ""
    fi

    # Show modifications (different values)
    if [ "$mod_count" -gt 0 ]; then
        log_info "Modified (different values): $mod_count"
        while IFS= read -r key; do
            if [ -n "$key" ]; then
                # Get values from exported environment
                local local_val
                local remote_val
                eval "local_val=\$DIFF_LOCAL_$key"
                eval "remote_val=\$DIFF_REMOTE_$key"

                # Mask secrets (show first 8 chars + ...)
                local local_masked="$local_val"
                local remote_masked="$remote_val"
                if [ "${#local_val}" -gt 12 ]; then
                    local_masked="${local_val:0:8}..."
                fi
                if [ "${#remote_val}" -gt 12 ]; then
                    remote_masked="${remote_val:0:8}..."
                fi

                echo "  $(log_color_yellow "±") $(log_color_cyan "$key")"
                echo "    Local:  $local_masked"
                echo "    Remote: $remote_masked"
            fi
        done <<< "$modifications"
        echo ""
    fi

    return 1  # Return non-zero to indicate differences found
}

# Helper functions for colored output (used in display_diff)
log_color_green() {
    if [ "${NO_COLOR:-}" = "1" ] || [ "${OP_QUIET_MODE:-false}" = "true" ]; then
        echo "$1"
    else
        echo -e "\033[0;32m$1\033[0m"
    fi
}

log_color_red() {
    if [ "${NO_COLOR:-}" = "1" ] || [ "${OP_QUIET_MODE:-false}" = "true" ]; then
        echo "$1"
    else
        echo -e "\033[0;31m$1\033[0m"
    fi
}

log_color_yellow() {
    if [ "${NO_COLOR:-}" = "1" ] || [ "${OP_QUIET_MODE:-false}" = "true" ]; then
        echo "$1"
    else
        echo -e "\033[0;33m$1\033[0m"
    fi
}

log_color_cyan() {
    if [ "${NO_COLOR:-}" = "1" ] || [ "${OP_QUIET_MODE:-false}" = "true" ]; then
        echo "$1"
    else
        echo -e "\033[0;36m$1\033[0m"
    fi
}

# Main function
main() {
    parse_args "$@"

    log_header "Comparing Local .env with 1Password"
    echo ""

    log_info "Vault: $VAULT"
    log_info "Item: $ITEM_NAME"
    if [ -n "$SECTION" ]; then
        log_info "Section: $SECTION"
    fi
    log_info "Local file: $ENV_FILE"
    echo ""

    # Check prerequisites
    check_op_cli

    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN: Would compare $ENV_FILE with $VAULT/$ITEM_NAME"
        if [ -n "$SECTION" ]; then
            log_info "Would compare section: $SECTION"
        fi
        exit 0
    fi

    # Parse local .env file and fetch from 1Password in parallel (optimization)
    log_step "Fetching data from local and remote sources (parallel)..."

    # Create temporary files for parallel operations
    local local_temp=$(mktemp)
    local remote_temp=$(mktemp)
    local remote_status_temp=$(mktemp)

    # Cleanup temps on exit
    trap 'rm -f "$local_temp" "$remote_temp" "$remote_status_temp"' EXIT

    # Build item title (with section suffix if specified)
    local item_title="$ITEM_NAME"
    if [ -n "$SECTION" ]; then
        item_title="${ITEM_NAME}_${SECTION}"
    fi

    # Start local parse in background
    {
        parse_env_file "$ENV_FILE" > "$local_temp"
    } &
    local local_pid=$!

    # Start remote fetch in background
    {
        # Check if item exists
        if retry_with_backoff "check if item exists" op item get "$item_title" --vault "$VAULT" &> /dev/null; then
            get_fields_from_item "$VAULT" "$ITEM_NAME" "$SECTION" > "$remote_temp"
            echo "0" > "$remote_status_temp"
        else
            echo "1" > "$remote_status_temp"
        fi
    } &
    local remote_pid=$!

    # Wait for both operations to complete
    wait $local_pid $remote_pid

    # Check remote status
    local remote_status=$(cat "$remote_status_temp")
    if [ "$remote_status" != "0" ]; then
        log_error "Item not found: $item_title in vault $VAULT"
        echo "" >&2
        suggest_item_push "$VAULT" "$ITEM_NAME" "$ENV_FILE"
        echo "" >&2
        suggest_item_list "$VAULT" "$ITEM_NAME"
        exit 2
    fi

    # Read results
    local local_vars=$(cat "$local_temp")
    local remote_vars=$(cat "$remote_temp")

    # Display results
    local local_count=$(echo "$local_vars" | grep -c "=" || echo "0")
    log_success "Found $local_count variables in local file"

    local remote_count=$(echo "$remote_vars" | grep -c "=" || echo "0")
    log_success "Found $remote_count variables in 1Password"
    echo ""

    # Compare states
    log_step "Computing differences..."
    local diff_json
    diff_json=$(compare_states "$local_vars" "$remote_vars")
    echo ""

    # Display differences
    if display_diff "$diff_json" "$item_title"; then
        exit 0  # No differences
    else
        exit 1  # Differences found
    fi
}

# Allow standalone execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
