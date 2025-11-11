#!/usr/bin/env bash
# Installation script for op-env-manager
# by Matteo Cervelli

set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Installation defaults
DEFAULT_INSTALL_DIR="$HOME/.local/bin"
INSTALL_DIR=""
CREATE_SYMLINK=true
ADD_TO_PATH=true

# Print colored output
log_info() { echo -e "${BLUE}ℹ${NC}  $1"; }
log_success() { echo -e "${GREEN}✓${NC}  $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC}  $1"; }
log_error() { echo -e "${RED}✗${NC}  $1"; }
log_header() { echo -e "\n${BLUE}═══${NC} $1 ${BLUE}═══${NC}\n"; }

# Show usage
usage() {
    cat << EOF
op-env-manager installation script

USAGE:
    ./install.sh [options]

OPTIONS:
    --dir DIR           Installation directory (default: ~/.local/bin)
    --no-symlink        Don't create symlink in bin directory
    --no-path           Don't modify PATH in shell config
    -h, --help          Show this help

EXAMPLES:
    # Install to default location (~/.local/bin)
    ./install.sh

    # Install to custom directory
    ./install.sh --dir ~/opt

    # Install without modifying PATH
    ./install.sh --no-path

EOF
    exit 0
}

# Check prerequisites
check_prerequisites() {
    log_header "Checking Prerequisites"

    # Check for bash
    if [ -z "$BASH_VERSION" ]; then
        log_error "Bash is required to run op-env-manager"
        exit 1
    fi
    log_success "Bash: $BASH_VERSION"

    # Check for jq
    if ! command -v jq &> /dev/null; then
        log_warning "jq is not installed (required for JSON parsing)"
        log_info "Install with: brew install jq (macOS) or apt install jq (Linux)"
        echo ""
        read -rp "Continue anyway? (y/n): " response
        if [ "$response" != "y" ]; then
            exit 1
        fi
    else
        log_success "jq: $(jq --version)"
    fi

    # Check for 1Password CLI (optional at install time)
    if command -v op &> /dev/null; then
        log_success "1Password CLI: $(op --version)"
    else
        log_warning "1Password CLI not installed (required to use op-env-manager)"
        log_info "See docs/1PASSWORD_SETUP.md for installation instructions"
    fi

    echo ""
}

# Determine install directory
determine_install_dir() {
    if [ -z "$INSTALL_DIR" ]; then
        INSTALL_DIR="$DEFAULT_INSTALL_DIR"
    fi

    # Expand ~ to $HOME
    INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

    log_info "Installation directory: $INSTALL_DIR"

    # Create directory if it doesn't exist
    if [ ! -d "$INSTALL_DIR" ]; then
        log_info "Creating directory: $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi
}

# Install files
install_files() {
    log_header "Installing op-env-manager"

    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local target_dir="$INSTALL_DIR/op-env-manager"

    # Create target directory
    if [ -d "$target_dir" ]; then
        log_warning "Target directory already exists: $target_dir"
        read -rp "Overwrite? (y/n): " response
        if [ "$response" != "y" ]; then
            log_info "Installation cancelled"
            exit 0
        fi
        rm -rf "$target_dir"
    fi

    mkdir -p "$target_dir"
    log_info "Installing to: $target_dir"

    # Copy files
    cp -r "$script_dir/bin" "$target_dir/"
    cp -r "$script_dir/lib" "$target_dir/"
    cp -r "$script_dir/docs" "$target_dir/" 2>/dev/null || true

    # Set permissions
    chmod +x "$target_dir/bin/op-env-manager"
    chmod +x "$target_dir/lib/"*.sh

    log_success "Files installed successfully"

    # Create symlink
    if [ "$CREATE_SYMLINK" = true ]; then
        local symlink_path="$INSTALL_DIR/op-env-manager"

        if [ -L "$symlink_path" ] || [ -f "$symlink_path" ]; then
            rm -f "$symlink_path"
        fi

        ln -s "$target_dir/bin/op-env-manager" "$symlink_path"
        log_success "Symlink created: $symlink_path"
    fi

    echo ""
}

# Add to PATH if needed
setup_path() {
    if [ "$ADD_TO_PATH" != true ]; then
        log_info "Skipping PATH setup (--no-path specified)"
        return
    fi

    log_header "Setting up PATH"

    # Check if already in PATH
    if echo "$PATH" | grep -q "$INSTALL_DIR"; then
        log_success "$INSTALL_DIR is already in PATH"
        return
    fi

    log_warning "$INSTALL_DIR is not in PATH"

    # Detect shell
    local shell_config=""
    local shell_name=$(basename "$SHELL")

    case "$shell_name" in
        bash)
            shell_config="$HOME/.bashrc"
            ;;
        zsh)
            shell_config="$HOME/.zshrc"
            ;;
        fish)
            log_warning "Fish shell detected - manual PATH setup required"
            log_info "Add to ~/.config/fish/config.fish:"
            echo "  set -gx PATH $INSTALL_DIR \$PATH"
            return
            ;;
        *)
            log_warning "Unknown shell: $shell_name"
            log_info "Manually add to your shell config:"
            echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
            return
            ;;
    esac

    echo ""
    read -rp "Add $INSTALL_DIR to PATH in $shell_config? (y/n): " response
    if [ "$response" = "y" ]; then
        echo "" >> "$shell_config"
        echo "# Added by op-env-manager installer" >> "$shell_config"
        echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$shell_config"
        log_success "PATH updated in $shell_config"
        log_warning "Restart your shell or run: source $shell_config"
    else
        log_info "Skipped PATH setup"
        log_info "Manually add to $shell_config:"
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
    fi

    echo ""
}

# Show completion message
show_completion() {
    log_header "Installation Complete!"

    log_success "op-env-manager installed successfully"
    echo ""

    log_info "Next steps:"
    echo "  1. Restart your shell or run: source ~/.${SHELL##*/}rc"
    echo "  2. Install 1Password CLI (if not already): see docs/1PASSWORD_SETUP.md"
    echo "  3. Test installation: op-env-manager --version"
    echo "  4. Get started: op-env-manager --help"
    echo ""

    log_info "Quick start:"
    echo "  # Push .env to 1Password"
    echo "  op-env-manager push --vault \"Personal\" --env .env"
    echo ""
    echo "  # Inject secrets from 1Password"
    echo "  op-env-manager inject --vault \"Personal\" --output .env.local"
    echo ""

    log_info "Documentation: $INSTALL_DIR/op-env-manager/docs/"
    echo ""
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --no-symlink)
                CREATE_SYMLINK=false
                shift
                ;;
            --no-path)
                ADD_TO_PATH=false
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Main installation function
main() {
    parse_args "$@"

    echo ""
    log_header "op-env-manager Installer"
    echo "by Matteo Cervelli"
    echo ""

    check_prerequisites
    determine_install_dir
    install_files
    setup_path
    show_completion
}

# Run installer
main "$@"
