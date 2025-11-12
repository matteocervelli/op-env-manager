# Team Collaboration Guide

Best practices for using `op-env-manager` with development teams, from onboarding to production workflows.

## Table of Contents

- [Team Setup](#team-setup)
- [Vault Organization](#vault-organization)
- [Onboarding New Team Members](#onboarding-new-team-members)
- [Multi-Environment Workflows](#multi-environment-workflows)
- [Secret Rotation](#secret-rotation)
- [Access Control](#access-control)
- [Communication Protocols](#communication-protocols)
- [Troubleshooting Common Team Issues](#troubleshooting-common-team-issues)

---

## Team Setup

### Initial Team Configuration

**Step 1: Choose vault strategy** (see [Vault Organization](#vault-organization))

**Step 2: Create team vault(s)**:
```bash
# In 1Password UI:
# 1. Create vault: "MyApp - Development"
# 2. Share with team (appropriate permissions)
# 3. Verify team members can access
```

**Step 3: Push initial secrets**:
```bash
# Team lead pushes production secrets
op-env-manager push \
  --vault "MyApp - Production" \
  --env .env.production \
  --item "myapp" \
  --section "production"

# Push development secrets
op-env-manager push \
  --vault "MyApp - Development" \
  --env .env.development \
  --item "myapp" \
  --section "development"
```

**Step 4: Generate templates for git**:
```bash
# Create .env.op template (safe for version control)
op-env-manager template \
  --vault "MyApp - Development" \
  --item "myapp" \
  --section "development" \
  --output .env.op

# Commit template
git add .env.op
git commit -m "Add environment variable template"
```

**Step 5: Document the workflow**:
```markdown
# Add to project README.md

## Environment Setup

1. Install 1Password CLI: https://developer.1password.com/docs/cli/get-started/
2. Install op-env-manager: https://github.com/matteocervelli/op-env-manager
3. Sign in to 1Password: `op signin`
4. Inject secrets: `op-env-manager inject --vault "MyApp - Development" --item "myapp"`
5. Run app: `npm start`

Ask team lead for vault access if you encounter permission errors.
```

---

## Vault Organization

### Strategy 1: Single Vault with Sections

**Best for**: Small teams (2-5 people), single application

**Structure**:
```
Vault: "MyApp"
└── Item: "myapp"
    ├── Section: "development"
    │   ├── DATABASE_URL=postgresql://localhost/myapp_dev
    │   ├── API_KEY=dev_key_xxx
    │   └── ...
    ├── Section: "staging"
    │   ├── DATABASE_URL=postgresql://staging.example.com/myapp
    │   ├── API_KEY=staging_key_xxx
    │   └── ...
    └── Section: "production"
        ├── DATABASE_URL=postgresql://prod.example.com/myapp
        ├── API_KEY=prod_key_xxx
        └── ...
```

**Pros**:
- Simple to manage
- Easy to compare environments
- Single vault to share

**Cons**:
- All team members see all environments
- Can't restrict production access separately

**Usage**:
```bash
# Dynamic section selection with APP_ENV
APP_ENV=development op-env-manager run --vault "MyApp" --item "myapp" -- npm start
APP_ENV=production op-env-manager run --vault "MyApp" --item "myapp" -- npm start
```

### Strategy 2: Separate Vaults per Environment

**Best for**: Medium to large teams (5+ people), strict access control

**Structure**:
```
Vault: "MyApp - Development"
└── Item: "myapp"
    ├── DATABASE_URL=postgresql://localhost/myapp_dev
    ├── API_KEY=dev_key_xxx
    └── ...

Vault: "MyApp - Staging"
└── Item: "myapp"
    ├── DATABASE_URL=postgresql://staging.example.com/myapp
    ├── API_KEY=staging_key_xxx
    └── ...

Vault: "MyApp - Production"
└── Item: "myapp"
    ├── DATABASE_URL=postgresql://prod.example.com/myapp
    ├── API_KEY=prod_key_xxx
    └── ...
```

**Pros**:
- Granular access control
- Production secrets isolated
- Clear audit trail per environment

**Cons**:
- More vaults to manage
- Harder to compare environments

**Access Control**:
```
Vault                    | Developers | DevOps | Seniors
-------------------------|------------|--------|--------
MyApp - Development      | Read/Write | RW     | RW
MyApp - Staging          | Read-Only  | RW     | RW
MyApp - Production       | None       | RO     | RW
```

**Usage**:
```bash
# Developers use dev vault
op-env-manager inject --vault "MyApp - Development" --item "myapp"

# DevOps deploys to production
op-env-manager run --vault "MyApp - Production" --item "myapp" -- ./deploy.sh
```

### Strategy 3: Hybrid Approach

**Best for**: Multiple projects, complex team structure

**Structure**:
```
Vault: "Shared Services"
└── Item: "database"
    ├── POSTGRES_HOST=db.internal.com
    ├── REDIS_URL=redis://cache.internal.com
    └── ...

Vault: "MyApp - Development"
└── Item: "myapp"
    ├── API_KEY=dev_key_xxx
    ├── SECRET_KEY=dev_secret
    └── ...

Vault: "MyApp - Production"
└── Item: "myapp"
    ├── API_KEY=prod_key_xxx
    ├── SECRET_KEY=prod_secret
    └── ...
```

**Usage**:
```bash
# Inject from multiple vaults (manual merge)
op-env-manager inject --vault "Shared Services" --item "database" --output .env.shared
op-env-manager inject --vault "MyApp - Development" --item "myapp" --output .env.app

# Merge files
cat .env.shared .env.app > .env.local
rm .env.shared .env.app
```

---

## Onboarding New Team Members

### Onboarding Checklist

**For Team Lead**:
- [ ] Add new member to 1Password team
- [ ] Grant access to appropriate vaults
- [ ] Send onboarding documentation
- [ ] Schedule pairing session

**For New Team Member**:
- [ ] Install 1Password desktop app
- [ ] Install 1Password CLI ([guide](1PASSWORD_SETUP.md))
- [ ] Sign in to 1Password CLI: `op signin`
- [ ] Verify vault access: `op vault list`
- [ ] Install op-env-manager
- [ ] Clone project repository
- [ ] Inject secrets and run app

### Onboarding Script

Create `.scripts/onboard.sh` in your repository:

```bash
#!/usr/bin/env bash
set -eo pipefail

echo "🚀 MyApp Onboarding Script"
echo ""

# Check prerequisites
echo "Checking prerequisites..."

if ! command -v op &> /dev/null; then
    echo "❌ 1Password CLI not found"
    echo "Install: https://developer.1password.com/docs/cli/get-started/"
    exit 1
fi

if ! command -v op-env-manager &> /dev/null; then
    echo "❌ op-env-manager not found"
    echo "Install: https://github.com/matteocervelli/op-env-manager"
    exit 1
fi

# Check 1Password authentication
if ! op account list &> /dev/null; then
    echo "❌ Not signed in to 1Password"
    echo "Run: op signin"
    exit 1
fi

echo "✅ Prerequisites met"
echo ""

# Check vault access
echo "Checking vault access..."
if ! op vault get "MyApp - Development" &> /dev/null; then
    echo "❌ Cannot access 'MyApp - Development' vault"
    echo "Ask your team lead for access"
    exit 1
fi

echo "✅ Vault access confirmed"
echo ""

# Inject development secrets
echo "Injecting development secrets..."
op-env-manager inject \
    --vault "MyApp - Development" \
    --item "myapp" \
    --output .env.local

echo "✅ Secrets injected to .env.local"
echo ""

# Install dependencies
echo "Installing dependencies..."
npm install

echo "✅ Dependencies installed"
echo ""

echo "🎉 Onboarding complete!"
echo ""
echo "Next steps:"
echo "  1. Run: npm start"
echo "  2. Visit: http://localhost:3000"
echo "  3. Check Slack #dev channel for team updates"
```

**Usage**:
```bash
# New team member runs:
./scripts/onboard.sh
```

---

## Multi-Environment Workflows

### Development Workflow

**Individual developer setup**:
```bash
# Each developer has own local .env
op-env-manager inject \
    --vault "MyApp - Development" \
    --item "myapp" \
    --section "development" \
    --output .env.local

# Run locally
npm run dev
```

**Shared development database**:
```bash
# All developers use same dev database credentials
# Stored in shared development vault
op-env-manager inject \
    --vault "MyApp - Development" \
    --item "database" \
    --output .env.database

# Start app with shared DB
op-env-manager run \
    --vault "MyApp - Development" \
    --item "myapp" \
    -- npm run dev
```

### Staging Workflow

**Automated deployment**:
```yaml
# .github/workflows/deploy-staging.yml
- name: Deploy to staging
  env:
    OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
  run: |
    op-env-manager run \
        --vault "MyApp - Staging" \
        --item "myapp" \
        -- ./deploy.sh staging
```

**Manual staging deployment**:
```bash
# DevOps engineer deploys manually
op-env-manager run \
    --vault "MyApp - Staging" \
    --item "myapp" \
    -- kubectl apply -f k8s/staging/
```

### Production Workflow

**Controlled production access**:
```bash
# Only senior engineers / DevOps have production vault access

# Review deployment plan
op-env-manager inject \
    --vault "MyApp - Production" \
    --item "myapp" \
    --dry-run

# Deploy to production (with approval)
op-env-manager run \
    --vault "MyApp - Production" \
    --item "myapp" \
    -- ./deploy.sh production
```

---

## Secret Rotation

### Rotation Strategy

**Quarterly rotation schedule**:
```
Q1: Rotate all API keys
Q2: Rotate database passwords
Q3: Rotate JWT secrets and encryption keys
Q4: Rotate third-party service credentials
```

### Rotation Workflow

**Step 1: Generate new secret**:
```bash
# Generate new secret (using your preferred method)
NEW_API_KEY=$(openssl rand -hex 32)
```

**Step 2: Update 1Password**:
```bash
# Update in 1Password (manually or via script)
# Use 1Password UI or CLI:
op item edit "myapp" \
    --vault "MyApp - Production" \
    "API_KEY=$NEW_API_KEY"
```

**Step 3: Deploy with new secret**:
```bash
# Deploy application with updated secret
op-env-manager run \
    --vault "MyApp - Production" \
    --item "myapp" \
    -- ./deploy.sh production
```

**Step 4: Verify and notify**:
```bash
# Verify application works with new secret
./scripts/health-check.sh

# Notify team in Slack
echo "🔑 Rotated API_KEY in production - deployed successfully"
```

### Rotation Script

Create `.scripts/rotate-secret.sh`:

```bash
#!/usr/bin/env bash
set -eo pipefail

SECRET_NAME=$1
VAULT=$2
ITEM=$3

if [ -z "$SECRET_NAME" ] || [ -z "$VAULT" ] || [ -z "$ITEM" ]; then
    echo "Usage: $0 <secret-name> <vault> <item>"
    exit 1
fi

echo "🔑 Rotating secret: $SECRET_NAME"
echo "Vault: $VAULT"
echo "Item: $ITEM"
echo ""

# Generate new secret
NEW_VALUE=$(openssl rand -hex 32)

echo "Generated new secret (first 10 chars): ${NEW_VALUE:0:10}..."
echo ""

# Confirm
read -p "Update $SECRET_NAME in 1Password? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 1
fi

# Update in 1Password
op item edit "$ITEM" --vault "$VAULT" "$SECRET_NAME=$NEW_VALUE"

echo "✅ Secret updated in 1Password"
echo ""
echo "Next steps:"
echo "  1. Deploy application: ./deploy.sh"
echo "  2. Verify health: ./scripts/health-check.sh"
echo "  3. Monitor logs: ./scripts/tail-logs.sh"
echo "  4. Notify team in Slack"
```

**Usage**:
```bash
./scripts/rotate-secret.sh API_KEY "MyApp - Production" "myapp"
```

---

## Access Control

### Permission Matrix

| Role | Development Vault | Staging Vault | Production Vault |
|------|------------------|---------------|------------------|
| **Junior Developer** | Read/Write | Read-Only | None |
| **Senior Developer** | Read/Write | Read/Write | Read-Only |
| **Tech Lead** | Read/Write | Read/Write | Read/Write |
| **DevOps Engineer** | Read/Write | Read/Write | Read/Write |
| **CI/CD Service Account** | Read-Only | Read-Only | Read-Only |

### Setting Up Permissions

**In 1Password UI**:
1. Go to vault → **Manage Access**
2. Add team members with appropriate roles
3. Set permissions: **View**, **View & Copy**, **Edit**, or **Manage**

**Recommended permissions**:
- Development: **Edit** (all developers)
- Staging: **View & Copy** (developers), **Edit** (seniors/DevOps)
- Production: **None** (juniors), **View & Copy** (seniors), **Edit** (DevOps only)

### Service Accounts

**Create separate service accounts per environment**:

```bash
# CI/CD for staging
Service Account: "GitHub Actions - Staging"
Vaults: "MyApp - Staging" (read-only)

# CI/CD for production
Service Account: "GitHub Actions - Production"
Vaults: "MyApp - Production" (read-only)

# Deployment automation
Service Account: "Deploy Bot - Production"
Vaults: "MyApp - Production" (read-only)
```

---

## Communication Protocols

### When to Notify Team

**Always notify for**:
- ✅ Production secret rotation
- ✅ Vault permission changes
- ✅ Breaking changes to .env structure
- ✅ New required environment variables

**Optional notification for**:
- ⚠️ Development vault updates
- ⚠️ New optional environment variables

### Slack Integration Example

Create `.scripts/notify-slack.sh`:

```bash
#!/usr/bin/env bash

SLACK_WEBHOOK_URL="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
MESSAGE=$1

curl -X POST -H 'Content-type: application/json' \
    --data "{\"text\":\"$MESSAGE\"}" \
    $SLACK_WEBHOOK_URL
```

**Usage**:
```bash
# After secret rotation
./scripts/notify-slack.sh "🔑 Rotated API_KEY in production vault"

# After adding new variable
./scripts/notify-slack.sh "⚠️ New env var added: FEATURE_FLAG_X (optional, defaults to false)"
```

### Documentation Updates

**Keep these updated**:
- `README.md` - Environment setup section
- `.env.example` - Example values for all variables
- `.env.op` - Template with op:// references
- `docs/ENVIRONMENT_VARIABLES.md` - Detailed variable descriptions

---

## Troubleshooting Common Team Issues

### "Vault not found" for new team member

**Cause**: Team member doesn't have vault access

**Solution**:
```bash
# Team member checks available vaults
op vault list

# Team lead grants access in 1Password UI
# Team member re-authenticates
op signin --force
op vault list  # Should now see vault
```

### Conflicting local .env files

**Cause**: Multiple developers modifying .env.example

**Solution**:
```bash
# Never commit .env files (except .env.example)
# Use .env.op template instead

# Add to .gitignore
.env
.env.*
.env.local
!.env.example
!.env.op

# Each developer injects locally
op-env-manager inject --vault "MyApp - Development" --output .env.local
```

### Production secret leak

**Response plan**:

1. **Immediate**: Rotate compromised secret
   ```bash
   ./scripts/rotate-secret.sh LEAKED_SECRET "MyApp - Production" "myapp"
   ```

2. **Deploy**: Push update to production
   ```bash
   op-env-manager run --vault "MyApp - Production" --item "myapp" -- ./deploy.sh
   ```

3. **Investigate**: Review 1Password activity log
4. **Notify**: Alert team and security lead
5. **Document**: Create incident report
6. **Prevent**: Review access controls and permissions

### Onboarding delays

**Common bottlenecks**:
- Waiting for 1Password account
- Waiting for vault access
- Installation issues

**Solution**: Create automated onboarding checklist

```markdown
# New Team Member Checklist

**Before Day 1** (Team Lead):
- [ ] Create 1Password account
- [ ] Grant vault access
- [ ] Add to GitHub team
- [ ] Send onboarding docs

**Day 1** (New Member):
- [ ] Install 1Password app
- [ ] Install 1Password CLI
- [ ] Install op-env-manager
- [ ] Clone repository
- [ ] Run: ./scripts/onboard.sh
- [ ] Verify: npm start

**Day 1** (Team Lead):
- [ ] Pair on first PR
- [ ] Review secret management workflow
```

---

## Best Practices Summary

### Do ✅

- **Use sections or separate vaults** for multi-environment
- **Grant minimal permissions** (principle of least privilege)
- **Rotate secrets regularly** (quarterly recommended)
- **Document the workflow** in README.md
- **Use service accounts for CI/CD** (not personal accounts)
- **Generate .env.op templates** (commit to git)
- **Notify team of production changes**
- **Automate onboarding** with scripts

### Don't ❌

- **Never commit .env files** (except .env.example)
- **Never share secrets over Slack/email**
- **Never use production secrets in development**
- **Don't grant everyone production access**
- **Don't forget to rotate secrets**
- **Don't modify secrets without team notification**

---

## Next Steps

- Review [CI_CD_EXAMPLES.md](CI_CD_EXAMPLES.md) for automation
- See [QUICKSTART.md](QUICKSTART.md) for command reference
- Read [1PASSWORD_SETUP.md](1PASSWORD_SETUP.md) for service account setup

---

**Questions?** [Open a discussion](https://github.com/matteocervelli/op-env-manager/discussions) or reach out in your team channel.
