# Getting Started with op-env-manager

Bidirectional `.env` sync with 1Password. Securely manage secrets across dev/staging/prod without committing them to git.

## Prerequisites

- A [1Password](https://1password.com) account (individual or team)
- macOS, Linux, or Windows
- Bash 3.2+ (pre-installed on all platforms)

## Step 1: Install 1Password CLI

### macOS

```bash
brew install --cask 1password-cli
```

### Linux (Debian/Ubuntu)

```bash
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] \
  https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list

sudo apt update && sudo apt install 1password-cli
```

For other platforms, see [1PASSWORD_SETUP.md](../1PASSWORD_SETUP.md) or the [official docs](https://developer.1password.com/docs/cli/get-started/).

### Verify

```bash
op --version
# 2.x.x
```

## Step 2: Install op-env-manager

```bash
git clone https://github.com/matteocervelli/op-env-manager.git
cd op-env-manager
./install.sh
```

Installs to `~/.local/bin/op-env-manager-install/` and creates a symlink at `~/.local/bin/op-env-manager`. Adds to PATH automatically.

### Verify

```bash
op-env-manager --version
# op-env-manager v0.3.0
```

## Step 3: Sign in to 1Password

```bash
op signin
```

Follow the prompts to authenticate. You'll need this each session unless you're using biometric unlock.

## Step 4: First Sync

### Option A: Interactive Setup Wizard (recommended)

```bash
op-env-manager init
```

The wizard (~2 minutes) will:

1. Detect existing `.env` files in your project
2. Let you select or create a 1Password vault
3. Ask for an item name (default: `env-secrets`)
4. Choose a multi-environment strategy (separate items or sections)
5. Run `push` + `template` automatically

### Option B: Manual Push

```bash
# Push your .env to 1Password
op-env-manager push --vault "Personal" --env-file .env

# Dry-run first (always a good idea)
op-env-manager push --vault "Personal" --env-file .env --dry-run
```

### Add .env to .gitignore

```bash
echo ".env" >> .gitignore
echo ".env.*" >> .gitignore
echo "!.env.example" >> .gitignore
git add .gitignore && git commit -m "Stop tracking .env files"
```

## Core Commands

| Command                          | What it does                                     |
| -------------------------------- | ------------------------------------------------ |
| `init`                           | Interactive setup wizard                         |
| `push --vault V --env-file F`    | Upload `.env` file to 1Password                  |
| `inject --vault V --output F`    | Download secrets to local `.env`                 |
| `run --vault V -- <cmd>`         | Run command with secrets injected (no plaintext) |
| `diff --vault V`                 | Compare local `.env` vs 1Password                |
| `sync --vault V`                 | Bidirectional sync with conflict resolution      |
| `template --vault V`             | Generate `.env.op` with `op://` references       |
| `convert --vault V --env-file F` | Migrate legacy `op://` references                |

## Daily Workflow

```bash
# Pull latest secrets before starting work
op-env-manager inject --vault "MyApp-Dev" --output .env.local

# Or just run with live secrets (preferred — no file written)
op-env-manager run --vault "MyApp-Dev" -- npm run dev
```

## Team Onboarding

Share the vault name with teammates. They run:

```bash
op signin
op-env-manager inject --vault "MyApp-Dev" --output .env.local
```

That's it. No Slack file sharing, no "which .env do I use" confusion.

## Multi-Environment Setup

```bash
# Push each environment separately
op-env-manager push --vault "MyApp-Dev" --env-file .env.development
op-env-manager push --vault "MyApp-Prod" --env-file .env.production

# Or use sections within one item
op-env-manager push --vault "MyApp" --env-file .env.dev --item "myapp" --section "dev"
op-env-manager push --vault "MyApp" --env-file .env.prod --item "myapp" --section "prod"
```

## CI/CD

Use a 1Password Service Account token for pipelines:

```bash
export OP_SERVICE_ACCOUNT_TOKEN="ops_..."

# Inject secrets during CI
op-env-manager --quiet inject --vault "CI-Secrets" --output .env --overwrite

# Or run tests with live injection
op-env-manager run --vault "CI-Secrets" -- npm test
```

See [CI_CD_EXAMPLES.md](../CI_CD_EXAMPLES.md) for GitHub Actions, GitLab CI, and Docker examples.

## Troubleshooting

```bash
# Check op CLI is installed and signed in
op --version
op account list

# List available vaults
op vault list

# Check items tagged by op-env-manager
op item list --vault "Personal" --tags "op-env-manager"

# Debug with disable retry
OP_DISABLE_RETRY=true op-env-manager push --vault "Personal" --dry-run
```

## Next Steps

- [Quick Reference](../QUICKSTART.md) — all flags and commands
- [1Password Setup](../1PASSWORD_SETUP.md) — detailed CLI configuration
- [Team Collaboration](../TEAM_COLLABORATION.md) — vault sharing and access control
- [CI/CD Examples](../CI_CD_EXAMPLES.md) — pipeline integration
