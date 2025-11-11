#!/usr/bin/env bash
# Install 1Password CLI for CNA CRM secret management
# Used to securely store and retrieve production credentials
#
# Usage:
#   ./scripts/setup/install-1password-cli.sh

set -eo pipefail

# Script directory and root detection
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source utilities
source "$PROJECT_ROOT/scripts/utils/logger.sh"

# Install 1Password CLI
install_1password_cli() {
    log_step "Installing 1Password CLI for Secret Management"

    if command -v op &> /dev/null; then
        local version
        version=$(op --version)
        log_success "1Password CLI already installed (version $version)"
        return 0
    fi

    log_info "Adding 1Password repository..."

    # Add GPG key
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

    # Add repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
        sudo tee /etc/apt/sources.list.d/1password.list > /dev/null

    # Add debsig policies
    sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
    curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol | \
        sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol > /dev/null

    # Add debsig keyring
    sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
    curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
        sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg

    # Install 1Password CLI
    log_info "Installing 1Password CLI package..."
    sudo apt-get update -qq
    sudo apt-get install -y 1password-cli

    log_success "1Password CLI installed successfully"

    # Show version
    local version
    version=$(op --version)
    log_info "Installed version: $version"
}

# Main function
main() {
    log_header "1Password CLI Installation"
    echo ""

    # Check if running on Ubuntu
    if [ ! -f /etc/os-release ]; then
        log_error "Cannot determine OS. This script requires Ubuntu."
        exit 1
    fi

    # shellcheck disable=SC1091
    source /etc/os-release
    if [ "$ID" != "ubuntu" ]; then
        log_error "This script is designed for Ubuntu. Detected: $ID"
        exit 1
    fi

    log_info "OS: Ubuntu $VERSION"
    echo ""

    # Install 1Password CLI
    install_1password_cli

    # Post-installation instructions
    echo ""
    log_header "Next Steps"
    echo ""
    log_info "Configure 1Password CLI:"
    echo "  1. Sign in: op signin"
    echo "  2. Create vault for CNA CRM: op vault create \"CNA CRM Production\""
    echo "  3. Store credentials:"
    echo ""
    echo "     # PostgreSQL password"
    echo "     op item create --category=password \\"
    echo "       --title=\"CNA CRM PostgreSQL\" \\"
    echo "       --vault=\"CNA CRM Production\" \\"
    echo "       password=<generated-password>"
    echo ""
    echo "     # Redis password"
    echo "     op item create --category=password \\"
    echo "       --title=\"CNA CRM Redis\" \\"
    echo "       --vault=\"CNA CRM Production\" \\"
    echo "       password=<generated-password>"
    echo ""
    echo "     # JWT secret"
    echo "     op item create --category=password \\"
    echo "       --title=\"CNA CRM JWT Secret\" \\"
    echo "       --vault=\"CNA CRM Production\" \\"
    echo "       password=<generated-secret>"
    echo ""
    log_info "Retrieve credentials:"
    echo "  op item get \"CNA CRM PostgreSQL\" --fields password"
    echo ""
    log_success "🔐 1Password CLI ready for secure credential management!"
}

# Run main function
main "$@"
