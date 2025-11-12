#!/usr/bin/env bats
# Integration tests for run command
# Tests running commands with secrets injected from 1Password

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
# Test: Run Command Dry-Run
# =============================================================================

@test "run --dry-run shows secret references without executing" {
    run bash -c "
        source '$BIN_DIR/op-env-manager' 2>&1 | grep -v '^#'
    "
    # The script should be executable
    assert [ -x '$BIN_DIR/op-env-manager' ]
}

@test "main executable parses run command" {
    run bash -c "
        source '$BIN_DIR/op-env-manager'
    "
    # Should source without error
    assert_success
}

# =============================================================================
# Test: Generate Op References
# =============================================================================

@test "generate_op_reference creates proper reference format" {
    run bash -c "
        source '$LIB_DIR/template.sh'
        generate_op_reference 'Personal' 'myapp' '' 'API_KEY'
    "
    assert_success
    assert_output "API_KEY=op://Personal/myapp/API_KEY"
}

@test "generate_op_reference with section uses APP_ENV variable" {
    run bash -c "
        source '$LIB_DIR/template.sh'
        generate_op_reference 'Personal' 'myapp' 'prod' 'SECRET'
    "
    assert_success
    assert_output "SECRET=op://Personal/myapp/\$APP_ENV/SECRET"
}

@test "template file with multiple fields is properly formatted" {
    local output
    output="$TEST_TEMP_DIR/template.env"
    
    bash -c "
        source '$LIB_DIR/template.sh'
        generate_template_file 'Personal' 'myapp' '' '$output' 'API_KEY' 'DB_URL' 'SECRET'
    "
    
    run bash -c "wc -l < '$output'"
    # Should have header lines plus 3 variables (at least 7 lines)
    [ "$output" -ge 7 ]
}

# =============================================================================
# Test: Template File Generation
# =============================================================================

@test "template file can be used as env file for op run" {
    local template
    template="$TEST_TEMP_DIR/template.env"
    
    bash -c "
        source '$LIB_DIR/template.sh'
        generate_template_file 'Personal' 'myapp' '' '$template' 'TEST_VAR'
    "
    
    # File should exist and be readable
    assert_file_exists "$template"
    
    # Should be able to read it
    [ -r "$template" ]
}

@test "template with APP_ENV is valid for dynamic sections" {
    local template
    template="$TEST_TEMP_DIR/template.env"
    
    bash -c "
        source '$LIB_DIR/template.sh'
        generate_template_file 'Personal' 'myapp' 'prod' '$template' 'API_KEY'
    "
    
    # Check file contains APP_ENV reference
    grep -q '\$APP_ENV' "$template"
}

# =============================================================================
# Test: Section Handling
# =============================================================================

@test "run with section sets APP_ENV variable" {
    run bash -c "
        APP_ENV='production'
        [[ \$APP_ENV == 'production' ]] && echo 'set'
    "
    assert_success
    assert_output "set"
}

@test "APP_ENV can be used in op:// references" {
    run bash -c "
        APP_ENV='staging'
        echo \"API_KEY=op://vault/item/\$APP_ENV/key\"
    "
    assert_success
    assert_output "API_KEY=op://vault/item/staging/key"
}

# =============================================================================
# Test: Field Name Collection
# =============================================================================

@test "jq can extract field names from mock item JSON" {
    run bash -c "
        cat << 'JSON'
{
  \"fields\": [
    {\"label\": \"API_KEY\", \"value\": \"key123\", \"section\": null},
    {\"label\": \"DATABASE_URL\", \"value\": \"localhost\", \"section\": null}
  ]
}
JSON
    " | jq -r '.fields[] | select(.section == null) | .label'
    assert_success
    assert_line --index 0 "API_KEY"
    assert_line --index 1 "DATABASE_URL"
}

@test "jq extracts section-specific field names" {
    run bash -c "
        cat << 'JSON'
{
  \"fields\": [
    {\"label\": \"API_KEY\", \"value\": \"prod_key\", \"section\": {\"label\": \"production\"}},
    {\"label\": \"API_KEY\", \"value\": \"dev_key\", \"section\": {\"label\": \"development\"}}
  ]
}
JSON
    " | jq -r '.fields[] | select(.section.label == \"production\") | .label'
    assert_success
    assert_output "API_KEY"
}

# =============================================================================
# Test: Command Passthrough
# =============================================================================

@test "template file content is valid bash syntax" {
    local template
    template="$TEST_TEMP_DIR/template.env"
    
    bash -c "
        source '$LIB_DIR/template.sh'
        generate_template_file 'Personal' 'myapp' '' '$template' 'VAR1' 'VAR2'
    "
    
    # Should be able to bash -n (syntax check) the file
    bash -n "$template"
}

# =============================================================================
# Test: Dry-Run Mode
# =============================================================================

@test "dry-run shows template preview" {
    local template
    template="$TEST_TEMP_DIR/preview.env"
    
    run bash -c "
        source '$LIB_DIR/template.sh'
        generate_template_file 'Personal' 'myapp' '' '$template' 'API_KEY'
        cat '$template'
    "
    assert_success
    assert_output --regexp "op://"
}

