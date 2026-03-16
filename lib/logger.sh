#!/usr/bin/env bash
# Logger utility for VPS scripts
# Provides colored logging functions for script output

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check if output should be suppressed (quiet mode)
is_quiet_mode() {
    [[ "${OP_QUIET_MODE}" == "true" ]]
}

# Log levels
log_header() {
    is_quiet_mode && return 0
    echo -e "${MAGENTA}========================================${NC}" >&2
    echo -e "${MAGENTA}$1${NC}" >&2
    echo -e "${MAGENTA}========================================${NC}" >&2
}

log_step() {
    is_quiet_mode && return 0
    echo -e "${CYAN}▶ $1${NC}" >&2
}

log_info() {
    is_quiet_mode && return 0
    echo -e "${BLUE}ℹ $1${NC}" >&2
}

log_success() {
    is_quiet_mode && return 0
    echo -e "${GREEN}✓ $1${NC}" >&2
}

log_warning() {
    # Critical warnings are always shown (even in quiet mode)
    # To suppress a warning in quiet mode, use log_info instead
    echo -e "${YELLOW}⚠ $1${NC}" >&2
}

log_error() {
    # Errors are always shown (even in quiet mode)
    echo -e "${RED}✗ $1${NC}" >&2
}

log_suggestion() {
    echo -e "${YELLOW}  💡 $1${NC}" >&2
}

log_command() {
    echo -e "${CYAN}    $1${NC}" >&2
}

log_troubleshoot() {
    echo -e "${BLUE}  🔍 $1${NC}" >&2
}

log_divider() {
    echo -e "${NC}  ────────────────────────────────${NC}" >&2
}
