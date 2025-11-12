#!/usr/bin/env bats
# Unit tests for lib/inject.sh
# Tests field extraction and argument handling for the inject command

load ../test_helper/common

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup() {
    verify_test_environment
    setup_temp_dir
    source "$LIB_DIR/inject.sh"
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Test: Module Exists
# =============================================================================

@test "inject.sh exists and is readable" {
    assert_file_exists "$LIB_DIR/inject.sh"
    assert [ -r "$LIB_DIR/inject.sh" ]
}

# =============================================================================
# Test: Argument Parsing
# =============================================================================

@test "parse_args sets VAULT from --vault=VALUE" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Personal' --output='.env.local'
        echo \$VAULT
    "
    assert_success
    assert_output "Personal"
}

@test "parse_args sets VAULT from --vault VALUE" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault 'Work' --output '.env'
        echo \$VAULT
    "
    assert_success
    assert_output "Work"
}

@test "parse_args sets OUTPUT_FILE from --output=VALUE" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Personal' --output='.env.production'
        echo \$OUTPUT_FILE
    "
    assert_success
    assert_output ".env.production"
}

@test "parse_args sets OUTPUT_FILE from --output VALUE" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Personal' --output '.env.local'
        echo \$OUTPUT_FILE
    "
    assert_success
    assert_output ".env.local"
}

@test "parse_args sets ITEM_NAME from --item=VALUE" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Personal' --item='myapp'
        echo \$ITEM_NAME
    "
    assert_success
    assert_output "myapp"
}

@test "parse_args sets SECTION from --section=VALUE" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Personal' --section='production'
        echo \$SECTION
    "
    assert_success
    assert_output "production"
}

@test "parse_args sets DRY_RUN from --dry-run flag" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Personal' --dry-run
        [[ \$DRY_RUN == 'true' ]] && echo 'true' || echo 'false'
    "
    assert_success
    assert_output "true"
}

@test "parse_args sets OVERWRITE from --overwrite flag" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Personal' --overwrite
        [[ \$OVERWRITE == 'true' ]] && echo 'true' || echo 'false'
    "
    assert_success
    assert_output "true"
}

@test "parse_args rejects unknown options" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --unknown-opt 'value' 2>&1
    "
    assert_failure
    assert_output --regexp "Unknown option"
}

@test "parse_args supports help flag" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --help 2>&1 || true
    "
    assert_output --regexp "Usage:"
}

# =============================================================================
# Test: Default Values
# =============================================================================

@test "OUTPUT_FILE defaults to .env" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        echo \$OUTPUT_FILE
    "
    assert_output ".env"
}

@test "ITEM_NAME defaults to env-secrets if not specified" {
    # Test by checking inject_to_env_file behavior
    skip "Requires mocking 1Password CLI"
}

@test "SECTION is empty by default" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        [[ -z \$SECTION ]] && echo 'empty' || echo 'not empty'
    "
    assert_output "empty"
}

@test "DRY_RUN defaults to false" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        [[ \$DRY_RUN == 'false' ]] && echo 'true' || echo 'false'
    "
    assert_success
    assert_output "true"
}

@test "OVERWRITE defaults to false" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        [[ \$OVERWRITE == 'false' ]] && echo 'true' || echo 'false'
    "
    assert_success
    assert_output "true"
}

# =============================================================================
# Test: Error Handling
# =============================================================================

@test "inject_to_env_file requires --vault argument" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        inject_to_env_file 2>&1 || true
    "
    assert_output --regexp "vault is required"
}

@test "get_fields_from_item validates vault parameter" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        get_fields_from_item '' 'myapp' '' 2>&1 || true
    "
    # Should fail when vault is empty
    assert_failure
}

# =============================================================================
# Test: Field Extraction Logic
# =============================================================================

@test "jq filters work correctly for field extraction" {
    # Test with mock JSON
    run bash -c "
        cat << 'JSON'
{
  \"fields\": [
    {\"label\": \"API_KEY\", \"value\": \"test_key\", \"type\": \"CONCEALED\", \"section\": null},
    {\"label\": \"DATABASE_URL\", \"value\": \"localhost\", \"type\": \"STRING\", \"section\": null}
  ]
}
JSON
    " | jq -r '.fields[] | select(.section == null) | "\(.label)=\(.value)"'
    assert_success
    assert_line --index 0 "API_KEY=test_key"
    assert_line --index 1 "DATABASE_URL=localhost"
}

@test "jq filters work for section-specific fields" {
    # Test with mock JSON
    run bash -c "
        cat << 'JSON'
{
  \"fields\": [
    {\"label\": \"API_KEY\", \"value\": \"prod_key\", \"type\": \"CONCEALED\", \"section\": {\"label\": \"production\"}},
    {\"label\": \"API_KEY\", \"value\": \"dev_key\", \"type\": \"CONCEALED\", \"section\": {\"label\": \"development\"}}
  ]
}
JSON
    " | jq -r '.fields[] | select(.section.label == \"production\") | "\(.label)=\(.value)"'
    assert_success
    assert_output "API_KEY=prod_key"
}

@test "jq handles empty field values" {
    run bash -c "
        cat << 'JSON'
{
  \"fields\": [
    {\"label\": \"OPTIONAL_VAR\", \"value\": null, \"type\": \"STRING\", \"section\": null}
  ]
}
JSON
    " | jq -r '.fields[] | select(.section == null) | "\(.label)=\(.value // \"\")"'
    assert_success
    assert_output "OPTIONAL_VAR="
}

# =============================================================================
# Test: File Output Considerations
# =============================================================================

@test "Output file path can be specified with relative paths" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Personal' --output='subdir/.env.local'
        echo \$OUTPUT_FILE
    "
    assert_success
    assert_output "subdir/.env.local"
}

@test "Output file path can be specified with absolute paths" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Personal' --output='/tmp/.env.local'
        echo \$OUTPUT_FILE
    "
    assert_success
    assert_output "/tmp/.env.local"
}

# =============================================================================
# Test: Integration Scenarios
# =============================================================================

@test "Multiple arguments are parsed correctly together" {
    run bash -c "
        source '$LIB_DIR/inject.sh'
        parse_args --vault='Projects' --item='myapp' --section='staging' --output='.env.staging' --dry-run --overwrite
        echo \"\$VAULT|\$ITEM_NAME|\$SECTION|\$OUTPUT_FILE|\$DRY_RUN|\$OVERWRITE\"
    "
    assert_success
    assert_output "Projects|myapp|staging|.env.staging|true|true"
}

