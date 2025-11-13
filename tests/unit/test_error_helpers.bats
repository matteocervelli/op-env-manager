#!/usr/bin/env bats

# Unit tests for error helper functions

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

# Setup - source the error helpers
setup() {
    # Set up lib directory
    export LIB_DIR="$(cd "${BATS_TEST_DIRNAME}/../../lib" && pwd)"

    # Source logger first (dependency)
    source "$LIB_DIR/logger.sh"

    # Source error helpers
    source "$LIB_DIR/error_helpers.sh"
}

# Test: check_op_installed when op is not installed
@test "check_op_installed fails when op CLI not installed" {
    # Mock op command to simulate not installed
    function op() { return 127; }
    export -f op

    # Redirect stderr to capture error messages
    run check_op_installed

    assert_failure
    assert_output --partial "1Password CLI (op) is not installed"
}

# Test: check_op_installed when op is installed
@test "check_op_installed succeeds when op CLI installed" {
    # Skip if op not actually installed
    if ! command -v op &> /dev/null; then
        skip "1Password CLI not installed in test environment"
    fi

    run check_op_installed

    assert_success
}

# Test: suggest_signin output format
@test "suggest_signin outputs signin command" {
    run suggest_signin

    assert_output --partial "op signin"
    assert_output --partial "To sign in to 1Password CLI:"
}

# Test: suggest_signin CI context detection
@test "suggest_signin detects CI environment" {
    export CI=true

    run suggest_signin

    assert_output --partial "Service Account token"
    assert_output --partial "OP_SERVICE_ACCOUNT_TOKEN"

    unset CI
}

# Test: suggest_vault_list output format
@test "suggest_vault_list outputs vault list command" {
    run suggest_vault_list "TestVault"

    assert_output --partial "op vault list"
    assert_output --partial "case-sensitive"
}

# Test: suggest_item_push output format
@test "suggest_item_push outputs correct push command" {
    run suggest_item_push "TestVault" "testitem" ".env"

    assert_output --partial "op-env-manager push"
    assert_output --partial "--vault=\"TestVault\""
    assert_output --partial "--item=\"testitem\""
}

# Test: suggest_file_check output
@test "suggest_file_check outputs file check commands" {
    run suggest_file_check "/path/to/missing.env"

    assert_output --partial "ls -la"
    assert_output --partial "/path/to/missing.env"
    assert_output --partial "pwd"
}

# Test: suggest_permission_fix output
@test "suggest_permission_fix outputs chmod command" {
    run suggest_permission_fix "/path/to/file.env"

    assert_output --partial "chmod 600"
    assert_output --partial "/path/to/file.env"
}

# Test: suggest_op_reference_format output
@test "suggest_op_reference_format shows correct format" {
    run suggest_op_reference_format "TestVault" "testitem" "API_KEY"

    assert_output --partial "op://TestVault/testitem/API_KEY"
    assert_output --partial "Correct op:// reference format:"
}

# Test: suggest_network_check output
@test "suggest_network_check provides troubleshooting steps" {
    run suggest_network_check

    assert_output --partial "internet connection"
    assert_output --partial "Retry the command"
    assert_output --partial "--dry-run"
}

# Test: suggest_field_limits output
@test "suggest_field_limits explains 1Password limits" {
    run suggest_field_limits

    assert_output --partial "255 characters"
    assert_output --partial "64KB"
    assert_output --partial "field size limits"
}

# Test: suggest_section_check output
@test "suggest_section_check provides section commands" {
    run suggest_section_check "TestVault" "testitem" "production"

    assert_output --partial "op item get \"testitem\""
    assert_output --partial "--vault=\"TestVault\""
    assert_output --partial "production"
}

# Test: suggest_similar_command output
@test "suggest_similar_command lists valid commands" {
    run suggest_similar_command "psh"

    assert_output --partial "push"
    assert_output --partial "inject"
    assert_output --partial "run"
    assert_output --partial "convert"
    assert_output --partial "template"
}

# Test: check_op_authenticated when not signed in
@test "check_op_authenticated fails when not signed in" {
    # Mock op command to simulate not authenticated
    function op() {
        if [[ "$1" == "account" ]]; then
            return 1
        fi
    }
    export -f op

    run check_op_authenticated

    assert_failure
    assert_output --partial "Not signed in to 1Password CLI"
}
