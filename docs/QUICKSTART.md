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

### Push .env to 1Password

```bash
# Push to Personal vault
op-env-manager push --vault "Personal" --env .env

# Push to custom vault with custom item name
op-env-manager push --vault "MyApp-Production" --env .env.prod --item "api-secrets"

# Dry run (preview only)
op-env-manager push --vault "Personal" --env .env --dry-run
```

### Inject secrets from 1Password

```bash
# Inject to .env.local
op-env-manager inject --vault "Personal" --output .env.local

# Inject from custom item
op-env-manager inject --vault "MyApp-Production" --item "api-secrets" --output .env.prod

# Overwrite without prompting
op-env-manager inject --vault "Personal" --overwrite

# Dry run (preview only)
op-env-manager inject --vault "Personal" --dry-run
```

### Run commands with secrets

```bash
# Run docker compose
op-env-manager run --vault "Production" -- docker compose up

# Run with custom item
op-env-manager run --vault "Production" --item "api-secrets" -- docker compose up

# Run any command
op-env-manager run --vault "Dev" -- npm run dev
op-env-manager run --vault "Production" -- python manage.py migrate
```

## Typical Workflows

### First Time Setup

```bash
# 1. Sign in to 1Password
op signin

# 2. Push your .env to 1Password
op-env-manager push --vault "Personal" --env .env

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
op-env-manager inject --vault "MyApp-Dev" --output .env.local

# 3. Start development
op-env-manager run --vault "MyApp-Dev" -- docker compose up
```

### Multi-Environment Setup

```bash
# Push different environments to different vaults
op-env-manager push --vault "MyApp-Dev" --env .env.dev
op-env-manager push --vault "MyApp-Staging" --env .env.staging
op-env-manager push --vault "MyApp-Prod" --env .env.prod

# Inject as needed
op-env-manager inject --vault "MyApp-Staging" --output .env.staging

# Run in specific environment
op-env-manager run --vault "MyApp-Prod" -- docker compose up -d
```

### Secret Rotation

```bash
# 1. Update secret in 1Password (via UI or CLI)
op item edit "env-secrets-DATABASE_PASSWORD" password="new-secure-password"

# 2. Team members pull updated secrets
op-env-manager inject --vault "MyApp-Dev" --output .env.local --overwrite

# Or just run with updated secrets (no file created)
op-env-manager run --vault "MyApp-Dev" -- docker compose restart
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

### Push Command

- `--env FILE` - .env file to push (default: `.env`)
- `--vault VAULT` - 1Password vault (required)
- `--item NAME` - Item name prefix (default: `env-secrets`)
- `--dry-run` - Preview only

### Inject Command

- `--vault VAULT` - 1Password vault (required)
- `--item NAME` - Item name prefix (default: `env-secrets`)
- `--output FILE` - Output file (default: `.env`)
- `--overwrite` - Skip confirmation prompt
- `--dry-run` - Preview only

### Run Command

- `--vault VAULT` - 1Password vault (required)
- `--item NAME` - Item name prefix (default: `env-secrets`)
- `--env-file FILE` - Additional .env file to merge
- `--` - Separator before command
- `<command>` - Command to run with injected secrets

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
