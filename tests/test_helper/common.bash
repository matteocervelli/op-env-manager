#!/usr/bin/env bash
# Common test helper utilities for op-env-manager tests
# Provides setup, teardown, and helper functions for bats tests

# Strict bash settings
set -euo pipefail

# =============================================================================
# Configuration and Paths
# =============================================================================

# Get the directory where this script is located
TEST_HELPER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Project root is three directories up from test_helper
PROJECT_ROOT="$(cd "$TEST_HELPER_DIR/../../" && pwd)"

# Important directories
export PROJECT_ROOT
export BIN_DIR="$PROJECT_ROOT/bin"
export LIB_DIR="$PROJECT_ROOT/lib"
export FIXTURES_DIR="$PROJECT_ROOT/tests/fixtures"
export TEST_HELPER_DIR

# =============================================================================
# Load bats helper libraries
# =============================================================================

# Load bats support library
# shellcheck source=/dev/null
source "$TEST_HELPER_DIR/bats-support/load.bash"

# Load bats assertions library
# shellcheck source=/dev/null
source "$TEST_HELPER_DIR/bats-assert/load.bash"

# Load bats file helpers
# shellcheck source=/dev/null
source "$TEST_HELPER_DIR/bats-file/load.bash"

# =============================================================================
# Temporary Directory Management
# =============================================================================

# Create a temporary directory for the test
setup_temp_dir() {
    export TEST_TEMP_DIR
    TEST_TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEST_TEMP_DIR"' EXIT
}

# Clean up temporary directory
teardown_temp_dir() {
    if [[ -n "${TEST_TEMP_DIR:-}" ]] && [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# =============================================================================
# Mock Detection and Management
# =============================================================================

# Check if mocks should be used (enabled via MOCK_OP environment variable)
is_mock_mode_enabled() {
    [[ "${MOCK_OP:-}" == "true" ]]
}

# Enable mock mode for a test
enable_mock_mode() {
    export MOCK_OP="true"
}

# Disable mock mode
disable_mock_mode() {
    export MOCK_OP="false"
}

# Get the mock function directory
get_mock_dir() {
    echo "$TEST_HELPER_DIR/mocks"
}

# =============================================================================
# Test Fixtures
# =============================================================================

# Create a temporary .env file for testing
create_test_env_file() {
    local output_file="${1:-.env.test}"
    local content="${2:-}"

    if [[ -z "$content" ]]; then
        # Default test content
        content=$(cat << 'ENVEOF'
# Test environment file
DATABASE_URL=postgresql://user:pass@localhost/testdb
API_KEY=test_api_key_123
DEBUG=true
EMPTY_VALUE=
QUOTED_VALUE="value with spaces"
SINGLE_QUOTED='single quoted value'
ENVEOF
        )
    fi

    echo "$content" > "$output_file"
    echo "$output_file"
}

# Create a test .env file with special characters
create_test_env_special() {
    local output_file="${1:-.env.special}"

    cat > "$output_file" << 'ENVEOF'
PASSWORD="p@ss\$w0rd!"
API_SECRET=abc123!@#$%^&*()
ESCAPED_QUOTE="value with \" escaped quote"
NEWLINE_TEST="line1\nline2"
ENVEOF

    echo "$output_file"
}

# Create a large test .env file with many variables
create_test_env_large() {
    local output_file="${1:-.env.large}"
    local count="${2:-100}"

    {
        echo "# Auto-generated large test file with $count variables"
        for i in $(seq 1 "$count"); do
            printf "VAR_%03d=value_%03d\n" "$i" "$i"
        done
    } > "$output_file"

    echo "$output_file"
}

# Create an empty .env file
create_test_env_empty() {
    local output_file="${1:-.env.empty}"
    touch "$output_file"
    echo "$output_file"
}

# Create a .env file with op:// references
create_test_env_with_references() {
    local output_file="${1:-.env.references}"

    cat > "$output_file" << 'ENVEOF'
DATABASE_URL=postgresql://user:op://vault/item/password@localhost/db
API_KEY=op://vault/item/api_key
CONFIG_SECRET=op://vault/item/production/secret
ENVEOF

    echo "$output_file"
}

# =============================================================================
# Assertion Helpers
# =============================================================================

# Assert that a variable has been exported
assert_exported() {
    local var_name="$1"
    if [[ -z "${!var_name+x}" ]]; then
        fail "Variable '$var_name' was not exported"
    fi
}

# Assert that a file has correct permissions (chmod)
assert_file_permissions() {
    local file="$1"
    local expected_perms="$2"
    local actual_perms
    actual_perms=$(stat -f "%OLp" "$file" 2>/dev/null || stat -c "%a" "$file")
    
    if [[ "$actual_perms" != "$expected_perms" ]]; then
        fail "File '$file' has permissions $actual_perms, expected $expected_perms"
    fi
}

# Assert that a function exists and is callable
assert_function_exists() {
    local func_name="$1"
    if ! declare -f "$func_name" > /dev/null; then
        fail "Function '$func_name' does not exist"
    fi
}

# =============================================================================
# Logging Utilities
# =============================================================================

# Print test debug information
test_debug() {
    local message="$1"
    if [[ "${TEST_DEBUG:-false}" == "true" ]]; then
        echo "[DEBUG] $message" >&3
    fi
}

# Print test information
test_info() {
    local message="$1"
    echo "[INFO] $message" >&3
}

# =============================================================================
# Environment Cleanup
# =============================================================================

# Save the current environment before test
save_environment() {
    export SAVED_ENV_FILE
    SAVED_ENV_FILE=$(mktemp)
    env > "$SAVED_ENV_FILE"
}

# Restore the saved environment
restore_environment() {
    if [[ -n "${SAVED_ENV_FILE:-}" ]] && [[ -f "$SAVED_ENV_FILE" ]]; then
        # This is a simplified restoration - full restoration would be complex
        rm -f "$SAVED_ENV_FILE"
    fi
}

# =============================================================================
# Path and Executable Helpers
# =============================================================================

# Verify that the main executable exists and is executable
assert_main_executable_exists() {
    assert_file_exists "$BIN_DIR/op-env-manager"
    assert [ -x "$BIN_DIR/op-env-manager" ]
}

# Verify that a library file exists
assert_lib_exists() {
    local lib_name="$1"
    assert_file_exists "$LIB_DIR/$lib_name"
}

# =============================================================================
# 1Password CLI Mocking Support
# =============================================================================

# Check if 1Password CLI is actually installed
has_op_cli() {
    command -v op &> /dev/null
}

# Get the path to 1Password CLI
get_op_cli_path() {
    command -v op
}

# Verify 1Password CLI version (requires at least 2.0)
check_op_cli_version() {
    if ! has_op_cli; then
        skip "1Password CLI (op) is not installed"
    fi

    local version
    version=$(op --version 2>&1 | grep -oE '2\.[0-9]+' | head -1)
    if [[ -z "$version" ]]; then
        skip "1Password CLI version 2.0+ required"
    fi
}

# =============================================================================
# Test Pre-flight Checks
# =============================================================================

# Verify test environment is properly set up
verify_test_environment() {
    # Check that project root exists
    if [[ ! -d "$PROJECT_ROOT" ]]; then
        fail "PROJECT_ROOT does not exist: $PROJECT_ROOT"
    fi

    # Check that bin directory exists
    if [[ ! -d "$BIN_DIR" ]]; then
        fail "BIN_DIR does not exist: $BIN_DIR"
    fi

    # Check that lib directory exists
    if [[ ! -d "$LIB_DIR" ]]; then
        fail "LIB_DIR does not exist: $LIB_DIR"
    fi

    # Check that main executable exists
    if [[ ! -f "$BIN_DIR/op-env-manager" ]]; then
        fail "Main executable does not exist: $BIN_DIR/op-env-manager"
    fi
}

# =============================================================================
# Export public interface
# =============================================================================

# These functions are safe to call from test files
export -f setup_temp_dir
export -f teardown_temp_dir
export -f is_mock_mode_enabled
export -f enable_mock_mode
export -f disable_mock_mode
export -f get_mock_dir
export -f create_test_env_file
export -f create_test_env_special
export -f create_test_env_large
export -f create_test_env_empty
export -f create_test_env_with_references
export -f assert_exported
export -f assert_file_permissions
export -f assert_function_exists
export -f test_debug
export -f test_info
export -f save_environment
export -f restore_environment
export -f assert_main_executable_exists
export -f assert_lib_exists
export -f has_op_cli
export -f get_op_cli_path
export -f check_op_cli_version
export -f verify_test_environment
