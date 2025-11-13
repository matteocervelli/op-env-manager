# op-env-manager

**Bidirectional environment variable sync with 1Password** - Securely manage your `.env` files using 1Password as the source of truth.

by [Matteo Cervelli](https://github.com/matteocervelli)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Test Suite](https://github.com/matteocervelli/tool-op-env-manager/actions/workflows/test.yml/badge.svg)](https://github.com/matteocervelli/tool-op-env-manager/actions/workflows/test.yml)
[![1Password CLI](https://img.shields.io/badge/1Password-CLI-blue.svg)](https://developer.1password.com/docs/cli/)
[![Buy Me A Coffee](https://img.shields.io/badge/☕-Buy%20me%20a%20coffee-orange.svg)](https://adli.men/coffee)

---

## What is this?

`op-env-manager` is a command-line tool that bridges your local `.env` files and 1Password vaults, enabling:

- **Push**: Upload your `.env` variables to 1Password for secure storage
- **Inject**: Download secrets from 1Password into local `.env` files
- **Run**: Execute commands with secrets injected from 1Password (no plaintext files!)
- **Convert**: Migrate legacy `.env` files with `op://` references to op-env-manager format
- **Template**: Generate `.env.op` files with `op://` references for version control

Stop committing secrets to git. Stop sharing `.env` files over Slack. Use 1Password.

## Architecture

```mermaid
graph LR
    A[.env Files] -->|push| B[op-env-manager]
    B -->|Secure Storage| C[1Password Vaults]
    C -->|inject| B
    B -->|.env Files| A
    B -->|run| D[App with Secrets]
    C -.->|runtime injection| D
    E[.env.op Templates] -.->|safe for git| F[Version Control]

    style C fill:#0094F5,color:#fff
    style B fill:#333,color:#fff
    style F fill:#2ea44f,color:#fff
```

**How it works**:
1. **Push**: Parse local `.env` → Create/update 1Password Secure Note with fields
2. **Inject**: Fetch 1Password fields → Write to local `.env` (chmod 600)
3. **Run**: Generate `op://` references → Execute with `op run` (no plaintext on disk)
4. **Template**: Create `.env.op` with references → Safe for git commits

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
✅ **Multiline Values** - Support for private keys, certificates, JSON configs (v0.2.0+)
✅ **Multiple Vaults** - Separate dev, staging, production secrets
✅ **Dry Run Mode** - Preview changes before applying
✅ **Runtime Injection** - Run commands with secrets (no disk storage)
✅ **Template Generation** - Create safe `.env.op` files for version control
✅ **Team Friendly** - Share vaults, control access
✅ **Git Safe** - Never commit secrets again
✅ **Auto-tagging** - All items tagged for easy filtering

## Comparison with Alternatives

| Feature | op-env-manager | dotenv | envkey | AWS Secrets | HashiCorp Vault |
|---------|---------------|--------|--------|-------------|-----------------|
| **Cost** | Free (uses 1Password) | Free | Paid plans | AWS pricing | Self-hosted/paid |
| **Setup Complexity** | Low (1Password CLI) | Very low | Medium | High | Very high |
| **Team Sharing** | ✅ (1Password vaults) | ❌ (manual files) | ✅ | ✅ | ✅ |
| **Access Control** | ✅ (1Password policies) | ❌ | ✅ | ✅ | ✅ |
| **Audit Trail** | ✅ (1Password logs) | ❌ | ✅ | ✅ | ✅ |
| **Runtime Injection** | ✅ (`run` command) | ❌ | ✅ | ❌ | ✅ |
| **Multi-Environment** | ✅ (sections/vaults) | Manual files | ✅ | ✅ | ✅ |
| **Git Safe** | ✅ (templates) | ⚠️ (gitignore) | ✅ | ✅ | ✅ |
| **CI/CD Integration** | ✅ (Service Accounts) | ✅ | ✅ | ✅ | ✅ |
| **Learning Curve** | Low | Very low | Medium | Medium | High |
| **Infrastructure** | None (SaaS) | None | SaaS | AWS account | Self-hosted |

**When to use op-env-manager**:
- ✅ You already use 1Password for your team
- ✅ You want simple, secure secret management without new infrastructure
- ✅ You need team collaboration with access control
- ✅ You want audit trails and versioning
- ✅ You prefer CLI tools over web dashboards

**When to use alternatives**:
- **dotenv**: Solo projects, no team collaboration needed, very simple setup
- **envkey**: Need dedicated secret management platform, willing to pay
- **AWS Secrets Manager**: Already on AWS, want tight AWS integration
- **HashiCorp Vault**: Enterprise needs, complex access patterns, dynamic secrets

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
  --env FILE             .env file to push (default: .env)
  --vault VAULT          1Password vault name (required)
  --item NAME            Item name prefix (default: env-secrets)
  --template             Also generate .env.op template file
  --template-output FILE Output path for template (default: .env.op)
  --dry-run              Preview without pushing

Examples:
  op-env-manager push --vault "Personal"
  op-env-manager push --vault "Production" --env .env.prod --item "api"
  op-env-manager push --vault "Dev" --dry-run
  op-env-manager push --vault "Personal" --template  # Also generate .env.op
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
  --vault VAULT          1Password vault name (required)
  --item NAME            Item name prefix (default: env-secrets)
  --env-file FILE        Additional .env file to merge
  --template             Also save .env.op template file
  --template-output FILE Output path for template (default: .env.op)

Examples:
  op-env-manager run --vault "Production" -- docker compose up
  op-env-manager run --vault "Dev" --item "api" -- npm start
  op-env-manager run --vault "Staging" -- python manage.py migrate
  op-env-manager run --vault "Personal" --template -- npm start  # Also save .env.op
```

#### `convert` - Migrate from op:// reference format

```bash
op-env-manager convert --vault VAULT --env FILE [options]

Options:
  --env FILE             .env file with op:// references (required)
  --vault VAULT          Target 1Password vault name (required)
  --item NAME            Target item name prefix (default: env-secrets)
  --section SECTION      Environment section (e.g., dev, prod)
  --template             Also generate .env.op template file
  --template-output FILE Output path for template (default: .env.op)
  --dry-run              Preview without converting

Examples:
  # Convert legacy .env.template with op:// references
  op-env-manager convert --vault "Personal" --env .env.template --item "myapp"

  # Convert with environment section
  op-env-manager convert --vault "Personal" --env .env.prod.template --item "myapp" --section "prod"

  # Preview conversion
  op-env-manager convert --vault "Personal" --env .env.template --dry-run

  # Convert and generate template
  op-env-manager convert --vault "Personal" --env .env.legacy --template

What it does:
  1. Parses .env file with op://vault/item/field references
  2. Resolves each reference using 'op read'
  3. Creates Secure Note with resolved values
  4. No temporary plaintext files created

See: docs/1password-formats.md for detailed format comparison
```

#### `template` - Generate op:// reference files

Generate `.env.op` template files with `op://` secret references that can be safely committed to version control.

```bash
op-env-manager template --vault VAULT [options]

Options:
  --vault VAULT          1Password vault name (required)
  --item NAME            Item name (default: env-secrets)
  --section SECTION      Environment section (e.g., dev, prod)
  --output FILE          Output file (default: .env.op)
  --dry-run              Preview without generating

Examples:
  # Generate template from existing 1Password item
  op-env-manager template --vault "Personal" --item "myapp"

  # Generate with section (uses $APP_ENV variable)
  op-env-manager template --vault "Projects" --item "myapp" --section "dev"

  # Custom output filename
  op-env-manager template --vault "Personal" --output ".env.template"

Generated Format:
  # Without section:
  API_KEY=op://Personal/myapp/API_KEY
  DATABASE_URL=op://Personal/myapp/DATABASE_URL

  # With section (dynamic):
  API_KEY=op://Personal/myapp/$APP_ENV/API_KEY
  DATABASE_URL=op://Personal/myapp/$APP_ENV/DATABASE_URL

Usage with op run:
  # Set APP_ENV to select section dynamically
  export APP_ENV="dev"
  op run --env-file=.env.op -- docker compose up

Using --template flag:
  All commands support --template flag to automatically generate .env.op:

  # Push and generate template
  op-env-manager push --vault "Personal" --template

  # Convert and generate template
  op-env-manager convert --vault "Personal" --env .env.legacy --template

  # Run and save template
  op-env-manager run --vault "Personal" --template -- docker compose up
```

### Multiline Values (v0.2.0+)

The tool supports multiline values for private keys, certificates, and JSON configurations.

**Supported format:**
```bash
# Single-line values (as before)
API_KEY=simple_value
DATABASE_URL="postgresql://localhost/db"

# Multiline values (wrap in double quotes)
PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA1234567890...
aBcDeFgHiJkLmNoPqRsTuVwXyZ...
-----END RSA PRIVATE KEY-----"

SSL_CERT="-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIJAKZ...
-----END CERTIFICATE-----"

JSON_CONFIG="{
  \"database\": {
    \"host\": \"localhost\",
    \"port\": 5432
  },
  \"cache\": {
    \"ttl\": 3600
  }
}"
```

**How it works:**
- Multiline values must be enclosed in double quotes
- When pushed to 1Password, newlines are converted to `\n` escape sequences
- When injected back, escape sequences are converted to actual newlines
- The injected `.env` file preserves the multiline format with quotes

**Example usage:**
```bash
# Push .env with multiline values
op-env-manager push --vault "Personal" --env .env.production

# Inject back - multiline values are restored
op-env-manager inject --vault "Personal" --output .env.local

# Use with runtime injection (no temp files)
op-env-manager run --vault "Personal" -- docker compose up
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

### Support This Project

If `op-env-manager` saves you time and improves your team's security, consider supporting its development:

[![Buy Me A Coffee](https://img.shields.io/badge/☕-Buy%20me%20a%20coffee-orange.svg?style=for-the-badge)](https://adli.men/coffee)

Your support helps me:
- Maintain and improve this tool
- Create more open-source developer tools
- Write documentation and tutorials
- Provide community support

---

**Made with ❤️ for developers who care about security**
