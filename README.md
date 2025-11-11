# op-env-manager

**Bidirectional environment variable sync with 1Password** - Securely manage your `.env` files using 1Password as the source of truth.

by [Matteo Cervelli](https://github.com/matteocervelli)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![1Password CLI](https://img.shields.io/badge/1Password-CLI-blue.svg)](https://developer.1password.com/docs/cli/)

---

## What is this?

`op-env-manager` is a command-line tool that bridges your local `.env` files and 1Password vaults, enabling:

- **Push**: Upload your `.env` variables to 1Password for secure storage
- **Inject**: Download secrets from 1Password into local `.env` files
- **Run**: Execute commands with secrets injected from 1Password (no plaintext files!)
- **Convert**: Migrate legacy `.env` files with `op://` references to op-env-manager format

Stop committing secrets to git. Stop sharing `.env` files over Slack. Use 1Password.

## Why?

**The Problem**:
- `.env` files contain sensitive secrets
- Sharing them is insecure (email, Slack, git)
- Keeping them in sync across team members is painful
- Rotating secrets requires manual updates everywhere

**The Solution**:
- Store secrets in 1Password (encrypted, shared, versioned)
- Push/pull on demand
- Run applications with secrets injected at runtime
- No plaintext secrets on disk

## Features

✅ **Bidirectional Sync** - Push `.env` → 1Password, Inject 1Password → `.env`
✅ **Multiple Vaults** - Separate dev, staging, production secrets
✅ **Dry Run Mode** - Preview changes before applying
✅ **Runtime Injection** - Run commands with secrets (no disk storage)
✅ **Team Friendly** - Share vaults, control access
✅ **Git Safe** - Never commit secrets again
✅ **Auto-tagging** - All items tagged for easy filtering

## Installation

### Quick Install

```bash
# Clone the repository
git clone https://github.com/matteocervelli/op-env-manager.git
cd op-env-manager

# Run installer
./install.sh
```

The installer will:
1. Install to `~/.local/bin/op-env-manager/`
2. Create symlink in `~/.local/bin/`
3. Add to PATH (if needed)
4. Verify prerequisites (jq, 1Password CLI)

### Manual Installation

```bash
# Clone and setup
git clone https://github.com/matteocervelli/op-env-manager.git
mkdir -p ~/.local/bin
ln -s "$(pwd)/op-env-manager/bin/op-env-manager" ~/.local/bin/op-env-manager

# Add to PATH (if not already)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc  # or ~/.bashrc
source ~/.zshrc
```

### Prerequisites

- **Bash** (4.0+)
- **jq** - JSON processor
  ```bash
  # macOS
  brew install jq

  # Linux
  sudo apt install jq    # Debian/Ubuntu
  sudo dnf install jq    # Fedora/RHEL
  ```
- **1Password CLI** - See [docs/1PASSWORD_SETUP.md](docs/1PASSWORD_SETUP.md)

## Quick Start

### 1. Install 1Password CLI

See [docs/1PASSWORD_SETUP.md](docs/1PASSWORD_SETUP.md) for detailed instructions.

```bash
# macOS
brew install --cask 1password-cli

# Linux (Debian/Ubuntu)
# See docs/1PASSWORD_SETUP.md for full instructions

# Sign in
op signin
```

### 2. Push your .env to 1Password

```bash
# Push .env to your Personal vault
op-env-manager push --vault "Personal" --env .env

# Push production secrets to separate vault
op-env-manager push --vault "Production" --env .env.production --item "myapp"
```

### 3. Inject secrets from 1Password

```bash
# Inject to .env.local
op-env-manager inject --vault "Personal" --output .env.local

# Inject production secrets
op-env-manager inject --vault "Production" --item "myapp" --output .env.production
```

### 4. Run commands with secrets

```bash
# Run docker compose with secrets (no .env file created!)
op-env-manager run --vault "Production" --item "myapp" -- docker compose up

# Run any command
op-env-manager run --vault "Personal" -- npm run dev
```

## Usage

### Commands

```bash
op-env-manager <command> [options]
```

#### `push` - Upload .env to 1Password

```bash
op-env-manager push --vault VAULT [options]

Options:
  --env FILE          .env file to push (default: .env)
  --vault VAULT       1Password vault name (required)
  --item NAME         Item name prefix (default: env-secrets)
  --dry-run           Preview without pushing

Examples:
  op-env-manager push --vault "Personal"
  op-env-manager push --vault "Production" --env .env.prod --item "api"
  op-env-manager push --vault "Dev" --dry-run
```

#### `inject` - Download secrets from 1Password

```bash
op-env-manager inject --vault VAULT [options]

Options:
  --vault VAULT       1Password vault name (required)
  --item NAME         Item name prefix (default: env-secrets)
  --output FILE       Output file (default: .env)
  --overwrite         Skip overwrite confirmation
  --dry-run           Preview without writing

Examples:
  op-env-manager inject --vault "Personal" --output .env.local
  op-env-manager inject --vault "Production" --item "api" --overwrite
  op-env-manager inject --vault "Staging" --dry-run
```

#### `run` - Execute command with secrets

```bash
op-env-manager run --vault VAULT [options] -- <command>

Options:
  --vault VAULT       1Password vault name (required)
  --item NAME         Item name prefix (default: env-secrets)
  --env-file FILE     Additional .env file to merge

Examples:
  op-env-manager run --vault "Production" -- docker compose up
  op-env-manager run --vault "Dev" --item "api" -- npm start
  op-env-manager run --vault "Staging" -- python manage.py migrate
```

#### `convert` - Migrate from op:// reference format

```bash
op-env-manager convert --vault VAULT --env FILE [options]

Options:
  --env FILE          .env file with op:// references (required)
  --vault VAULT       Target 1Password vault name (required)
  --item NAME         Target item name prefix (default: env-secrets)
  --section SECTION   Environment section (e.g., dev, prod)
  --dry-run           Preview without converting

Examples:
  # Convert legacy .env.template with op:// references
  op-env-manager convert --vault "Personal" --env .env.template --item "myapp"

  # Convert with environment section
  op-env-manager convert --vault "Personal" --env .env.prod.template --item "myapp" --section "prod"

  # Preview conversion
  op-env-manager convert --vault "Personal" --env .env.template --dry-run

What it does:
  1. Parses .env file with op://vault/item/field references
  2. Resolves each reference using 'op read'
  3. Creates Secure Note with resolved values
  4. No temporary plaintext files created

See: docs/1password-formats.md for detailed format comparison
```

## Workflows

### Development Team Workflow

**Setup (once per team member)**:
```bash
# Team lead: Create shared vault and push secrets
op-env-manager push --vault "MyApp-Dev" --env .env.development

# Team members: Pull secrets
op-env-manager inject --vault "MyApp-Dev" --output .env.local
```

**Daily development**:
```bash
# Run with fresh secrets from 1Password
op-env-manager run --vault "MyApp-Dev" -- docker compose up
```

**Update secrets**:
```bash
# Update in 1Password UI or CLI
# Team members automatically get updated secrets on next inject/run
```

### Multi-Environment Deployment

```bash
# Different vaults for different environments
op-env-manager push --vault "MyApp-Dev" --env .env.dev
op-env-manager push --vault "MyApp-Staging" --env .env.staging
op-env-manager push --vault "MyApp-Prod" --env .env.prod

# Deploy to production
op-env-manager run --vault "MyApp-Prod" -- docker compose -f docker-compose.prod.yml up -d
```

### CI/CD Integration

Use 1Password Service Accounts for automated pipelines:

```bash
# Set service account token (in CI environment variables)
export OP_SERVICE_ACCOUNT_TOKEN="ops_..."

# Inject secrets in CI pipeline
op-env-manager inject --vault "CI-Secrets" --output .env.ci

# Or run tests with secrets
op-env-manager run --vault "CI-Secrets" -- npm test
```

See [1Password Service Accounts docs](https://developer.1password.com/docs/service-accounts/).

### Migrating from op:// References

If you have existing `.env` files with 1Password secret references (`op://vault/item/field`), use the convert command:

```bash
# You have: .env.template with op:// references
# Example: API_KEY=op://Production/api-keys/stripe_key

# Convert to op-env-manager format
op-env-manager convert \
  --env .env.template \
  --vault "Production" \
  --item "myapp"

# Now use op-env-manager commands
op-env-manager run --vault "Production" --item "myapp" -- docker compose up

# Old workflow still works (both formats can coexist)
op run --env-file=.env.template -- docker compose up
```

**Why convert?**
- Automated item management (no manual creation)
- Bidirectional sync (push updates back)
- Organized in single Secure Note per environment
- Team-friendly structure

See [docs/1password-formats.md](docs/1password-formats.md) for detailed comparison of the two formats.

## Best Practices

### Security

- ✅ **Never commit `.env` files** - Add to `.gitignore`
- ✅ **Use separate vaults** for dev/staging/production
- ✅ **Rotate secrets regularly** - Update in 1Password, team auto-syncs
- ✅ **Use Service Accounts in CI/CD** - Principle of least privilege
- ✅ **Prefer `run` over `inject`** - No plaintext files on disk

### Organization

```bash
# Vault structure
Personal/           # Your personal projects
MyApp-Dev/         # Shared development secrets
MyApp-Staging/     # Staging environment
MyApp-Production/  # Production (restricted access)
CI-CD/             # Service account secrets
```

### .gitignore

Always add to your `.gitignore`:

```gitignore
# Environment files
.env
.env.*
.env.local
.env.*.local
!.env.example

# op-env-manager shouldn't be committed
# (each dev installs separately)
```

## Troubleshooting

### "1Password CLI not installed"

See [docs/1PASSWORD_SETUP.md](docs/1PASSWORD_SETUP.md) for installation instructions.

### "Not signed in to 1Password CLI"

```bash
op signin
```

### "Vault not found"

```bash
# List available vaults
op vault list

# Use exact vault name (case-sensitive)
op-env-manager push --vault "Personal"  # ✅ Correct
op-env-manager push --vault "personal"  # ❌ Wrong case
```

### "No items found"

You need to push first:

```bash
# Push .env to create items
op-env-manager push --vault "Personal" --env .env

# Then inject
op-env-manager inject --vault "Personal"
```

### Permission Issues

Check vault permissions in 1Password UI - you need read/write access.

## Development

### Project Structure

```
op-env-manager/
├── bin/
│   └── op-env-manager          # Main executable
├── lib/
│   ├── logger.sh               # Logging utilities
│   ├── push.sh                 # Push command
│   ├── inject.sh               # Inject command
│   └── convert.sh              # Convert command
├── docs/
│   ├── 1PASSWORD_SETUP.md      # 1Password CLI setup guide
│   ├── 1password-formats.md    # Format comparison guide
│   ├── CONVERT_TESTING.md      # Convert command testing guide
│   └── QUICKSTART.md           # Quick reference
├── examples/
│   └── .env.example            # Example .env file
├── install.sh                  # Installation script
├── README.md                   # This file
└── LICENSE                     # MIT license
```

### Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## Roadmap

- [ ] `init` command - Interactive vault setup wizard
- [ ] `sync` command - Bidirectional sync with conflict resolution
- [ ] `diff` command - Compare local .env with 1Password
- [ ] `rotate` command - Generate new secrets and update
- [ ] Shell script installer (curl | bash)
- [ ] Homebrew tap
- [ ] Support for `.env.schema` validation
- [ ] Docker image for CI/CD
- [ ] GitHub Action

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Author

**Matteo Cervelli**
Transformation & Business Scalability Engineer

- GitHub: [@matteocervelli](https://github.com/matteocervelli)
- Company: [Ad Limen S.r.l.](https://adlimen.it)

## Acknowledgments

- Built on [1Password CLI](https://developer.1password.com/docs/cli/)
- Inspired by the need for secure, team-friendly secret management
- Part of my open-source tooling for developer productivity

## Support

- **Issues**: [GitHub Issues](https://github.com/matteocervelli/op-env-manager/issues)
- **Discussions**: [GitHub Discussions](https://github.com/matteocervelli/op-env-manager/discussions)
- **1Password CLI**: [1Password Support](https://support.1password.com/)

---

**Made with ❤️ for developers who care about security**
