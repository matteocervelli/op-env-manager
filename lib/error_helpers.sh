#!/usr/bin/env bash
# Error helper utilities for op-env-manager
# Provides centralized error diagnostics and actionable suggestions

# Source logger if not already loaded
if [[ -z "${RED:-}" ]]; then
    # shellcheck source=lib/logger.sh
    source "${LIB_DIR:-$(dirname "$0")}/logger.sh"
fi

# Suggest signing in to 1Password CLI
suggest_signin() {
    local context="${1:-}"

    echo "" >&2
    log_suggestion "To sign in to 1Password CLI:"
    log_command "op signin"
    echo "" >&2

    # Detect CI/CD context
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || [[ -n "${GITLAB_CI:-}" ]] || [[ "$context" == "ci" ]]; then
        log_troubleshoot "For CI/CD environments, use a Service Account token:"
        log_command "export OP_SERVICE_ACCOUNT_TOKEN=\"your-token\""
        echo "" >&2
    fi

    log_info "Need help? See: docs/1PASSWORD_SETUP.md"
}

# Suggest listing available vaults
suggest_vault_list() {
    local vault_name="${1:-}"

    echo "" >&2
    log_suggestion "To list available vaults:"
    log_command "op vault list"
    echo "" >&2

    if [[ -n "$vault_name" ]]; then
        log_troubleshoot "Note: Vault names are case-sensitive"
        log_info "Check that \"$vault_name\" matches exactly (including capitalization)"
        echo "" >&2
    fi

    # Try to list vaults if authenticated
    if command -v op &> /dev/null && op account list &> /dev/null 2>&1; then
        local vaults
        vaults=$(op vault list --format=json 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")

        if [[ -n "$vaults" ]]; then
            log_info "Available vaults:"
            while IFS= read -r vault; do
                if [[ -n "$vault" ]]; then
                    echo "    - $vault" >&2
                fi
            done <<< "$vaults"
            echo "" >&2
        fi
    fi
}

# Suggest push command to create item
suggest_item_push() {
    local vault="${1}"
    local item="${2}"
    local env_file="${3:-.env}"

    echo "" >&2
    log_suggestion "Did you push your .env file first?"
    log_command "op-env-manager push --vault=\"$vault\" --item=\"$item\" --env=\"$env_file\""
    echo "" >&2

    log_troubleshoot "To see what's in this vault:"
    log_command "op item list --vault=\"$vault\" --tags=\"op-env-manager\""
    echo "" >&2
}

# Suggest listing items in vault
suggest_item_list() {
    local vault="${1}"
    local item_prefix="${2:-}"

    echo "" >&2
    log_suggestion "To list items in vault \"$vault\":"

    if [[ -n "$item_prefix" ]]; then
        log_command "op item list --vault=\"$vault\" --tags=\"op-env-manager,$item_prefix\""
    else
        log_command "op item list --vault=\"$vault\" --tags=\"op-env-manager\""
    fi
    echo "" >&2
}

# Check if op CLI is installed
check_op_installed() {
    if ! command -v op &> /dev/null; then
        log_error "1Password CLI (op) is not installed"
        echo "" >&2
        log_suggestion "Install 1Password CLI:"
        log_command "# macOS"
        log_command "brew install 1password-cli"
        echo "" >&2
        log_command "# Ubuntu/Debian"
        log_command "curl -sS https://downloads.1password.com/linux/keys/1password.asc | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg"
        log_command "echo 'deb [signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main' | sudo tee /etc/apt/sources.list.d/1password.list"
        log_command "sudo apt update && sudo apt install 1password-cli"
        echo "" >&2
        log_info "More info: https://developer.1password.com/docs/cli/get-started/"
        return 1
    fi
    return 0
}

# Check if authenticated to 1Password CLI
check_op_authenticated() {
    if ! op account list &> /dev/null; then
        log_error "Not signed in to 1Password CLI"
        suggest_signin
        return 1
    fi
    return 0
}

# Diagnose op CLI installation and authentication
diagnose_op_cli() {
    check_op_installed || return 1
    check_op_authenticated || return 1
    return 0
}

# Check if vault exists (requires authentication)
check_vault_exists() {
    local vault="$1"

    if ! op vault get "$vault" &> /dev/null; then
        log_error "Vault not found: $vault"
        suggest_vault_list "$vault"
        return 1
    fi
    return 0
}

# Suggest fixing file not found error
suggest_file_check() {
    local file_path="$1"

    echo "" >&2
    log_suggestion "Check the file path:"
    log_command "ls -la \"$file_path\""
    echo "" >&2

    log_troubleshoot "Current directory:"
    log_command "pwd"
    echo "" >&2

    log_info "Tip: Use absolute paths or check you're in the correct directory"
}

# Suggest fixing permission errors
suggest_permission_fix() {
    local file_path="$1"

    echo "" >&2
    log_suggestion "Fix file permissions:"
    log_command "chmod 600 \"$file_path\""
    echo "" >&2

    log_info "Note: Secret files should be readable only by owner (600)"
}

# Format multi-step troubleshooting guide
format_troubleshooting_steps() {
    local title="$1"
    shift
    local steps=("$@")

    echo "" >&2
    log_troubleshoot "$title"
    local i=1
    for step in "${steps[@]}"; do
        echo "    $i. $step" >&2
        ((i++))
    done
    echo "" >&2
}

# Suggest network/timeout troubleshooting
suggest_network_check() {
    echo "" >&2
    log_suggestion "Try these steps:"
    echo "    1. Check your internet connection" >&2
    echo "    2. Retry the command" >&2
    echo "    3. Use --dry-run to test without network calls" >&2
    echo "" >&2

    log_troubleshoot "If timeout persists:"
    log_command "# Check 1Password service status"
    log_command "op account list"
    echo "" >&2
}

# Suggest op:// reference format
suggest_op_reference_format() {
    local vault="${1:-VAULT}"
    local item="${2:-ITEM}"
    local field="${3:-FIELD}"

    echo "" >&2
    log_suggestion "Correct op:// reference format:"
    log_command "op://$vault/$item/$field"
    echo "" >&2

    log_troubleshoot "Examples:"
    log_command "op://Personal/myapp-API_KEY/password"
    log_command "op://Production/myapp_prod-DATABASE_URL/password"
    echo "" >&2

    log_info "Test reference resolution:"
    log_command "op read \"op://$vault/$item/$field\""
    echo "" >&2
}

# Suggest section troubleshooting
suggest_section_check() {
    local vault="$1"
    local item="$2"
    local section="${3:-}"

    echo "" >&2
    if [[ -n "$section" ]]; then
        log_suggestion "Section \"$section\" not found"
        echo "" >&2
        log_troubleshoot "Check available sections:"
    else
        log_suggestion "To list sections in item:"
    fi

    log_command "op item get \"$item\" --vault=\"$vault\" --format=json | jq '.fields[] | select(.section) | .section.label' | sort -u"
    echo "" >&2

    if [[ -n "$section" ]]; then
        log_info "Note: Section names are case-sensitive"
    fi
}

# Suggest similar command when unknown command is used
suggest_similar_command() {
    local unknown_cmd="$1"
    local valid_commands=("push" "inject" "run" "convert" "template")

    echo "" >&2
    log_suggestion "Did you mean one of these?"
    for cmd in "${valid_commands[@]}"; do
        echo "    - $cmd" >&2
    done
    echo "" >&2

    log_info "For help:"
    log_command "op-env-manager --help"
    log_command "op-env-manager $unknown_cmd --help"
    echo "" >&2
}

# Suggest checking 1Password field limits
suggest_field_limits() {
    echo "" >&2
    log_warning "1Password has field size limits:"
    echo "    - Field name: 255 characters max" >&2
    echo "    - Field value: 64KB max" >&2
    echo "" >&2

    log_suggestion "For large values, consider:"
    echo "    1. Split into multiple environment variables" >&2
    echo "    2. Store in a separate file and reference the file path" >&2
    echo "    3. Use a secrets file manager for large configs" >&2
    echo "" >&2
}

# Show empty output explanation
explain_empty_result() {
    local context="$1"

    echo "" >&2
    log_warning "No $context found"
    echo "" >&2
}
