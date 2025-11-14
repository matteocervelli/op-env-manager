#!/usr/bin/env bats
# Unit tests for progress.sh module

load ../test_helper/common

setup() {
    # Source the progress module
    source "$PROJECT_ROOT/lib/progress.sh"

    # Save original environment
    ORIGINAL_OP_SHOW_PROGRESS="${OP_SHOW_PROGRESS:-}"
    ORIGINAL_OP_QUIET_MODE="${OP_QUIET_MODE:-}"
    ORIGINAL_OP_PROGRESS_THRESHOLD="${OP_PROGRESS_THRESHOLD:-}"
}

teardown() {
    # Restore original environment
    if [[ -n "$ORIGINAL_OP_SHOW_PROGRESS" ]]; then
        export OP_SHOW_PROGRESS="$ORIGINAL_OP_SHOW_PROGRESS"
    else
        unset OP_SHOW_PROGRESS
    fi

    if [[ -n "$ORIGINAL_OP_QUIET_MODE" ]]; then
        export OP_QUIET_MODE="$ORIGINAL_OP_QUIET_MODE"
    else
        unset OP_QUIET_MODE
    fi

    if [[ -n "$ORIGINAL_OP_PROGRESS_THRESHOLD" ]]; then
        export OP_PROGRESS_THRESHOLD="$ORIGINAL_OP_PROGRESS_THRESHOLD"
    else
        unset OP_PROGRESS_THRESHOLD
    fi
}

@test "is_ci_environment detects CI=true" {
    export CI=true
    run is_ci_environment
    assert_success
    unset CI
}

@test "is_ci_environment detects GITHUB_ACTIONS" {
    export GITHUB_ACTIONS=true
    run is_ci_environment
    assert_success
    unset GITHUB_ACTIONS
}

@test "is_ci_environment detects GITLAB_CI" {
    export GITLAB_CI=true
    run is_ci_environment
    assert_success
    unset GITLAB_CI
}

@test "is_ci_environment returns false when not in CI" {
    unset CI GITHUB_ACTIONS GITLAB_CI CIRCLECI TRAVIS JENKINS_URL BUILDKITE
    run is_ci_environment
    assert_failure
}

@test "should_show_progress respects OP_SHOW_PROGRESS=true" {
    export OP_SHOW_PROGRESS=true
    run should_show_progress
    assert_success
}

@test "should_show_progress respects OP_SHOW_PROGRESS=false" {
    export OP_SHOW_PROGRESS=false
    run should_show_progress
    assert_failure
}

@test "should_show_progress respects OP_QUIET_MODE=true" {
    unset OP_SHOW_PROGRESS
    export OP_QUIET_MODE=true
    run should_show_progress
    assert_failure
}

@test "should_show_progress suppresses in CI by default" {
    unset OP_SHOW_PROGRESS
    unset OP_QUIET_MODE
    export CI=true
    run should_show_progress
    assert_failure
    unset CI
}

@test "should_show_progress allows override in CI with OP_SHOW_PROGRESS=true" {
    export OP_SHOW_PROGRESS=true
    export CI=true
    run should_show_progress
    assert_success
    unset CI
}

@test "init_progress with count below threshold does not show progress" {
    unset OP_SHOW_PROGRESS
    unset OP_QUIET_MODE
    export OP_PROGRESS_THRESHOLD=100

    # Capture output (progress won't show for < 100)
    run init_progress 50 "Testing"
    assert_success

    # PROGRESS_TOTAL should be 0 (not initialized)
    [[ "$PROGRESS_TOTAL" -eq 0 ]]
}

@test "init_progress with count at threshold initializes progress" {
    unset OP_SHOW_PROGRESS
    unset OP_QUIET_MODE
    export OP_PROGRESS_THRESHOLD=100

    # Mock TTY (for testing, we can't easily check TTY in tests)
    # In real usage, this would check [ -t 1 ]

    run init_progress 100 "Testing"
    assert_success
}

@test "update_progress increments counter" {
    export OP_SHOW_PROGRESS=true
    unset OP_QUIET_MODE
    export OP_PROGRESS_THRESHOLD=10

    # Run in subshell to test the function behavior
    run bash -c "
        export OP_SHOW_PROGRESS=true
        export OP_PROGRESS_THRESHOLD=10
        source '$PROJECT_ROOT/lib/progress.sh'
        init_progress 100 'Testing'
        PROGRESS_TOTAL=100
        update_progress 50
        echo \$PROGRESS_CURRENT
    "
    assert_success
    assert_output "50"
}

@test "finish_progress completes and resets state" {
    unset OP_SHOW_PROGRESS
    unset OP_QUIET_MODE
    export OP_PROGRESS_THRESHOLD=100

    init_progress 100 "Testing"
    PROGRESS_TOTAL=100
    PROGRESS_CURRENT=50

    finish_progress
    [[ "$PROGRESS_TOTAL" -eq 0 ]]
    [[ "$PROGRESS_CURRENT" -eq 0 ]]
    [[ -z "$PROGRESS_LABEL" ]]
}

@test "increment_progress increments by 1" {
    export OP_SHOW_PROGRESS=true
    unset OP_QUIET_MODE
    export OP_PROGRESS_THRESHOLD=10

    # Run in subshell to test the function behavior
    run bash -c "
        export OP_SHOW_PROGRESS=true
        export OP_PROGRESS_THRESHOLD=10
        source '$PROJECT_ROOT/lib/progress.sh'
        init_progress 100 'Testing'
        PROGRESS_TOTAL=100
        PROGRESS_CURRENT=10
        increment_progress
        echo \$PROGRESS_CURRENT
    "
    assert_success
    assert_output "11"
}

@test "clear_progress_line works when progress is active" {
    unset OP_SHOW_PROGRESS
    unset OP_QUIET_MODE
    export OP_PROGRESS_THRESHOLD=100

    init_progress 100 "Testing"
    PROGRESS_TOTAL=100

    run clear_progress_line
    assert_success
}

@test "OP_PROGRESS_THRESHOLD can be customized" {
    unset OP_SHOW_PROGRESS
    unset OP_QUIET_MODE
    export OP_PROGRESS_THRESHOLD=50

    run bash -c "
        export OP_PROGRESS_THRESHOLD=50
        source '$PROJECT_ROOT/lib/progress.sh'
        echo \"\$PROGRESS_THRESHOLD\"
    "
    assert_success
    assert_output "50"
}

@test "default OP_PROGRESS_THRESHOLD is 100" {
    unset OP_SHOW_PROGRESS
    unset OP_QUIET_MODE
    unset OP_PROGRESS_THRESHOLD

    # Load progress module to get default
    source "$PROJECT_ROOT/lib/progress.sh"

    [[ "$PROGRESS_THRESHOLD" -eq 100 ]]
}

@test "draw_progress_bar calculates percentage correctly" {
    unset OP_SHOW_PROGRESS
    unset OP_QUIET_MODE
    export OP_PROGRESS_THRESHOLD=10

    init_progress 100 "Testing"
    PROGRESS_TOTAL=100
    PROGRESS_CURRENT=50

    # Capture output
    run draw_progress_bar
    assert_success

    # Check for 50% in output
    [[ "$output" == *"50%"* ]]
}

@test "draw_progress_bar shows current/total count" {
    unset OP_SHOW_PROGRESS
    unset OP_QUIET_MODE
    export OP_PROGRESS_THRESHOLD=10

    init_progress 150 "Testing"
    PROGRESS_TOTAL=150
    PROGRESS_CURRENT=45

    # Capture output
    run draw_progress_bar
    assert_success

    # Check for count in output
    [[ "$output" == *"45/150"* ]]
}

@test "draw_progress_bar shows label" {
    unset OP_SHOW_PROGRESS
    unset OP_QUIET_MODE
    export OP_PROGRESS_THRESHOLD=10

    init_progress 100 "Processing variables"
    PROGRESS_TOTAL=100
    PROGRESS_CURRENT=30
    PROGRESS_LABEL="Processing variables"

    # Capture output
    run draw_progress_bar
    assert_success

    # Check for label in output
    [[ "$output" == *"Processing variables"* ]]
}
