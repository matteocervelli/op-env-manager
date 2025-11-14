#!/usr/bin/env bash
# Interactive setup wizard for op-env-manager
# Part of op-env-manager by Matteo Cervelli

set -eo pipefail

# Get script directory
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/logger.sh"
source "$LIB_DIR/error_helpers.sh"
source "$LIB_DIR/retry.sh"

# Global variables
DRY_RUN=false

# Show usage
usage() {
    cat << EOF
Usage: op-env-manager init [options]

Interactive setup wizard to configure op-env-manager with your 1Password vault.
Guides you through vault selection, item naming, and initial .env file push.

Options:
    --dry-run              Preview what would be created without actually creating

Examples:
    op-env-manager init                    # Start interactive wizard
    op-env-manager init --dry-run          # Preview wizard flow

Notes:
    - Guides you through complete setup in under 2 minutes
    - Checks prerequisites (1Password CLI, authentication)
    - Offers vault creation if needed
    - Supports multi-environment setups
    - Optionally generates .env.op template file
EOF
}

# Prompt user for input with default value
# Usage: prompt_with_default "Question?" "default_value"
# Returns: User input or default if empty
prompt_with_default() {
    local question="$1"
    local default="$2"
    local user_input

    if [[ -n "$default" ]]; then
        read -p "$question [$default]: " user_input
        echo "${user_input:-$default}"
    else
        read -p "$question: " user_input
        echo "$user_input"
    fi
}

# Prompt user for yes/no question
# Usage: prompt_yes_no "Question?" "default(y/n)"
# Returns: 0 for yes, 1 for no
prompt_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local prompt_suffix
    local user_input

    if [[ "$default" == "y" ]]; then
        prompt_suffix="[Y/n]"
    else
        prompt_suffix="[y/N]"
    fi

    read -p "$question $prompt_suffix: " user_input
    user_input="${user_input:-$default}"

    if [[ "$user_input" =~ ^[Yy] ]]; then
        return 0
    else
        return 1
    fi
}

# List available vaults
# Returns: Array of vault names (one per line)
list_vaults() {
    retry_with_backoff op vault list --format=json | jq -r '.[].name' 2>/dev/null || echo ""
}

# Check if vault exists
# Usage: vault_exists "vault_name"
# Returns: 0 if exists, 1 if not
vault_exists() {
    local vault_name="$1"
    retry_with_backoff op vault get "$vault_name" &> /dev/null
}

# Create new vault
# Usage: create_vault "vault_name"
# Returns: 0 on success, 1 on failure
create_vault() {
    local vault_name="$1"

    log_step "Creating vault: $vault_name"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] Would create vault: $vault_name"
        return 0
    fi

    if retry_with_backoff op vault create "$vault_name" &> /dev/null; then
        log_success "Vault created: $vault_name"
        return 0
    else
        log_error "Failed to create vault: $vault_name"
        log_warning "You may not have permission to create vaults."
        log_suggestion "Try selecting an existing vault instead, or ask your 1Password administrator for vault creation permissions."
        return 1
    fi
}

# Prompt for vault selection or creation
# Returns: Selected/created vault name
prompt_vault_selection() {
    log_header "Step 1: Select 1Password Vault"
    echo ""

    log_info "Listing available vaults..."
    local vaults
    vaults=$(list_vaults)

    if [[ -z "$vaults" ]]; then
        log_warning "No vaults found in your 1Password account."
        echo ""

        if prompt_yes_no "Would you like to create a new vault?" "y"; then
            local vault_name
            vault_name=$(prompt_with_default "Enter vault name" "op-env-manager")

            if create_vault "$vault_name"; then
                echo "$vault_name"
                return 0
            else
                return 1
            fi
        else
            log_error "Cannot proceed without a vault."
            return 1
        fi
    fi

    # Display available vaults
    log_info "Available vaults:"
    echo ""
    local vault_array=()
    while IFS= read -r vault; do
        vault_array+=("$vault")
        echo "  • $vault"
    done <<< "$vaults"
    echo ""

    # Prompt for selection or creation
    log_info "You can select an existing vault or create a new one."
    local vault_name
    vault_name=$(prompt_with_default "Enter vault name" "${vault_array[0]}")

    # Check if vault exists
    if vault_exists "$vault_name"; then
        log_success "Using vault: $vault_name"
        echo "$vault_name"
        return 0
    else
        log_warning "Vault '$vault_name' not found."
        echo ""

        if prompt_yes_no "Would you like to create it?" "y"; then
            if create_vault "$vault_name"; then
                echo "$vault_name"
                return 0
            else
                return 1
            fi
        else
            log_error "Cannot proceed without a valid vault."
            return 1
        fi
    fi
}

# Prompt for item name
# Returns: Item name
prompt_item_name() {
    log_header "Step 2: Choose Item Name"
    echo ""

    log_info "The item name is used to organize your environment variables in 1Password."
    log_info "For multi-project setups, use descriptive names like 'myapp', 'frontend', 'backend'."
    echo ""

    local item_name
    item_name=$(prompt_with_default "Enter item name" "env-secrets")

    log_success "Using item name: $item_name"
    echo "$item_name"
}

# Find .env files in current directory
# Returns: Array of .env file paths (one per line)
find_env_files() {
    find . -maxdepth 1 -name ".env*" -type f ! -name "*.bak" ! -name "*.example" ! -name "*.op" 2>/dev/null | sort || echo ""
}

# Prompt for .env file location
# Returns: Path to .env file
prompt_env_file_location() {
    log_header "Step 3: Select .env File"
    echo ""

    log_info "Searching for .env files in current directory..."
    local env_files
    env_files=$(find_env_files)

    if [[ -z "$env_files" ]]; then
        log_warning "No .env files found in current directory."
        echo ""

        local env_file
        env_file=$(prompt_with_default "Enter path to .env file" ".env")

        if [[ ! -f "$env_file" ]]; then
            log_error "File not found: $env_file"
            log_suggestion "Create a .env file first with your environment variables:"
            log_command "echo 'API_KEY=your_key' > .env"
            return 1
        fi

        echo "$env_file"
        return 0
    fi

    # Display found .env files
    log_info "Found .env files:"
    echo ""
    local file_array=()
    while IFS= read -r file; do
        file_array+=("$file")
        echo "  • $file"
    done <<< "$env_files"
    echo ""

    # Prompt for selection
    local env_file
    env_file=$(prompt_with_default "Enter path to .env file" "${file_array[0]}")

    if [[ ! -f "$env_file" ]]; then
        log_error "File not found: $env_file"
        return 1
    fi

    log_success "Using .env file: $env_file"
    echo "$env_file"
}

# Prompt for multi-environment setup
# Returns: "none", "items", or "sections"
prompt_multi_env_strategy() {
    log_header "Step 4: Multi-Environment Setup"
    echo ""

    log_info "Do you need to manage multiple environments (dev, staging, production)?"
    echo ""

    if ! prompt_yes_no "Enable multi-environment setup?" "n"; then
        echo "none"
        return 0
    fi

    echo ""
    log_info "Choose your multi-environment strategy:"
    echo ""
    echo "  [i] Separate items: myapp-dev, myapp-staging, myapp-prod"
    echo "      → Pros: Simpler, each environment is independent"
    echo "      → Cons: More items to manage"
    echo ""
    echo "  [s] Single item with sections: myapp (dev/staging/prod sections)"
    echo "      → Pros: Cleaner, all environments in one item"
    echo "      → Cons: Requires --section flag in commands"
    echo ""

    local strategy
    read -p "Choose strategy [i/s]: " strategy

    case "$strategy" in
        i|I)
            echo "items"
            ;;
        s|S)
            echo "sections"
            ;;
        *)
            log_warning "Invalid choice, defaulting to sections."
            echo "sections"
            ;;
    esac
}

# Prompt for environment names
# Returns: Space-separated list of environment names
prompt_environment_names() {
    local default_envs="dev staging prod"

    log_info "Enter environment names (space-separated)."
    local envs
    envs=$(prompt_with_default "Environment names" "$default_envs")

    echo "$envs"
}

# Execute push command
# Usage: execute_push "vault" "item" "section" "env_file"
execute_push() {
    local vault="$1"
    local item="$2"
    local section="$3"
    local env_file="$4"

    log_step "Pushing $env_file to 1Password..."

    local push_cmd="$LIB_DIR/push.sh"
    local args=(
        "--vault=$vault"
        "--item=$item"
        "--env-file=$env_file"
    )

    if [[ -n "$section" ]]; then
        args+=("--section=$section")
    fi

    if [[ "$DRY_RUN" == true ]]; then
        args+=("--dry-run")
    fi

    # Source and call push command
    source "$push_cmd"
    push_env_to_1password "${args[@]}"
}

# Generate template file
# Usage: generate_template "vault" "item" "section" "output_file"
generate_template() {
    local vault="$1"
    local item="$2"
    local section="$3"
    local output_file="$4"

    log_step "Generating template file: $output_file"

    local template_cmd="$LIB_DIR/template.sh"
    local args=(
        "--vault=$vault"
        "--item=$item"
        "--output=$output_file"
    )

    if [[ -n "$section" ]]; then
        args+=("--section=$section")
    fi

    if [[ "$DRY_RUN" == true ]]; then
        args+=("--dry-run")
    fi

    # Source and call template command
    source "$template_cmd"
    generate_template_from_1password "${args[@]}"
}

# Display success summary
# Usage: display_success_summary "vault" "item" "section" "strategy"
display_success_summary() {
    local vault="$1"
    local item="$2"
    local section="$3"
    local strategy="$4"

    echo ""
    log_divider
    log_success "Setup complete! 🎉"
    log_divider
    echo ""

    log_info "Your environment variables are now securely stored in 1Password."
    echo ""

    log_header "Next Steps:"
    echo ""

    log_info "1. Inject secrets to a local .env file:"
    if [[ "$strategy" == "sections" && -n "$section" ]]; then
        log_command "op-env-manager inject --vault=\"$vault\" --item=\"$item\" --section=\"$section\" --output=.env.local"
    else
        log_command "op-env-manager inject --vault=\"$vault\" --item=\"$item\" --output=.env.local"
    fi
    echo ""

    log_info "2. Run commands with secrets injected at runtime (recommended):"
    if [[ "$strategy" == "sections" && -n "$section" ]]; then
        log_command "op-env-manager run --vault=\"$vault\" --item=\"$item\" --section=\"$section\" -- your-command"
    else
        log_command "op-env-manager run --vault=\"$vault\" --item=\"$item\" -- your-command"
    fi
    echo ""

    if [[ "$strategy" == "items" ]]; then
        log_info "3. For other environments, use the environment-specific item names:"
        log_command "op-env-manager inject --vault=\"$vault\" --item=\"${item}-staging\""
        log_command "op-env-manager inject --vault=\"$vault\" --item=\"${item}-prod\""
        echo ""
    elif [[ "$strategy" == "sections" ]]; then
        log_info "3. For other environments, change the --section flag:"
        log_command "op-env-manager inject --vault=\"$vault\" --item=\"$item\" --section=\"staging\""
        log_command "op-env-manager inject --vault=\"$vault\" --item=\"$item\" --section=\"prod\""
        echo ""
    fi

    log_info "4. Learn more:"
    log_command "op-env-manager --help"
    log_command "op-env-manager push --help"
    log_command "op-env-manager run --help"
    echo ""
}

# Main wizard function
init_vault_wizard() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Welcome message
    log_header "🔐 op-env-manager Setup Wizard"
    echo ""
    log_info "This wizard will guide you through setting up op-env-manager with your 1Password vault."
    log_info "Estimated time: ~2 minutes"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        log_warning "[DRY RUN MODE] No changes will be made."
        echo ""
    fi

    # Check prerequisites
    diagnose_op_cli || exit 1
    echo ""

    # Step 1: Vault selection
    local vault
    vault=$(prompt_vault_selection) || exit 1
    echo ""

    # Step 2: Item name
    local item
    item=$(prompt_item_name) || exit 1
    echo ""

    # Step 3: .env file location
    local env_file
    env_file=$(prompt_env_file_location) || exit 1
    echo ""

    # Step 4: Multi-environment strategy
    local strategy
    strategy=$(prompt_multi_env_strategy) || exit 1
    echo ""

    # Handle multi-environment setup
    if [[ "$strategy" == "none" ]]; then
        # Single environment setup
        log_header "Step 5: Confirm and Push"
        echo ""

        log_info "Summary:"
        echo "  Vault:     $vault"
        echo "  Item:      $item"
        echo "  .env file: $env_file"
        echo ""

        if ! prompt_yes_no "Push variables to 1Password?" "y"; then
            log_warning "Setup cancelled."
            exit 0
        fi

        echo ""
        execute_push "$vault" "$item" "" "$env_file" || exit 1
        echo ""

        # Offer template generation
        if prompt_yes_no "Generate .env.op template file?" "y"; then
            echo ""
            local output_file=".env.op"
            generate_template "$vault" "$item" "" "$output_file" || true
        fi

        echo ""
        display_success_summary "$vault" "$item" "" "none"

    elif [[ "$strategy" == "items" ]]; then
        # Separate items strategy
        log_header "Step 5: Environment Setup (Separate Items)"
        echo ""

        local envs
        envs=$(prompt_environment_names) || exit 1
        echo ""

        log_info "Summary:"
        echo "  Vault:        $vault"
        echo "  Base item:    $item"
        echo "  Environments: $envs"
        echo "  .env file:    $env_file"
        echo ""

        log_info "This will create separate items for each environment:"
        for env in $envs; do
            echo "  • ${item}-${env}"
        done
        echo ""

        if ! prompt_yes_no "Proceed with push?" "y"; then
            log_warning "Setup cancelled."
            exit 0
        fi

        echo ""

        # Push to each environment item
        for env in $envs; do
            local env_item="${item}-${env}"
            local env_file_path=".env.${env}"

            # Check if environment-specific file exists, otherwise use base file
            if [[ ! -f "$env_file_path" ]]; then
                log_warning "File $env_file_path not found, using $env_file for $env"
                env_file_path="$env_file"
            fi

            execute_push "$vault" "$env_item" "" "$env_file_path" || log_warning "Failed to push $env_file_path"
            echo ""
        done

        # Offer template generation for first environment
        local first_env
        first_env=$(echo "$envs" | awk '{print $1}')
        if prompt_yes_no "Generate .env.op template for ${item}-${first_env}?" "y"; then
            echo ""
            local output_file=".env.${first_env}.op"
            generate_template "$vault" "${item}-${first_env}" "" "$output_file" || true
        fi

        echo ""
        display_success_summary "$vault" "$item" "" "items"

    elif [[ "$strategy" == "sections" ]]; then
        # Sections strategy
        log_header "Step 5: Environment Setup (Sections)"
        echo ""

        local envs
        envs=$(prompt_environment_names) || exit 1
        echo ""

        log_info "Summary:"
        echo "  Vault:        $vault"
        echo "  Item:         $item"
        echo "  Environments: $envs (as sections)"
        echo "  .env file:    $env_file"
        echo ""

        log_info "This will create one item with sections for each environment:"
        echo "  Item: $item"
        for env in $envs; do
            echo "    └─ Section: $env"
        done
        echo ""

        if ! prompt_yes_no "Proceed with push?" "y"; then
            log_warning "Setup cancelled."
            exit 0
        fi

        echo ""

        # Push to each section
        for env in $envs; do
            local env_file_path=".env.${env}"

            # Check if environment-specific file exists, otherwise use base file
            if [[ ! -f "$env_file_path" ]]; then
                log_warning "File $env_file_path not found, using $env_file for section $env"
                env_file_path="$env_file"
            fi

            execute_push "$vault" "$item" "$env" "$env_file_path" || log_warning "Failed to push $env_file_path to section $env"
            echo ""
        done

        # Offer template generation for first environment
        local first_env
        first_env=$(echo "$envs" | awk '{print $1}')
        if prompt_yes_no "Generate .env.op template for section $first_env?" "y"; then
            echo ""
            local output_file=".env.${first_env}.op"
            generate_template "$vault" "$item" "$first_env" "$output_file" || true
        fi

        echo ""
        display_success_summary "$vault" "$item" "$first_env" "sections"
    fi
}

# If script is run directly (not sourced), execute main function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    init_vault_wizard "$@"
fi
