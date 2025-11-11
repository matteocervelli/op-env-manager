# Understanding 1Password Secret Reference Formats

This document explains the two different approaches for managing environment variables with 1Password and when to use each.

## The Two Formats

### 1. Secret References Format (op:// URIs)

**What it is**: Environment files containing `op://` URIs that reference secrets stored in 1Password items.

**Format**: `VAR_NAME=op://vault/item-name/field`

**Example**:
```bash
# .env.template
DATABASE_URL=postgresql://user:op://Production/db-password/password@localhost:5432/mydb
API_KEY=op://Production/api-keys/stripe_key
REDIS_PASSWORD=op://Production/redis-creds/password
```

**How it works**:
- You create items in 1Password manually or via CLI
- You write `.env` files with `op://` references pointing to those items
- You use `op run` or `op inject` to resolve references at runtime
- Secrets are never stored in plaintext in your `.env` files

**Use cases**:
- Legacy projects already using 1Password CLI workflows
- Teams standardized on `op run` / `op inject` commands
- Complex multi-service setups with shared credentials
- CI/CD pipelines using 1Password Service Accounts

**Pros**:
- Native 1Password CLI workflow
- Explicit control over item organization in 1Password
- Can embed references within larger strings (like connection URLs)
- Works with any 1Password item structure

**Cons**:
- Manual item creation and management
- Need to track which items/fields exist in 1Password
- `.env` files are templates, not directly usable
- Harder to see what variables exist without resolving

### 2. op-env-manager Format (Secure Note Items)

**What it is**: A standardized structure where all environment variables are stored as fields in a single 1Password Secure Note item.

**Format**: Single Secure Note with variable names as field labels

**Example**:
```bash
# 1Password Item: "myapp" (Secure Note)
# Fields:
#   - DATABASE_URL[password] = postgresql://user:secret@localhost:5432/mydb
#   - API_KEY[password] = sk_live_abc123...
#   - REDIS_PASSWORD[password] = supersecret
```

**How it works**:
- You push a plaintext `.env` file using `op-env-manager push`
- Tool creates a Secure Note with each variable as a password field
- You inject back to `.env` with `op-env-manager inject`
- You run commands with `op-env-manager run`

**Use cases**:
- New projects starting fresh with 1Password
- Simple environment variable management
- Projects with clearly defined environment stages (dev/staging/prod)
- When you want bidirectional sync between `.env` and 1Password

**Pros**:
- Automated item creation and updates
- All variables for an environment in one place
- Easy to see all variables in 1Password UI
- Supports sections for multi-environment organization
- Tagged for easy filtering

**Cons**:
- Less flexible than manual item organization
- One Secure Note per environment/section
- Can't embed references in complex strings

## Choosing Between Formats

| Scenario | Recommended Format |
|----------|-------------------|
| New project, simple environment variables | **op-env-manager format** |
| Existing project using `op run` | **Secret references format** |
| Need to embed secrets in URLs/connection strings | **Secret references format** |
| Want automated bidirectional sync | **op-env-manager format** |
| Multiple services sharing credentials | **Secret references format** |
| Clear environment stages (dev/staging/prod) | **op-env-manager format** |
| CI/CD with 1Password Service Accounts | **Secret references format** |
| Team already trained on `op inject` | **Secret references format** |

## Converting Between Formats

### From Secret References → op-env-manager

Use the `convert` command to migrate from `op://` format to op-env-manager format:

```bash
# You have: .env.template with op:// references
# You want: Secure Note with resolved values

op-env-manager convert \
  --env-file=.env.template \
  --vault="Production" \
  --item="myapp"
```

**What happens**:
1. Tool parses `.env.template` line by line
2. Detects `op://` references in values
3. Uses `op read` to resolve each reference
4. Creates/updates Secure Note with resolved values
5. No temporary plaintext files created

**Example**:

Before (`.env.template`):
```bash
API_KEY=op://Production/stripe-keys/live_key
DB_PASSWORD=op://Production/postgres/password
```

After (1Password Secure Note "myapp"):
- Field: `API_KEY[password]` = `sk_live_abc123...`
- Field: `DB_PASSWORD[password]` = `supersecretpassword`

### From op-env-manager → Secret References

You can export and manually create references:

```bash
# Inject to plaintext .env
op-env-manager inject \
  --vault="Production" \
  --item="myapp" \
  --output=.env.local

# Manually create .env.template with references
# Then delete .env.local
```

Or use 1Password CLI to generate references programmatically.

## Multi-Environment Organization

Both formats support multiple environments, but differently:

### Secret References Approach

Use separate items per environment:

```bash
# .env.dev.template
API_KEY=op://Development/myapp-keys/api_key

# .env.prod.template
API_KEY=op://Production/myapp-keys/api_key
```

### op-env-manager Approach

Use sections within a single item:

```bash
# Push dev environment
op-env-manager push \
  --vault="Projects" \
  --item="myapp" \
  --section="dev" \
  --env-file=.env.dev

# Push prod environment
op-env-manager push \
  --vault="Projects" \
  --item="myapp" \
  --section="prod" \
  --env-file=.env.prod

# Inject using $APP_ENV variable
export APP_ENV=dev
op-env-manager inject \
  --vault="Projects" \
  --item="myapp" \
  --section="$APP_ENV"
```

**Result in 1Password**:
- Single Secure Note: "myapp"
- Section "dev" with dev variables
- Section "prod" with prod variables

## Security Considerations

### Secret References Format

**Risks**:
- Template files in repo can reveal infrastructure details
- Need to ensure references point to correct vault/items
- Misconfigured references can expose secrets from wrong environment

**Best practices**:
- Keep templates in version control (no secrets)
- Use vault names that match environments
- Document required 1Password items/fields
- Test with `op inject --dry-run` before production

### op-env-manager Format

**Risks**:
- Need plaintext `.env` temporarily during push
- Must secure/delete injected files after use
- All variables in one item (larger blast radius)

**Best practices**:
- Use `--dry-run` before pushing
- Immediately `chmod 600` on injected files
- Delete plaintext `.env` after pushing to 1Password
- Prefer `run` command over `inject` (no plaintext file)
- Use `.gitignore` for all `.env*` except `.env.example`

## Real-World Workflow Examples

### Workflow 1: New Project (op-env-manager)

```bash
# 1. Create .env.dev locally
cat > .env.dev << EOF
DATABASE_URL=postgresql://user:devpass@localhost/db
API_KEY=test_key_dev
EOF

# 2. Push to 1Password
op-env-manager push \
  --vault="Personal" \
  --item="myproject" \
  --section="dev" \
  --env-file=.env.dev

# 3. Delete plaintext file
rm .env.dev

# 4. Run app with secrets
op-env-manager run \
  --vault="Personal" \
  --item="myproject" \
  --section="dev" \
  -- docker compose up

# 5. Teammate pulls secrets
op-env-manager inject \
  --vault="Personal" \
  --item="myproject" \
  --section="dev" \
  --output=.env
```

### Workflow 2: Legacy Project Migration (convert)

```bash
# 1. You have existing .env.template with op:// refs
cat .env.template
# API_KEY=op://Production/legacy-app/api_key
# DB_PASS=op://Production/legacy-app/db_password

# 2. Convert to op-env-manager format
op-env-manager convert \
  --env-file=.env.template \
  --vault="Production" \
  --item="legacy-app-migrated"

# 3. Now use op-env-manager commands
op-env-manager run \
  --vault="Production" \
  --item="legacy-app-migrated" \
  -- ./start-app.sh

# 4. Old workflow still works (both formats coexist)
op run --env-file=.env.template -- ./start-app.sh
```

### Workflow 3: CI/CD Pipeline (secret references)

```bash
# .env.ci.template (in repo)
DATABASE_URL=op://CI/myapp-ci/database_url
API_KEY=op://CI/myapp-ci/api_key

# GitHub Actions workflow
- name: Run tests
  env:
    OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
  run: |
    op run --env-file=.env.ci.template -- pytest

# Alternative: Use op-env-manager in CI
- name: Run tests
  run: |
    op-env-manager run \
      --vault="CI" \
      --item="myapp-ci" \
      -- pytest
```

## Key Takeaways

1. **Secret references (`op://`)** are native 1Password CLI format, flexible but manual
2. **op-env-manager format** automates item management with standardized structure
3. Use `convert` command to migrate from `op://` to op-env-manager
4. Both formats can coexist - use what fits your workflow
5. Security best practice: avoid plaintext `.env` files on disk when possible
6. Use `run` commands instead of `inject` to keep secrets in memory only

## References

- [1Password CLI Documentation](https://developer.1password.com/docs/cli)
- [1Password Secret References](https://developer.1password.com/docs/cli/secret-references)
- [op-env-manager README](../README.md)
