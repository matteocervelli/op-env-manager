# Changelog

All notable changes to op-env-manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2025-01-14

### Added - Interactive Setup & User Experience

#### Init Command
- **Interactive Setup Wizard** (`lib/init.sh`):
  - Guided onboarding for new users and project setup
  - Auto-detection of existing `.env` files in current directory
  - Vault selection with option to create new vaults
  - Smart item naming with sensible defaults
  - Multi-environment strategy selection:
    - Separate items (`myapp-dev`, `myapp-prod`)
    - Sections within single item (`myapp` with `dev`/`prod` sections)
  - Integration with existing push and template commands
  - Comprehensive dry-run support for workflow preview
  - Success summary with actionable next steps

#### Progress Indicators
- **Progress Module** (`lib/progress.sh`):
  - Visual progress bars for operations with 100+ variables
  - Auto-detection of CI/CD environments (suppresses progress in CI)
  - TTY detection (only shows in interactive terminals)
  - Configurable threshold via `OP_PROGRESS_THRESHOLD`
  - Manual control via `OP_SHOW_PROGRESS` environment variable
  - Format: `[=====>     ] 45/150 (30%) Processing variables...`

#### Global Quiet Mode
- **Quiet Flag** (`--quiet`):
  - Suppresses informational output (`log_info`, `log_step`, `log_success`)
  - Always shows errors and critical warnings
  - Sets `OP_QUIET_MODE=true` for subprocess inheritance
  - Ideal for scripting and CI/CD pipelines
  - Applies to all commands: `op-env-manager --quiet <command>`

#### Documentation
- **docs/QUICKSTART.md**: Enhanced with init command examples
- **README.md**: Updated with interactive setup workflow
- **Testing documentation**: Added init command test coverage

#### Testing
- **tests/unit/test_init.bats**: 70+ unit tests covering:
  - Interactive prompts and defaults
  - Vault selection/creation flow
  - Multi-environment strategies
  - .env file detection and exclusions
  - Dry-run mode behavior
  - Integration with push/template commands
- **tests/integration/test_init_e2e.bats**: 30+ end-to-end tests
- **tests/unit/test_progress.bats**: Progress bar functionality tests

### Changed
- **bin/op-env-manager**: Added `init` command to main dispatcher
- **lib/logger.sh**: Enhanced with quiet mode support
- **All commands**: Now respect `OP_QUIET_MODE` for CI/CD friendliness

### Performance Notes
- Progress bars add negligible overhead (<0.1s for 1000+ variables)
- Auto-suppressed in non-interactive environments (no CI/CD impact)
- Init wizard completes in <2 minutes for most setups

### Related Issues
- Closes #10 - Interactive setup wizard (init command)
- Closes #8 - Progress indicators for large files

---

## [0.2.0] - 2025-01-13

### Added - Reliability & Multiline Support

#### Retry Logic with Exponential Backoff
- **Retry Module** (`lib/retry.sh`):
  - Automatic retry for transient 1Password CLI failures
  - Exponential backoff with configurable jitter
  - Smart error classification (retryable vs. permanent)
  - Comprehensive configuration via environment variables:
    - `OP_MAX_RETRIES` (default: 3, range: 0-10)
    - `OP_RETRY_DELAY` (default: 1s, range: 0.1-10s)
    - `OP_BACKOFF_FACTOR` (default: 2, range: 1.5-5)
    - `OP_MAX_DELAY` (default: 30s, range: 5-300s)
    - `OP_RETRY_JITTER` (default: true)
  - Retryable errors: network issues, timeouts, rate limiting (429), service unavailability (503)
  - Non-retryable errors: authentication failures, not found, permission denied

#### Multiline Value Support
- **Enhanced .env Parsing**:
  - Support for quoted multiline values in `.env` files
  - Proper handling of newlines within double-quoted strings
  - Storage format: Converted to `\n` escape sequences for 1Password
  - Injection format: Restored to actual newlines when injected
  - Use cases: Private keys, JSON configs, certificates, SQL queries

#### Documentation
- **README.md**: Added retry configuration section
- **CLAUDE.md**: Comprehensive retry logic documentation with examples
- **Error handling guide**: Best practices for network resilience

#### Testing
- **tests/unit/test_retry.bats**: Retry logic unit tests
- **tests/integration/test_multiline.bats**: Multiline value tests
- **examples/.env.multiline**: Example file with multiline values

### Changed
- **All commands**: Wrapped 1Password CLI calls with retry logic
- **lib/push.sh**, **lib/inject.sh**: Enhanced to handle multiline values
- **lib/convert.sh**: `op read` calls now use retry wrapper

### Performance Notes
- Default retry sequence: ~7 seconds total (3 retries: 1s, 2s, 4s)
- Network resilience significantly improved for unstable connections
- No performance impact when operations succeed on first attempt

### Related Issues
- Closes #6 - Enhance error messages with actionable suggestions
- Closes #7 - Add retry logic for network failures

---

## [0.1.0] - 2025-01-11

### Added - Initial Release

#### Core Functionality
- **Push command**: Upload `.env` files to 1Password vault as individual password items
- **Inject command**: Download secrets from 1Password into local `.env` files
- **Run command**: Execute commands with secrets injected from 1Password (no plaintext files)
- **Dry-run mode**: Preview changes before applying them (--dry-run flag)
- **Version command**: Display version and 1Password CLI information
- **Help system**: Comprehensive help for all commands

#### Installation & Setup
- **install.sh**: Automated installation script for `~/.local/bin`
- Cross-platform support (macOS, Linux)
- Automatic PATH configuration for bash/zsh
- Prerequisites checking (bash, jq, 1Password CLI)

#### Documentation
- **README.md**: Complete usage guide with examples and workflows
- **docs/1PASSWORD_SETUP.md**: 1Password CLI installation and configuration guide
- **docs/QUICKSTART.md**: Quick reference for common tasks
- **MIGRATION.md**: Migration guide from old scripts
- **examples/.env.example**: Example environment file for testing

#### Project Organization
- Modular structure (bin/, lib/, docs/, examples/)
- MIT License
- Proper .gitignore for security
- VERSION file for version tracking
- Archive of legacy scripts for reference

#### Features
- Individual password items per environment variable (better for automation)
- Auto-tagging with `op-env-manager` for easy filtering
- Support for custom vault names
- Support for custom item name prefixes
- Overwrite protection with confirmation prompts
- Color-coded logging (info, success, warning, error)
- Comprehensive error handling and validation

### Changed - Migration from Legacy

#### Breaking Changes from Previous Version
- Moved from Secure Notes with sections to individual password items
- Changed from `create/update` commands to `push/inject/run` paradigm
- Removed project-specific references (CNA CRM)
- New file structure (bin/, lib/, docs/ instead of scripts/)
- New installation location (`~/.local/bin` instead of project-specific)

#### Improvements
- Simplified command interface
- Better 1Password CLI integration using recommended practices
- More modular and maintainable code architecture
- Comprehensive documentation for public sharing
- Better security practices (prefer `run` over `inject`)
- Support for CI/CD workflows with Service Accounts

### Security
- File permissions set to 600 (owner read/write only) for injected .env files
- No plaintext secrets when using `run` command
- Secure handling of 1Password references
- Warnings about git commit safety
- Recommendations for secret rotation

### Infrastructure
- Automated tests for all commands
- Example .env file with 50+ common variables
- Migration path from legacy scripts
- Archive of old scripts for reference

---

## [Unreleased]

### Planned Features

#### v0.4.0
- [ ] `diff` command - Compare local .env with 1Password
- [ ] `sync` command - Bidirectional sync with conflict resolution
- [ ] Enhanced logging with verbosity levels

#### v0.5.0
- [ ] Performance optimizations (parallel operations, caching)
- [ ] Batch field operations optimization
- [ ] Performance benchmarking and documentation

#### v1.0.0
- [ ] `rotate` command - Generate new secrets and update
- [ ] Support for .env.schema validation
- [ ] Homebrew tap for easier installation
- [ ] Docker image for CI/CD usage
- [ ] GitHub Action for workflows

#### Future Considerations
- Multi-vault injection (merge from multiple vaults)
- Secret expiration warnings
- Audit trail logging
- Integration with other secret managers
- GUI wrapper or TUI interface
- VSCode extension

---

## Migration Notes

### From Legacy Scripts (pre-0.1.0)

If you were using the old project-specific scripts:

**Old**: `./scripts/1password-env-manager.sh create --env .env --vault "CNA CRM"`
**New**: `op-env-manager push --vault "CNA-CRM" --env .env`

**Old**: `./scripts/manage-credentials.sh generate`
**New**: `op-env-manager inject --vault "Production" --output .env.production`

See [MIGRATION.md](MIGRATION.md) for complete migration guide.

---

## Links

- [Repository](https://github.com/matteocervelli/op-env-manager)
- [Issues](https://github.com/matteocervelli/op-env-manager/issues)
- [Documentation](README.md)
- [1Password CLI Docs](https://developer.1password.com/docs/cli/)
