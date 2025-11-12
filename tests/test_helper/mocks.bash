#!/usr/bin/env bash
# Mock implementations for 1Password CLI and other external dependencies
# Used when MOCK_OP=true environment variable is set

# Strict bash settings
set -euo pipefail

# =============================================================================
# Mock Response Fixtures
# =============================================================================

# Mock response for: op account list
mock_op_account_list() {
    cat << 'JSONEOF'
[
  {
    "shorthand": "personal",
    "url": "https://my.1password.com",
    "email": "user@example.com",
    "userUUID": "testuuid12345"
  }
]
JSONEOF
}

# Mock response for: op vault list
mock_op_vault_list() {
    cat << 'JSONEOF'
[
  {
    "id": "vault123",
    "type": "USER_OWNED",
    "name": "Personal",
    "content_version": 100,
    "items": 50,
    "created_at": "2023-01-01T00:00:00Z",
    "updated_at": "2024-01-01T00:00:00Z"
  },
  {
    "id": "vault456",
    "type": "USER_OWNED",
    "name": "Work",
    "content_version": 200,
    "items": 75,
    "created_at": "2023-01-01T00:00:00Z",
    "updated_at": "2024-01-01T00:00:00Z"
  }
]
JSONEOF
}

# Mock response for: op item list with filters
mock_op_item_list() {
    local vault="$1"
    local tags="$2"

    cat << JSONEOF
[
  {
    "id": "item123",
    "title": "myapp",
    "version": 1,
    "vault": {
      "id": "vault123",
      "name": "$vault"
    },
    "category": "SECURE_NOTE",
    "last_edited_by": "user123",
    "created_at": "2023-01-01T00:00:00Z",
    "updated_at": "2024-01-01T00:00:00Z",
    "additional_information": "$tags"
  }
]
JSONEOF
}

# Mock response for: op item get with fields
mock_op_item_get_with_fields() {
    local item_name="$1"
    local section="${2:-}"

    if [[ -z "$section" ]]; then
        cat << JSONEOF
{
  "id": "item123",
  "title": "$item_name",
  "version": 1,
  "vault": {
    "id": "vault123",
    "name": "Personal"
  },
  "category": "SECURE_NOTE",
  "created_at": "2023-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z",
  "fields": [
    {
      "id": "field1",
      "type": "concealed",
      "label": "DATABASE_URL",
      "value": "postgresql://user:pass@localhost/testdb",
      "section": null
    },
    {
      "id": "field2",
      "type": "concealed",
      "label": "API_KEY",
      "value": "test_api_key_123",
      "section": null
    }
  ]
}
JSONEOF
    else
        # Return fields for specific section
        cat << JSONEOF
{
  "id": "item123",
  "title": "$item_name",
  "version": 1,
  "vault": {
    "id": "vault123",
    "name": "Personal"
  },
  "category": "SECURE_NOTE",
  "created_at": "2023-01-01T00:00:00Z",
  "updated_at": "2024-01-01T00:00:00Z",
  "fields": [
    {
      "id": "field1",
      "type": "concealed",
      "label": "API_KEY",
      "value": "test_api_key_prod",
      "section": {
        "id": "section1",
        "label": "$section"
      }
    }
  ]
}
JSONEOF
    fi
}

# =============================================================================
# Mock op Command Implementation
# =============================================================================

# Main mock op CLI command
mock_op() {
    local subcommand="${1:-}"

    case "$subcommand" in
        account)
            if [[ "${2:-}" == "list" ]]; then
                mock_op_account_list
                return 0
            fi
            ;;
        vault)
            if [[ "${2:-}" == "list" ]]; then
                mock_op_vault_list
                return 0
            fi
            ;;
        item)
            case "${2:-}" in
                list)
                    # Parse arguments for vault and tags
                    local vault=""
                    local tags=""
                    while [[ $# -gt 0 ]]; do
                        case $1 in
                            --vault)
                                vault="$2"
                                shift 2
                                ;;
                            --tags)
                                tags="$2"
                                shift 2
                                ;;
                            *)
                                shift
                                ;;
                        esac
                    done
                    mock_op_item_list "$vault" "$tags"
                    return 0
                    ;;
                get)
                    # Get item by title
                    local item_name="${3:-}"
                    local section=""
                    while [[ $# -gt 3 ]]; do
                        shift
                        if [[ "$1" == "--format" && "${2:-}" == "json" ]]; then
                            shift 2
                        fi
                    done
                    mock_op_item_get_with_fields "$item_name" "$section"
                    return 0
                    ;;
                create|edit)
                    # Mock successful item creation/update
                    echo "{\"id\":\"item123\",\"title\":\"${3:-}\",\"version\":1}"
                    return 0
                    ;;
            esac
            ;;
        --version)
            echo "2.24.0"
            return 0
            ;;
    esac

    # Default: command not found
    echo "op: unknown command: $subcommand" >&2
    return 1
}

# =============================================================================
# Mock Function Installation
# =============================================================================

# Install mocks by replacing op with mock_op in the PATH
install_mocks() {
    # Create a temporary directory for mock scripts
    local mock_bin_dir
    mock_bin_dir=$(mktemp -d)
    export MOCK_BIN_DIR="$mock_bin_dir"

    # Create a mock op script
    cat > "$mock_bin_dir/op" << 'MOCKEOF'
#!/usr/bin/env bash
# This is a temporary mock op command for testing

# Source the mocks
source "${MOCKS_SOURCE_FILE:-}"

# Call the mock implementation
mock_op "$@"
MOCKEOF

    chmod +x "$mock_bin_dir/op"

    # Prepend mock directory to PATH
    export MOCKS_SOURCE_FILE="${TEST_HELPER_DIR}/mocks.bash"
    export PATH="$mock_bin_dir:$PATH"

    export MOCK_OP="true"
}

# Clean up mocks after test
uninstall_mocks() {
    if [[ -n "${MOCK_BIN_DIR:-}" ]] && [[ -d "$MOCK_BIN_DIR" ]]; then
        rm -rf "$MOCK_BIN_DIR"
    fi
    export MOCK_OP="false"
}

# =============================================================================
# Verification Helpers for Tests
# =============================================================================

# Verify that a mock command was called
verify_mock_called() {
    local command="$1"
    if [[ ! -f "${MOCK_CALL_LOG:-}" ]]; then
        fail "Mock call log not found"
    fi
    
    if ! grep -q "$command" "$MOCK_CALL_LOG"; then
        fail "Mock command '$command' was not called"
    fi
}

# Get mock call count
get_mock_call_count() {
    local command="$1"
    if [[ ! -f "${MOCK_CALL_LOG:-}" ]]; then
        echo 0
        return
    fi
    grep -c "$command" "$MOCK_CALL_LOG" || echo 0
}

# =============================================================================
# Export public interface
# =============================================================================

export -f mock_op
export -f mock_op_account_list
export -f mock_op_vault_list
export -f mock_op_item_list
export -f mock_op_item_get_with_fields
export -f install_mocks
export -f uninstall_mocks
export -f verify_mock_called
export -f get_mock_call_count
