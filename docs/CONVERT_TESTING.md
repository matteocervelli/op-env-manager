# Testing the Convert Command

This guide walks you through testing the new `convert` command that migrates `.env` files with `op://` secret references to op-env-manager format.

## Overview

The `convert` command allows you to:
1. Take a `.env` file with `op://vault/item/field` references
2. Resolve those references to actual secret values
3. Store them in a new 1Password Secure Note using op-env-manager's structure
4. All without creating temporary plaintext files

## Prerequisites

1. 1Password CLI installed and authenticated:
   ```bash
   op --version
   op account list  # Should show your account
   ```

2. A 1Password vault to use for testing (e.g., "Personal" or create "op-env-manager-test")

## Step 1: Create Test Items in 1Password

First, we'll create some test secrets in 1Password that we can reference:

```bash
# Create test vault (optional - can use existing vault)
# Do this in 1Password app if you want a dedicated test vault

# Create test password items using 1Password CLI
op item create \
  --category=password \
  --title="test-db-creds" \
  --vault="Personal" \
  password="my_super_secret_db_password_123"

op item create \
  --category=password \
  --title="test-api-keys" \
  --vault="Personal" \
  password="sk_test_abcdef123456789"

op item create \
  --category=password \
  --title="test-redis-creds" \
  --vault="Personal" \
  password="redis_secret_password_xyz"

op item create \
  --category=password \
  --title="test-jwt-secret" \
  --vault="Personal" \
  password="jwt_super_secret_key_for_signing"

# Verify items were created
op item list --vault="Personal" --tags=""
```

## Step 2: Create Test .env File with op:// References

Create a test `.env.template` file with references to the items we just created:

```bash
cat > .env.convert-test << 'EOF'
# Test Environment Configuration with 1Password References
# This file demonstrates the op:// reference format

# Database Configuration
DATABASE_URL=postgresql://testuser:op://Personal/test-db-creds/password@localhost:5432/testdb
POSTGRES_PASSWORD=op://Personal/test-db-creds/password

# API Keys
STRIPE_API_KEY=op://Personal/test-api-keys/password
PAYMENT_GATEWAY_KEY=op://Personal/test-api-keys/password

# Cache Configuration
REDIS_URL=redis://:op://Personal/test-redis-creds/password@localhost:6379/0
REDIS_PASSWORD=op://Personal/test-redis-creds/password

# Security
JWT_SECRET_KEY=op://Personal/test-jwt-secret/password
SESSION_SECRET=op://Personal/test-jwt-secret/password

# Regular non-secret variables (will be included as-is)
APP_NAME=Test Application
ENVIRONMENT=development
DEBUG=true
PORT=3000
LOG_LEVEL=info
EOF
```

**Important**: Change "Personal" to your actual vault name if different.

## Step 3: Verify References Work with Standard op CLI

Before converting, verify the references are valid:

```bash
# Test resolving a single reference
op read "op://Personal/test-db-creds/password"
# Should output: my_super_secret_db_password_123

# Test with op inject (preview mode)
op inject -i .env.convert-test
# Should show resolved values (be careful - secrets visible!)

# Test with op run (dry-run equivalent)
op run --env-file=.env.convert-test -- env | grep -E '(DATABASE|API_KEY|REDIS|JWT)'
# Should show environment variables with resolved secrets
```

## Step 4: Test Convert Command (Dry-Run)

Now test the convert command without making changes:

```bash
# Preview what would be converted
./bin/op-env-manager convert \
  --env-file=.env.convert-test \
  --vault="Personal" \
  --item="convert-test" \
  --dry-run
```

**Expected output**:
```
╔═══════════════════════════════════════════════════════════════╗
║  Converting Environment Variables to op-env-manager Format    ║
╚═══════════════════════════════════════════════════════════════╝

ℹ Using default item name prefix: convert-test
✓ 1Password CLI authenticated
→ Parsing and resolving: .env.convert-test
ℹ [DRY RUN] Would create/update item: convert-test

ℹ [DRY RUN] Would set: DATABASE_URL = postgresql://testuser:[RESOLVED...]...
ℹ [DRY RUN] Would set: POSTGRES_PASSWORD = [RESOLVED:op://Personal/test-db-creds/password]...
ℹ [DRY RUN] Would set: STRIPE_API_KEY = [RESOLVED:op://Personal/test-api-keys/password]...
... (more variables) ...

⚠ DRY RUN: No changes made. Remove --dry-run to convert for real.
ℹ Would convert 11 variables (8 with op:// references)
```

## Step 5: Run Actual Conversion

If dry-run looks good, run the actual conversion:

```bash
./bin/op-env-manager convert \
  --env-file=.env.convert-test \
  --vault="Personal" \
  --item="convert-test"
```

**Expected output**:
```
╔═══════════════════════════════════════════════════════════════╗
║  Converting Environment Variables to op-env-manager Format    ║
╚═══════════════════════════════════════════════════════════════╝

ℹ Using default item name prefix: convert-test
✓ 1Password CLI authenticated
→ Parsing and resolving: .env.convert-test
ℹ Creating new item: convert-test

✓ Converted: DATABASE_URL
✓ Converted: POSTGRES_PASSWORD
✓ Converted: STRIPE_API_KEY
... (more variables) ...

✓ Successfully converted and pushed environment variables!

ℹ To inject these back into your environment:
  op-env-manager inject --vault="Personal" --item="convert-test"
```

## Step 6: Verify Conversion in 1Password

Check that the Secure Note was created correctly:

```bash
# View item in CLI
op item get "convert-test" --vault="Personal"

# Get specific field
op item get "convert-test" --vault="Personal" --fields "POSTGRES_PASSWORD"
# Should output: my_super_secret_db_password_123

# List all fields
op item get "convert-test" --vault="Personal" --format=json | jq '.fields[] | {label, value}'
```

**Or check in 1Password app**:
1. Open 1Password app
2. Navigate to your vault
3. Find "convert-test" Secure Note
4. Verify all 11 fields are present with correct values

## Step 7: Test Inject Back to .env

Now verify you can inject the converted secrets:

```bash
# Inject to new file
./bin/op-env-manager inject \
  --vault="Personal" \
  --item="convert-test" \
  --output=.env.test-output

# Verify contents
cat .env.test-output
# Should show all variables with resolved values (CAREFUL - plaintext!)

# Compare with original (secrets will differ in format)
diff .env.convert-test .env.test-output
# Will show differences (op:// refs vs actual values)

# Clean up
chmod 600 .env.test-output
rm .env.test-output
```

## Step 8: Test Run Command

Test using the converted secrets with a command:

```bash
# Run a simple command that prints environment variables
./bin/op-env-manager run \
  --vault="Personal" \
  --item="convert-test" \
  -- env | grep -E '(DATABASE|API_KEY|REDIS|JWT|APP_NAME)'
```

**Expected output**:
```
DATABASE_URL=postgresql://testuser:my_super_secret_db_password_123@localhost:5432/testdb
POSTGRES_PASSWORD=my_super_secret_db_password_123
STRIPE_API_KEY=sk_test_abcdef123456789
REDIS_URL=redis://:redis_secret_password_xyz@localhost:6379/0
JWT_SECRET_KEY=jwt_super_secret_key_for_signing
APP_NAME=Test Application
```

## Step 9: Clean Up Test Data

After testing, clean up the test items:

```bash
# Delete the converted Secure Note
op item delete "convert-test" --vault="Personal"

# Delete test password items (optional - keep if useful)
op item delete "test-db-creds" --vault="Personal"
op item delete "test-api-keys" --vault="Personal"
op item delete "test-redis-creds" --vault="Personal"
op item delete "test-jwt-secret" --vault="Personal"

# Delete test .env file
rm .env.convert-test
```

## Testing with Sections

To test multi-environment organization with sections:

```bash
# Create separate .env files for dev and prod
cat > .env.dev.template << 'EOF'
API_KEY=op://Personal/test-api-keys/password
DATABASE_URL=postgresql://user:op://Personal/test-db-creds/password@localhost:5432/dev_db
ENVIRONMENT=development
EOF

cat > .env.prod.template << 'EOF'
API_KEY=op://Personal/test-api-keys/password
DATABASE_URL=postgresql://user:op://Personal/test-db-creds/password@prod-host:5432/prod_db
ENVIRONMENT=production
EOF

# Convert both to same item with different sections
./bin/op-env-manager convert \
  --env-file=.env.dev.template \
  --vault="Personal" \
  --item="myapp" \
  --section="dev"

./bin/op-env-manager convert \
  --env-file=.env.prod.template \
  --vault="Personal" \
  --item="myapp" \
  --section="prod"

# Verify sections in 1Password
op item get "myapp" --vault="Personal" --format=json | jq '.fields[] | {section: .section.label, label, value}'

# Inject from specific section
./bin/op-env-manager inject \
  --vault="Personal" \
  --item="myapp" \
  --section="dev" \
  --output=.env.dev

# Clean up
rm .env.dev.template .env.prod.template .env.dev
op item delete "myapp" --vault="Personal"
```

## Troubleshooting

### Error: "Failed to resolve reference"

**Problem**: `op read` can't find the referenced item/field

**Solutions**:
```bash
# Check if item exists
op item get "item-name" --vault="VaultName"

# Verify vault name spelling
op vault list

# Ensure you're authenticated
op signin
```

### Error: "No variables found or resolved"

**Problem**: .env file is empty or all lines are comments

**Solutions**:
```bash
# Check file contents
cat .env.convert-test

# Ensure KEY=VALUE format (not KEY: VALUE)
# Ensure no BOM or encoding issues
file .env.convert-test
```

### Error: "Item already exists" conflicts

**Problem**: Running convert multiple times creates field conflicts

**Solutions**:
```bash
# Delete existing item first
op item delete "item-name" --vault="Personal"

# Or use a different item name
./bin/op-env-manager convert --item="item-name-v2" ...
```

## Success Criteria

✅ Test passes if:
1. Dry-run shows all variables detected and op:// refs identified
2. Actual conversion creates Secure Note with all fields
3. Fields contain resolved secret values (not op:// references)
4. Non-secret variables included as-is
5. `inject` command retrieves all variables correctly
6. `run` command executes with secrets injected

## Next Steps

After successful testing:
1. Read [docs/1password-formats.md](./1password-formats.md) to understand format differences
2. Update project README with convert command documentation
3. Migrate your real `.env.template` files using convert
4. Update team documentation with new workflow

## Example Real-World Usage

Here's the prompt to generate test files for your actual project:

```bash
# Prompt for creating test setup for your project:

"I want to test the op-env-manager convert command. Please help me:

1. Create 3-4 test password items in my 1Password vault 'Personal' with these names:
   - myproject-db-password
   - myproject-api-key
   - myproject-redis-password

2. Generate a .env.template file that references these items using op:// format, including:
   - Database connection URL with embedded password reference
   - API keys
   - Redis URL with embedded password reference
   - Some non-secret variables (APP_NAME, ENVIRONMENT, etc.)

3. Walk me through testing:
   - Verify references work with 'op inject'
   - Test convert with --dry-run
   - Run actual conversion
   - Verify in 1Password
   - Test inject and run commands

Use my actual vault name 'Personal' and make the secrets realistic but fake."
```

Replace "Personal" with your actual vault name and "myproject" with your project name.
