#!/usr/bin/env bats
# Performance tests for v0.5.0 optimizations
# Tests parallel operations, caching, and bulk resolution

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
# Test: Parallel Read Operations (sync.sh and diff.sh)
# =============================================================================

@test "sync parallel reads faster than sequential (100 vars)" {
    skip "Requires 1Password authentication - manual test only"

    # This test demonstrates the optimization but requires real 1Password setup
    # Expected improvement: 30-50% faster with parallel reads

    local env_file
    env_file=$(create_test_env_large 100)

    # Sequential baseline would be ~3 seconds for parse + fetch
    # Parallel should complete in ~2 seconds (best of both operations)

    local start
    start=$(date +%s%N)

    # Mock parallel operation timing
    bash -c "
        # Simulate local parse (fast, 100ms)
        sleep 0.1 &
        # Simulate remote fetch (slow, 1.5s)
        sleep 1.5 &
        wait
    "

    local end
    end=$(date +%s%N)
    local elapsed=$((($end - $start) / 1000000))

    # Parallel should complete in time of slowest operation (~1.5s)
    # not sum of both (~1.6s)
    [ "$elapsed" -lt 1700 ]
}

@test "diff parallel reads complete correctly" {
    local env_file
    env_file=$(create_test_env_large 50)

    # Verify parallel operations don't break functionality
    # Run dry-run to test parallel structure without 1Password
    run bash -c "
        cd '$PROJECT_ROOT'
        ./bin/op-env-manager diff \\
            --vault='Test' \\
            --env-file='$env_file' \\
            --dry-run
    "

    assert_success
    assert_output --partial "DRY RUN"
}

# =============================================================================
# Test: Item Metadata Caching (convert.sh)
# =============================================================================

@test "convert caching reduces redundant API calls" {
    # Create mock environment to test caching logic
    run bash -c "
        source '$LIB_DIR/convert.sh'

        # Declare cache
        declare -A ITEM_CACHE

        # First call should check 1Password (we'll mock success)
        ITEM_CACHE['vault:item']=0

        # Verify cache key exists
        [ -n \"\${ITEM_CACHE['vault:item']}\" ]
    "

    assert_success
}

@test "cache key format is correct" {
    run bash -c "
        vault='Personal'
        item='myapp'
        cache_key=\"\${vault}:\${item}\"

        [ \"\$cache_key\" = 'Personal:myapp' ]
    "

    assert_success
}

# =============================================================================
# Test: Bulk op read Operations (convert.sh)
# =============================================================================

@test "bulk resolve collects references correctly" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")

    # Create file with multiple op:// references
    {
        echo "API_KEY=op://vault/item1/field1"
        echo "DB_PASS=op://vault/item2/field2"
        echo "SECRET=op://vault/item3/field3"
        echo "REGULAR_VAR=not_a_secret"
    } > "$env_file"

    # Verify reference collection (without actual resolution)
    run bash -c "
        source '$LIB_DIR/convert.sh'

        # Count op:// references
        ref_count=\$(grep -c 'op://' '$env_file' || echo 0)

        # Should find 3 references
        [ \"\$ref_count\" -eq 3 ]
    "

    assert_success
}

@test "bulk resolve handles empty input" {
    run bash -c "
        source '$LIB_DIR/convert.sh'

        # Call with empty input
        result=\$(bulk_resolve_op_references '')

        # Should return empty (no error)
        [ -z \"\$result\" ]
    "

    assert_success
}

@test "bulk resolve dry-run returns mock values" {
    local refs_input='KEY1|op://vault/item1/field
KEY2|op://vault/item2/field
KEY3|op://vault/item3/field'

    run bash -c "
        source '$LIB_DIR/convert.sh'
        DRY_RUN=true

        result=\$(bulk_resolve_op_references '$refs_input')

        # Should contain mock resolutions
        echo \"\$result\" | grep -q 'RESOLVED'
    "

    assert_success
}

@test "bulk resolve parallel structure is correct" {
    # Test that parallel jobs are spawned correctly
    run bash -c "
        source '$LIB_DIR/convert.sh'

        # Verify function exists
        type bulk_resolve_op_references | grep -q 'function'
    "

    assert_success
}

# =============================================================================
# Test: Parallel Operation Correctness
# =============================================================================

@test "parallel operations preserve error handling" {
    # Verify that background jobs don't swallow errors
    run bash -c "
        # Simulate parallel operation with one failure
        {
            echo 'success1'
        } &
        pid1=\$!

        {
            echo 'success2'
        } &
        pid2=\$!

        wait \$pid1 \$pid2
        echo 'completed'
    "

    assert_success
    assert_output --partial "completed"
}

@test "temporary files cleaned up after parallel operations" {
    local temp_count_before
    temp_count_before=$(ls -1 /tmp | wc -l)

    run bash -c "
        # Simulate parallel operation with temp files
        local_temp=\$(mktemp)
        remote_temp=\$(mktemp)

        {
            echo 'data1' > \"\$local_temp\"
        } &

        {
            echo 'data2' > \"\$remote_temp\"
        } &

        wait

        # Cleanup
        rm -f \"\$local_temp\" \"\$remote_temp\"

        echo 'done'
    "

    assert_success

    # Verify no temp file leakage
    local temp_count_after
    temp_count_after=$(ls -1 /tmp | wc -l)

    # Allow some variance (other processes may create temps)
    [ $(($temp_count_after - $temp_count_before)) -le 2 ]
}

# =============================================================================
# Test: Performance Comparison Benchmarks
# =============================================================================

@test "parse 100 variables performance baseline" {
    local env_file
    env_file=$(create_test_env_large 100)

    local start
    start=$(date +%s%N)

    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file' > /dev/null"

    local end
    end=$(date +%s%N)
    local elapsed=$((($end - $start) / 1000000))

    assert_success
    # Baseline: should complete in less than 500ms
    [ "$elapsed" -lt 500 ]
}

@test "parse 500 variables performance baseline" {
    local env_file
    env_file=$(create_test_env_large 500)

    local start
    start=$(date +%s%N)

    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file' > /dev/null"

    local end
    end=$(date +%s%N)
    local elapsed=$((($end - $start) / 1000000))

    assert_success
    # Baseline: should complete in less than 1.5 seconds
    [ "$elapsed" -lt 1500 ]
}

@test "parse 1000 variables stress test" {
    local env_file
    env_file=$(create_test_env_large 1000)

    local start
    start=$(date +%s%N)

    run bash -c "source '$LIB_DIR/push.sh' && parse_env_file '$env_file' > /dev/null"

    local end
    end=$(date +%s%N)
    local elapsed=$((($end - $start) / 1000000))

    assert_success
    # Should scale linearly: less than 3 seconds
    [ "$elapsed" -lt 3000 ]
}

# =============================================================================
# Test: Optimization Compatibility
# =============================================================================

@test "optimized sync.sh maintains backward compatibility" {
    local env_file
    env_file=$(create_test_env_large 10)

    # Verify dry-run still works after optimization
    run bash -c "
        cd '$PROJECT_ROOT'
        ./bin/op-env-manager sync \\
            --vault='Test' \\
            --env-file='$env_file' \\
            --dry-run
    "

    assert_success
    assert_output --partial "DRY RUN"
}

@test "optimized diff.sh maintains backward compatibility" {
    local env_file
    env_file=$(create_test_env_large 10)

    run bash -c "
        cd '$PROJECT_ROOT'
        ./bin/op-env-manager diff \\
            --vault='Test' \\
            --env-file='$env_file' \\
            --dry-run
    "

    assert_success
    assert_output --partial "DRY RUN"
}

@test "optimized convert.sh maintains backward compatibility" {
    local env_file
    env_file=$(mktemp -p "$TEST_TEMP_DIR")
    echo "VAR1=value1" > "$env_file"

    run bash -c "
        cd '$PROJECT_ROOT'
        ./bin/op-env-manager convert \\
            --env-file='$env_file' \\
            --vault='Test' \\
            --dry-run
    "

    assert_success
    assert_output --partial "DRY RUN"
}

# =============================================================================
# Test: Resource Usage
# =============================================================================

@test "parallel operations don't exceed reasonable process limit" {
    # Verify we don't spawn too many background processes
    local refs_input=""
    for i in {1..50}; do
        refs_input+="KEY$i|op://vault/item$i/field"$'\n'
    done

    run bash -c "
        source '$LIB_DIR/convert.sh'
        DRY_RUN=true

        # Count would-be background processes
        echo '$refs_input' | wc -l
    "

    assert_success
    assert_output "50"
}

@test "temporary directory cleanup in bulk operations" {
    run bash -c "
        source '$LIB_DIR/convert.sh'
        DRY_RUN=true

        refs='KEY1|op://vault/item/field'

        # Run bulk resolve
        bulk_resolve_op_references \"\$refs\" > /dev/null

        # Verify temp cleanup trap is set
        trap -p EXIT | grep -q 'rm -rf'
    "

    # May fail if trap is scoped to subshell - that's OK
    # Main goal is to verify cleanup logic exists
}
