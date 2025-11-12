# Test Suite for op-env-manager

This directory contains the comprehensive test suite for op-env-manager, including unit tests, integration tests, security tests, and performance benchmarks.

## Quick Start

### Run All Tests

```bash
# Run unit and integration tests
make test

# Run all test suites (unit, integration, security, performance)
make test-all

# Run tests with verbose output
make test-verbose
```

### Check Code Quality

```bash
# Check all shell scripts with shellcheck
make shellcheck

# Check and run tests
make check
```

## Test Organization

```
tests/
├── unit/                    # Unit tests for individual functions
├── integration/             # Integration tests for complete workflows
├── security/                # Security and safety tests
├── performance/             # Performance and benchmark tests
├── fixtures/                # Test data files
└── test_helper/             # Test infrastructure and utilities
    ├── common.bash          # Common test helpers
    ├── mocks.bash           # Mock 1Password CLI
    └── (bats libraries)
```

## Test Categories

### Unit Tests (`tests/unit/`)

Test individual functions in isolation:

- **test_logger.bats** - Logging functions and output formatting
- **test_push.bats** - Parse .env files, argument parsing for push command
- **test_inject.bats** - Field extraction, argument parsing for inject command
- **test_convert.bats** - op:// reference detection and extraction
- **test_template.bats** - Template file generation and op:// reference creation

Run with:
```bash
make test-unit
# or
bats tests/unit/
```

### Integration Tests (`tests/integration/`)

Test how components work together:

- **test_push_inject_cycle.bats** - Full push/inject workflow, multi-environment handling, large files
- **test_run_command.bats** - Run command with template generation, section handling

Run with:
```bash
make test-integration
# or
bats tests/integration/
```

### Security Tests (`tests/security/`)

Validate security properties:

- **test_secret_handling.bats** - Secret handling, file permissions, no secret logging, authentication checks, injection prevention

Run with:
```bash
make test-security
# or
bats tests/security/
```

### Performance Tests (`tests/performance/`)

Benchmark and validate performance:

- **test_large_files.bats** - Large file parsing, memory usage, comment/empty line efficiency, template generation performance

Run with:
```bash
make test-performance
# or
bats tests/performance/
```

## Running Specific Tests

Run a specific test file:
```bash
bats tests/unit/test_logger.bats
```

Run tests matching a pattern:
```bash
bats tests/unit/test_logger.bats -t "log_header"
```

Run with verbose output:
```bash
bats -t tests/unit/test_logger.bats
```

Enable debug output:
```bash
TEST_DEBUG=true bats tests/unit/test_logger.bats
```

## Test Infrastructure

### Common Helpers (`test_helper/common.bash`)

Provides test setup, teardown, and helper functions:

**Setup/Teardown:**
- `setup_temp_dir()` - Create temporary directory for test
- `teardown_temp_dir()` - Clean up temporary directory
- `verify_test_environment()` - Validate test environment

**Fixture Creation:**
- `create_test_env_file()` - Basic .env file with standard variables
- `create_test_env_special()` - .env with special characters and quotes
- `create_test_env_large(count)` - Large .env with many variables
- `create_test_env_empty()` - Empty .env file
- `create_test_env_with_references()` - .env with op:// references

**Assertions:**
- `assert_file_permissions(file, perms)` - Verify chmod
- `assert_function_exists(name)` - Verify function exists
- `assert_main_executable_exists()` - Verify main script
- `assert_lib_exists(name)` - Verify library file

**1Password Helpers:**
- `has_op_cli()` - Check if CLI installed
- `check_op_cli_version()` - Verify version 2.0+

**Mock Management:**
- `enable_mock_mode()` - Use mock 1Password CLI
- `install_mocks()` - Install mock op command
- `uninstall_mocks()` - Remove mock op command

### Mock Infrastructure (`test_helper/mocks.bash`)

Provides mock implementations of the 1Password CLI for testing without real authentication:

**Mock Functions:**
- `mock_op()` - Main mock op command
- `mock_op_account_list()` - Mock account list response
- `mock_op_vault_list()` - Mock vault list response
- `mock_op_item_list()` - Mock item list with filters
- `mock_op_item_get_with_fields()` - Mock item with fields
- `install_mocks()` - Install mock in PATH
- `uninstall_mocks()` - Clean up mocks

**Usage:**
```bash
load ../test_helper/mocks

setup() {
    enable_mock_mode
    install_mocks
}

teardown() {
    uninstall_mocks
}

@test "my test using mocks" {
    run my_command_that_uses_op
    assert_success
}
```

## Writing Tests

### Basic Template

```bash
#!/usr/bin/env bats
load ../test_helper/common

setup() {
    verify_test_environment
    setup_temp_dir
    source "$LIB_DIR/module.sh"
}

teardown() {
    teardown_temp_dir
}

@test "description of what is tested" {
    local test_file
    test_file=$(create_test_env_file)
    
    run some_function "$test_file"
    
    assert_success
    assert_output --regexp "expected pattern"
}
```

### Test Naming Convention

Use clear, descriptive names:

```bash
@test "logger: log_header outputs three lines"
@test "parse_env: ignores comment lines"
@test "push_command: requires --vault argument"
@test "template: generates op:// reference for field"
```

### Using Fixtures

```bash
@test "works with test fixtures" {
    # Create test data
    local env_file
    env_file=$(create_test_env_file)
    
    # Use in test
    run my_function "$env_file"
    
    assert_success
}

@test "handles large files" {
    local env_file
    env_file=$(create_test_env_large 100)  # 100 variables
    
    run my_function "$env_file"
    assert_success
}

@test "handles special characters" {
    local env_file
    env_file=$(create_test_env_special)
    
    run my_function "$env_file"
    assert_success
}
```

### Using Mocks

```bash
@test "works with mocked 1Password" {
    load ../test_helper/mocks
    
    run my_1password_command
    assert_success
    # op CLI calls are mocked, no real authentication needed
}
```

## Code Quality Standards

All code must pass quality checks:

```bash
# Check shell scripts
make shellcheck

# Run all tests
make test-all

# Combined quality check
make check
```

### shellcheck Rules

We suppress `SC1091` (not following sourced files) as tests dynamically source modules.

Check quality:
```bash
shellcheck -x lib/*.sh bin/op-env-manager
shellcheck -x tests/test_helper/*.bash
```

## Coverage Analysis

Target coverage: **80% minimum**

Coverage breakdown by category:
- **Unit Tests**: ~60% - Core function coverage
- **Integration Tests**: ~15% - Workflow coverage
- **Security Tests**: ~3% - Security-specific coverage
- **Performance Tests**: ~2% - Performance-specific coverage

Run tests and view coverage report:
```bash
make coverage
```

## Continuous Integration

The test suite is designed for CI/CD integration:

```bash
#!/bin/bash
set -eo pipefail

# Install dependencies
make install-deps

# Run quality checks
make shellcheck

# Run all tests
make test-all

echo "All tests passed!"
```

See `.github/workflows/test.yml` for GitHub Actions configuration.

## Troubleshooting

### Tests not found

```bash
# Verify bats is installed
bats --version

# List test files
ls tests/unit/test_*.bats

# Check test directory exists
ls -la tests/
```

### Test failures

```bash
# Run specific failing test with verbose output
bats -t tests/unit/test_logger.bats --filter "specific test name"

# Enable debug mode
TEST_DEBUG=true bats tests/unit/test_logger.bats

# Run with set -x for bash debugging
bash -x tests/unit/test_logger.bats 2>&1 | head -50
```

### Mock issues

```bash
# Check mocks are installed
echo $MOCK_OP
echo $MOCK_BIN_DIR

# Verify mock op command
which op
op --version

# Check mocks.bash exists
ls -la tests/test_helper/mocks.bash
```

### Performance test timeouts

Performance tests use date for timing. On some systems, timing may vary:

```bash
# Run performance tests individually
bats -t tests/performance/test_large_files.bats::parse_env_file

# Increase timeout in test if needed
```

## Resources

- **bats documentation**: https://bats-core.readthedocs.io/
- **bats-assert**: https://github.com/bats-core/bats-assert
- **bats-file**: https://github.com/bats-core/bats-file
- **shellcheck**: https://www.shellcheck.net/
- **bash testing patterns**: https://github.com/bats-core/bats-core/wiki

## Contributing

When adding new tests:

1. Follow the existing directory structure (unit/integration/security/performance)
2. Use clear test names following the convention
3. Include setup/teardown for resource cleanup
4. Use helpers from test_helper/common.bash
5. Test both success and failure cases
6. Verify tests pass and are shellcheck compliant
7. Update this README with new test categories

## Current Coverage Status

- **Unit Tests**: 122 tests passing
- **Integration Tests**: 24 tests passing
- **Security Tests**: 10 tests passing
- **Performance Tests**: 2 tests passing
- **Total**: 158+ tests passing

For detailed results: `make test-all`

