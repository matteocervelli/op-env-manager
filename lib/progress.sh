#!/usr/bin/env bash
set -eo pipefail

# Progress bar module for op-env-manager
# Provides ASCII progress indicators for operations with 100+ variables

# Progress bar configuration
PROGRESS_BAR_WIDTH=50
PROGRESS_CURRENT=0
PROGRESS_TOTAL=0
PROGRESS_LABEL=""
PROGRESS_THRESHOLD="${OP_PROGRESS_THRESHOLD:-100}"

# CI environment detection patterns
CI_ENV_VARS=(
    "CI"
    "GITHUB_ACTIONS"
    "GITLAB_CI"
    "CIRCLECI"
    "TRAVIS"
    "JENKINS_URL"
    "BUILDKITE"
    "DRONE"
    "TEAMCITY_VERSION"
    "BITBUCKET_PIPELINE"
)

# Detect if running in CI/CD environment
is_ci_environment() {
    for var in "${CI_ENV_VARS[@]}"; do
        # Use parameter expansion with default to avoid unbound variable error
        if [[ -n "${!var:-}" ]]; then
            return 0  # True - is CI
        fi
    done
    return 1  # False - not CI
}

# Check if progress bars should be displayed
should_show_progress() {
    # Explicit override via environment variable
    if [[ -n "${OP_SHOW_PROGRESS:-}" ]]; then
        [[ "${OP_SHOW_PROGRESS}" == "true" ]] && return 0 || return 1
    fi

    # Respect global quiet mode
    if [[ "${OP_QUIET_MODE:-false}" == "true" ]]; then
        return 1
    fi

    # Auto-suppress in CI environments
    if is_ci_environment; then
        return 1
    fi

    # Check if stdout is a terminal (not piped/redirected)
    if [[ ! -t 1 ]]; then
        return 1
    fi

    return 0
}

# Initialize progress tracking
# Usage: init_progress <total> <label>
init_progress() {
    local total="$1"
    local label="${2:-Processing}"

    # Check if we should show progress
    if ! should_show_progress; then
        return 0
    fi

    # Only show progress for operations above threshold
    if [[ "$total" -lt "$PROGRESS_THRESHOLD" ]]; then
        return 0
    fi

    PROGRESS_TOTAL="$total"
    PROGRESS_CURRENT=0
    PROGRESS_LABEL="$label"

    # Draw initial progress bar
    draw_progress_bar
}

# Update progress counter and redraw bar
# Usage: update_progress <current>
update_progress() {
    local current="$1"

    # Check if we should show progress
    if ! should_show_progress; then
        return 0
    fi

    # Only update if progress was initialized
    if [[ "$PROGRESS_TOTAL" -eq 0 ]]; then
        return 0
    fi

    PROGRESS_CURRENT="$current"
    draw_progress_bar
}

# Draw the progress bar
draw_progress_bar() {
    # Calculate percentage
    local percent=0
    if [[ "$PROGRESS_TOTAL" -gt 0 ]]; then
        percent=$(( (PROGRESS_CURRENT * 100) / PROGRESS_TOTAL ))
    fi

    # Calculate filled portion of bar
    local filled=$(( (PROGRESS_CURRENT * PROGRESS_BAR_WIDTH) / PROGRESS_TOTAL ))
    local empty=$(( PROGRESS_BAR_WIDTH - filled ))

    # Build progress bar string
    local bar="["
    for ((i=0; i<filled; i++)); do
        bar+="="
    done
    if [[ $filled -lt $PROGRESS_BAR_WIDTH ]]; then
        bar+=">"
        empty=$((empty - 1))
    fi
    for ((i=0; i<empty; i++)); do
        bar+=" "
    done
    bar+="]"

    # Print progress bar with carriage return (in-place update)
    printf "\r%s %s %d/%d (%d%%) %s" \
        "$bar" \
        "" \
        "$PROGRESS_CURRENT" \
        "$PROGRESS_TOTAL" \
        "$percent" \
        "$PROGRESS_LABEL"
}

# Finish progress and print newline
finish_progress() {
    # Check if we should show progress
    if ! should_show_progress; then
        return 0
    fi

    # Only finish if progress was initialized
    if [[ "$PROGRESS_TOTAL" -eq 0 ]]; then
        return 0
    fi

    # Set to 100% complete
    PROGRESS_CURRENT="$PROGRESS_TOTAL"
    draw_progress_bar

    # Print newline to finalize
    printf "\n"

    # Reset state
    PROGRESS_TOTAL=0
    PROGRESS_CURRENT=0
    PROGRESS_LABEL=""
}

# Clear progress bar line (for error messages mid-progress)
clear_progress_line() {
    if should_show_progress && [[ "$PROGRESS_TOTAL" -gt 0 ]]; then
        # Clear the line by printing spaces
        printf "\r%*s\r" "$((PROGRESS_BAR_WIDTH + 30))" ""
    fi
}

# Increment progress by 1
increment_progress() {
    update_progress $((PROGRESS_CURRENT + 1))
}
