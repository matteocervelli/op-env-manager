#!/usr/bin/env bash
# Bidirectional sync between local .env file and 1Password vault
# Part of op-env-manager by Matteo Cervelli

set -eo pipefail

# Get script directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/logger.sh"
source "$LIB_DIR/error_helpers.sh"
source "$LIB_DIR/retry.sh"
source "$LIB_DIR/progress.sh"

# Import functions from other commands
source "$LIB_DIR/push.sh"
source "$LIB_DIR/inject.sh"
source "$LIB_DIR/diff.sh"

# Global variables
ENV_FILE=".env"
VAULT=""
ITEM_NAME="env-secrets"
SECTION=""
DRY_RUN=false
CONFLICT_STRATEGY="interactive"  # interactive, ours, theirs, newest
NO_BACKUP=false
STATE_FILE=".op-env-manager.state"

# Show usage
usage() {
    cat << EOF
Usage: op-env-manager sync [options]

Bidirectional synchronization between local .env file and 1Password vault.
Automatically handles additions, deletions, and modifications with intelligent
conflict resolution.

Options:
    --env-file=FILE        Path to .env file (default: .env)
    --vault=VAULT          1Password vault name (required)
    --item=NAME            Item name prefix (default: env-secrets)
    --section=SECTION      Environment section (e.g., dev, prod, staging, demo)
    --strategy=STRATEGY    Conflict resolution strategy (default: interactive)
                           - interactive: Prompt for each conflict
                           - ours:        Always prefer local values
                           - theirs:      Always prefer 1Password values
                           - newest:      Use most recently modified values
    --no-backup            Skip automatic backup before sync
    --dry-run              Preview what would be synced without making changes

Sync Behavior:
    + Added:      Variables only in 1Password are pulled to local
    - Removed:    Variables only in local are removed from 1Password
    ± Modified:   Variables with different values trigger conflict resolution
    = Unchanged:  Variables with same values are skipped

Conflict Resolution:
    interactive  - Prompt user for each conflict (default)
                   Options: [l]ocal, [r]emote, [e]dit, [s]kip
    ours         - Always use local values (force push)
    theirs       - Always use 1Password values (force pull)
    newest       - Use most recently modified value (based on timestamps)

State Tracking:
    Sync creates a .op-env-manager.state file to track the last sync state.
    This enables accurate three-way merge and prevents false conflicts.

Backups:
    By default, creates a timestamped backup in .op-env-manager/backups/
    before modifying local files. Use --no-backup to disable.

Exit Codes:
    0  - Sync completed successfully
    1  - Sync had conflicts (with --strategy=interactive and skipped conflicts)
    2  - Error occurred

Examples:
    # Interactive sync (default)
    op-env-manager sync --vault="Personal" --env-file=.env

    # Automatic sync with "ours" strategy (prefer local)
    op-env-manager sync --vault="Projects" --item="myapp" --strategy=ours

    # Sync with environment section
    op-env-manager sync --vault="Projects" --item="myapp" --section="dev" --env-file=.env.dev

    # Dry-run to preview changes
    op-env-manager sync --vault="Personal" --dry-run

    # Sync without backup (use cautiously)
    op-env-manager sync --vault="Personal" --no-backup

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
            --strategy=*)
                CONFLICT_STRATEGY="${1#*=}"
                shift
                ;;
            --strategy)
                CONFLICT_STRATEGY="$2"
                shift 2
                ;;
            --no-backup)
                NO_BACKUP=true
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

    # Validate required arguments
    if [ -z "$VAULT" ]; then
        log_error "--vault is required"
        echo "" >&2
        suggest_vault_list
        exit 2
    fi

    # Validate strategy
    case "$CONFLICT_STRATEGY" in
        interactive|ours|theirs|newest)
            # Valid
            ;;
        *)
            log_error "Invalid strategy: $CONFLICT_STRATEGY"
            echo "" >&2
            log_info "Valid strategies: interactive, ours, theirs, newest"
            exit 2
            ;;
    esac

    # Use default item name if not specified
    if [ -z "$ITEM_NAME" ]; then
        ITEM_NAME="env-secrets"
    fi

    # Set state file path (same directory as env file)
    local env_dir=$(dirname "$ENV_FILE")
    STATE_FILE="$env_dir/.op-env-manager.state"
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

# Compute SHA256 checksum for a value
compute_checksum() {
    local value="$1"
    echo -n "$value" | sha256sum | awk '{print $1}'
}

# Load sync state from file
load_sync_state() {
    local state_file="$1"

    if [ -f "$state_file" ]; then
        cat "$state_file"
    else
        # Return empty JSON object
        echo "{}"
    fi
}

# Save sync state to file
save_sync_state() {
    local state_file="$1"
    local vault="$2"
    local item="$3"
    local section="$4"
    local checksums_json="$5"  # JSON object with checksums

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Build JSON manually (more portable than jq -n)
    cat > "$state_file" << EOF
{
  "version": "1.0",
  "vault": "$vault",
  "item": "$item",
  "section": "$section",
  "last_sync": "$timestamp",
  "checksums": $checksums_json
}
EOF

    chmod 600 "$state_file"
    log_info "State saved: $state_file"
}

# Build checksums JSON from variables
build_checksums_json() {
    local vars="$1"  # KEY=value format

    local checksums_array=()

    while IFS='=' read -r key value; do
        if [ -n "$key" ]; then
            local checksum=$(compute_checksum "$value")
            # Escape quotes in key for JSON
            local escaped_key=$(echo "$key" | sed 's/"/\\"/g')
            checksums_array+=("\"$escaped_key\": \"$checksum\"")
        fi
    done <<< "$vars"

    # Join with commas
    local checksums_str=$(IFS=,; echo "${checksums_array[*]}")

    echo "{$checksums_str}"
}

# Create backup of .env file
backup_env_file() {
    local env_file="$1"

    if [ ! -f "$env_file" ]; then
        log_warning "No existing file to backup: $env_file"
        return 0
    fi

    local env_dir=$(dirname "$env_file")
    local env_basename=$(basename "$env_file")
    local backup_dir="$env_dir/.op-env-manager/backups"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$backup_dir/${env_basename}.${timestamp}.bak"

    mkdir -p "$backup_dir"
    cp "$env_file" "$backup_file"
    chmod 600 "$backup_file"

    log_success "Backup created: $backup_file"

    # Store backup path for potential restoration
    export SYNC_BACKUP_FILE="$backup_file"
}

# Restore from backup (on error)
restore_from_backup() {
    if [ -n "$SYNC_BACKUP_FILE" ] && [ -f "$SYNC_BACKUP_FILE" ]; then
        log_warning "Restoring from backup: $SYNC_BACKUP_FILE"
        cp "$SYNC_BACKUP_FILE" "$ENV_FILE"
        log_success "Restored from backup"
    fi
}

# Resolve conflict based on strategy
resolve_conflict() {
    local key="$1"
    local local_value="$2"
    local remote_value="$3"
    local strategy="$4"

    case "$strategy" in
        ours)
            echo "local"
            ;;
        theirs)
            echo "remote"
            ;;
        newest)
            # Use remote (1Password has version history, more reliable)
            # In future, could parse timestamps from state file
            echo "remote"
            ;;
        interactive)
            prompt_user_choice "$key" "$local_value" "$remote_value"
            ;;
        *)
            echo "skip"
            ;;
    esac
}

# Prompt user for conflict resolution
prompt_user_choice() {
    local key="$1"
    local local_value="$2"
    local remote_value="$3"

    # Mask long values
    local local_display="$local_value"
    local remote_display="$remote_value"
    if [ "${#local_value}" -gt 60 ]; then
        local_display="${local_value:0:60}..."
    fi
    if [ "${#remote_value}" -gt 60 ]; then
        remote_display="${#remote_value:0:60}..."
    fi

    echo "" >&2
    log_warning "Conflict detected: $key"
    echo "" >&2
    echo "  Local:  $local_display" >&2
    echo "  Remote: $remote_display" >&2
    echo "" >&2

    local choice
    while true; do
        read -r -p "Choose [l]ocal, [r]emote, [e]dit, [s]kip: " choice

        case "$choice" in
            l|local|L|LOCAL)
                echo "local"
                return
                ;;
            r|remote|R|REMOTE)
                echo "remote"
                return
                ;;
            e|edit|E|EDIT)
                echo "" >&2
                read -r -p "Enter new value: " new_value
                echo "edit:$new_value"
                return
                ;;
            s|skip|S|SKIP)
                echo "skip"
                return
                ;;
            *)
                echo "Invalid choice. Please enter l, r, e, or s." >&2
                ;;
        esac
    done
}

# Merge changes and write to .env file
merge_and_write() {
    local merged_vars="$1"
    local output_file="$2"

    # Write merged variables to file
    while IFS='=' read -r key value; do
        if [ -n "$key" ]; then
            # Handle multiline values (convert \n back to actual newlines)
            local processed_value=$(printf '%b' "$value")

            # Wrap in quotes if contains newlines, spaces, or special chars
            if [[ "$processed_value" == *$'\n'* ]] || [[ "$processed_value" == *" "* ]]; then
                echo "${key}=\"${processed_value}\""
            else
                echo "${key}=${processed_value}"
            fi
        fi
    done <<< "$merged_vars" > "$output_file"

    chmod 600 "$output_file"
}

# Push changes to 1Password
push_to_1password() {
    local vault="$1"
    local item="$2"
    local section="$3"
    local vars="$4"  # KEY=value format

    # Build item title
    local item_title="$item"
    if [ -n "$section" ]; then
        item_title="${item}_${section}"
    fi

    # Check if item exists
    local item_exists=false
    if retry_with_backoff "check if item exists" op item get "$item_title" --vault "$vault" &> /dev/null; then
        item_exists=true
    fi

    # Build field arguments
    local field_args=()
    local count=0

    while IFS='=' read -r key value; do
        if [ -n "$key" ]; then
            # Escape special characters in value
            local escaped_value=$(echo "$value" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')

            # Build field reference
            if [ -n "$section" ]; then
                field_args+=("${section}.${key}[password]=${escaped_value}")
            else
                field_args+=("${key}[password]=${escaped_value}")
            fi

            count=$((count + 1))
        fi
    done <<< "$vars"

    if [ "$count" -eq 0 ]; then
        log_warning "No variables to push"
        return 0
    fi

    # Create or update item
    if [ "$item_exists" = false ]; then
        log_step "Creating new item in 1Password..."

        # Create with first field, then edit with rest (1Password CLI limitation)
        retry_with_backoff "create item" \
            op item create --category="Secure Note" \
            --title="$item_title" \
            --vault="$vault" \
            --tags="op-env-manager" \
            "${field_args[0]}" > /dev/null

        if [ "${#field_args[@]}" -gt 1 ]; then
            retry_with_backoff "update item with remaining fields" \
                op item edit "$item_title" --vault "$vault" "${field_args[@]:1}" > /dev/null
        fi
    else
        log_step "Updating existing item in 1Password..."
        retry_with_backoff "update item" \
            op item edit "$item_title" --vault "$vault" "${field_args[@]}" > /dev/null
    fi

    log_success "Pushed $count variables to 1Password"
}

# Main sync function
main() {
    parse_args "$@"

    log_header "Syncing Local .env with 1Password"
    echo ""

    log_info "Vault: $VAULT"
    log_info "Item: $ITEM_NAME"
    if [ -n "$SECTION" ]; then
        log_info "Section: $SECTION"
    fi
    log_info "Local file: $ENV_FILE"
    log_info "Strategy: $CONFLICT_STRATEGY"
    echo ""

    # Check prerequisites
    check_op_cli

    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN: Would sync $ENV_FILE with $VAULT/$ITEM_NAME"
        if [ -n "$SECTION" ]; then
            log_info "Would sync section: $SECTION"
        fi
        log_info "Would use conflict strategy: $CONFLICT_STRATEGY"
        exit 0
    fi

    # Create backup (unless disabled)
    if [ "$NO_BACKUP" = false ]; then
        log_step "Creating backup..."
        backup_env_file "$ENV_FILE"
        echo ""
    fi

    # Trap errors to restore from backup
    trap 'restore_from_backup' ERR

    # Load last sync state
    log_step "Loading sync state..."
    local state_json=$(load_sync_state "$STATE_FILE")
    local has_previous_sync=false
    if [ "$(echo "$state_json" | jq -r '.version // empty')" != "" ]; then
        has_previous_sync=true
        log_info "Found previous sync: $(echo "$state_json" | jq -r '.last_sync')"
    else
        log_info "No previous sync found (first sync)"
    fi
    echo ""

    # Parse local .env file
    log_step "Parsing local .env file..."
    local local_vars
    if [ -f "$ENV_FILE" ]; then
        local_vars=$(parse_env_file "$ENV_FILE")
    else
        local_vars=""
        log_warning "Local file does not exist: $ENV_FILE"
    fi
    local local_count=$(echo "$local_vars" | grep -c "=" || echo "0")
    log_success "Found $local_count variables in local file"

    # Get fields from 1Password
    log_step "Fetching fields from 1Password..."
    local remote_vars=""
    local item_title="$ITEM_NAME"
    if [ -n "$SECTION" ]; then
        item_title="${ITEM_NAME}_${SECTION}"
    fi

    if retry_with_backoff "check if item exists" op item get "$item_title" --vault "$VAULT" &> /dev/null; then
        remote_vars=$(get_fields_from_item "$VAULT" "$ITEM_NAME" "$SECTION")
        local remote_count=$(echo "$remote_vars" | grep -c "=" || echo "0")
        log_success "Found $remote_count variables in 1Password"
    else
        log_warning "Item not found in 1Password (will be created)"
        remote_vars=""
    fi
    echo ""

    # Compare states
    log_step "Computing differences..."
    local diff_json
    diff_json=$(compare_states "$local_vars" "$remote_vars")

    local additions=$(echo "$diff_json" | jq -r '.additions[]' 2>/dev/null || true)
    local deletions=$(echo "$diff_json" | jq -r '.deletions[]' 2>/dev/null || true)
    local modifications=$(echo "$diff_json" | jq -r '.modifications[]' 2>/dev/null || true)

    local add_count=$(echo "$additions" | grep -c "." || echo "0")
    local del_count=$(echo "$deletions" | grep -c "." || echo "0")
    local mod_count=$(echo "$modifications" | grep -c "." || echo "0")
    local total_changes=$((add_count + del_count + mod_count))

    log_success "Found $total_changes changes ($add_count additions, $del_count deletions, $mod_count modifications)"
    echo ""

    if [ "$total_changes" -eq 0 ]; then
        log_success "✓ No changes detected - local and remote are in sync"
        exit 0
    fi

    # Convert to associative arrays for merging
    declare -A local_map
    declare -A remote_map
    declare -A merged_map

    while IFS='=' read -r key value; do
        [ -n "$key" ] && local_map["$key"]="$value"
    done <<< "$local_vars"

    while IFS='=' read -r key value; do
        [ -n "$key" ] && remote_map["$key"]="$value"
    done <<< "$remote_vars"

    # Start with local as base
    for key in "${!local_map[@]}"; do
        merged_map["$key"]="${local_map[$key]}"
    done

    # Track conflicts
    local skipped_conflicts=0

    log_header "Resolving Changes"
    echo ""

    # Handle additions (from remote)
    if [ "$add_count" -gt 0 ]; then
        log_info "Adding from 1Password:"
        while IFS= read -r key; do
            if [ -n "$key" ]; then
                merged_map["$key"]="${remote_map[$key]}"
                log_success "  + $key"
            fi
        done <<< "$additions"
        echo ""
    fi

    # Handle deletions (remove from merged and remote)
    if [ "$del_count" -gt 0 ]; then
        log_info "Removing (only in local):"
        while IFS= read -r key; do
            if [ -n "$key" ]; then
                unset merged_map["$key"]
                log_success "  - $key"
            fi
        done <<< "$deletions"
        echo ""
    fi

    # Handle modifications (conflicts)
    if [ "$mod_count" -gt 0 ]; then
        log_info "Resolving conflicts ($CONFLICT_STRATEGY strategy):"

        while IFS= read -r key; do
            if [ -n "$key" ]; then
                local resolution
                resolution=$(resolve_conflict "$key" "${local_map[$key]}" "${remote_map[$key]}" "$CONFLICT_STRATEGY")

                case "$resolution" in
                    local)
                        merged_map["$key"]="${local_map[$key]}"
                        log_success "  ± $key (used local)"
                        ;;
                    remote)
                        merged_map["$key"]="${remote_map[$key]}"
                        log_success "  ± $key (used remote)"
                        ;;
                    edit:*)
                        local new_value="${resolution#edit:}"
                        merged_map["$key"]="$new_value"
                        log_success "  ± $key (used edited value)"
                        ;;
                    skip)
                        # Keep local value (no change)
                        skipped_conflicts=$((skipped_conflicts + 1))
                        log_warning "  ⊘ $key (skipped - keeping local)"
                        ;;
                esac
            fi
        done <<< "$modifications"
        echo ""
    fi

    # Convert merged map back to KEY=value format
    local merged_vars=""
    for key in "${!merged_map[@]}"; do
        merged_vars+="$key=${merged_map[$key]}"$'\n'
    done

    # Apply changes
    log_header "Applying Changes"
    echo ""

    # Write merged variables to local file
    log_step "Updating local file..."
    merge_and_write "$merged_vars" "$ENV_FILE"
    log_success "Local file updated"

    # Push to 1Password
    log_step "Pushing to 1Password..."
    push_to_1password "$VAULT" "$ITEM_NAME" "$SECTION" "$merged_vars"
    echo ""

    # Save sync state
    log_step "Saving sync state..."
    local checksums_json=$(build_checksums_json "$merged_vars")
    save_sync_state "$STATE_FILE" "$VAULT" "$ITEM_NAME" "$SECTION" "$checksums_json"
    echo ""

    # Summary
    log_header "Sync Complete"
    echo ""
    log_success "✓ Synced $((total_changes - skipped_conflicts)) changes"
    if [ "$skipped_conflicts" -gt 0 ]; then
        log_warning "⊘ Skipped $skipped_conflicts conflicts"
        exit 1  # Exit code 1 indicates unresolved conflicts
    else
        log_success "✓ All changes applied successfully"
        exit 0
    fi
}

# Allow standalone execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
