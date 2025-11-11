# 1Password CLI Setup Guide

This guide walks you through installing and configuring the 1Password CLI for use with `op-env-manager`.

## Prerequisites

- A 1Password account (individual or team)
- macOS, Linux, or Windows operating system
- Terminal/command line access

## Installation

### macOS (Homebrew)

```bash
brew install --cask 1password-cli
```

### Linux (Debian/Ubuntu)

```bash
# Add 1Password repository
curl -sS https://downloads.1password.com/linux/keys/1password.asc | \
  sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" | \
  sudo tee /etc/apt/sources.list.d/1password.list

# Install
sudo apt update
sudo apt install 1password-cli
```

### Linux (Red Hat/CentOS/Fedora)

```bash
# Add 1Password repository
sudo rpm --import https://downloads.1password.com/linux/keys/1password.asc

sudo sh -c 'echo -e "[1password]\nname=1Password\nbaseurl=https://downloads.1password.com/linux/rpm/stable/\$basearch\nenabled=1\ngpgcheck=1\nrepo_gpgcheck=1\ngpgkey=https://downloads.1password.com/linux/keys/1password.asc" > /etc/yum.repos.d/1password.repo'

# Install
sudo dnf install 1password-cli
```

### Manual Installation (All Platforms)

Download from the official 1Password CLI page:
https://developer.1password.com/docs/cli/get-started/

## Configuration

### 1. Sign In to 1Password

```bash
op signin
```

Follow the prompts to authenticate with your 1Password account.

### 2. Verify Installation

```bash
op --version
```

You should see the version number (e.g., `2.x.x`).

### 3. Test Access

```bash
# List your vaults
op vault list

# List items in a vault (replace "Personal" with your vault name)
op item list --vault "Personal"
```

## Usage with op-env-manager

### Basic Workflow

1. **Sign in** (once per session):
   ```bash
   op signin
   ```

2. **Push environment variables to 1Password**:
   ```bash
   op-env-manager push --vault "Personal" --env .env
   ```

3. **Inject secrets back to a project**:
   ```bash
   op-env-manager inject --vault "Personal" --output .env.local
   ```

4. **Run commands with secrets**:
   ```bash
   op-env-manager run --vault "Personal" -- docker compose up
   ```

### Advanced: Service Accounts (CI/CD)

For automated environments (CI/CD pipelines, servers), use 1Password Service Accounts instead of personal accounts.

1. Create a Service Account in your 1Password account settings
2. Grant access to specific vaults
3. Use the service account token:
   ```bash
   export OP_SERVICE_ACCOUNT_TOKEN="your-token-here"
   op-env-manager push --vault "CI-CD" --env .env.production
   ```

**Security Note**: Service accounts follow the principle of least privilege - they only access what they need.

## Vault Organization

### Recommended Structure

Create separate vaults for different environments:

- **Development**: Development secrets (shared with team)
- **Staging**: Staging environment secrets
- **Production**: Production secrets (restricted access)
- **Personal**: Your personal projects

### Best Practices

1. **Use meaningful vault names** that reflect their purpose
2. **Grant minimal access** - only give access to those who need it
3. **Rotate secrets regularly** - update passwords/tokens quarterly
4. **Never commit .env files** - always use 1Password references
5. **Tag items consistently** - `op-env-manager` automatically tags items

## Secret References

1Password uses `op://` references for secrets:

```bash
# Format: op://vault/item/field
DATABASE_PASSWORD=op://Production/postgres-db/password
API_KEY=op://Production/api-credentials/api-key
```

These references are resolved at runtime by the 1Password CLI, keeping secrets secure.

## Troubleshooting

### "op command not found"

- Verify installation: `which op`
- Check PATH: `echo $PATH`
- Reinstall or add to PATH manually

### "Not signed in"

```bash
op signin
```

If that fails, check your internet connection and 1Password account status.

### "Vault not found"

```bash
# List available vaults
op vault list

# Use exact vault name (case-sensitive)
op-env-manager push --vault "My Vault Name"
```

### "Permission denied"

- Check vault access permissions in 1Password
- Verify you have write access (for `push` command)
- Use Service Account with correct permissions (for CI/CD)

### Session Expired

```bash
# Re-authenticate
op signin

# For long-running processes, use Service Account
export OP_SERVICE_ACCOUNT_TOKEN="your-token"
```

## Additional Resources

- [1Password CLI Documentation](https://developer.1password.com/docs/cli/)
- [Secret References Guide](https://developer.1password.com/docs/cli/secrets-environment-variables/)
- [Service Accounts](https://developer.1password.com/docs/service-accounts/)
- [Security Best Practices](https://support.1password.com/security/)

## Support

For issues with:
- **1Password CLI**: https://support.1password.com/
- **op-env-manager**: https://github.com/matteocervelli/op-env-manager/issues
