# Migration to v0.1.0

This project has been refactored from project-specific scripts to a shareable, generic tool.

## What Changed

### New Structure

```
op-env-manager/
├── bin/
│   └── op-env-manager          # Main executable
├── lib/
│   ├── logger.sh               # Logging utilities
│   ├── push.sh                 # Push command
│   └── inject.sh               # Inject command
├── docs/
│   ├── 1PASSWORD_SETUP.md      # 1Password CLI setup
│   ├── QUICKSTART.md           # Quick reference
│   ├── README-old.md           # Archived old README
│   └── QUICKSTART-old.md       # Archived old quickstart
├── examples/
│   └── .env.example            # Test .env file
├── archive/
│   ├── 1password-env-manager.sh    # Old create/update script
│   ├── manage-credentials.sh       # Old credential manager
│   └── test-1password-env-manager.sh # Old test script
├── install.sh                  # Installation script
├── install-1password-cli.sh    # 1Password CLI installer (kept for reference)
├── README.md                   # New README
├── LICENSE                     # MIT License
├── VERSION                     # Version file
└── .gitignore                  # Git ignore rules
```

### New Commands

**Old way** (project-specific):
```bash
./scripts/1password-env-manager.sh create --env .env --vault "CNA CRM"
./scripts/manage-credentials.sh store
```

**New way** (generic tool):
```bash
op-env-manager push --vault "Personal" --env .env
op-env-manager inject --vault "Personal" --output .env.local
op-env-manager run --vault "Personal" -- docker compose up
```

### Key Improvements

1. **Bidirectional Sync**: Both push and inject supported
2. **Runtime Injection**: Run commands with secrets (no plaintext files)
3. **Generic Naming**: No project-specific references
4. **Better Organization**: Modular structure (bin/, lib/, docs/)
5. **Proper Installation**: install.sh for ~/.local/bin
6. **Comprehensive Docs**: README, QUICKSTART, 1PASSWORD_SETUP guides
7. **Examples**: Test .env file included
8. **Git Ready**: .gitignore, LICENSE, VERSION files

### Migration Path

If you were using the old scripts:

#### From `1password-env-manager.sh create`

**Old**:
```bash
./scripts/1password-env-manager.sh create \
  --env .env.production.example \
  --sections "dev,prod" \
  --vault "CNA CRM"
```

**New**:
```bash
# Push to vault (creates individual items, not secure note)
op-env-manager push --vault "CNA-CRM" --env .env.production --item "crm"
```

**Note**: The new approach creates individual password items instead of a single Secure Note with sections. This is better for automation and `op://` references.

#### From `manage-credentials.sh generate`

**Old**:
```bash
./scripts/setup/manage-credentials.sh generate
# Creates .env.production with op:// references
```

**New**:
```bash
# Option 1: Inject to file
op-env-manager inject --vault "Production" --item "crm" --output .env.production

# Option 2: Run with secrets (preferred - no file created)
op-env-manager run --vault "Production" --item "crm" -- docker compose up
```

### Breaking Changes

1. **No more Secure Notes with sections** - Now uses individual password items
2. **Different item naming** - `env-secrets-{KEY}` instead of single note
3. **Simplified workflow** - No separate `create` and `update` modes
4. **Push/inject paradigm** - Clearer than create/update

### Data Migration

To migrate from old Secure Notes to new structure:

1. **Export from old Secure Note**:
   ```bash
   op item get "CNA-CRM-Environment-Secrets" --vault "CNA CRM" --format json | \
     jq -r '.fields[] | select(.id=="notesPlain") | .value' | \
     awk '/^SECTION: prod$/,/^SECTION: / {print}' > .env.prod.temp
   ```

2. **Push to new structure**:
   ```bash
   op-env-manager push --vault "CNA-CRM" --env .env.prod.temp --item "crm-prod"
   ```

3. **Clean up**:
   ```bash
   rm .env.prod.temp
   ```

### Recommended Setup

For new installations:

```bash
# 1. Clone repository
git clone https://github.com/matteocervelli/op-env-manager.git
cd op-env-manager

# 2. Install
./install.sh

# 3. Test
op-env-manager --version

# 4. Push your secrets
op-env-manager push --vault "Personal" --env .env

# 5. Use in projects
cd ~/your-project
op-env-manager inject --vault "Personal" --output .env.local
```

## Archived Files

Old scripts are in `archive/` for reference:
- `archive/1password-env-manager.sh` - Old create/update script
- `archive/manage-credentials.sh` - Old credential manager
- `archive/test-1password-env-manager.sh` - Old test script
- `docs/README-old.md` - Old README
- `docs/QUICKSTART-old.md` - Old quickstart

These are kept for reference but should not be used going forward.

## Questions?

See:
- [README.md](README.md) - Full documentation
- [docs/QUICKSTART.md](docs/QUICKSTART.md) - Quick reference
- [docs/1PASSWORD_SETUP.md](docs/1PASSWORD_SETUP.md) - 1Password CLI setup
- [GitHub Issues](https://github.com/matteocervelli/op-env-manager/issues) - Report issues
