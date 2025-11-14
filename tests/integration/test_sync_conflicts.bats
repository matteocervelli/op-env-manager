#!/usr/bin/env bats
# Integration tests for sync conflict resolution strategies
# Tests all conflict resolution modes

load ../test_helper/common

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup() {
    verify_test_environment
    setup_temp_dir
    enable_mock_mode
    install_mocks
}

teardown() {
    uninstall_mocks
    teardown_temp_dir
}

# =============================================================================
# Test: 'ours' Strategy
# =============================================================================

@test "sync --strategy=ours prefers local values for all conflicts" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "VAR1=local1
VAR2=local2
VAR3=local3" > "$env_file"

    # Mock 1Password with all different values
    mock_op_item_get_with_fields "Test" "env-secrets" "" "VAR1=remote1
VAR2=remote2
VAR3=remote3"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success

    # All local values should be preserved
    run grep "VAR1=local1" "$env_file"
    assert_success

    run grep "VAR2=local2" "$env_file"
    assert_success

    run grep "VAR3=local3" "$env_file"
    assert_success
}

@test "sync --strategy=ours still pulls additions from remote" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "LOCAL_VAR=local" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "LOCAL_VAR=local
REMOTE_ONLY=remote_value"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success

    # Should pull REMOTE_ONLY
    run grep "REMOTE_ONLY=remote_value" "$env_file"
    assert_success
}

@test "sync --strategy=ours still pushes deletions to remote" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "KEEP_VAR=keep" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "KEEP_VAR=keep
DELETE_VAR=should_be_deleted"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
    assert_output --regexp "Removing"
}

# =============================================================================
# Test: 'theirs' Strategy
# =============================================================================

@test "sync --strategy=theirs prefers remote values for all conflicts" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "VAR1=local1
VAR2=local2
VAR3=local3" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "VAR1=remote1
VAR2=remote2
VAR3=remote3"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=theirs --no-backup

    assert_success

    # All remote values should be used
    run grep "VAR1=remote1" "$env_file"
    assert_success

    run grep "VAR2=remote2" "$env_file"
    assert_success

    run grep "VAR3=remote3" "$env_file"
    assert_success
}

@test "sync --strategy=theirs pulls additions from remote" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "LOCAL_VAR=local" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "LOCAL_VAR=remote
NEW_VAR=new_value"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=theirs --no-backup

    assert_success

    run grep "NEW_VAR=new_value" "$env_file"
    assert_success
}

@test "sync --strategy=theirs removes local-only variables" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "SHARED_VAR=value
LOCAL_ONLY=local" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "SHARED_VAR=value"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=theirs --no-backup

    assert_success

    # LOCAL_ONLY should be removed
    run grep "LOCAL_ONLY" "$env_file"
    assert_failure
}

# =============================================================================
# Test: 'newest' Strategy
# =============================================================================

@test "sync --strategy=newest resolves conflicts automatically" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "VAR1=local1" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "VAR1=remote1"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=newest --no-backup

    assert_success

    # Currently 'newest' defaults to remote (1Password has version history)
    run grep "VAR1=remote1" "$env_file"
    assert_success
}

# =============================================================================
# Test: Conflict Detection
# =============================================================================

@test "sync detects conflicts when values differ" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "CONFLICT_VAR=local_value" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "CONFLICT_VAR=remote_value"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
    assert_output --regexp "Resolving conflicts"
}

@test "sync does not detect conflict when values are identical" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "SAME_VAR=same_value" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "SAME_VAR=same_value"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
    refute_output --regexp "Resolving conflicts"
}

# =============================================================================
# Test: Multiple Conflicts
# =============================================================================

@test "sync handles multiple conflicts with ours strategy" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "CONFLICT1=local1
CONFLICT2=local2
CONFLICT3=local3
SAME_VAR=same" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "CONFLICT1=remote1
CONFLICT2=remote2
CONFLICT3=remote3
SAME_VAR=same"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success

    # All local values should win
    run grep "CONFLICT1=local1" "$env_file"
    assert_success

    run grep "CONFLICT2=local2" "$env_file"
    assert_success

    run grep "CONFLICT3=local3" "$env_file"
    assert_success
}

@test "sync handles multiple conflicts with theirs strategy" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "CONFLICT1=local1
CONFLICT2=local2
CONFLICT3=local3" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "CONFLICT1=remote1
CONFLICT2=remote2
CONFLICT3=remote3"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=theirs --no-backup

    assert_success

    # All remote values should win
    run grep "CONFLICT1=remote1" "$env_file"
    assert_success

    run grep "CONFLICT2=remote2" "$env_file"
    assert_success

    run grep "CONFLICT3=remote3" "$env_file"
    assert_success
}

# =============================================================================
# Test: Special Value Types in Conflicts
# =============================================================================

@test "sync handles multiline value conflicts" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo 'PRIVATE_KEY=-----BEGIN KEY-----\nLOCAL_KEY\n-----END KEY-----' > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" 'PRIVATE_KEY=-----BEGIN KEY-----\nREMOTE_KEY\n-----END KEY-----'

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success

    # Should keep local multiline value
    run grep "LOCAL_KEY" "$env_file"
    assert_success
}

@test "sync handles empty value conflicts" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "EMPTY_VAR=" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "EMPTY_VAR=now_has_value"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=theirs --no-backup

    assert_success

    run grep "EMPTY_VAR=now_has_value" "$env_file"
    assert_success
}

@test "sync handles special characters in conflicting values" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo 'SPECIAL_VAR=local!@#$%^&*()' > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" 'SPECIAL_VAR=remote!@#$%^&*()'

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success

    run grep 'SPECIAL_VAR=local!@#$%^&*()' "$env_file"
    assert_success
}

# =============================================================================
# Test: Conflict Resolution Summary
# =============================================================================

@test "sync reports number of resolved conflicts" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "VAR1=local1
VAR2=local2" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "VAR1=remote1
VAR2=remote2"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
    assert_output --regexp "modifications"
}

@test "sync exits with code 0 when all conflicts resolved" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "CONFLICT=local" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "CONFLICT=remote"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
    assert_equal "$status" "0"
}

# Note: Interactive strategy tests require user input simulation
# These are documented in manual testing checklist rather than automated tests
