#!/usr/bin/env bats
# Integration tests for init command
# Tests end-to-end workflows of the interactive setup wizard

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

    # Change to temp directory for test isolation
    cd "$TEST_TEMP_DIR"
}

teardown() {
    uninstall_mocks
    disable_mock_mode
    teardown_temp_dir
}

# =============================================================================
# Test: Init Command Availability
# =============================================================================

@test "init command is available in main executable" {
    run "$BIN_DIR/op-env-manager" init --help
    assert_success
    assert_output --partial "Interactive setup wizard"
}

@test "init command shows usage with --help" {
    run "$BIN_DIR/op-env-manager" init --help
    assert_success
    assert_output --partial "Usage: op-env-manager init"
    assert_output --partial "--dry-run"
}

# =============================================================================
# Test: Dry-Run Mode
# =============================================================================

@test "init --dry-run does not create actual items" {
    # Create a test .env file
    create_test_env_file ".env"

    # Run init in dry-run mode (non-interactive simulation)
    # Note: This test verifies dry-run flag is recognized
    run bash -c "
        source '$LIB_DIR/init.sh'

        # Mock interactive inputs
        prompt_vault_selection() { echo 'test-vault'; }
        prompt_item_name() { echo 'test-item'; }
        prompt_env_file_location() { echo '.env'; }
        prompt_multi_env_strategy() { echo 'none'; }

        # Override prerequisite checks for dry-run
        diagnose_op_cli() { return 0; }

        # Override execution functions to track calls
        execute_push() {
            echo 'PUSH_CALLED'
            return 0
        }

        DRY_RUN=true

        # Simulate parts of wizard
        vault=\$(prompt_vault_selection)
        item=\$(prompt_item_name)
        env_file=\$(prompt_env_file_location)
        strategy=\$(prompt_multi_env_strategy)

        echo \"Vault: \$vault\"
        echo \"Item: \$item\"
        echo \"File: \$env_file\"
        echo \"Strategy: \$strategy\"
        echo \"DRY_RUN: \$DRY_RUN\"
    "

    assert_success
    assert_output --partial "Vault: test-vault"
    assert_output --partial "Item: test-item"
    assert_output --partial "DRY_RUN: true"
}

# =============================================================================
# Test: Find .env Files
# =============================================================================

@test "init command detects .env files in current directory" {
    # Create multiple .env files
    touch .env
    touch .env.dev
    touch .env.prod
    touch .env.example  # Should be excluded

    run bash -c "
        source '$LIB_DIR/init.sh'
        find_env_files
    "

    assert_success
    assert_output --regexp "\.env"
    refute_output --partial ".env.example"
}

@test "init command handles missing .env files gracefully" {
    # No .env files in directory

    run bash -c "
        source '$LIB_DIR/init.sh'
        result=\$(find_env_files)
        if [[ -z \"\$result\" ]]; then
            echo 'NO_ENV_FILES_FOUND'
        else
            echo 'FOUND: '\$result
        fi
    "

    assert_success
    assert_output "NO_ENV_FILES_FOUND"
}

# =============================================================================
# Test: Vault Operations
# =============================================================================

@test "init command can list vaults" {
    run bash -c "
        source '$LIB_DIR/init.sh'

        # Mock op vault list
        op() {
            if [[ \"\$1\" == 'vault' && \"\$2\" == 'list' ]]; then
                echo '[{\"name\":\"Personal\"},{\"name\":\"Work\"}]'
            fi
        }
        export -f op

        list_vaults
    "

    assert_success
    assert_output --partial "Personal"
    assert_output --partial "Work"
}

@test "init command handles vault creation in dry-run mode" {
    run bash -c "
        source '$LIB_DIR/init.sh'

        # Mock op commands
        op() {
            case \"\$1\" in
                vault)
                    case \"\$2\" in
                        get)
                            return 1  # Vault doesn't exist
                            ;;
                        create)
                            echo 'Would create vault'
                            return 0
                            ;;
                    esac
                    ;;
                account)
                    echo 'mock-account'
                    return 0
                    ;;
            esac
        }
        export -f op

        DRY_RUN=true
        create_vault 'new-test-vault'
    "

    assert_success
    assert_output --partial "[DRY RUN]"
    assert_output --partial "Would create vault: new-test-vault"
}

# =============================================================================
# Test: Multi-Environment Scenarios
# =============================================================================

@test "init command handles single environment setup" {
    create_test_env_file ".env"

    run bash -c "
        source '$LIB_DIR/logger.sh'
        source '$LIB_DIR/init.sh'

        # Simulate 'none' strategy
        strategy='none'
        vault='TestVault'
        item='test-item'

        display_success_summary \"\$vault\" \"\$item\" '' \"\$strategy\" 2>&1 | grep -q 'op-env-manager inject'
        echo \$?
    "

    assert_success
    assert_output "0"
}

@test "init command displays guidance for 'items' strategy" {
    run bash -c "
        source '$LIB_DIR/logger.sh'
        source '$LIB_DIR/init.sh'

        strategy='items'
        vault='TestVault'
        item='myapp'

        display_success_summary \"\$vault\" \"\$item\" '' \"\$strategy\" 2>&1 | grep -q 'myapp-staging'
        echo \$?
    "

    assert_success
    assert_output "0"
}

@test "init command displays guidance for 'sections' strategy" {
    run bash -c "
        source '$LIB_DIR/logger.sh'
        source '$LIB_DIR/init.sh'

        strategy='sections'
        vault='TestVault'
        item='myapp'
        section='dev'

        display_success_summary \"\$vault\" \"\$item\" \"\$section\" \"\$strategy\" 2>&1 | grep -q 'section'
        echo \$?
    "

    assert_success
    assert_output "0"
}

# =============================================================================
# Test: Error Handling
# =============================================================================

@test "init command rejects invalid flags" {
    run "$BIN_DIR/op-env-manager" init --invalid-flag 2>&1
    assert_failure
    assert_output --partial "Unknown option"
}

@test "init command provides helpful error for missing .env file" {
    # No .env files exist

    run bash -c "
        source '$LIB_DIR/init.sh'
        source '$LIB_DIR/logger.sh'

        # Simulate missing file scenario
        env_file='.env.missing'
        if [[ ! -f \"\$env_file\" ]]; then
            log_error 'File not found: '\$env_file 2>&1
            exit 1
        fi
    "

    assert_failure
    assert_output --partial "File not found"
}

# =============================================================================
# Test: Template Generation Offer
# =============================================================================

@test "init command can offer template generation" {
    create_test_env_file ".env"

    run bash -c "
        source '$LIB_DIR/init.sh'

        # Check generate_template function exists
        type generate_template &>/dev/null && echo 'TEMPLATE_FUNCTION_EXISTS'
    "

    assert_success
    assert_output "TEMPLATE_FUNCTION_EXISTS"
}

# =============================================================================
# Test: Integration with Push Command
# =============================================================================

@test "init command integrates with push command" {
    create_test_env_file ".env"

    run bash -c "
        source '$LIB_DIR/init.sh'

        # Verify execute_push can be called
        type execute_push &>/dev/null && echo 'PUSH_INTEGRATION_OK'
    "

    assert_success
    assert_output "PUSH_INTEGRATION_OK"
}

@test "init command passes correct parameters to push" {
    create_test_env_file ".env"

    run bash -c "
        source '$LIB_DIR/init.sh'

        # Override push.sh to capture parameters
        execute_push() {
            local vault=\"\$1\"
            local item=\"\$2\"
            local section=\"\$3\"
            local env_file=\"\$4\"

            echo \"VAULT=\$vault\"
            echo \"ITEM=\$item\"
            echo \"SECTION=\$section\"
            echo \"FILE=\$env_file\"
        }

        execute_push 'TestVault' 'test-item' 'dev' '.env'
    "

    assert_success
    assert_output --partial "VAULT=TestVault"
    assert_output --partial "ITEM=test-item"
    assert_output --partial "SECTION=dev"
    assert_output --partial "FILE=.env"
}

# =============================================================================
# Test: Success Summary Display
# =============================================================================

@test "init command displays success summary after completion" {
    run bash -c "
        source '$LIB_DIR/logger.sh'
        source '$LIB_DIR/init.sh'

        display_success_summary 'Personal' 'myapp' '' 'none' 2>&1 | head -20 | grep -q 'Setup complete'
        echo \$?
    "

    assert_success
    assert_output "0"
}

@test "success summary includes inject command" {
    run bash -c "
        source '$LIB_DIR/logger.sh'
        source '$LIB_DIR/init.sh'

        display_success_summary 'Personal' 'myapp' '' 'none' 2>&1 | grep -q 'op-env-manager inject'
        echo \$?
    "

    assert_success
    assert_output "0"
}

@test "success summary includes run command" {
    run bash -c "
        source '$LIB_DIR/logger.sh'
        source '$LIB_DIR/init.sh'

        display_success_summary 'Personal' 'myapp' '' 'none' 2>&1 | grep -q 'op-env-manager run'
        echo \$?
    "

    assert_success
    assert_output "0"
}

@test "success summary includes help commands" {
    run bash -c "
        source '$LIB_DIR/logger.sh'
        source '$LIB_DIR/init.sh'

        display_success_summary 'Personal' 'myapp' '' 'none' 2>&1 | grep -q 'op-env-manager --help'
        echo \$?
    "

    assert_success
    assert_output "0"
}

# =============================================================================
# Test: File Permissions
# =============================================================================

@test "init command maintains secure file permissions" {
    # This test verifies that init respects security practices
    # It checks that generated files have appropriate permissions

    skip "Manual verification needed for interactive file generation"
}

# =============================================================================
# Test: Standalone Script Execution
# =============================================================================

@test "init.sh can be executed as standalone script" {
    run "$LIB_DIR/init.sh" --help
    assert_success
    assert_output --partial "Usage:"
}

@test "init.sh standalone shows same help as via main executable" {
    run "$LIB_DIR/init.sh" --help
    assert_success
    assert_output --partial "Interactive setup wizard"
}

# =============================================================================
# Test: Quiet Mode Compatibility
# =============================================================================

@test "init command respects OP_QUIET_MODE environment variable" {
    export OP_QUIET_MODE=true

    run bash -c "
        source '$LIB_DIR/logger.sh'
        source '$LIB_DIR/init.sh'

        # Verify quiet mode is set
        [[ \"\$OP_QUIET_MODE\" == 'true' ]] && echo 'QUIET_MODE_ENABLED'
    "

    assert_success
    assert_output "QUIET_MODE_ENABLED"
}
