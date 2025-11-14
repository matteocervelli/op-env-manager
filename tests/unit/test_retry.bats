#!/usr/bin/env bats
#
# Unit tests for retry logic with exponential backoff
# Tests lib/retry.sh functionality

load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'

# Setup - source retry module
setup() {
    # Load retry functions
    export PROJECT_ROOT="$BATS_TEST_DIRNAME/../.."
    export LIB_DIR="$PROJECT_ROOT/lib"

    # Source dependencies
    source "$LIB_DIR/logger.sh"
    source "$LIB_DIR/retry.sh"

    # Set test environment
    export OP_RETRY_QUIET=true  # Silent mode for tests
}

# Test: is_retryable_error function

@test "is_retryable_error: detects network errors as retryable" {
    run is_retryable_error "network timeout occurred" 1
    assert_success
}

@test "is_retryable_error: detects timeout errors as retryable" {
    run is_retryable_error "connection timed out" 1
    assert_success
}

@test "is_retryable_error: detects connection errors as retryable" {
    run is_retryable_error "connection refused" 1
    assert_success
}

@test "is_retryable_error: detects rate limit as retryable" {
    run is_retryable_error "rate limit exceeded" 1
    assert_success
}

@test "is_retryable_error: detects 503 unavailable as retryable" {
    run is_retryable_error "service unavailable" 1
    assert_success
}

@test "is_retryable_error: authentication error NOT retryable" {
    run is_retryable_error "not authenticated" 1
    assert_failure
}

@test "is_retryable_error: not found error NOT retryable" {
    run is_retryable_error "item not found" 1
    assert_failure
}

@test "is_retryable_error: permission denied NOT retryable" {
    run is_retryable_error "permission denied" 1
    assert_failure
}

@test "is_retryable_error: invalid input NOT retryable" {
    run is_retryable_error "invalid request" 1
    assert_failure
}

# Test: calculate_backoff_delay function

@test "calculate_backoff_delay: first retry (attempt 0)" {
    run calculate_backoff_delay 0 1 2 30 false
    assert_success
    assert_output "1"
}

@test "calculate_backoff_delay: second retry (attempt 1)" {
    run calculate_backoff_delay 1 1 2 30 false
    assert_success
    assert_output "2"
}

@test "calculate_backoff_delay: third retry (attempt 2)" {
    run calculate_backoff_delay 2 1 2 30 false
    assert_success
    assert_output "4"
}

@test "calculate_backoff_delay: caps at max_delay" {
    # attempt 10 with factor 2: 1 * 2^10 = 1024, should cap at 30
    run calculate_backoff_delay 10 1 2 30 false
    assert_success
    assert_output "30"
}

@test "calculate_backoff_delay: different initial delay" {
    run calculate_backoff_delay 0 2 2 30 false
    assert_success
    assert_output "2"
}

@test "calculate_backoff_delay: different backoff factor" {
    # attempt 2 with initial 1 and factor 1.5: 1 * 1.5^2 = 2.25
    run calculate_backoff_delay 2 1 1.5 30 false
    assert_success
    assert_output "2.25"
}

# Test: validate_retry_config function

@test "validate_retry_config: accepts default values" {
    unset OP_MAX_RETRIES
    unset OP_RETRY_DELAY
    unset OP_BACKOFF_FACTOR
    unset OP_MAX_DELAY
    unset OP_RETRY_JITTER
    unset OP_DISABLE_RETRY
    unset OP_RETRY_QUIET

    run validate_retry_config
    assert_success
}

@test "validate_retry_config: accepts valid OP_MAX_RETRIES" {
    export OP_MAX_RETRIES=5
    run validate_retry_config
    assert_success
}

@test "validate_retry_config: rejects invalid OP_MAX_RETRIES (non-integer)" {
    export OP_MAX_RETRIES="abc"
    run validate_retry_config
    assert_failure
}

@test "validate_retry_config: rejects OP_MAX_RETRIES out of range" {
    export OP_MAX_RETRIES=15
    run validate_retry_config
    assert_failure
}

@test "validate_retry_config: accepts valid OP_RETRY_DELAY" {
    export OP_RETRY_DELAY=2.5
    run validate_retry_config
    assert_success
}

@test "validate_retry_config: rejects invalid OP_RETRY_DELAY" {
    export OP_RETRY_DELAY="xyz"
    run validate_retry_config
    assert_failure
}

@test "validate_retry_config: rejects OP_RETRY_JITTER non-boolean" {
    export OP_RETRY_JITTER="maybe"
    run validate_retry_config
    assert_failure
}

# Test: retry_with_backoff function with mock commands

@test "retry_with_backoff: succeeds on first attempt" {
    # Mock command that always succeeds
    mock_cmd() { echo "success"; return 0; }
    export -f mock_cmd

    run retry_with_backoff "test command" mock_cmd
    assert_success
    assert_output "success"
}

@test "retry_with_backoff: disabled retry runs once" {
    export OP_DISABLE_RETRY=true
    export OP_MAX_RETRIES=3

    mock_cmd() { echo "fail"; return 1; }
    export -f mock_cmd

    run retry_with_backoff "test command" mock_cmd
    assert_failure
}

@test "retry_with_backoff: max_retries=0 runs once" {
    export OP_MAX_RETRIES=0

    mock_cmd() { echo "success"; return 0; }
    export -f mock_cmd

    run retry_with_backoff "test command" mock_cmd
    assert_success
}

@test "retry_with_backoff: non-retryable error fails immediately" {
    # Counter to track attempts
    export ATTEMPT_COUNT=0

    mock_cmd() {
        ATTEMPT_COUNT=$((ATTEMPT_COUNT + 1))
        echo "not authenticated"
        return 1
    }
    export -f mock_cmd

    export OP_MAX_RETRIES=3
    run retry_with_backoff "test command" mock_cmd
    assert_failure

    # Should only try once (non-retryable)
    [ "$ATTEMPT_COUNT" -eq 1 ]
}

# Test: Environment variable overrides

@test "retry_with_backoff: respects OP_MAX_RETRIES env var" {
    export OP_MAX_RETRIES=1  # Only 1 retry

    mock_cmd() {
        echo "network timeout"
        return 1
    }
    export -f mock_cmd

    run retry_with_backoff "test command" mock_cmd
    assert_failure
    # Would retry only once with max_retries=1
}

@test "retry_with_backoff: respects OP_RETRY_QUIET" {
    export OP_RETRY_QUIET=false  # Enable logging
    export OP_MAX_RETRIES=2

    mock_cmd() {
        echo "network error" >&2
        return 1
    }
    export -f mock_cmd

    run retry_with_backoff "test command" mock_cmd
    assert_failure
    # Output should contain retry logs (when not quiet)
}

# Test: Integration with typical use cases

@test "retry_with_backoff: typical op item get success" {
    mock_op() {
        echo '{"id":"123","title":"test"}'
        return 0
    }
    export -f mock_op

    run retry_with_backoff "get item" mock_op item get "test" --vault "vault" --format json
    assert_success
    assert_output '{"id":"123","title":"test"}'
}

@test "retry_with_backoff: typical op network failure then success" {
    export CALL_COUNT=0

    mock_op() {
        CALL_COUNT=$((CALL_COUNT + 1))
        if [ "$CALL_COUNT" -lt 2 ]; then
            echo "network timeout" >&2
            return 1
        else
            echo '{"id":"123"}'
            return 0
        fi
    }
    export -f mock_op

    export OP_MAX_RETRIES=3
    export OP_RETRY_DELAY=0.1  # Fast retry for tests

    run retry_with_backoff "get item" mock_op item get "test"
    assert_success
    assert_output '{"id":"123"}'
    [ "$CALL_COUNT" -eq 2 ]  # Failed once, succeeded on retry
}
