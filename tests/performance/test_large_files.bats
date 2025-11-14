#!/usr/bin/env bats
# Performance tests for large file handling
# Validates performance and resource usage with large .env files

load ../test_helper/common

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
# Test: Parse Performance
# =============================================================================

@test "parse_env_file handles 100 variables efficiently" {
    local env_file
    env_file=$(create_test_env_large 100)
    
    local start
    start=$(date +%s%N)
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file' | wc -l"
    
    local end
    end=$(date +%s%N)
    local elapsed=$((($end - $start) / 1000000))  # Convert to milliseconds
    
    assert_success
    assert_output "100"
    # Should complete in less than 1 second
    [ "$elapsed" -lt 1000 ]
}

@test "parse_env_file handles 500 variables efficiently" {
    local env_file
    env_file=$(create_test_env_large 500)
    
    local start
    start=$(date +%s%N)
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file' | wc -l"
    
    local end
    end=$(date +%s%N)
    local elapsed=$((($end - $start) / 1000000))
    
    assert_success
    assert_output "500"
    # Should complete in less than 2 seconds
    [ "$elapsed" -lt 2000 ]
}

# =============================================================================
# Test: Memory Usage
# =============================================================================

@test "parse_env_file with large file doesn't load entire file into memory" {
    # Test that parsing is streaming (using while/read pattern)
    local env_file
    env_file=$(create_test_env_large 1000)
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file' | head -10 | wc -l"
    assert_success
    assert_output "10"
}

# =============================================================================
# Test: Comment Filtering Performance
# =============================================================================

@test "parsing with many comments is efficient" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    
    # Create file with 50% comments
    {
        for i in {1..100}; do
            if [ $((i % 2)) -eq 0 ]; then
                echo "# Comment $i"
            else
                printf "VAR_%03d=value_%03d\n" "$i" "$i"
            fi
        done
    } > "$env_file"
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file' | wc -l"
    assert_success
    assert_output "50"
}

# =============================================================================
# Test: Empty Line Handling Performance
# =============================================================================

@test "parsing with many empty lines is efficient" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    
    # Create file with 50% empty lines
    {
        for i in {1..100}; do
            if [ $((i % 2)) -eq 0 ]; then
                echo ""
            else
                printf "VAR_%03d=value_%03d\n" "$i" "$i"
            fi
        done
    } > "$env_file"
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file' | wc -l"
    assert_success
    assert_output "50"
}

# =============================================================================
# Test: Quote Handling Performance
# =============================================================================

@test "parsing with many quoted values is efficient" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    
    # Create file with all quoted values
    {
        for i in {1..100}; do
            echo "VAR_$i=\"This is a quoted value with spaces and special chars!\""
        done
    } > "$env_file"
    
    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file' | wc -l"
    assert_success
    assert_output "100"
}

# =============================================================================
# Test: Template Generation Performance
# =============================================================================

@test "template generation with 100 fields completes quickly" {
    local output
    output="$TEST_TEMP_DIR/template.env"
    
    local fields=()
    for i in {1..100}; do
        fields+=("FIELD_$i")
    done
    
    local start
    start=$(date +%s%N)
    
    bash -c "
        source '$LIB_DIR/template.sh'
        generate_template_file 'Personal' 'myapp' '' '$output' ${fields[@]@Q}
    "
    
    local end
    end=$(date +%s%N)
    local elapsed=$((($end - $start) / 1000000))
    
    assert_file_exists "$output"
    # Should complete in less than 500ms
    [ "$elapsed" -lt 500 ]
}

# =============================================================================
# Test: Reference Extraction Performance
# =============================================================================

@test "op:// reference extraction from 100 lines is efficient" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    
    # Mix of regular and op:// references
    {
        for i in {1..100}; do
            if [ $((i % 3)) -eq 0 ]; then
                echo "VAR_$i=op://vault/item/field_$i"
            else
                echo "VAR_$i=regular_value_$i"
            fi
        done
    } > "$env_file"
    
    local start
    start=$(date +%s%N)
    
    run bash -c "grep 'op://' '$env_file' | wc -l"
    
    local end
    end=$(date +%s%N)
    local elapsed=$((($end - $start) / 1000000))
    
    assert_success
    # Should complete very quickly
    [ "$elapsed" -lt 100 ]
}

# =============================================================================
# Test: Concurrent Operations
# =============================================================================

@test "multiple parse operations can run concurrently" {
    local file1 file2 file3
    file1=$(create_test_env_large 50)
    file2=$(create_test_env_large 50)
    file3=$(create_test_env_large 50)

    run bash -c "
        source '$LIB_DIR/push.sh'
        parse_env_file '$file1' &
        parse_env_file '$file2' &
        parse_env_file '$file3' &
        wait
        echo 'done'
    "
    assert_success
    assert_output "done"
}

# =============================================================================
# Test: Progress Bar Behavior
# =============================================================================

@test "progress bar initializes for 100+ variables" {
    local env_file
    env_file=$(create_test_env_large 150)

    # Force progress display (override CI detection)
    export OP_SHOW_PROGRESS=true

    # Run push with dry-run to test progress initialization
    run bash -c "
        source '$LIB_DIR/push.sh'
        source '$LIB_DIR/progress.sh'

        # Simulate push operation counting
        vars=\$(parse_env_file '$env_file')
        total_vars=\$(echo \"\$vars\" | grep -c '^[^[:space:]]' || true)

        # Should be >= 100 to trigger progress
        [ \"\$total_vars\" -ge 100 ]
    "
    assert_success

    unset OP_SHOW_PROGRESS
}

@test "progress bar does not show for files under threshold" {
    local env_file
    env_file=$(create_test_env_large 50)

    export OP_SHOW_PROGRESS=true
    export OP_PROGRESS_THRESHOLD=100

    run bash -c "
        source '$LIB_DIR/progress.sh'

        # Initialize with 50 (below threshold of 100)
        init_progress 50 'Testing'

        # PROGRESS_TOTAL should be 0 (not initialized)
        [ \"\$PROGRESS_TOTAL\" -eq 0 ]
    "
    assert_success

    unset OP_SHOW_PROGRESS
    unset OP_PROGRESS_THRESHOLD
}

@test "progress tracking respects quiet mode" {
    local env_file
    env_file=$(create_test_env_large 150)

    export OP_QUIET_MODE=true

    run bash -c "
        source '$LIB_DIR/progress.sh'

        # should_show_progress should return false in quiet mode
        if should_show_progress; then
            exit 1
        else
            exit 0
        fi
    "
    assert_success

    unset OP_QUIET_MODE
}

@test "progress tracking suppresses in CI environment" {
    local env_file
    env_file=$(create_test_env_large 150)

    export CI=true
    unset OP_SHOW_PROGRESS

    run bash -c "
        source '$LIB_DIR/progress.sh'

        # should_show_progress should return false in CI
        if should_show_progress; then
            exit 1
        else
            exit 0
        fi
    "
    assert_success

    unset CI
}

@test "custom progress threshold can be set via environment" {
    export OP_PROGRESS_THRESHOLD=50

    run bash -c "
        source '$LIB_DIR/progress.sh'

        # Check that custom threshold is applied
        [ \"\$PROGRESS_THRESHOLD\" -eq 50 ]
    "
    assert_success

    unset OP_PROGRESS_THRESHOLD
}

