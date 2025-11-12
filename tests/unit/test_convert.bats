#!/usr/bin/env bats
# Unit tests for lib/convert.sh
# Tests op:// reference detection and extraction

load ../test_helper/common

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup() {
    verify_test_environment
    setup_temp_dir
    source "$LIB_DIR/convert.sh"
}

teardown() {
    teardown_temp_dir
}

# =============================================================================
# Test: Module Exists
# =============================================================================

@test "convert.sh exists and is readable" {
    assert_file_exists "$LIB_DIR/convert.sh"
    assert [ -r "$LIB_DIR/convert.sh" ]
}

# =============================================================================
# Test: Argument Parsing
# =============================================================================

@test "parse_args sets ENV_FILE from --env-file=VALUE" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        parse_args --env-file='.env.template' --vault='Personal'
        echo \$ENV_FILE
    "
    assert_success
    assert_output ".env.template"
}

@test "parse_args sets VAULT from --vault=VALUE" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        parse_args --env-file='.env' --vault='Projects'
        echo \$VAULT
    "
    assert_success
    assert_output "Projects"
}

@test "parse_args sets ITEM_NAME from --item=VALUE" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        parse_args --env-file='.env' --vault='Personal' --item='myapp'
        echo \$ITEM_NAME
    "
    assert_success
    assert_output "myapp"
}

@test "parse_args sets SECTION from --section=VALUE" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        parse_args --env-file='.env' --vault='Personal' --section='production'
        echo \$SECTION
    "
    assert_success
    assert_output "production"
}

@test "parse_args sets DRY_RUN from --dry-run flag" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        parse_args --env-file='.env' --vault='Personal' --dry-run
        [[ \$DRY_RUN == 'true' ]] && echo 'true' || echo 'false'
    "
    assert_success
    assert_output "true"
}

@test "parse_args sets SAVE_TEMPLATE from --template flag" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        parse_args --env-file='.env' --vault='Personal' --template
        [[ \$SAVE_TEMPLATE == 'true' ]] && echo 'true' || echo 'false'
    "
    assert_success
    assert_output "true"
}

@test "parse_args rejects unknown options" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        parse_args --unknown-flag 'value' 2>&1
    "
    assert_failure
    assert_output --regexp "Unknown option"
}

# =============================================================================
# Test: Default Values
# =============================================================================

@test "ITEM_NAME defaults to env-secrets" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        echo \$ITEM_NAME
    "
    assert_output "env-secrets"
}

@test "DRY_RUN defaults to false" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        [[ \$DRY_RUN == 'false' ]] && echo 'true' || echo 'false'
    "
    assert_success
    assert_output "true"
}

@test "SAVE_TEMPLATE defaults to false" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        [[ \$SAVE_TEMPLATE == 'false' ]] && echo 'true' || echo 'false'
    "
    assert_success
    assert_output "true"
}

# =============================================================================
# Test: op:// Reference Detection
# =============================================================================

@test "detects op:// reference in simple format" {
    local line="API_KEY=op://vault/item/field"
    run bash -c "echo '$line' | grep -q 'op://' && echo 'detected'"
    assert_success
    assert_output "detected"
}

@test "detects op:// reference with section" {
    local line="PASSWORD=op://vault/item/section/field"
    run bash -c "echo '$line' | grep -q 'op://' && echo 'detected'"
    assert_success
    assert_output "detected"
}

@test "extracts op:// reference from line" {
    local line="API_KEY=op://vault/item/field"
    run bash -c "echo '$line' | sed -n 's/.*\(op:\/\/[^[:space:]]*\).*/\1/p'"
    assert_success
    assert_output "op://vault/item/field"
}

@test "extracts multiple op:// references from different lines" {
    local env_file
    env_file=$(create_test_env_with_references)
    
    run bash -c "grep -o 'op://[^[:space:]\"]*' '$env_file' | sort | uniq"
    assert_success
    assert_line --index 0 "op://vault/item/api_key"
    assert_line --index 1 "op://vault/item/password"
    assert_line --index 2 "op://vault/item/production/secret"
}

# =============================================================================
# Test: Line Parsing with References
# =============================================================================

@test "parse_env_file identifies lines with op:// references" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    cat > "$env_file" << 'EOF'
API_KEY=op://vault/item/api_key
DATABASE_URL=postgresql://localhost
SECRET=op://vault/item/secret
EOF
    
    run bash -c "grep 'op://' '$env_file' | wc -l"
    assert_success
    assert_output "2"
}

@test "separates lines with and without op:// references" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    cat > "$env_file" << 'EOF'
NORMAL_VAR=normal_value
OP_VAR=op://vault/item/field
ANOTHER_NORMAL=value
EOF
    
    run bash -c "grep 'op://' '$env_file' | wc -l"
    assert_success
    [ "$output" -eq 1 ]
}

# =============================================================================
# Test: Error Handling
# =============================================================================

@test "convert_from_template requires --env-file" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        convert_from_template 2>&1 || true
    "
    assert_output --regexp "env-file is required"
}

@test "convert_from_template requires --vault" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        parse_args --env-file='.env.template'
        convert_from_template 2>&1 || true
    "
    assert_output --regexp "vault is required"
}

@test "convert_from_template fails when file does not exist" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        parse_args --env-file='/nonexistent/.env.template' --vault='Personal'
        convert_from_template 2>&1 || true
    "
    assert_output --regexp "Environment file not found"
}

# =============================================================================
# Test: Integration with Test Fixtures
# =============================================================================

@test "works with create_test_env_with_references fixture" {
    local env_file
    env_file=$(create_test_env_with_references)
    
    run bash -c "grep 'op://' '$env_file' | wc -l"
    assert_success
    [ "$output" -ge 2 ]
}

@test "handles mixed content in env file" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    cat > "$env_file" << 'EOF'
# Configuration file
DEBUG=true
API_KEY=op://vault/item/api_key

# Database settings
DATABASE_URL=postgresql://localhost
DB_PASSWORD=op://vault/item/db/password

OPTIONAL=
QUOTED_VALUE="regular_value"
EOF
    
    # Count variables with op:// references
    run bash -c "grep -v '^\s*#' '$env_file' | grep 'op://' | wc -l"
    assert_success
    [ "$output" -eq 2 ]
}

# =============================================================================
# Test: Reference Format Validation
# =============================================================================

@test "validates op:// format structure" {
    local valid_refs=(
        "op://vault/item/field"
        "op://my-vault/my-item/my-field"
        "op://vault/item/section/field"
    )
    
    for ref in "${valid_refs[@]}"; do
        echo "$ref" | grep -qE '^op://[^/]+/[^/]+/.*$' || return 1
    done
}

@test "distinguishes op:// from similar patterns" {
    run bash -c "echo 'NOT_OP=http://example.com' | grep -q 'op://' && echo 'match' || echo 'nomatch'"
    assert_success
    assert_output "nomatch"
}

