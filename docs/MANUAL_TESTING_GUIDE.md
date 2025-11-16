# Manual End-to-End Testing Guide

This guide provides a comprehensive walkthrough for manually testing all features of `op-env-manager`. Use this to validate functionality before releases or after major changes.

## Prerequisites

### Required Setup

1. **1Password CLI installed and authenticated**
   ```bash
   op --version  # Should be 2.0+
   op account list  # Should show your account
   ```

2. **Test vault in 1Password**
   - Create a dedicated vault named "Test" or "Development"
   - Ensure you have write permissions

3. **Test environment**
   ```bash
   cd /path/to/op-env-manager
   ./install.sh --no-path  # Install locally
   export PATH="$HOME/.local/bin:$PATH"
   ```

4. **Create test directory**
   ```bash
   mkdir -p ~/op-env-test
   cd ~/op-env-test
   ```

---

## Test Scenarios

### 1. Interactive Setup (init command)

**Objective:** Validate the interactive wizard creates proper configuration.

**Steps:**

1. Start the wizard:
   ```bash
   op-env-manager init
   ```

2. **Vault selection:**
   - Verify list of vaults appears
   - Select your test vault (e.g., "Test")
   - Confirm selection is stored

3. **Item name:**
   - Enter: `test-app-env`
   - Press Enter

4. **Environment variables:**
   - When prompted "Add environment variable?", answer `y`
   - Add these variables:
     ```
     DATABASE_URL=postgresql://localhost:5432/testdb
     API_KEY=sk_test_1234567890abcdef
     DEBUG=true
     MAX_CONNECTIONS=50
     ```
   - Answer `n` when done

5. **Verification:**
   ```bash
   # Check created files
   ls -la
   # Should show: .env, .env.template

   # Check .env content
   cat .env
   # Should contain the 4 variables you entered

   # Check .env.template
   cat .env.template
   # Should contain op:// references like:
   # DATABASE_URL=op://Test/test-app-env/DATABASE_URL
   ```

6. **Verify in 1Password:**
   ```bash
   op item get test-app-env --vault Test --format json | jq
   # Should show item with 4 fields
   ```

**Expected Result:** ✅ .env and .env.template files created, item exists in 1Password with all fields.

---

### 2. Push Command (Local → 1Password)

**Objective:** Sync local .env file to 1Password.

#### 2.1 Basic Push

1. **Create test .env file:**
   ```bash
   cat > .env.push-test << 'EOF'
   # Database configuration
   DB_HOST=localhost
   DB_PORT=5432
   DB_NAME=myapp
   DB_USER=admin
   DB_PASSWORD=super_secret_password

   # API Keys
   STRIPE_KEY=sk_live_abc123
   SENDGRID_KEY=SG.xyz789

   # Feature flags
   ENABLE_BETA=false
   MAX_RETRIES=3
   EOF
   ```

2. **Push with dry-run:**
   ```bash
   op-env-manager push --vault Test --item push-test-app --env .env.push-test --dry-run
   ```

   **Expected:**
   - Shows "Would create/update" messages
   - Lists all 9 variables
   - No actual changes made

3. **Actual push:**
   ```bash
   op-env-manager push --vault Test --item push-test-app --env .env.push-test
   ```

   **Expected:**
   - Success messages
   - "✓ Pushed 9 variables"

4. **Verify in 1Password:**
   ```bash
   op item get push-test-app --vault Test --format json | jq '.fields[] | {label, value}'
   ```

   **Expected:** All 9 fields present with correct values

#### 2.2 Push with Updates

1. **Modify .env file:**
   ```bash
   cat >> .env.push-test << 'EOF'

   # New variable
   NEW_FEATURE=enabled
   EOF

   # Also change DB_PORT=5433
   sed -i.bak 's/DB_PORT=5432/DB_PORT=5433/' .env.push-test
   ```

2. **Push again:**
   ```bash
   op-env-manager push --vault Test --item push-test-app --env .env.push-test
   ```

3. **Verify changes:**
   ```bash
   op item get push-test-app --vault Test --format json | jq '.fields[] | select(.label=="DB_PORT" or .label=="NEW_FEATURE")'
   ```

   **Expected:** DB_PORT=5433, NEW_FEATURE=enabled

#### 2.3 Push with Special Characters

1. **Create file with edge cases:**
   ```bash
   cat > .env.special << 'EOF'
   # Multiline value
   SSH_KEY="-----BEGIN RSA PRIVATE KEY-----
   MIIEpAIBAAKCAQEA1234567890
   abcdefghijklmnop
   -----END RSA PRIVATE KEY-----"

   # Special characters
   PASSWORD_WITH_QUOTES="He said \"hello\""
   PASSWORD_WITH_EQUALS=key=value=here
   EMPTY_VALUE=
   SPACES_IN_VALUE="  leading and trailing  "
   URL_WITH_SPECIAL=https://user:p@ss@example.com:8080/path?q=1&x=2
   EOF
   ```

2. **Push:**
   ```bash
   op-env-manager push --vault Test --item special-chars --env .env.special
   ```

3. **Verify:**
   ```bash
   op item get special-chars --vault Test --format json | jq '.fields[] | {label, value}'
   ```

   **Expected:** All special characters preserved correctly

---

### 3. Inject Command (1Password → Local)

**Objective:** Pull secrets from 1Password into local .env file.

#### 3.1 Basic Inject

1. **Inject from push-test-app:**
   ```bash
   op-env-manager inject --vault Test --item push-test-app --output .env.injected
   ```

2. **Verify:**
   ```bash
   cat .env.injected
   diff .env.push-test .env.injected
   ```

   **Expected:** Files should be identical

3. **Check file permissions:**
   ```bash
   ls -l .env.injected
   ```

   **Expected:** `-rw-------` (600 permissions - owner read/write only)

#### 3.2 Inject to stdout

1. **Inject without output file:**
   ```bash
   op-env-manager inject --vault Test --item push-test-app
   ```

   **Expected:** All variables printed to stdout

#### 3.3 Inject with Force Overwrite

1. **Try to overwrite existing file:**
   ```bash
   op-env-manager inject --vault Test --item push-test-app --output .env.injected
   ```

   **Expected:** Error about file existing

2. **Force overwrite:**
   ```bash
   op-env-manager inject --vault Test --item push-test-app --output .env.injected --force
   ```

   **Expected:** File overwritten successfully

---

### 4. Run Command (Ephemeral Injection)

**Objective:** Run commands with secrets injected via environment, no plaintext files.

#### 4.1 Basic Run

1. **Create simple script:**
   ```bash
   cat > test-script.sh << 'EOF'
   #!/bin/bash
   echo "DB_HOST=$DB_HOST"
   echo "DB_PORT=$DB_PORT"
   echo "STRIPE_KEY length: ${#STRIPE_KEY}"
   EOF
   chmod +x test-script.sh
   ```

2. **Run with inject:**
   ```bash
   op-env-manager run --vault Test --item push-test-app -- ./test-script.sh
   ```

   **Expected:**
   - Script executes
   - Variables are available
   - STRIPE_KEY length shown (not the actual key)

#### 4.2 Run with Template

1. **Create .env.template:**
   ```bash
   cat > .env.template << 'EOF'
   DB_HOST=op://Test/push-test-app/DB_HOST
   DB_PORT=op://Test/push-test-app/DB_PORT
   STRIPE_KEY=op://Test/push-test-app/STRIPE_KEY
   EOF
   ```

2. **Run using template:**
   ```bash
   op-env-manager run --env-file .env.template -- ./test-script.sh
   ```

   **Expected:** Same output as 4.1

#### 4.3 Run Complex Command

1. **Test with Node.js (if installed):**
   ```bash
   cat > test.js << 'EOF'
   console.log('DB Config:', {
     host: process.env.DB_HOST,
     port: process.env.DB_PORT,
     database: process.env.DB_NAME
   });
   EOF
   ```

2. **Run:**
   ```bash
   op-env-manager run --vault Test --item push-test-app -- node test.js
   ```

   **Expected:** JSON object with DB configuration

---

### 5. Template Command (Generate op:// References)

**Objective:** Create template files with 1Password references.

#### 5.1 Template from 1Password Item

1. **Generate template:**
   ```bash
   op-env-manager template --vault Test --item push-test-app --output .env.template.generated
   ```

2. **Verify:**
   ```bash
   cat .env.template.generated
   ```

   **Expected:**
   - All fields from `push-test-app` as `op://Test/push-test-app/FIELD_NAME`
   - Format: `FIELD_NAME=op://vault/item/field`

3. **Test template is valid:**
   ```bash
   op run --env-file=.env.template.generated -- env | grep DB_HOST
   ```

   **Expected:** Shows actual DB_HOST value

#### 5.2 Template with Merge Mode

1. **Create .env.example with structure:**
   ```bash
   cat > .env.example << 'EOF'
   # ===========================================
   # Database Configuration
   # ===========================================
   DB_HOST=localhost
   DB_PORT=5432
   DB_NAME=myapp

   # ===========================================
   # External Services
   # ===========================================
   STRIPE_KEY=your_stripe_key_here
   SENDGRID_KEY=your_sendgrid_key_here

   # ===========================================
   # Feature Flags
   # ===========================================
   ENABLE_BETA=false
   EOF
   ```

2. **Generate merged template:**
   ```bash
   op-env-manager template --vault Test --item push-test-app \
     --env-file .env.example \
     --output .env.template.merged
   ```

3. **Verify:**
   ```bash
   cat .env.template.merged
   ```

   **Expected:**
   - Comments and structure from .env.example preserved
   - Values replaced with op:// references
   - Example:
     ```
     # Database Configuration
     DB_HOST=op://Test/push-test-app/DB_HOST
     ```

#### 5.3 Template with Dynamic Section

1. **Create multi-environment template:**
   ```bash
   cat > .env.dynamic << 'EOF'
   DB_HOST=op://Test/myapp/$APP_ENV/db_host
   API_KEY=op://Test/myapp/$APP_ENV/api_key
   EOF
   ```

2. **Test with different environments:**
   ```bash
   export APP_ENV=production
   op-env-manager run --env-file .env.dynamic -- env | grep DB_HOST

   export APP_ENV=staging
   op-env-manager run --env-file .env.dynamic -- env | grep DB_HOST
   ```

   **Expected:** Different values based on APP_ENV (requires items setup in 1Password)

---

### 6. Convert Command (Existing Item → .env)

**Objective:** Convert existing 1Password items to .env format.

#### 6.1 Basic Convert

1. **Create a random 1Password item:**
   ```bash
   op item create --category=Login \
     --vault=Test \
     --title=legacy-app \
     username=admin \
     password=legacy123 \
     "Server URL[url]=https://legacy.example.com" \
     "API Token[password]=token_abc123"
   ```

2. **Convert to .env:**
   ```bash
   op-env-manager convert --vault Test --item legacy-app --output .env.converted
   ```

3. **Verify:**
   ```bash
   cat .env.converted
   ```

   **Expected:**
   - Variables like `USERNAME=admin`, `PASSWORD=legacy123`
   - Field names sanitized (uppercase, underscores)

#### 6.2 Convert with Template Generation

1. **Convert and generate template:**
   ```bash
   op-env-manager convert --vault Test --item legacy-app \
     --output .env.converted \
     --template .env.template.converted
   ```

2. **Verify template:**
   ```bash
   cat .env.template.converted
   ```

   **Expected:**
   - op:// references for all fields
   - Example: `USERNAME=op://Test/legacy-app/username`

#### 6.3 Convert with Prefix

1. **Convert with prefix:**
   ```bash
   op-env-manager convert --vault Test --item legacy-app \
     --output .env.prefixed \
     --prefix LEGACY_
   ```

2. **Verify:**
   ```bash
   cat .env.prefixed
   ```

   **Expected:**
   - All variables prefixed: `LEGACY_USERNAME=admin`, `LEGACY_PASSWORD=legacy123`

---

### 7. Diff Command (Compare Sources)

**Objective:** Compare .env files with 1Password items.

#### 7.1 Basic Diff (No Changes)

1. **Push a known state:**
   ```bash
   cat > .env.baseline << 'EOF'
   APP_NAME=MyApp
   VERSION=1.0.0
   DEBUG=false
   EOF

   op-env-manager push --vault Test --item diff-test --env .env.baseline
   ```

2. **Run diff:**
   ```bash
   op-env-manager diff --vault Test --item diff-test --env .env.baseline
   ```

   **Expected:** "No differences found" message

#### 7.2 Diff with Local Changes

1. **Modify local file:**
   ```bash
   cat > .env.local-changes << 'EOF'
   APP_NAME=MyApp
   VERSION=2.0.0
   DEBUG=true
   NEW_FEATURE=enabled
   EOF
   ```

2. **Run diff:**
   ```bash
   op-env-manager diff --vault Test --item diff-test --env .env.local-changes
   ```

   **Expected:** Shows:
   - Changed: VERSION (1.0.0 → 2.0.0)
   - Changed: DEBUG (false → true)
   - Added: NEW_FEATURE
   - Summary counts

#### 7.3 Diff with Remote Changes

1. **Modify 1Password item:**
   ```bash
   op item edit diff-test --vault Test "VERSION[text]=3.0.0"
   op item edit diff-test --vault Test "ADMIN_EMAIL[text]=admin@example.com"
   ```

2. **Run diff:**
   ```bash
   op-env-manager diff --vault Test --item diff-test --env .env.baseline
   ```

   **Expected:** Shows:
   - Changed: VERSION (1.0.0 in local, 3.0.0 in 1Password)
   - Deleted: ADMIN_EMAIL (exists in 1Password, not in local)

---

### 8. Sync Command (Bidirectional Sync)

**Objective:** Synchronize changes between local and 1Password with conflict resolution.

#### 8.1 Initial Sync (Establish Baseline)

1. **Create baseline:**
   ```bash
   cat > .env.sync << 'EOF'
   SERVICE=api
   PORT=3000
   TIMEOUT=30
   EOF

   op-env-manager push --vault Test --item sync-test --env .env.sync
   ```

2. **First sync:**
   ```bash
   op-env-manager sync --vault Test --item sync-test --env .env.sync
   ```

   **Expected:**
   - "No differences found"
   - State file created: `.op-env-manager.state`

3. **Verify state file:**
   ```bash
   cat .op-env-manager.state
   ```

   **Expected:** JSON with checksums for each variable

#### 8.2 Sync with Local-Only Changes

1. **Modify local:**
   ```bash
   cat >> .env.sync << 'EOF'

   NEW_LOCAL_VAR=local_value
   EOF
   sed -i.bak 's/PORT=3000/PORT=4000/' .env.sync
   ```

2. **Sync:**
   ```bash
   op-env-manager sync --vault Test --item sync-test --env .env.sync
   ```

   **Expected:**
   - Detects 1 change (PORT) and 1 addition (NEW_LOCAL_VAR)
   - Pushes to 1Password
   - Updates state file

3. **Verify:**
   ```bash
   op item get sync-test --vault Test --format json | jq '.fields[] | select(.label=="PORT" or .label=="NEW_LOCAL_VAR")'
   ```

#### 8.3 Sync with Remote-Only Changes

1. **Modify 1Password:**
   ```bash
   op item edit sync-test --vault Test "TIMEOUT[text]=60"
   op item edit sync-test --vault Test "NEW_REMOTE_VAR[text]=remote_value"
   ```

2. **Sync:**
   ```bash
   op-env-manager sync --vault Test --item sync-test --env .env.sync
   ```

   **Expected:**
   - Detects remote changes
   - Pulls to local .env file
   - Updates state

3. **Verify:**
   ```bash
   grep -E 'TIMEOUT|NEW_REMOTE_VAR' .env.sync
   ```

   **Expected:** Shows TIMEOUT=60 and NEW_REMOTE_VAR=remote_value

#### 8.4 Sync with Conflicts (Interactive)

1. **Create conflict:**
   ```bash
   # Change locally
   sed -i.bak 's/PORT=4000/PORT=5000/' .env.sync

   # Change remotely (same variable)
   op item edit sync-test --vault Test "PORT[text]=6000"
   ```

2. **Sync interactively:**
   ```bash
   op-env-manager sync --vault Test --item sync-test --env .env.sync --strategy interactive
   ```

   **Expected:**
   - Shows conflict for PORT
   - Displays both values:
     - Local: 5000
     - Remote: 6000
   - Prompts for choice: [L]ocal / [R]emote / [S]kip

3. **Test each option:**
   - Choose `L`: Local value (5000) wins
   - Reset and choose `R`: Remote value (6000) wins
   - Reset and choose `S`: Skip, keep conflict

#### 8.5 Sync with Automatic Strategies

1. **Strategy: ours (local wins)**
   ```bash
   # Create conflict again
   sed -i.bak 's/PORT=5000/PORT=7000/' .env.sync
   op item edit sync-test --vault Test "PORT[text]=8000"

   # Sync with --strategy ours
   op-env-manager sync --vault Test --item sync-test --env .env.sync --strategy ours
   ```

   **Expected:**
   - No prompts
   - Local value (7000) wins
   - Remote updated to 7000

2. **Strategy: theirs (remote wins)**
   ```bash
   # Create conflict
   sed -i.bak 's/PORT=7000/PORT=9000/' .env.sync
   op item edit sync-test --vault Test "PORT[text]=10000"

   # Sync with --strategy theirs
   op-env-manager sync --vault Test --item sync-test --env .env.sync --strategy theirs
   ```

   **Expected:**
   - Remote value (10000) wins
   - Local updated to 10000

3. **Strategy: newest**
   ```bash
   # Create conflict with timestamp
   sleep 2
   op item edit sync-test --vault Test "PORT[text]=11000"

   # Sync with --strategy newest
   op-env-manager sync --vault Test --item sync-test --env .env.sync --strategy newest
   ```

   **Expected:**
   - Remote value wins (most recent modification)

#### 8.6 Sync with Backup

1. **Verify backup created:**
   ```bash
   op-env-manager sync --vault Test --item sync-test --env .env.sync
   ```

2. **Check backup:**
   ```bash
   ls -lt .env.sync.backup.*
   ```

   **Expected:** Timestamped backup file exists

---

### 9. Error Handling & Edge Cases

**Objective:** Validate error handling and recovery.

#### 9.1 Missing Arguments

1. **Test missing vault:**
   ```bash
   op-env-manager push --item test
   ```

   **Expected:** Error message with helpful suggestion

2. **Test missing item:**
   ```bash
   op-env-manager inject --vault Test
   ```

   **Expected:** Error message listing available items

#### 9.2 Invalid Vault/Item

1. **Non-existent vault:**
   ```bash
   op-env-manager push --vault NonExistent --item test --env .env.test
   ```

   **Expected:** Error with vault list suggestion

2. **Non-existent item:**
   ```bash
   op-env-manager inject --vault Test --item does-not-exist
   ```

   **Expected:** Error suggesting to list items or use push

#### 9.3 File Permissions

1. **Read-only .env file:**
   ```bash
   cat > .env.readonly << 'EOF'
   TEST=value
   EOF
   chmod 444 .env.readonly

   op-env-manager sync --vault Test --item perm-test --env .env.readonly
   ```

   **Expected:** Error about write permissions

2. **Verify injected file permissions:**
   ```bash
   op-env-manager inject --vault Test --item sync-test --output .env.check-perms
   ls -l .env.check-perms
   ```

   **Expected:** `-rw-------` (600)

#### 9.4 Network Retry Logic

1. **Simulate flaky network (requires network manipulation):**
   ```bash
   # If possible, use network link conditioner or similar
   # Otherwise, just note this behavior is tested in bats tests

   # With retries enabled (default):
   OP_MAX_RETRIES=3 op-env-manager push --vault Test --item retry-test --env .env.baseline
   ```

   **Expected:** Retries on transient failures

2. **Disable retries:**
   ```bash
   OP_DISABLE_RETRY=true op-env-manager push --vault Test --item retry-test --env .env.baseline
   ```

   **Expected:** Fails immediately on error

#### 9.5 Large File Performance

1. **Create large .env file:**
   ```bash
   cat > .env.large << 'EOF'
   EOF
   for i in {1..500}; do
     echo "VAR_$i=value_$i" >> .env.large
   done
   ```

2. **Push with progress bar:**
   ```bash
   time op-env-manager push --vault Test --item large-test --env .env.large
   ```

   **Expected:**
   - Progress bar appears (threshold = 100 vars)
   - Completes in reasonable time (batch operations)
   - Success message with count

3. **Push without progress:**
   ```bash
   OP_SHOW_PROGRESS=false time op-env-manager push --vault Test --item large-test --env .env.large
   ```

   **Expected:** No progress bar, just final message

---

### 10. Quiet Mode & Output Control

**Objective:** Validate output suppression for CI/CD.

#### 10.1 Quiet Mode

1. **Normal output:**
   ```bash
   op-env-manager push --vault Test --item quiet-test --env .env.baseline
   ```

   **Expected:** Headers, steps, success messages

2. **Quiet mode:**
   ```bash
   OP_QUIET_MODE=true op-env-manager push --vault Test --item quiet-test --env .env.baseline
   ```

   **Expected:** Only errors (if any) to stderr, no success messages

3. **Quiet mode with error:**
   ```bash
   OP_QUIET_MODE=true op-env-manager push --vault NonExistent --item test --env .env.baseline 2>&1
   ```

   **Expected:** Error message visible

#### 10.2 Progress Bar Suppression

1. **CI environment detection:**
   ```bash
   CI=true op-env-manager push --vault Test --item large-test --env .env.large
   ```

   **Expected:** No progress bar (CI detected)

2. **Pipe detection:**
   ```bash
   op-env-manager push --vault Test --item large-test --env .env.large | cat
   ```

   **Expected:** No progress bar (not a TTY)

---

### 11. Integration with op run

**Objective:** Verify compatibility with native 1Password CLI.

#### 11.1 Template Compatibility

1. **Generate template:**
   ```bash
   op-env-manager template --vault Test --item push-test-app --output .env.op-compatible
   ```

2. **Use with native op run:**
   ```bash
   op run --env-file=.env.op-compatible -- env | grep DB_HOST
   ```

   **Expected:** Works seamlessly with native `op run`

#### 11.2 Round-Trip Test

1. **Push → Template → Run:**
   ```bash
   # Push
   op-env-manager push --vault Test --item roundtrip --env .env.baseline

   # Generate template
   op-env-manager template --vault Test --item roundtrip --output .env.roundtrip

   # Run with op
   op run --env-file=.env.roundtrip -- bash -c 'echo $APP_NAME'

   # Run with op-env-manager
   op-env-manager run --env-file .env.roundtrip -- bash -c 'echo $APP_NAME'
   ```

   **Expected:** Both produce same output

---

## Performance Benchmarks

### Measure Command Performance

1. **Small file (10 vars):**
   ```bash
   time op-env-manager push --vault Test --item perf-small --env .env.baseline
   ```

   **Expected:** < 2 seconds

2. **Medium file (50 vars):**
   ```bash
   # Create 50-var file
   for i in {1..50}; do echo "VAR_$i=value_$i"; done > .env.medium

   time op-env-manager push --vault Test --item perf-medium --env .env.medium
   ```

   **Expected:** < 5 seconds

3. **Large file (500 vars):**
   ```bash
   time op-env-manager push --vault Test --item perf-large --env .env.large
   ```

   **Expected:** < 30 seconds (network-bound)

4. **Sync performance:**
   ```bash
   time op-env-manager sync --vault Test --item perf-medium --env .env.medium
   ```

   **Expected:** < 5 seconds (parallel reads)

---

## Security Validation

### Secret Handling

1. **Verify secrets not logged:**
   ```bash
   # Enable debug mode (if available)
   TEST_DEBUG=true op-env-manager push --vault Test --item security-test --env .env.special 2>&1 | grep -i "super_secret"
   ```

   **Expected:** No secret values in output

2. **Verify file permissions:**
   ```bash
   op-env-manager inject --vault Test --item security-test --output .env.secured
   ls -l .env.secured
   ```

   **Expected:** `-rw-------` (600)

3. **Verify no plaintext storage:**
   ```bash
   op-env-manager template --vault Test --item security-test --output .env.no-secrets
   cat .env.no-secrets | grep -v "op://"
   ```

   **Expected:** Only op:// references, no actual secrets

---

## Cleanup

After testing, clean up test items:

```bash
# List test items
op item list --vault Test | grep -E 'test-app|push-test|special-chars|diff-test|sync-test|large-test'

# Delete test items
op item delete test-app-env --vault Test
op item delete push-test-app --vault Test
op item delete special-chars --vault Test
op item delete legacy-app --vault Test
op item delete diff-test --vault Test
op item delete sync-test --vault Test
op item delete large-test --vault Test
op item delete quiet-test --vault Test
op item delete roundtrip --vault Test
op item delete perf-small --vault Test
op item delete perf-medium --vault Test
op item delete perf-large --vault Test
op item delete security-test --vault Test

# Clean up test files
cd ~/op-env-test
rm -rf *

# Remove test directory
cd ~
rm -rf op-env-test
```

---

## Checklist

Use this checklist to track your testing progress:

- [ ] 1. Interactive Setup (init)
  - [ ] 1.1 Vault selection works
  - [ ] 1.2 Item creation works
  - [ ] 1.3 Variable input works
  - [ ] 1.4 Files created correctly
  - [ ] 1.5 1Password item created

- [ ] 2. Push Command
  - [ ] 2.1 Basic push works
  - [ ] 2.2 Dry-run mode works
  - [ ] 2.3 Updates work
  - [ ] 2.4 Special characters preserved

- [ ] 3. Inject Command
  - [ ] 3.1 Basic inject works
  - [ ] 3.2 Stdout injection works
  - [ ] 3.3 Force overwrite works
  - [ ] 3.4 File permissions correct (600)

- [ ] 4. Run Command
  - [ ] 4.1 Basic run works
  - [ ] 4.2 Template mode works
  - [ ] 4.3 Complex commands work

- [ ] 5. Template Command
  - [ ] 5.1 Generation from 1Password works
  - [ ] 5.2 Merge mode preserves structure
  - [ ] 5.3 Dynamic sections work

- [ ] 6. Convert Command
  - [ ] 6.1 Basic conversion works
  - [ ] 6.2 Template generation works
  - [ ] 6.3 Prefix option works

- [ ] 7. Diff Command
  - [ ] 7.1 No-change detection works
  - [ ] 7.2 Local changes detected
  - [ ] 7.3 Remote changes detected

- [ ] 8. Sync Command
  - [ ] 8.1 Initial sync works
  - [ ] 8.2 Local-only changes sync
  - [ ] 8.3 Remote-only changes sync
  - [ ] 8.4 Interactive conflict resolution works
  - [ ] 8.5 Automatic strategies work
  - [ ] 8.6 Backups created

- [ ] 9. Error Handling
  - [ ] 9.1 Missing arguments handled
  - [ ] 9.2 Invalid vault/item handled
  - [ ] 9.3 File permissions checked
  - [ ] 9.4 Retry logic works
  - [ ] 9.5 Large files handled

- [ ] 10. Output Control
  - [ ] 10.1 Quiet mode works
  - [ ] 10.2 Progress bars suppressed in CI

- [ ] 11. Integration
  - [ ] 11.1 Templates work with native op run
  - [ ] 11.2 Round-trip consistency

- [ ] Performance
  - [ ] Small file performance acceptable
  - [ ] Medium file performance acceptable
  - [ ] Large file performance acceptable
  - [ ] Sync performance acceptable

- [ ] Security
  - [ ] Secrets not logged
  - [ ] File permissions secure
  - [ ] No plaintext storage

---

## Reporting Issues

If you find issues during testing:

1. **Note the command that failed:**
   ```
   Command: op-env-manager sync --vault Test --item test
   Error: ...
   ```

2. **Capture environment:**
   ```bash
   op --version
   bash --version
   uname -a
   ```

3. **Create minimal reproduction:**
   - Simplest .env file that reproduces issue
   - Exact command sequence

4. **Check logs/debug output:**
   ```bash
   TEST_DEBUG=true op-env-manager [command] [args]
   ```

5. **File issue with:**
   - Description
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment info
   - Error messages

---

## Additional Notes

### Best Practices During Testing

1. **Use a dedicated test vault** - Don't test with production secrets
2. **Take notes** - Document any unexpected behavior
3. **Test incrementally** - Don't skip to advanced features without testing basics
4. **Verify after each step** - Don't assume success without checking
5. **Clean up regularly** - Remove test items to avoid clutter
6. **Test in isolation** - One feature at a time for clear results

### Common Issues and Solutions

**Issue:** "op: command not found"
- **Solution:** Install 1Password CLI: `brew install 1password-cli`

**Issue:** "You are not currently signed in"
- **Solution:** Authenticate: `eval $(op signin)`

**Issue:** "Permission denied"
- **Solution:** Check file permissions and user has vault access

**Issue:** Progress bar not showing
- **Solution:** Check threshold (100+ vars) and that output is TTY

**Issue:** Sync conflicts not detected
- **Solution:** Ensure state file exists and has correct checksums

---

## Version Compatibility

This testing guide is for **op-env-manager v0.3.0** and requires:
- 1Password CLI v2.0+
- Bash 3.2+
- Standard Unix utilities (awk, sed, grep)

For earlier versions, some features (init, sync, diff) may not be available.
