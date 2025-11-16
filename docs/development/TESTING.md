# Testing Guide for op-env-manager

This document describes how to run, write, and maintain tests for the op-env-manager project.

## Quick Start

### Install Dependencies

Install bats test framework (one-time):

```bash
brew install bats-core      # macOS
apt-get install bats        # Ubuntu/Debian
```

Git submodules are already included in the project.

### Run All Tests

```bash
bats tests/
```

### Run Specific Test File

```bash
bats tests/unit/test_logger.bats
```

### Run with Verbose Output

```bash
bats -t tests/unit/test_logger.bats
```

## Test Infrastructure

### Directory Structure

```
tests/
├── fixtures/                # Test data files
├── integration/             # Integration tests
├── performance/             # Performance benchmarks
├── security/                # Security validation tests
├── unit/                    # Unit tests
└── test_helper/             # Test infrastructure
    ├── common.bash          # Common utilities
    ├── mocks.bash           # 1Password CLI mocks
    └── (bats libraries)
```

### Test Categories

**Unit Tests** (`tests/unit/`)
- Test individual functions in isolation
- Examples: logger functions, parsing, conversion
- Run: `bats tests/unit/`

**Integration Tests** (`tests/integration/`)
- Test how components work together
- Examples: full command workflows
- Run: `bats tests/integration/`

**Security Tests** (`tests/security/`)
- Validate security properties
- Examples: secret handling, permissions, auth
- Run: `bats tests/security/`

**Performance Tests** (`tests/performance/`)
- Benchmark and validate performance
- Examples: large files, batch operations
- Run: `bats tests/performance/`

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
    assert_output --regexp "expected"
}
```

### Available Helpers

**Fixture Creation**
- create_test_env_file() - Basic .env file
- create_test_env_special() - Special characters
- create_test_env_large() - Many variables
- create_test_env_empty() - Empty file
- create_test_env_with_references() - op:// references

**Mock Management**
- enable_mock_mode() - Use mock 1Password CLI
- disable_mock_mode() - Use real 1Password CLI
- install_mocks() - Install mock op command
- uninstall_mocks() - Remove mock op command

**Assertions**
- assert_file_permissions() - Check chmod
- assert_function_exists() - Verify function
- assert_main_executable_exists() - Main script
- assert_lib_exists() - Library file

**1Password Helpers**
- has_op_cli() - Check if installed
- check_op_cli_version() - Verify version 2.0+

**Setup/Teardown**
- verify_test_environment() - Validate environment
- setup_temp_dir() - Create temp directory
- teardown_temp_dir() - Clean up

## Test Naming

Use clear, descriptive names:

```bash
@test "logger: log_header outputs three lines"
@test "parse_env: ignores comment lines"
@test "push_command: requires --vault argument"
```

## Code Quality

All test code must pass quality checks:

```bash
# Check all bash scripts
shellcheck -x tests/test_helper/common.bash
shellcheck -x tests/test_helper/mocks.bash

# Run all tests
bats tests/
```

Current Status: All tests pass, shellcheck validation complete.

## Environment Variables

Test-specific variables available:

- PROJECT_ROOT - Root directory of project
- BIN_DIR - Path to bin/ directory
- LIB_DIR - Path to lib/ directory
- FIXTURES_DIR - Path to fixtures/ directory
- TEST_TEMP_DIR - Temporary directory for test
- MOCK_OP - Set to "true" to use mocks
- TEST_DEBUG - Set to "true" for debug output

## CI/CD Integration

Add to `.git/hooks/pre-commit` for automated testing:

```bash
#!/bin/bash
shellcheck -x bin/* lib/* tests/test_helper/*.bash
bats tests/unit/
```

## Troubleshooting

**Tests not found:**
```bash
bats --version
ls tests/unit/test_logger.bats
```

**Test failures:**
```bash
bats -t tests/unit/test_logger.bats
TEST_DEBUG=true bats tests/
```

**Mock issues:**
```bash
echo "MOCK_OP=$MOCK_OP"
ls tests/test_helper/mocks.bash
```

## Resources

- bats documentation: https://bats-core.readthedocs.io/
- bats-assert: https://github.com/bats-core/bats-assert
- bats-file: https://github.com/bats-core/bats-file
- shellcheck: https://www.shellcheck.net/

For more details, see tests/QUALITY_REPORT.md
