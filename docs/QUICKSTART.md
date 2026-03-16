# op-env-manager - Quick Reference

Fast reference guide for common tasks.

## Prerequisites

```bash
# 1. Install 1Password CLI (see 1PASSWORD_SETUP.md for details)
brew install --cask 1password-cli  # macOS

# 2. Sign in
op signin

# 3. Install op-env-manager
cd op-env-manager && ./install.sh
```

## Common Commands

### Interactive setup (first time)

```bash
# Guided wizard: detects .env files, configures vault, pushes secrets
op-env-manager init
```

### Push .env to 1Password

```bash
# Push to Personal vault
op-env-manager push --vault="Personal" --env-file=.env

# Push to custom vault with custom item name
op-env-manager push --vault="MyApp-Production" --env-file=.env.prod --item="api-secrets"

# Push with environment section (enables op://vault/item/$APP_ENV/KEY references)
op-env-manager push --vault="Projects" --item="myapp" --section="dev" --env-file=.env.dev

# Push and also generate a .env.op template file
op-env-manager push --vault="Personal" --env-file=.env --template

# Dry run (preview only)
op-env-manager push --vault="Personal" --env-file=.env --dry-run
```

### Inject secrets from 1Password

```bash
# Inject to .env.local
op-env-manager inject --vault="Personal" --output=.env.local

# Inject from custom item
op-env-manager inject --vault="MyApp-Production" --item="api-secrets" --output=.env.prod

# Inject a specific environment section
op-env-manager inject --vault="Projects" --item="myapp" --section="prod" --output=.env.prod

# Overwrite without prompting
op-env-manager inject --vault="Personal" --overwrite

# Dry run (preview only)
op-env-manager inject --vault="Personal" --dry-run
```

### Run commands with secrets

```bash
# Run docker compose
op-env-manager run --vault="Production" -- docker compose up

# Run with custom item
op-env-manager run --vault="Production" --item="api-secrets" -- docker compose up

# Run with environment section
op-env-manager run --vault="Projects" --item="myapp" --section="dev" -- npm run dev

# Run with unmasked secrets (shows full values in output — use carefully)
op-env-manager run --vault="Dev" --item="myapp" --no-masking -- env | grep API_KEY

# Run any command
op-env-manager run --vault="Dev" -- npm run dev
op-env-manager run --vault="Production" -- python manage.py migrate
```

### Compare local .env with 1Password

```bash
# Show differences between local file and vault
op-env-manager diff --vault="Personal" --env-file=.env

# Diff a specific section
op-env-manager diff --vault="Projects" --item="myapp" --section="dev" --env-file=.env.dev
```

### Sync local .env with 1Password (bidirectional)

```bash
# Interactive sync (prompts on conflicts)
op-env-manager sync --vault="Personal" --env-file=.env

# Automatic: prefer local values on conflict
op-env-manager sync --vault="Projects" --item="myapp" --strategy=ours

# Automatic: prefer 1Password values on conflict
op-env-manager sync --vault="Projects" --item="myapp" --strategy=theirs

# Sync a specific section, dry-run first
op-env-manager sync --vault="Projects" --item="myapp" --section="dev" --dry-run
```

### Convert legacy .env (op:// references)

```bash
# Convert a .env file that already contains op:// references into the op-env-manager format
op-env-manager convert --vault="Personal" --item="myapp" --env-file=.env.template
```

### Generate .env.op template

```bash
# Generate template with op:// references from existing 1Password item
op-env-manager template --vault="Personal" --item="myapp"

# Merge with an existing .env.example to preserve structure and comments
op-env-manager template --vault="Personal" --item="myapp" --env-file=.env.example

# Custom output path
op-env-manager template --vault="Personal" --item="myapp" --output=.env.template
```

## Typical Workflows

### First Time Setup

```bash
# 1. Sign in to 1Password
op signin

# 2. Run the interactive wizard (recommended)
op-env-manager init

# Or manually push your .env to 1Password
op-env-manager push --vault="Personal" --env-file=.env

# 3. Add .env to .gitignore
echo ".env" >> .gitignore
echo ".env.*" >> .gitignore
echo "!.env.example" >> .gitignore

# 4. Commit .gitignore change
git add .gitignore
git commit -m "Add .env files to gitignore"
```

### Team Member Onboarding

```bash
# 1. Sign in to 1Password
op signin

# 2. Pull secrets from shared vault
op-env-manager inject --vault="MyApp-Dev" --output=.env.local

# 3. Start development
op-env-manager run --vault="MyApp-Dev" -- docker compose up
```

### Multi-Environment Setup

```bash
# Option A: separate items per environment (separate vaults)
op-env-manager push --vault="MyApp-Dev" --env-file=.env.dev
op-env-manager push --vault="MyApp-Staging" --env-file=.env.staging
op-env-manager push --vault="MyApp-Prod" --env-file=.env.prod

# Option B: sections in a single item
op-env-manager push --vault="Projects" --item="myapp" --section="dev" --env-file=.env.dev
op-env-manager push --vault="Projects" --item="myapp" --section="prod" --env-file=.env.prod

# Inject as needed
op-env-manager inject --vault="MyApp-Staging" --output=.env.staging

# Run in specific environment
op-env-manager run --vault="MyApp-Prod" -- docker compose up -d
```

### Secret Rotation

```bash
# 1. Update secret in 1Password (via UI or CLI)
op item edit "env-secrets-DATABASE_PASSWORD" password="new-secure-password"

# 2. Check what has changed before pulling
op-env-manager diff --vault="MyApp-Dev" --item="myapp"

# 3. Team members pull updated secrets
op-env-manager inject --vault="MyApp-Dev" --output=.env.local --overwrite

# Or just run with updated secrets (no file created)
op-env-manager run --vault="MyApp-Dev" -- docker compose restart
```

## Quick Troubleshooting

```bash
# Check if op CLI is installed
op --version

# Check if signed in
op vault list

# List available vaults
op vault list

# Check what items exist
op item list --vault "Personal" --tags "op-env-manager"

# Sign in if needed
op signin
```

## Common Patterns

### Development

```bash
# Daily workflow: run with fresh secrets
op-env-manager run --vault "Dev" -- docker compose up
```

### CI/CD

```bash
# Use service account token
export OP_SERVICE_ACCOUNT_TOKEN="ops_..."

# Inject secrets in pipeline
op-env-manager inject --vault "CI-Secrets" --output .env.ci --overwrite

# Or run tests directly
op-env-manager run --vault "CI-Secrets" -- npm test
```

### Production Deployment

```bash
# Deploy with secrets injected at runtime
op-env-manager run --vault "Production" -- \
  docker compose -f docker-compose.prod.yml up -d
```

## Flags Reference

### Global Flags

- `--help`, `-h` - Show help
- `--version`, `-v` - Show version
- `--quiet`, `-q` - Suppress all non-error output (sets `OP_QUIET_MODE=true`)

### Init Command

- _(interactive wizard, no required flags)_
- `--dry-run` - Preview workflow without making changes

### Push Command

- `--env-file=FILE` - .env file to push (default: `.env`)
- `--vault=VAULT` - 1Password vault (required)
- `--item=NAME` - Item name prefix (default: `env-secrets`)
- `--section=SECTION` - Environment section, e.g. `dev`, `prod` (enables `op://vault/item/$APP_ENV/KEY` references)
- `--template` - Also generate `.env.op` template file
- `--template-output=FILE` - Path for template file (default: `.env.op`); implies `--template`
- `--dry-run` - Preview only

### Inject Command

- `--vault=VAULT` - 1Password vault (required)
- `--item=NAME` - Item name prefix (default: `env-secrets`)
- `--section=SECTION` - Environment section to retrieve
- `--output=FILE` - Output file (default: `.env`)
- `--overwrite` - Skip confirmation prompt
- `--dry-run` - Preview only

### Run Command

- `--vault=VAULT` - 1Password vault (required)
- `--item=NAME` - Item name prefix (default: `env-secrets`)
- `--section=SECTION` - Environment section; also sets `APP_ENV` for the subprocess
- `--env-file=FILE` - Additional .env file to merge alongside 1Password secrets
- `--no-masking` - Show full secret values in output (use carefully)
- `--template` - Save a `.env.op` template alongside running the command
- `--template-output=FILE` - Path for template file (default: `.env.op`); implies `--template`
- `--dry-run` - Preview secret references without executing
- `--` - Separator before command
- `<command>` - Command to run with injected secrets

### Diff Command

- `--vault=VAULT` - 1Password vault (required)
- `--item=NAME` - Item name prefix (default: `env-secrets`)
- `--env-file=FILE` - Local file to compare (default: `.env`)
- `--section=SECTION` - Environment section to compare
- `--dry-run` - Preview without contacting 1Password

### Sync Command

- `--vault=VAULT` - 1Password vault (required)
- `--item=NAME` - Item name prefix (default: `env-secrets`)
- `--env-file=FILE` - Local file to sync (default: `.env`)
- `--section=SECTION` - Environment section to sync
- `--strategy=STRATEGY` - Conflict resolution: `interactive` (default), `ours`, `theirs`, `newest`
- `--no-backup` - Skip automatic backup before sync
- `--dry-run` - Preview changes only

### Convert Command

- `--env-file=FILE` - .env file containing `op://` references (required)
- `--vault=VAULT` - Target 1Password vault (required)
- `--item=NAME` - Target item name prefix (default: `env-secrets`)
- `--section=SECTION` - Environment section
- `--template` - Also generate `.env.op` template file
- `--template-output=FILE` - Path for template file (default: `.env.op`); implies `--template`
- `--dry-run` - Preview only

### Template Command

- `--vault=VAULT` - 1Password vault (required)
- `--item=NAME` - Item name (default: `env-secrets`)
- `--section=SECTION` - Environment section
- `--env-file=FILE` - Existing file to merge with (e.g. `.env.example`); preserves structure and comments
- `--output=FILE` - Output file path (default: `.env.op`)
- `--dry-run` - Preview only

## Examples by Use Case

### Web Application

```bash
# Development
op-env-manager run --vault "webapp-dev" -- npm run dev

# Production
op-env-manager run --vault "webapp-prod" -- npm start
```

### Docker Services

```bash
# Local development
op-env-manager run --vault "services-dev" -- docker compose up

# Production deployment
op-env-manager run --vault "services-prod" -- \
  docker compose -f docker-compose.prod.yml up -d
```

### Python/Django

```bash
# Run migrations
op-env-manager run --vault "django-prod" -- python manage.py migrate

# Start server
op-env-manager run --vault "django-dev" -- python manage.py runserver
```

### Database Scripts

```bash
# Backup with credentials
op-env-manager run --vault "db-prod" -- ./backup-database.sh

# Restore
op-env-manager run --vault "db-prod" -- ./restore-database.sh backup.sql
```

## Security Reminders

✅ **Always use `--dry-run` first** to preview changes
✅ **Never commit .env files** to git
✅ **Use separate vaults** for different environments
✅ **Prefer `run` over `inject`** to avoid plaintext files
✅ **Rotate secrets regularly** in 1Password
✅ **Use Service Accounts** for CI/CD

## Need More Help?

- Full documentation: `README.md`
- 1Password setup: `docs/1PASSWORD_SETUP.md`
- GitHub issues: https://github.com/matteocervelli/op-env-manager/issues
