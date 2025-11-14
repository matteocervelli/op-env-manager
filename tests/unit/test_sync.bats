#!/usr/bin/env bats
# Unit tests for lib/sync.sh
# Tests sync functions, state management, and conflict resolution

load ../test_helper/common

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup() {
    verify_test_environment
    setup_temp_dir
    source "$LIB_DIR/sync.sh"
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Test: Module Exists
# =============================================================================

@test "sync.sh exists and is readable" {
    assert_file_exists "$LIB_DIR/sync.sh"
    assert [ -r "$LIB_DIR/sync.sh" ]
}

# =============================================================================
# Test: State Management Functions
# =============================================================================

@test "compute_checksum produces consistent output" {
    local value="test_value_123"

    local checksum1=$(compute_checksum "$value")
    local checksum2=$(compute_checksum "$value")

    assert_equal "$checksum1" "$checksum2"
}

@test "compute_checksum produces different output for different values" {
    local checksum1=$(compute_checksum "value1")
    local checksum2=$(compute_checksum "value2")

    assert_not_equal "$checksum1" "$checksum2"
}

@test "compute_checksum handles empty string" {
    run compute_checksum ""
    assert_success
    assert_output --regexp "[0-9a-f]{64}"
}

@test "compute_checksum handles multiline values" {
    local multiline="line1
line2
line3"

    run compute_checksum "$multiline"
    assert_success
    assert_output --regexp "[0-9a-f]{64}"
}

@test "load_sync_state returns empty JSON for non-existent file" {
    local state_file="$TEST_TEMP_DIR/nonexistent.state"

    run load_sync_state "$state_file"
    assert_success
    assert_output "{}"
}

@test "load_sync_state reads existing state file" {
    local state_file="$TEST_TEMP_DIR/test.state"

    cat > "$state_file" << 'EOF'
{
  "version": "1.0",
  "vault": "Personal",
  "item": "myapp",
  "last_sync": "2024-01-01T00:00:00Z"
}
EOF

    run load_sync_state "$state_file"
    assert_success
    assert_output --regexp '"version".*"1.0"'
    assert_output --regexp '"vault".*"Personal"'
}

@test "save_sync_state creates valid JSON file" {
    local state_file="$TEST_TEMP_DIR/test.state"
    local checksums_json='{"API_KEY":"abc123","DATABASE_URL":"def456"}'

    save_sync_state "$state_file" "Personal" "myapp" "dev" "$checksums_json"

    assert_file_exists "$state_file"

    # Verify JSON is valid
    run jq -r '.version' "$state_file"
    assert_success
    assert_output "1.0"

    run jq -r '.vault' "$state_file"
    assert_success
    assert_output "Personal"

    run jq -r '.checksums.API_KEY' "$state_file"
    assert_success
    assert_output "abc123"
}

@test "save_sync_state sets file permissions to 600" {
    local state_file="$TEST_TEMP_DIR/test.state"
    local checksums_json='{}'

    save_sync_state "$state_file" "Personal" "myapp" "" "$checksums_json"

    assert_file_permissions "$state_file" 600
}

@test "build_checksums_json creates valid JSON" {
    local vars="API_KEY=test123
DATABASE_URL=localhost"

    run build_checksums_json "$vars"
    assert_success

    # Should be valid JSON
    echo "$output" | jq . > /dev/null
}

@test "build_checksums_json handles empty input" {
    run build_checksums_json ""
    assert_success
    assert_output "{}"
}

@test "build_checksums_json handles single variable" {
    local vars="API_KEY=test123"

    run build_checksums_json "$vars"
    assert_success
    assert_output --regexp '"API_KEY".*"[0-9a-f]{64}"'
}

# =============================================================================
# Test: Backup Functions
# =============================================================================

@test "backup_env_file creates backup directory" {
    local env_file="$TEST_TEMP_DIR/.env"
    echo "API_KEY=test123" > "$env_file"

    backup_env_file "$env_file"

    assert [ -d "$TEST_TEMP_DIR/.op-env-manager/backups" ]
}

@test "backup_env_file creates timestamped backup" {
    local env_file="$TEST_TEMP_DIR/.env"
    echo "API_KEY=test123" > "$env_file"

    backup_env_file "$env_file"

    # Check backup was created with timestamp pattern
    local backup_count=$(ls "$TEST_TEMP_DIR/.op-env-manager/backups/.env."*.bak 2>/dev/null | wc -l)
    assert [ "$backup_count" -eq 1 ]
}

@test "backup_env_file preserves file contents" {
    local env_file="$TEST_TEMP_DIR/.env"
    echo "API_KEY=test123" > "$env_file"

    backup_env_file "$env_file"

    local backup_file=$(ls "$TEST_TEMP_DIR/.op-env-manager/backups/.env."*.bak | head -1)
    local backup_content=$(cat "$backup_file")

    assert_equal "$backup_content" "API_KEY=test123"
}

@test "backup_env_file sets backup permissions to 600" {
    local env_file="$TEST_TEMP_DIR/.env"
    echo "API_KEY=test123" > "$env_file"

    backup_env_file "$env_file"

    local backup_file=$(ls "$TEST_TEMP_DIR/.op-env-manager/backups/.env."*.bak | head -1)
    assert_file_permissions "$backup_file" 600
}

@test "backup_env_file handles non-existent file gracefully" {
    local env_file="$TEST_TEMP_DIR/nonexistent.env"

    run backup_env_file "$env_file"
    assert_success
}

# =============================================================================
# Test: Conflict Resolution
# =============================================================================

@test "resolve_conflict with 'ours' strategy returns local" {
    run resolve_conflict "API_KEY" "local_value" "remote_value" "ours"
    assert_success
    assert_output "local"
}

@test "resolve_conflict with 'theirs' strategy returns remote" {
    run resolve_conflict "API_KEY" "local_value" "remote_value" "theirs"
    assert_success
    assert_output "remote"
}

@test "resolve_conflict with 'newest' strategy returns remote" {
    # 'newest' currently defaults to remote (1Password has version history)
    run resolve_conflict "API_KEY" "local_value" "remote_value" "newest"
    assert_success
    assert_output "remote"
}

# Note: interactive strategy requires user input, tested in integration tests

# =============================================================================
# Test: Merge and Write Functions
# =============================================================================

@test "merge_and_write creates output file" {
    local merged_vars="API_KEY=test123
DATABASE_URL=localhost"
    local output_file="$TEST_TEMP_DIR/output.env"

    merge_and_write "$merged_vars" "$output_file"

    assert_file_exists "$output_file"
}

@test "merge_and_write preserves variable content" {
    local merged_vars="API_KEY=test123
DATABASE_URL=localhost"
    local output_file="$TEST_TEMP_DIR/output.env"

    merge_and_write "$merged_vars" "$output_file"

    run cat "$output_file"
    assert_success
    assert_line --index 0 "API_KEY=test123"
    assert_line --index 1 "DATABASE_URL=localhost"
}

@test "merge_and_write wraps multiline values in quotes" {
    local merged_vars='PRIVATE_KEY=-----BEGIN KEY-----\nMIIE...\n-----END KEY-----'
    local output_file="$TEST_TEMP_DIR/output.env"

    merge_and_write "$merged_vars" "$output_file"

    run cat "$output_file"
    assert_success
    assert_output --regexp 'PRIVATE_KEY=".*"'
}

@test "merge_and_write sets file permissions to 600" {
    local merged_vars="API_KEY=test123"
    local output_file="$TEST_TEMP_DIR/output.env"

    merge_and_write "$merged_vars" "$output_file"

    assert_file_permissions "$output_file" 600
}

@test "merge_and_write handles empty input" {
    local merged_vars=""
    local output_file="$TEST_TEMP_DIR/output.env"

    merge_and_write "$merged_vars" "$output_file"

    assert_file_exists "$output_file"
    run cat "$output_file"
    assert_success
    assert_output ""
}

@test "merge_and_write handles values with spaces" {
    local merged_vars="MESSAGE=hello world"
    local output_file="$TEST_TEMP_DIR/output.env"

    merge_and_write "$merged_vars" "$output_file"

    run cat "$output_file"
    assert_success
    assert_output 'MESSAGE="hello world"'
}

# =============================================================================
# Test: Command Line Argument Parsing
# =============================================================================

@test "sync requires --vault argument" {
    run bash -c "source '$LIB_DIR/sync.sh' && parse_args --env-file=.env"
    assert_failure
}

@test "sync accepts valid conflict strategies" {
    for strategy in interactive ours theirs newest; do
        run bash -c "source '$LIB_DIR/sync.sh' && parse_args --vault=Test --strategy=$strategy && echo \$CONFLICT_STRATEGY"
        assert_success
        assert_output "$strategy"
    done
}

@test "sync rejects invalid conflict strategy" {
    run bash -c "source '$LIB_DIR/sync.sh' && parse_args --vault=Test --strategy=invalid"
    assert_failure
}

@test "sync uses 'interactive' as default strategy" {
    run bash -c "source '$LIB_DIR/sync.sh' && parse_args --vault=Test && echo \$CONFLICT_STRATEGY"
    assert_success
    assert_output "interactive"
}

@test "sync accepts --no-backup flag" {
    run bash -c "source '$LIB_DIR/sync.sh' && parse_args --vault=Test --no-backup && echo \$NO_BACKUP"
    assert_success
    assert_output "true"
}

@test "sync enables backup by default" {
    run bash -c "source '$LIB_DIR/sync.sh' && parse_args --vault=Test && echo \$NO_BACKUP"
    assert_success
    assert_output "false"
}

@test "sync accepts --dry-run flag" {
    run bash -c "source '$LIB_DIR/sync.sh' && parse_args --vault=Test --dry-run && echo \$DRY_RUN"
    assert_success
    assert_output "true"
}

@test "sync sets state file path based on env file directory" {
    run bash -c "source '$LIB_DIR/sync.sh' && parse_args --vault=Test --env-file=/path/to/.env && echo \$STATE_FILE"
    assert_success
    assert_output "/path/to/.op-env-manager.state"
}

@test "sync accepts section parameter" {
    run bash -c "source '$LIB_DIR/sync.sh' && parse_args --vault=Test --section=prod && echo \$SECTION"
    assert_success
    assert_output "prod"
}

# =============================================================================
# Test: Edge Cases
# =============================================================================

@test "compute_checksum handles special characters" {
    local value='special!@#$%^&*()characters'

    run compute_checksum "$value"
    assert_success
    assert_output --regexp "[0-9a-f]{64}"
}

@test "build_checksums_json escapes quotes in keys" {
    local vars='MY"KEY=value'

    run build_checksums_json "$vars"
    assert_success

    # Should be valid JSON
    echo "$output" | jq . > /dev/null
}

@test "merge_and_write handles equals signs in values" {
    local merged_vars="URL=https://example.com?key=value"
    local output_file="$TEST_TEMP_DIR/output.env"

    merge_and_write "$merged_vars" "$output_file"

    run cat "$output_file"
    assert_success
    assert_output "URL=https://example.com?key=value"
}
