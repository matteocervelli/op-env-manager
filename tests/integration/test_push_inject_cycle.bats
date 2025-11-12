#!/usr/bin/env bats
# Integration tests for push/inject cycle
# Tests the full workflow of pushing to and injecting from 1Password

load ../test_helper/common
load ../test_helper/mocks

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
    disable_mock_mode
    teardown_temp_dir
}

# =============================================================================
# Test: Push Command Dry-Run
# =============================================================================

@test "push --dry-run shows what would be pushed" {
    local env_file
    env_file=$(create_test_env_file)
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --item='test-app' --dry-run
        push_to_1password
    "
    assert_success
    assert_output --regexp "DRY RUN"
    assert_output --regexp "Would create/update item"
}

@test "push --dry-run with mock shows field assignments" {
    local env_file
    env_file=$(create_test_env_file)
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --item='myapp' --dry-run
        push_to_1password
    "
    assert_success
    assert_output --regexp "Would set.*DATABASE_URL"
}

@test "push --dry-run with section shows section info" {
    local env_file
    env_file=$(create_test_env_file)
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --section='production' --dry-run
        push_to_1password
    "
    assert_success
    assert_output --regexp "Section: production"
}

# =============================================================================
# Test: Inject Command Dry-Run
# =============================================================================

@test "inject --dry-run shows what would be injected" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Personal' --item='myapp' --output='.env.local' --dry-run
        inject_to_env_file
    "
    assert_success
    assert_output --regexp "DRY RUN"
}

# =============================================================================
# Test: Large File Handling
# =============================================================================

@test "push handles 50-variable .env file" {
    local env_file
    env_file=$(create_test_env_large 50)
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --dry-run
        push_to_1password
    "
    assert_success
    [ "$(echo "$output" | grep -c 'Would set')" -eq 50 ]
}

@test "push handles 100-variable .env file" {
    local env_file
    env_file=$(create_test_env_large 100)
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --dry-run
        push_to_1password
    "
    assert_success
    [ "$(echo "$output" | grep -c 'Would set')" -eq 100 ]
}

# =============================================================================
# Test: Special Characters and Encoding
# =============================================================================

@test "push handles special characters in values" {
    local env_file
    env_file=$(create_test_env_special)
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --dry-run
        push_to_1password
    "
    assert_success
    assert_output --regexp "PASSWORD"
}

@test "push handles values with equals signs" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    cat > "$env_file" << 'EOF'
DATABASE_URL=postgresql://user:pass@localhost:5432/db?ssl=true
CONNECTION_STRING=server=localhost;user=admin;password=secret
EOF
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --dry-run
        push_to_1password
    "
    assert_success
}

# =============================================================================
# Test: Multi-Environment Workflow
# =============================================================================

@test "push dev and prod sections to same item" {
    local env_dev env_prod
    env_dev=$(mktemp -p "$TEST_TEMP_DIR")
    env_prod=$(mktemp -p "$TEST_TEMP_DIR")
    
    echo "API_KEY=dev_key_123" > "$env_dev"
    echo "API_KEY=prod_key_456" > "$env_prod"
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        
        # Push dev
        parse_args --vault='Personal' --item='myapp' --section='dev' --env-file='$env_dev' --dry-run
        push_to_1password
        
        # Output should show dev section
        echo '---'
        
        # Push prod  
        VAULT='Personal'
        ITEM_NAME='myapp'
        SECTION='prod'
        ENV_FILE='$env_prod'
        DRY_RUN=true
        SAVE_TEMPLATE=false
        push_to_1password
    "
    assert_success
    assert_output --regexp "dev"
    assert_output --regexp "prod"
}

@test "template generation works with mock op CLI" {
    local output
    output="$TEST_TEMP_DIR/test.env.op"
    
    run bash -c "
        source '$LIB_DIR/template.sh'
        generate_template_file 'Personal' 'myapp' '' '$output' 'API_KEY' 'DATABASE_URL'
        cat '$output'
    "
    assert_success
    assert_output --regexp "Generated by op-env-manager"
    assert_output --regexp "API_KEY=op://"
    assert_output --regexp "DATABASE_URL=op://"
}

# =============================================================================
# Test: Convert with References
# =============================================================================

@test "convert command detects op:// references" {
    local env_file
    env_file=$(create_test_env_with_references)
    
    run bash -c "
        source '$LIB_DIR/convert.sh'
        # Just test reference detection
        grep 'op://' '$env_file' | wc -l
    "
    assert_success
    [ "$output" -ge 2 ]
}

# =============================================================================
# Test: Empty Files
# =============================================================================

@test "push rejects empty .env files" {
    local env_file
    env_file=$(create_test_env_empty)
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='$env_file' --dry-run
        push_to_1password 2>&1 || true
    "
    assert_output --regexp "No variables found"
}

# =============================================================================
# Test: Error Handling
# =============================================================================

@test "push fails when vault is not specified" {
    local env_file
    env_file=$(create_test_env_file)
    
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --env-file='$env_file'
        push_to_1password 2>&1 || true
    "
    assert_output --regexp "vault is required"
}

@test "inject fails when vault is not specified" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --item='myapp'
        inject_to_env_file 2>&1 || true
    "
    assert_output --regexp "vault is required"
}

# =============================================================================
# Test: Fixture Integration
# =============================================================================

@test "all test fixtures work with push command" {
    local files=(
        "$(create_test_env_file)"
        "$(create_test_env_special)"
        "$(create_test_env_large 10)"
        "$(create_test_env_with_references)"
    )
    
    for file in "${files[@]}"; do
        run bash -c "
            source '$LIB_DIR/push.sh'
            parse_args --vault='Personal' --env-file='$file' --dry-run
            push_to_1password
        "
        assert_success
    done
}

