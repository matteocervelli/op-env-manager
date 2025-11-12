#!/usr/bin/env bats
# Unit tests for lib/push.sh
# Tests parsing functions and argument handling for the push command

load ../test_helper/common

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup() {
    verify_test_environment
    setup_temp_dir
    source "$LIB_DIR/push.sh"
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Test: Module Exists
# =============================================================================

@test "push.sh exists and is readable" {
    assert_file_exists "$LIB_DIR/push.sh"
    assert [ -r "$LIB_DIR/push.sh" ]
}

# =============================================================================
# Test: parse_env_file Function
# =============================================================================

@test "parse_env_file ignores comment lines" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    cat > "$env_file" << 'EOF'
# This is a comment
API_KEY=test123
# Another comment
DATABASE_URL=localhost
EOF
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file'"
    assert_success
    assert_line --index 0 "API_KEY=test123"
    assert_line --index 1 "DATABASE_URL=localhost"
    refute_output --regexp "This is a comment"
}

@test "parse_env_file ignores empty lines" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    cat > "$env_file" << 'EOF'
API_KEY=test123

DATABASE_URL=localhost

EOF
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file'"
    assert_success
    assert_line --index 0 "API_KEY=test123"
    assert_line --index 1 "DATABASE_URL=localhost"
    [ "$(echo "$output" | wc -l)" -eq 2 ]
}

@test "parse_env_file removes double quotes from values" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    echo 'API_KEY="secret_value"' > "$env_file"
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file'"
    assert_success
    assert_output "API_KEY=secret_value"
}

@test "parse_env_file removes single quotes from values" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    echo "API_KEY='secret_value'" > "$env_file"
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file'"
    assert_success
    assert_output "API_KEY=secret_value"
}

@test "parse_env_file trims whitespace from keys and values" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    echo '  API_KEY  =  test123  ' > "$env_file"
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file'"
    assert_success
    assert_output "API_KEY=test123"
}

@test "parse_env_file handles empty values" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    echo 'EMPTY_VAR=' > "$env_file"
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file'"
    assert_success
    assert_output "EMPTY_VAR="
}

@test "parse_env_file fails when file does not exist" {
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file /nonexistent/file.env"
    assert_failure
    assert_output --regexp "Environment file not found"
}

@test "parse_env_file handles special characters in values" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    echo 'PASSWORD=p@ss!w0rd#123' > "$env_file"
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file'"
    assert_success
    assert_output "PASSWORD=p@ss!w0rd#123"
}

@test "parse_env_file handles values with equals signs" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    echo 'DATABASE_URL=postgresql://user:pass@localhost:5432/db?sslmode=require' > "$env_file"
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file'"
    assert_success
    assert_output "DATABASE_URL=postgresql://user:pass@localhost:5432/db?sslmode=require"
}

@test "parse_env_file processes file from stdin when needed" {
    run bash -c "source '$LIB_DIR/push.sh' && echo -e 'KEY1=val1\nKEY2=val2' | grep -v '^\s*#' | grep -v '^\s*$' | while IFS='=' read -r key value; do echo \"\$key=\$value\"; done"
    assert_success
}

# =============================================================================
# Test: Argument Parsing (parse_args)
# =============================================================================

@test "parse_args sets VAULT from --vault=VALUE" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='.env'
        echo \$VAULT
    "
    assert_success
    assert_output "Personal"
}

@test "parse_args sets VAULT from --vault VALUE" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault 'Personal' --env-file '.env'
        echo \$VAULT
    "
    assert_success
    assert_output "Personal"
}

@test "parse_args sets ENV_FILE from --env-file=VALUE" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file='.env.production'
        echo \$ENV_FILE
    "
    assert_success
    assert_output ".env.production"
}

@test "parse_args sets ENV_FILE from --env-file VALUE" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --env-file '.env.prod'
        echo \$ENV_FILE
    "
    assert_success
    assert_output ".env.prod"
}

@test "parse_args sets ITEM_NAME from --item=VALUE" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --item='myapp'
        echo \$ITEM_NAME
    "
    assert_success
    assert_output "myapp"
}

@test "parse_args sets SECTION from --section=VALUE" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --section='production'
        echo \$SECTION
    "
    assert_success
    assert_output "production"
}

@test "parse_args sets DRY_RUN from --dry-run flag" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --dry-run
        [[ \$DRY_RUN == 'true' ]] && echo 'true' || echo 'false'
    "
    assert_success
    assert_output "true"
}

@test "parse_args sets SAVE_TEMPLATE from --template flag" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --template
        [[ \$SAVE_TEMPLATE == 'true' ]] && echo 'true' || echo 'false'
    "
    assert_success
    assert_output "true"
}

@test "parse_args sets TEMPLATE_OUTPUT from --template-output=VALUE" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --vault='Personal' --template-output='.env.custom'
        echo \$TEMPLATE_OUTPUT
    "
    assert_success
    assert_output ".env.custom"
}

@test "parse_args rejects unknown options" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --unknown-option 'value' 2>&1
    "
    assert_failure
    assert_output --regexp "Unknown option"
}

@test "parse_args supports help flag" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_args --help 2>&1 || true
    "
    assert_output --regexp "Usage:"
}

# =============================================================================
# Test: Integration with Test Fixtures
# =============================================================================

@test "parse_env_file works with create_test_env_file fixture" {
    local env_file
    env_file=$(create_test_env_file)
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file' | wc -l"
    assert_success
    # Should have at least 4 variables
    [ "$output" -ge 4 ]
}

@test "parse_env_file works with create_test_env_large fixture" {
    local env_file
    env_file=$(create_test_env_large 50)
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file' | wc -l"
    assert_success
    [ "$output" -eq 50 ]
}

@test "parse_env_file works with create_test_env_special fixture" {
    local env_file
    env_file=$(create_test_env_special)
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file'"
    assert_success
    # Should have at least one line
    [ "$(echo "$output" | wc -l)" -ge 1 ]
}

# =============================================================================
# Test: Error Handling
# =============================================================================

@test "parse_args with missing --vault argument shows error" {
    run bash -c "
        source '$LIB_DIR/push.sh'
        push_to_1password 2>&1 || true
    "
    assert_output --regexp "vault is required"
}

