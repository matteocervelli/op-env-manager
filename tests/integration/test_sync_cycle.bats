#!/usr/bin/env bats
# Integration tests for sync command - full workflow tests
# Tests complete sync cycles with mocked 1Password

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
# Test: Basic Sync Workflow
# =============================================================================

@test "sync creates state file on first sync" {
    local env_file="$TEST_TEMP_DIR/.env"
    local state_file="$TEST_TEMP_DIR/.op-env-manager.state"

    echo "API_KEY=test123" > "$env_file"

    # Mock 1Password to return same values
    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=test123"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
    assert_file_exists "$state_file"

    # Verify state file structure
    run jq -r '.version' "$state_file"
    assert_success
    assert_output "1.0"
}

@test "sync with no changes exits successfully" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "API_KEY=test123
DATABASE_URL=localhost" > "$env_file"

    # Mock 1Password to return identical values
    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=test123
DATABASE_URL=localhost"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
    assert_output --regexp "No changes detected"
}

@test "sync pulls additions from 1Password" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "API_KEY=test123" > "$env_file"

    # Mock 1Password with additional variable
    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=test123
NEW_VAR=new_value"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=theirs --no-backup

    assert_success

    # Verify NEW_VAR was added to local file
    run grep "NEW_VAR=new_value" "$env_file"
    assert_success
}

@test "sync pushes deletions to 1Password" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "API_KEY=test123" > "$env_file"

    # Mock 1Password with extra variable (that should be deleted)
    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=test123
OLD_VAR=old_value"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
    assert_output --regexp "Removing"
}

@test "sync handles 'ours' strategy for conflicts" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "API_KEY=local_value" > "$env_file"

    # Mock 1Password with different value
    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=remote_value"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success

    # Verify local value was kept
    run grep "API_KEY=local_value" "$env_file"
    assert_success
}

@test "sync handles 'theirs' strategy for conflicts" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "API_KEY=local_value" > "$env_file"

    # Mock 1Password with different value
    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=remote_value"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=theirs --no-backup

    assert_success

    # Verify remote value was used
    run grep "API_KEY=remote_value" "$env_file"
    assert_success
}

# =============================================================================
# Test: Backup Functionality
# =============================================================================

@test "sync creates backup by default" {
    local env_file="$TEST_TEMP_DIR/.env"
    local backup_dir="$TEST_TEMP_DIR/.op-env-manager/backups"

    echo "API_KEY=test123" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=test123"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours

    assert_success
    assert [ -d "$backup_dir" ]

    # Check backup was created
    local backup_count=$(ls "$backup_dir"/.env.*.bak 2>/dev/null | wc -l)
    assert [ "$backup_count" -ge 1 ]
}

@test "sync skips backup with --no-backup flag" {
    local env_file="$TEST_TEMP_DIR/.env"
    local backup_dir="$TEST_TEMP_DIR/.op-env-manager/backups"

    echo "API_KEY=test123" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=test123"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
    assert [ ! -d "$backup_dir" ]
}

# =============================================================================
# Test: State File Management
# =============================================================================

@test "sync updates state file after successful sync" {
    local env_file="$TEST_TEMP_DIR/.env"
    local state_file="$TEST_TEMP_DIR/.op-env-manager.state"

    echo "API_KEY=test123" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=test123"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
    assert_file_exists "$state_file"

    # Verify checksums are stored
    run jq -r '.checksums.API_KEY' "$state_file"
    assert_success
    assert_output --regexp "[0-9a-f]{64}"
}

@test "sync preserves state file permissions" {
    local env_file="$TEST_TEMP_DIR/.env"
    local state_file="$TEST_TEMP_DIR/.op-env-manager.state"

    echo "API_KEY=test123" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=test123"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
    assert_file_permissions "$state_file" 600
}

# =============================================================================
# Test: Section Support
# =============================================================================

@test "sync works with environment sections" {
    local env_file="$TEST_TEMP_DIR/.env.dev"

    echo "API_KEY=dev_key" > "$env_file"

    mock_op_item_get_with_fields "Test" "myapp" "dev" "API_KEY=dev_key"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --item="myapp" --section="dev" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
}

@test "sync updates section-specific state" {
    local env_file="$TEST_TEMP_DIR/.env.prod"
    local state_file="$TEST_TEMP_DIR/.op-env-manager.state"

    echo "API_KEY=prod_key" > "$env_file"

    mock_op_item_get_with_fields "Test" "myapp" "prod" "API_KEY=prod_key"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --item="myapp" --section="prod" --env-file="$env_file" --strategy=ours --no-backup

    assert_success

    # Verify section is stored in state
    run jq -r '.section' "$state_file"
    assert_success
    assert_output "prod"
}

# =============================================================================
# Test: Dry-Run Mode
# =============================================================================

@test "sync --dry-run does not modify files" {
    local env_file="$TEST_TEMP_DIR/.env"
    local original_content="API_KEY=original"

    echo "$original_content" > "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=different"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --dry-run

    assert_success

    # Verify file was not modified
    run cat "$env_file"
    assert_success
    assert_output "$original_content"
}

@test "sync --dry-run does not create state file" {
    local env_file="$TEST_TEMP_DIR/.env"
    local state_file="$TEST_TEMP_DIR/.op-env-manager.state"

    echo "API_KEY=test123" > "$env_file"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --dry-run

    assert_success
    assert [ ! -f "$state_file" ]
}

# =============================================================================
# Test: Error Handling
# =============================================================================

@test "sync fails gracefully when vault not found" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "API_KEY=test123" > "$env_file"

    # Don't mock vault - simulate not found
    run "$BIN_DIR/op-env-manager" sync --vault="NonExistent" --env-file="$env_file" --no-backup

    assert_failure
}

@test "sync handles empty .env file" {
    local env_file="$TEST_TEMP_DIR/.env"

    touch "$env_file"

    mock_op_item_get_with_fields "Test" "env-secrets" "" ""

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
}

@test "sync creates .env file if it doesn't exist" {
    local env_file="$TEST_TEMP_DIR/.env"

    # Don't create env file
    mock_op_item_get_with_fields "Test" "env-secrets" "" "API_KEY=test123"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=theirs --no-backup

    assert_success
    assert_file_exists "$env_file"

    # Verify content was pulled from 1Password
    run grep "API_KEY=test123" "$env_file"
    assert_success
}

# =============================================================================
# Test: Multi-Variable Sync
# =============================================================================

@test "sync handles large number of variables" {
    local env_file="$TEST_TEMP_DIR/.env"

    # Create file with 50 variables
    for i in {1..50}; do
        echo "VAR_$i=value_$i" >> "$env_file"
    done

    # Mock 1Password with same variables
    local mock_vars=""
    for i in {1..50}; do
        mock_vars+="VAR_$i=value_$i"$'\n'
    done

    mock_op_item_get_with_fields "Test" "env-secrets" "" "$mock_vars"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=ours --no-backup

    assert_success
}

@test "sync handles mixed additions, deletions, and modifications" {
    local env_file="$TEST_TEMP_DIR/.env"

    echo "KEEP_VAR=keep
MODIFY_VAR=local_value
DELETE_VAR=delete_me" > "$env_file"

    # Mock 1Password with:
    # - KEEP_VAR same
    # - MODIFY_VAR different
    # - DELETE_VAR missing
    # - ADD_VAR new
    mock_op_item_get_with_fields "Test" "env-secrets" "" "KEEP_VAR=keep
MODIFY_VAR=remote_value
ADD_VAR=new_value"

    run "$BIN_DIR/op-env-manager" sync --vault="Test" --env-file="$env_file" --strategy=theirs --no-backup

    assert_success

    # Verify final state
    run grep "KEEP_VAR=keep" "$env_file"
    assert_success

    run grep "MODIFY_VAR=remote_value" "$env_file"
    assert_success

    run grep "ADD_VAR=new_value" "$env_file"
    assert_success

    run grep "DELETE_VAR" "$env_file"
    assert_failure  # Should be deleted
}
