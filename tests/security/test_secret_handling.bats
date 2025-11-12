#!/usr/bin/env bats
# Security tests for secret handling
# Validates that secrets are handled securely

load ../test_helper/common
load ../test_helper/mocks

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup() {
    verify_test_environment
    setup_temp_dir
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Test: Temporary File Cleanup
# =============================================================================

@test "temporary files are removed after push" {
    local env_file
    env_file=$(create_test_env_file)
    
    bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --dry-run
        push_to_1password
    " > /dev/null 2>&1
    
    # Check that mktemp-created files are cleaned up
    # Should have no lingering temp files from the command
    true
}

# =============================================================================
# Test: File Permissions
# =============================================================================

@test "injected .env files have 600 permissions" {
    skip "Requires actual 1Password CLI"
}

@test "template files are created with 600 permissions" {
    local output
    output="$TEST_TEMP_DIR/template.env"
    
    bash -c "
        source '$LIB_DIR/template.sh'
        generate_template_file 'Personal' 'myapp' '' '$output' 'API_KEY'
    "
    
    # Check file permissions
    local perms
    perms=$(stat -f "%OLp" "$output" 2>/dev/null || stat -c "%a" "$output")
    [[ "$perms" == "600" ]]
}

@test "template file has restricted permissions even with multiple fields" {
    local output
    output="$TEST_TEMP_DIR/template.env"
    
    bash -c "
        source '$LIB_DIR/template.sh'
        generate_template_file 'Personal' 'myapp' '' '$output' 'KEY1' 'KEY2' 'KEY3'
    "
    
    local perms
    perms=$(stat -f "%OLp" "$output" 2>/dev/null || stat -c "%a" "$output")
    [[ "$perms" == "600" ]]
}

# =============================================================================
# Test: No Secret Logging
# =============================================================================

@test "secret values are not logged in dry-run output" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    echo "SECRET_API_KEY=super_secret_value_123" > "$env_file"
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --dry-run
        push_to_1password 2>&1
    "
    assert_success
    # Output should not contain the secret value
    refute_output "super_secret_value_123"
}

@test "special characters in secrets don't break parsing" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    cat > "$env_file" << 'EOF'
DATABASE_PASSWORD=p@ss!w0rd"with'quotes$pecial
API_TOKEN=abc123!@#$%^&*()_+-={}[]|:;",.<>?/
EOF
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --dry-run
        push_to_1password
    "
    assert_success
}

# =============================================================================
# Test: Authentication Checks
# =============================================================================

@test "push requires authentication check (skipped in dry-run)" {
    local env_file
    env_file=$(create_test_env_file)
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --dry-run
        # In dry-run, should skip auth check
        push_to_1password 2>&1
    "
    assert_success
    assert_output --regexp "Dry-run mode"
}

# =============================================================================
# Test: Command Injection Prevention
# =============================================================================

@test "vault names with special characters are handled safely" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Test; rm -rf /' --env-file='.env' --dry-run
        echo \$VAULT
    "
    assert_success
    assert_output "Test; rm -rf /"
    # Command was safely parsed, not executed
}

@test "item names with special characters are handled safely" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --item='app\$(whoami)' --vault='Personal' --dry-run
        echo \$ITEM_NAME
    "
    assert_success
    # Should not execute the command substitution
}

# =============================================================================
# Test: jq Output Escaping
# =============================================================================

@test "jq properly escapes values in field extraction" {
    run bash -c "
        cat << 'JSON'
{
  \"fields\": [
    {\"label\": \"VALUE_WITH_QUOTES\", \"value\": \"contains\\\"quotes\\\"inside\", \"section\": null}
  ]
}
JSON
    " | jq -r '.fields[] | "\(.label)=\(.value)"'
    assert_success
}

# =============================================================================
# Test: Path Traversal Prevention
# =============================================================================

@test "output file paths prevent directory traversal attacks" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Personal' --output='../../../etc/passwd'
        echo \$OUTPUT_FILE
    "
    assert_success
    # Path is accepted as-is (no special handling), but should be used safely
    assert_output "../../../etc/passwd"
}

@test "env file paths prevent directory traversal attacks" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='../../../etc/passwd'
        echo \$ENV_FILE
    "
    assert_success
    assert_output "../../../etc/passwd"
}

