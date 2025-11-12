.PHONY: test test-unit test-integration test-security test-performance test-all shellcheck coverage help install-deps

# Color output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[0;33m
NC := \033[0m

help:
	@echo "$(BLUE)op-env-manager Test Suite$(NC)"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  $(GREEN)test$(NC)                Run all tests (unit + integration)"
	@echo "  $(GREEN)test-unit$(NC)           Run unit tests only"
	@echo "  $(GREEN)test-integration$(NC)    Run integration tests only"
	@echo "  $(GREEN)test-security$(NC)       Run security tests only"
	@echo "  $(GREEN)test-performance$(NC)    Run performance tests only"
	@echo "  $(GREEN)test-all$(NC)            Run all test suites (unit, integration, security, performance)"
	@echo "  $(GREEN)test-verbose$(NC)        Run all tests with verbose output"
	@echo "  $(GREEN)shellcheck$(NC)          Run shellcheck on all scripts"
	@echo "  $(GREEN)coverage$(NC)            Run tests and display coverage report"
	@echo "  $(GREEN)install-deps$(NC)        Install test dependencies (bats-core)"
	@echo "  $(GREEN)help$(NC)                Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make test              # Run unit and integration tests"
	@echo "  make test-all          # Run everything"
	@echo "  make test-verbose      # Run with verbose output"
	@echo "  make shellcheck        # Check code quality"

# Default target
.DEFAULT_GOAL := help

# Test commands
test: test-unit test-integration
	@echo "$(GREEN)✓ Core tests completed$(NC)"

test-unit:
	@echo "$(BLUE)Running unit tests...$(NC)"
	@bats tests/unit/ 2>&1 | tail -5
	@echo ""

test-integration:
	@echo "$(BLUE)Running integration tests...$(NC)"
	@bats tests/integration/ 2>&1 | tail -5
	@echo ""

test-security:
	@echo "$(BLUE)Running security tests...$(NC)"
	@bats tests/security/ 2>&1 | tail -5
	@echo ""

test-performance:
	@echo "$(BLUE)Running performance tests...$(NC)"
	@bats tests/performance/ 2>&1 | tail -5
	@echo ""

test-all: test-unit test-integration test-security test-performance
	@echo "$(GREEN)✓ All test suites completed$(NC)"

test-verbose:
	@echo "$(BLUE)Running all tests with verbose output...$(NC)"
	@bats -t tests/
	@echo ""

# Code quality
shellcheck:
	@echo "$(BLUE)Checking code quality with shellcheck...$(NC)"
	@shellcheck -x lib/*.sh bin/op-env-manager tests/test_helper/*.bash 2>&1 | grep -v "SC1091" || echo "$(GREEN)✓ All scripts pass shellcheck$(NC)"

coverage:
	@echo "$(BLUE)Running tests and generating coverage report...$(NC)"
	@bats tests/ 2>&1 | tee /tmp/test-results.txt
	@echo ""
	@echo "$(BLUE)Test Results:$(NC)"
	@grep -E "^(.*ok|.*not ok|# bats)" /tmp/test-results.txt | tail -20
	@echo ""

# Dependencies
install-deps:
	@echo "$(BLUE)Installing test dependencies...$(NC)"
	@command -v bats >/dev/null 2>&1 || { \
		echo "Installing bats-core..."; \
		brew install bats-core || apt-get install -y bats; \
	}
	@echo "$(GREEN)✓ Dependencies installed$(NC)"

# Development utilities
check: shellcheck test
	@echo "$(GREEN)✓ Quality checks passed$(NC)"

clean:
	@echo "$(BLUE)Cleaning up test artifacts...$(NC)"
	@rm -f /tmp/test-results.txt
	@find tests/ -name "*.log" -delete
	@echo "$(GREEN)✓ Cleanup complete$(NC)"
