#!/usr/bin/env bash
#
# retry.sh - Retry logic with exponential backoff for 1Password CLI operations
#
# Provides configurable retry logic with exponential backoff for network errors.
# Retries transient failures (network/timeout) while failing fast on permanent errors.
#
# Configuration via environment variables:
#   OP_MAX_RETRIES      - Maximum retry attempts (default: 3, range: 0-10)
#   OP_RETRY_DELAY      - Initial delay in seconds (default: 1, range: 0.1-10)
#   OP_BACKOFF_FACTOR   - Exponential multiplier (default: 2, range: 1.5-5)
#   OP_MAX_DELAY        - Maximum delay cap in seconds (default: 30, range: 5-300)
#   OP_RETRY_JITTER     - Add randomness to delays (default: true)
#   OP_DISABLE_RETRY    - Disable all retry logic (default: false)
#   OP_RETRY_QUIET      - Silent retries, no logging (default: false)

set -eo pipefail

# Get script directory for sourcing dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source logger if not already loaded
if ! declare -f log_error &>/dev/null; then
    # shellcheck source=lib/logger.sh
    source "$SCRIPT_DIR/logger.sh"
fi

# Configuration defaults
readonly DEFAULT_MAX_RETRIES=3
readonly DEFAULT_RETRY_DELAY=1
readonly DEFAULT_BACKOFF_FACTOR=2
readonly DEFAULT_MAX_DELAY=30
readonly DEFAULT_RETRY_JITTER="true"
readonly DEFAULT_DISABLE_RETRY="false"
readonly DEFAULT_RETRY_QUIET="false"

# Configuration validation ranges
readonly MIN_MAX_RETRIES=0
readonly MAX_MAX_RETRIES=10
readonly MIN_RETRY_DELAY=0.1
readonly MAX_RETRY_DELAY=10
readonly MIN_BACKOFF_FACTOR=1.5
readonly MAX_BACKOFF_FACTOR=5
readonly MIN_MAX_DELAY=5
readonly MAX_MAX_DELAY=300

#######################################
# Check if an error is retryable (transient network/timeout errors)
# Arguments:
#   $1 - Error output from failed command
#   $2 - Exit code from failed command
# Returns:
#   0 if error is retryable, 1 if not retryable
#######################################
is_retryable_error() {
    local error_output="$1"
    local exit_code="$2"

    # Network-related errors (retryable)
    if echo "$error_output" | grep -qiE "network|timeout|connection|timed out|unreachable"; then
        return 0
    fi

    # Rate limiting (429 errors) - retryable
    if echo "$error_output" | grep -qiE "rate limit|too many requests|429"; then
        return 0
    fi

    # Temporary unavailability - retryable
    if echo "$error_output" | grep -qiE "temporarily unavailable|service unavailable|503"; then
        return 0
    fi

    # DNS resolution failures - retryable
    if echo "$error_output" | grep -qiE "could not resolve|dns|name resolution"; then
        return 0
    fi

    # Connection reset/refused - retryable
    if echo "$error_output" | grep -qiE "connection reset|connection refused|ECONNRESET|ECONNREFUSED"; then
        return 0
    fi

    # Non-retryable errors (permanent failures):
    # - Authentication failures (need user action)
    # - Not found errors (item/vault doesn't exist)
    # - Permission denied (access control issue)
    # - Invalid input (malformed request)
    if echo "$error_output" | grep -qiE "not authenticated|authentication|invalid token|permission denied|access denied|not found|no item|no vault|invalid"; then
        return 1
    fi

    # If exit code is 0, no error (shouldn't happen, but defensive)
    if [[ $exit_code -eq 0 ]]; then
        return 1
    fi

    # For unknown errors with non-zero exit, be conservative - don't retry
    # This prevents infinite retry loops on unexpected errors
    return 1
}

#######################################
# Add random jitter to delay (0-25% reduction)
# Prevents thundering herd when multiple processes retry simultaneously
# Arguments:
#   $1 - Base delay in seconds
# Outputs:
#   Delay with jitter applied (to stdout)
#######################################
add_jitter() {
    local base_delay="$1"

    # Generate random jitter: 0 to 25% reduction
    # Using $RANDOM (0-32767) to get percentage
    local jitter_percent=$(( RANDOM % 26 ))  # 0-25

    # Calculate jitter amount: base_delay * (jitter_percent / 100)
    # Using bc for floating point arithmetic
    local jitter_amount
    jitter_amount=$(echo "scale=2; $base_delay * $jitter_percent / 100" | bc)

    # Final delay: base_delay - jitter_amount
    local final_delay
    final_delay=$(echo "scale=2; $base_delay - $jitter_amount" | bc)

    echo "$final_delay"
}

#######################################
# Calculate exponential backoff delay
# Formula: delay = initial_delay * (backoff_factor ^ attempt)
# Capped at max_delay, optionally with jitter
# Arguments:
#   $1 - Attempt number (0-based: 0 = first retry)
#   $2 - Initial delay in seconds
#   $3 - Backoff factor (exponential multiplier)
#   $4 - Maximum delay cap in seconds
#   $5 - Enable jitter (true/false)
# Outputs:
#   Calculated delay in seconds (to stdout)
#######################################
calculate_backoff_delay() {
    local attempt="$1"
    local initial_delay="$2"
    local backoff_factor="$3"
    local max_delay="$4"
    local enable_jitter="$5"

    # Calculate exponential backoff: initial * (factor ^ attempt)
    # Using bc for floating point arithmetic
    local base_delay
    base_delay=$(echo "scale=2; $initial_delay * ($backoff_factor ^ $attempt)" | bc)

    # Cap at max_delay
    local capped_delay
    capped_delay=$(echo "if ($base_delay > $max_delay) $max_delay else $base_delay" | bc)

    # Add jitter if enabled
    if [[ "$enable_jitter" == "true" ]]; then
        add_jitter "$capped_delay"
    else
        echo "$capped_delay"
    fi
}

#######################################
# Validate retry configuration parameters
# Ensures all config values are within valid ranges
# Returns:
#   0 if valid, 1 if invalid (with error messages)
#######################################
validate_retry_config() {
    local config_valid=0

    # Validate OP_MAX_RETRIES
    if [[ -n "${OP_MAX_RETRIES:-}" ]]; then
        if ! [[ "$OP_MAX_RETRIES" =~ ^[0-9]+$ ]]; then
            log_error "Invalid OP_MAX_RETRIES='$OP_MAX_RETRIES': must be an integer"
            config_valid=1
        elif [[ $OP_MAX_RETRIES -lt $MIN_MAX_RETRIES || $OP_MAX_RETRIES -gt $MAX_MAX_RETRIES ]]; then
            log_error "Invalid OP_MAX_RETRIES='$OP_MAX_RETRIES': must be between $MIN_MAX_RETRIES and $MAX_MAX_RETRIES"
            config_valid=1
        fi
    fi

    # Validate OP_RETRY_DELAY
    if [[ -n "${OP_RETRY_DELAY:-}" ]]; then
        if ! [[ "$OP_RETRY_DELAY" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            log_error "Invalid OP_RETRY_DELAY='$OP_RETRY_DELAY': must be a number"
            config_valid=1
        else
            local delay_check
            delay_check=$(echo "$OP_RETRY_DELAY >= $MIN_RETRY_DELAY && $OP_RETRY_DELAY <= $MAX_RETRY_DELAY" | bc)
            if [[ $delay_check -eq 0 ]]; then
                log_error "Invalid OP_RETRY_DELAY='$OP_RETRY_DELAY': must be between $MIN_RETRY_DELAY and $MAX_RETRY_DELAY"
                config_valid=1
            fi
        fi
    fi

    # Validate OP_BACKOFF_FACTOR
    if [[ -n "${OP_BACKOFF_FACTOR:-}" ]]; then
        if ! [[ "$OP_BACKOFF_FACTOR" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            log_error "Invalid OP_BACKOFF_FACTOR='$OP_BACKOFF_FACTOR': must be a number"
            config_valid=1
        else
            local factor_check
            factor_check=$(echo "$OP_BACKOFF_FACTOR >= $MIN_BACKOFF_FACTOR && $OP_BACKOFF_FACTOR <= $MAX_BACKOFF_FACTOR" | bc)
            if [[ $factor_check -eq 0 ]]; then
                log_error "Invalid OP_BACKOFF_FACTOR='$OP_BACKOFF_FACTOR': must be between $MIN_BACKOFF_FACTOR and $MAX_BACKOFF_FACTOR"
                config_valid=1
            fi
        fi
    fi

    # Validate OP_MAX_DELAY
    if [[ -n "${OP_MAX_DELAY:-}" ]]; then
        if ! [[ "$OP_MAX_DELAY" =~ ^[0-9]+$ ]]; then
            log_error "Invalid OP_MAX_DELAY='$OP_MAX_DELAY': must be an integer"
            config_valid=1
        elif [[ $OP_MAX_DELAY -lt $MIN_MAX_DELAY || $OP_MAX_DELAY -gt $MAX_MAX_DELAY ]]; then
            log_error "Invalid OP_MAX_DELAY='$OP_MAX_DELAY': must be between $MIN_MAX_DELAY and $MAX_MAX_DELAY"
            config_valid=1
        fi
    fi

    # Validate boolean flags
    if [[ -n "${OP_RETRY_JITTER:-}" ]] && [[ "$OP_RETRY_JITTER" != "true" && "$OP_RETRY_JITTER" != "false" ]]; then
        log_error "Invalid OP_RETRY_JITTER='$OP_RETRY_JITTER': must be 'true' or 'false'"
        config_valid=1
    fi

    if [[ -n "${OP_DISABLE_RETRY:-}" ]] && [[ "$OP_DISABLE_RETRY" != "true" && "$OP_DISABLE_RETRY" != "false" ]]; then
        log_error "Invalid OP_DISABLE_RETRY='$OP_DISABLE_RETRY': must be 'true' or 'false'"
        config_valid=1
    fi

    if [[ -n "${OP_RETRY_QUIET:-}" ]] && [[ "$OP_RETRY_QUIET" != "true" && "$OP_RETRY_QUIET" != "false" ]]; then
        log_error "Invalid OP_RETRY_QUIET='$OP_RETRY_QUIET': must be 'true' or 'false'"
        config_valid=1
    fi

    return $config_valid
}

#######################################
# Execute command with retry logic and exponential backoff
# Retries transient network/timeout errors, fails fast on permanent errors
# Arguments:
#   $1 - Human-readable description of the command (for logging)
#   $@ - Command and arguments to execute
# Outputs:
#   Command output (stdout/stderr)
# Returns:
#   0 on success, non-zero on failure after all retries exhausted
#######################################
retry_with_backoff() {
    local command_description="$1"
    shift
    local -a command=("$@")

    # Validate configuration first
    if ! validate_retry_config; then
        log_error "Invalid retry configuration, please check environment variables"
        return 1
    fi

    # Load configuration from environment or use defaults
    local max_retries="${OP_MAX_RETRIES:-$DEFAULT_MAX_RETRIES}"
    local initial_delay="${OP_RETRY_DELAY:-$DEFAULT_RETRY_DELAY}"
    local backoff_factor="${OP_BACKOFF_FACTOR:-$DEFAULT_BACKOFF_FACTOR}"
    local max_delay="${OP_MAX_DELAY:-$DEFAULT_MAX_DELAY}"
    local enable_jitter="${OP_RETRY_JITTER:-$DEFAULT_RETRY_JITTER}"
    local disable_retry="${OP_DISABLE_RETRY:-$DEFAULT_DISABLE_RETRY}"
    local quiet_mode="${OP_RETRY_QUIET:-$DEFAULT_RETRY_QUIET}"

    # If retry disabled, execute once and return immediately
    if [[ "$disable_retry" == "true" ]]; then
        "${command[@]}"
        return $?
    fi

    # If max_retries is 0, execute once without retry
    if [[ $max_retries -eq 0 ]]; then
        "${command[@]}"
        return $?
    fi

    # Retry loop
    local attempt=0
    local max_attempts=$((max_retries + 1))  # +1 for initial attempt

    while [[ $attempt -lt $max_attempts ]]; do
        # Execute command and capture output and exit code
        local output
        local exit_code
        set +e  # Temporarily disable exit on error
        output=$("${command[@]}" 2>&1)
        exit_code=$?
        set -e  # Re-enable exit on error

        # Success - return immediately
        if [[ $exit_code -eq 0 ]]; then
            # Log success if this was a retry (not first attempt)
            if [[ $attempt -gt 0 ]] && [[ "$quiet_mode" != "true" ]]; then
                log_success "Succeeded on attempt $((attempt + 1))/$max_attempts: $command_description"
            fi
            echo "$output"
            return 0
        fi

        # Failure - check if retryable
        if ! is_retryable_error "$output" "$exit_code"; then
            # Non-retryable error - fail immediately
            if [[ "$quiet_mode" != "true" ]]; then
                log_error "Non-retryable error: $command_description (exit code $exit_code)"
            fi
            echo "$output" >&2
            return $exit_code
        fi

        # Retryable error - check if we have retries left
        attempt=$((attempt + 1))

        if [[ $attempt -ge $max_attempts ]]; then
            # Out of retries - fail
            if [[ "$quiet_mode" != "true" ]]; then
                log_error "Failed after $max_attempts attempts: $command_description"
                log_error "Last error: $(echo "$output" | head -n 1)"
            fi
            echo "$output" >&2
            return $exit_code
        fi

        # Calculate delay for next retry
        local retry_number=$((attempt - 1))  # 0-based for calculation
        local delay
        delay=$(calculate_backoff_delay "$retry_number" "$initial_delay" "$backoff_factor" "$max_delay" "$enable_jitter")

        # Log retry attempt
        if [[ "$quiet_mode" != "true" ]]; then
            log_warning "Attempt $attempt/$max_attempts failed: $command_description"
            log_info "Retrying in ${delay}s... (attempt $((attempt + 1))/$max_attempts)"
        fi

        # Sleep before next retry
        sleep "$delay"
    done

    # Should never reach here, but defensive
    echo "$output" >&2
    return $exit_code
}

# Export functions for use in other scripts
export -f is_retryable_error
export -f add_jitter
export -f calculate_backoff_delay
export -f validate_retry_config
export -f retry_with_backoff
