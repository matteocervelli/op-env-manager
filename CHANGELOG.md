# Changelog

All notable changes to op-env-manager will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

#### v0.2.0
- [ ] `init` command - Interactive vault setup wizard
- [ ] `sync` command - Bidirectional sync with conflict resolution
- [ ] `diff` command - Compare local .env with 1Password
- [ ] Enhanced logging with verbosity levels
- [ ] Support for .env.schema validation

#### v0.3.0
- [ ] `rotate` command - Generate new secrets and update
- [ ] Shell script installer (curl | bash)
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
