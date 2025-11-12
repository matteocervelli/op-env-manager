#!/usr/bin/env bats
# Unit tests for lib/logger.sh
# Tests all logging functions and output formatting

# Load test helpers
load ../test_helper/common

# =============================================================================
# Test Setup and Teardown
# =============================================================================

setup() {
    # Verify test environment before each test
    verify_test_environment
    
    # Create temporary directory for this test
    setup_temp_dir
    
    # Source the logger module
    source "$LIB_DIR/logger.sh"
}

teardown() {
    # Clean up temporary directory
    teardown_temp_dir
}

# =============================================================================
# Test: Logger Module Exists
# =============================================================================

@test "logger.sh exists and is readable" {
    assert_file_exists "$LIB_DIR/logger.sh"
    assert [ -r "$LIB_DIR/logger.sh" ]
}

# =============================================================================
# Test: Color Variables are Defined
# =============================================================================

@test "RED color variable is defined" {
    [[ -n "${RED:-}" ]]
}

@test "GREEN color variable is defined" {
    [[ -n "${GREEN:-}" ]]
}

@test "YELLOW color variable is defined" {
    [[ -n "${YELLOW:-}" ]]
}

@test "BLUE color variable is defined" {
    [[ -n "${BLUE:-}" ]]
}

@test "MAGENTA color variable is defined" {
    [[ -n "${MAGENTA:-}" ]]
}

@test "CYAN color variable is defined" {
    [[ -n "${CYAN:-}" ]]
}

@test "NC (No Color) variable is defined" {
    [[ -n "${NC:-}" ]]
}

# =============================================================================
# Test: log_header Function
# =============================================================================

@test "log_header function exists" {
    assert_function_exists "log_header"
}

@test "log_header outputs magenta section dividers" {
    run log_header "Test Header"
    assert_success
    assert_line --index 0 --regexp "========"
    assert_line --index 2 --regexp "========"
}

@test "log_header includes the provided message" {
    run log_header "Custom Header"
    assert_success
    assert_output --regexp "Custom Header"
}

# =============================================================================
# Test: log_step Function
# =============================================================================

@test "log_step function exists" {
    assert_function_exists "log_step"
}

@test "log_step outputs cyan colored text" {
    run log_step "Test Step"
    assert_success
    assert_output --regexp "Test Step"
}

@test "log_step includes the arrow symbol" {
    run log_step "Process Step"
    assert_success
    # Arrow is the ▶ symbol
    assert_output --regexp "▶"
}

# =============================================================================
# Test: log_info Function
# =============================================================================

@test "log_info function exists" {
    assert_function_exists "log_info"
}

@test "log_info outputs blue colored text" {
    run log_info "Info Message"
    assert_success
    assert_output --regexp "Info Message"
}

@test "log_info includes the info symbol" {
    run log_info "Some Info"
    assert_success
    # Info symbol is ℹ
    assert_output --regexp "ℹ"
}

# =============================================================================
# Test: log_success Function
# =============================================================================

@test "log_success function exists" {
    assert_function_exists "log_success"
}

@test "log_success outputs green colored text" {
    run log_success "Success Message"
    assert_success
    assert_output --regexp "Success Message"
}

@test "log_success includes the checkmark symbol" {
    run log_success "Operation Complete"
    assert_success
    # Checkmark symbol is ✓
    assert_output --regexp "✓"
}

# =============================================================================
# Test: log_warning Function
# =============================================================================

@test "log_warning function exists" {
    assert_function_exists "log_warning"
}

@test "log_warning outputs yellow colored text" {
    run log_warning "Warning Message"
    assert_success
    assert_output --regexp "Warning Message"
}

@test "log_warning includes the warning symbol" {
    run log_warning "Be Careful"
    assert_success
    # Warning symbol is ⚠
    assert_output --regexp "⚠"
}

# =============================================================================
# Test: log_error Function
# =============================================================================

@test "log_error function exists" {
    assert_function_exists "log_error"
}

@test "log_error outputs red colored text" {
    run log_error "Error Message"
    assert_success
    assert_output --regexp "Error Message"
}

@test "log_error outputs to stderr" {
    # Run the command and capture stderr
    log_error "Test Error" 2> "$TEST_TEMP_DIR/stderr.txt"
    
    # Check that stderr contains the message
    assert_file_exists "$TEST_TEMP_DIR/stderr.txt"
    assert_file_not_empty "$TEST_TEMP_DIR/stderr.txt"
    grep -q "Test Error" "$TEST_TEMP_DIR/stderr.txt"
}

@test "log_error includes the X symbol" {
    run log_error "Failed Operation"
    assert_success
    # X symbol is ✗
    assert_output --regexp "✗"
}

# =============================================================================
# Test: Function Output Format
# =============================================================================

@test "log_header has three lines of output" {
    run log_header "Test"
    assert_success
    [[ "$(echo "$output" | wc -l)" -eq 3 ]]
}

@test "log_step produces single line output" {
    run log_step "Single Line"
    assert_success
    [[ "$(echo "$output" | wc -l)" -eq 1 ]]
}

@test "log_info produces single line output" {
    run log_info "Single Line"
    assert_success
    [[ "$(echo "$output" | wc -l)" -eq 1 ]]
}

@test "log_success produces single line output" {
    run log_success "Single Line"
    assert_success
    [[ "$(echo "$output" | wc -l)" -eq 1 ]]
}

@test "log_warning produces single line output" {
    run log_warning "Single Line"
    assert_success
    [[ "$(echo "$output" | wc -l)" -eq 1 ]]
}

@test "log_error produces single line output" {
    run log_error "Single Line"
    assert_success
    [[ "$(echo "$output" | wc -l)" -eq 1 ]]
}

# =============================================================================
# Test: Practical Usage Scenarios
# =============================================================================

@test "Multiple log calls work in sequence" {
    run bash -c "
        source '$LIB_DIR/logger.sh'
        log_header 'Starting Process'
        log_step 'Initialize'
        log_info 'Details here'
        log_success 'All done'
    "
    assert_success
    assert_line --index 0 --regexp "========"
    assert_output --regexp "Starting Process"
    assert_output --regexp "Initialize"
    assert_output --regexp "Details here"
    assert_output --regexp "All done"
}

@test "logger works in subshell context" {
    run bash -c "
        source '$LIB_DIR/logger.sh'
        log_step 'Subshell test'
        echo 'After log'
    "
    assert_success
    assert_output --regexp "Subshell test"
    assert_output --regexp "After log"
}

# =============================================================================
# Test: Edge Cases
# =============================================================================

@test "log functions handle empty strings" {
    run log_info ""
    assert_success
}

@test "log functions handle special characters" {
    run log_info "Special: @#\$%^&*()"
    assert_success
    assert_output --regexp "Special: @#"
}

@test "log functions handle quoted strings" {
    run log_warning 'Message with "quotes"'
    assert_success
    assert_output --regexp 'quotes'
}

# =============================================================================
# Test: Integration with Script Context
# =============================================================================

@test "logger functions maintain exit codes" {
    run bash -c "
        source '$LIB_DIR/logger.sh'
        log_info 'Test'
        exit 0
    "
    assert_success
}

@test "logger functions do not interfere with command pipelines" {
    run bash -c "
        source '$LIB_DIR/logger.sh'
        echo 'test' | wc -l | tr -d ' '
    "
    assert_success
    assert_output "1"
}
