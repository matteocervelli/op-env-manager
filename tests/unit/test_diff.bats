#!/usr/bin/env bats
# Unit tests for lib/diff.sh
# Tests comparison functions and diff logic

load ../test_helper/common

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup() {
    verify_test_environment
    setup_temp_dir
    source "$LIB_DIR/diff.sh"
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Test: Module Exists
# =============================================================================

@test "diff.sh exists and is readable" {
    assert_file_exists "$LIB_DIR/diff.sh"
    assert [ -r "$LIB_DIR/diff.sh" ]
}

# =============================================================================
# Test: compare_states Function
# =============================================================================

@test "compare_states detects additions (only in remote)" {
    local local_vars="API_KEY=local123"
    local remote_vars="API_KEY=local123
DATABASE_URL=postgres://localhost/db"

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    # Parse JSON output
    local additions=$(echo "$output" | jq -r '.additions[]')
    assert_equal "$additions" "DATABASE_URL"
}

@test "compare_states detects deletions (only in local)" {
    local local_vars="API_KEY=local123
OLD_VAR=old_value"
    local remote_vars="API_KEY=local123"

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    # Parse JSON output
    local deletions=$(echo "$output" | jq -r '.deletions[]')
    assert_equal "$deletions" "OLD_VAR"
}

@test "compare_states detects modifications (different values)" {
    local local_vars="API_KEY=local123
DATABASE_URL=localhost"
    local remote_vars="API_KEY=local123
DATABASE_URL=production"

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    # Parse JSON output
    local modifications=$(echo "$output" | jq -r '.modifications[]')
    assert_equal "$modifications" "DATABASE_URL"
}

@test "compare_states handles identical states" {
    local local_vars="API_KEY=test123
DATABASE_URL=localhost"
    local remote_vars="API_KEY=test123
DATABASE_URL=localhost"

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    # Should have empty arrays
    local additions=$(echo "$output" | jq -r '.additions[]')
    local deletions=$(echo "$output" | jq -r '.deletions[]')
    local modifications=$(echo "$output" | jq -r '.modifications[]')

    assert_equal "$additions" ""
    assert_equal "$deletions" ""
    assert_equal "$modifications" ""
}

@test "compare_states handles empty local state" {
    local local_vars=""
    local remote_vars="API_KEY=test123
DATABASE_URL=localhost"

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    # All remote vars should be additions
    local additions=$(echo "$output" | jq -r '.additions[]' | wc -l)
    assert_equal "$additions" "2"
}

@test "compare_states handles empty remote state" {
    local local_vars="API_KEY=test123
DATABASE_URL=localhost"
    local remote_vars=""

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    # All local vars should be deletions
    local deletions=$(echo "$output" | jq -r '.deletions[]' | wc -l)
    assert_equal "$deletions" "2"
}

@test "compare_states handles mixed changes" {
    local local_vars="API_KEY=local123
DATABASE_URL=localhost
OLD_VAR=old"
    local remote_vars="API_KEY=remote123
DATABASE_URL=localhost
NEW_VAR=new"

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    # Parse JSON output
    local additions=$(echo "$output" | jq -r '.additions[]')
    local deletions=$(echo "$output" | jq -r '.deletions[]')
    local modifications=$(echo "$output" | jq -r '.modifications[]')

    assert_equal "$additions" "NEW_VAR"
    assert_equal "$deletions" "OLD_VAR"
    assert_equal "$modifications" "API_KEY"
}

@test "compare_states handles multiline values" {
    local local_vars='PRIVATE_KEY=-----BEGIN KEY-----\nMIIE...\n-----END KEY-----'
    local remote_vars='PRIVATE_KEY=-----BEGIN KEY-----\nDIFFERENT...\n-----END KEY-----'

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    # Should detect modification
    local modifications=$(echo "$output" | jq -r '.modifications[]')
    assert_equal "$modifications" "PRIVATE_KEY"
}

@test "compare_states handles special characters in keys" {
    local local_vars="MY_VAR_123=value1
ANOTHER-VAR=value2"
    local remote_vars="MY_VAR_123=value1
ANOTHER-VAR=different"

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    local modifications=$(echo "$output" | jq -r '.modifications[]')
    assert_equal "$modifications" "ANOTHER-VAR"
}

# =============================================================================
# Test: Command Line Argument Parsing
# =============================================================================

@test "diff requires --vault argument" {
    run bash -c "source '$LIB_DIR/diff.sh' && parse_args --env-file=.env"
    assert_failure
}

@test "diff accepts --vault with equals syntax" {
    run bash -c "source '$LIB_DIR/diff.sh' && parse_args --vault=\"Personal\" --env-file=.env"
    assert_success
}

@test "diff accepts --vault with space syntax" {
    run bash -c "source '$LIB_DIR/diff.sh' && parse_args --vault Personal --env-file=.env"
    assert_success
}

@test "diff accepts --dry-run flag" {
    run bash -c "source '$LIB_DIR/diff.sh' && parse_args --vault=Test --dry-run && echo \$DRY_RUN"
    assert_success
    assert_output --regexp "true"
}

@test "diff uses default item name when not specified" {
    run bash -c "source '$LIB_DIR/diff.sh' && parse_args --vault=Test && echo \$ITEM_NAME"
    assert_success
    assert_output "env-secrets"
}

@test "diff accepts custom item name" {
    run bash -c "source '$LIB_DIR/diff.sh' && parse_args --vault=Test --item=myapp && echo \$ITEM_NAME"
    assert_success
    assert_output "myapp"
}

@test "diff accepts section parameter" {
    run bash -c "source '$LIB_DIR/diff.sh' && parse_args --vault=Test --section=dev && echo \$SECTION"
    assert_success
    assert_output "dev"
}

# =============================================================================
# Test: Color Output Functions
# =============================================================================

@test "log_color_green produces colored output when NO_COLOR not set" {
    unset NO_COLOR
    run log_color_green "test"
    assert_success
    assert_output --regexp "\033\[0;32mtest\033\[0m"
}

@test "log_color_green produces plain output when NO_COLOR=1" {
    NO_COLOR=1
    run log_color_green "test"
    assert_success
    assert_output "test"
}

@test "log_color_red produces colored output when NO_COLOR not set" {
    unset NO_COLOR
    run log_color_red "test"
    assert_success
    assert_output --regexp "\033\[0;31mtest\033\[0m"
}

@test "log_color_yellow produces colored output when NO_COLOR not set" {
    unset NO_COLOR
    run log_color_yellow "test"
    assert_success
    assert_output --regexp "\033\[0;33mtest\033\[0m"
}

@test "log_color_cyan produces colored output when NO_COLOR not set" {
    unset NO_COLOR
    run log_color_cyan "test"
    assert_success
    assert_output --regexp "\033\[0;36mtest\033\[0m"
}

# =============================================================================
# Test: Edge Cases
# =============================================================================

@test "compare_states handles variables with equals sign in value" {
    local local_vars="URL=https://example.com?key=value"
    local remote_vars="URL=https://example.com?key=different"

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    local modifications=$(echo "$output" | jq -r '.modifications[]')
    assert_equal "$modifications" "URL"
}

@test "compare_states handles empty values" {
    local local_vars="EMPTY_VAR="
    local remote_vars="EMPTY_VAR=value"

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    local modifications=$(echo "$output" | jq -r '.modifications[]')
    assert_equal "$modifications" "EMPTY_VAR"
}

@test "compare_states handles whitespace in values" {
    local local_vars="VAR=value with spaces"
    local remote_vars="VAR=value with  different  spaces"

    run compare_states "$local_vars" "$remote_vars"
    assert_success

    local modifications=$(echo "$output" | jq -r '.modifications[]')
    assert_equal "$modifications" "VAR"
}
