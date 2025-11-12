# Architecture Decision Records (ADRs)

This document records the key architectural decisions made during the development of `op-env-manager`.

## Format

Each ADR follows this structure:
- **Status**: Accepted, Proposed, Deprecated, or Superseded
- **Context**: The issue motivating this decision
- **Decision**: The decision made
- **Consequences**: What becomes easier or harder as a result

---

## ADR-001: Use Bash Instead of Python/Node.js

**Status**: Accepted

**Date**: 2024-12

**Context**:
- Need CLI tool for environment variable management
- Target audience: developers on Unix-like systems (macOS, Linux)
- Integration with 1Password CLI (also a command-line tool)
- Want minimal dependencies and fast execution
- Considered: Bash, Python, Node.js, Go

**Decision**:
Use Bash (v4.0+) as the implementation language.

**Consequences**:

*Positive*:
- ✅ Ubiquitous on target platforms (no installation required)
- ✅ Natural integration with 1Password CLI (shell to shell)
- ✅ Fast execution (no runtime startup overhead)
- ✅ Simple distribution (just copy files)
- ✅ Easy for developers to read and debug
- ✅ Can be run standalone or installed

*Negative*:
- ❌ Windows support requires WSL/Git Bash
- ❌ Less structured than compiled languages
- ❌ Complex error handling compared to exceptions
- ❌ Limited type safety

*Mitigations*:
- Use `set -eo pipefail` for error handling
- Extensive validation and error messages
- Follow Google Shell Style Guide
- Comprehensive testing strategy

---

## ADR-002: Store Variables as Secure Note Fields Instead of Individual Password Items

**Status**: Accepted

**Date**: 2024-12

**Context**:
- Need to store multiple environment variables per project
- Two approaches considered:
  1. **Individual items**: Each variable is a separate Password item (e.g., "myapp-API_KEY")
  2. **Single item with fields**: One Secure Note item with multiple fields

**Decision**:
Use Secure Note items with multiple fields.

**Item structure**:
```
Item: "myapp" (Secure Note)
├── Field: API_KEY = "secret_value_1"
├── Field: DATABASE_URL = "secret_value_2"
├── Field: SECRET_KEY = "secret_value_3"
└── ...
```

**Consequences**:

*Positive*:
- ✅ Logical grouping (all variables for one project together)
- ✅ Cleaner 1Password UI (fewer items)
- ✅ Easier to compare environments (view all fields at once)
- ✅ Atomic updates (all fields in one operation)
- ✅ Simpler injection (one API call gets all variables)
- ✅ Better performance (fewer round trips to 1Password API)

*Negative*:
- ❌ All-or-nothing access control (can't restrict individual fields)
- ❌ Large items with 100+ fields may be unwieldy
- ❌ 1Password field limits (64KB per field value)

*Alternatives considered*:
- Individual Password items: Rejected due to clutter and complexity
- JSON in single field: Rejected due to lack of structured editing

---

## ADR-003: Use Sections for Multi-Environment Organization

**Status**: Accepted

**Date**: 2024-12

**Context**:
- Projects need secrets for multiple environments (dev, staging, prod)
- Three approaches:
  1. **Sections within single item**: Use 1Password sections to organize
  2. **Separate items per environment**: "myapp-dev", "myapp-staging", "myapp-prod"
  3. **Separate vaults per environment**: Different vaults for each env

**Decision**:
Support sections as the primary organization method, but allow separate vaults as well.

**Implementation**:
```bash
# Section-based (recommended)
op-env-manager push --vault "MyApp" --item "myapp" --section "production"

# Vault-based (also supported)
op-env-manager push --vault "MyApp-Production" --item "myapp"
```

**Consequences**:

*Positive*:
- ✅ Flexible: Teams choose what works for them
- ✅ Sections keep related environments together
- ✅ Easy environment comparison (all in one item)
- ✅ Dynamic selection with `$APP_ENV` variable
- ✅ Separate vaults provide granular access control

*Negative*:
- ❌ Two patterns may confuse users
- ❌ Documentation needs to explain both approaches

*Rationale*:
- Small teams benefit from sections (simplicity)
- Large teams benefit from separate vaults (access control)
- Supporting both provides flexibility

---

## ADR-004: Implement `run` Command with op:// References Instead of Injecting Files

**Status**: Accepted

**Date**: 2024-12

**Context**:
- Need to execute commands with environment variables from 1Password
- Two approaches:
  1. **Inject then source**: Create .env file, source it, run command
  2. **Runtime injection**: Use 1Password's `op run` with references

**Decision**:
Implement `run` command that generates `op://` references and uses `op run` for runtime injection.

**Implementation**:
```bash
# Creates temp file with references:
# API_KEY=op://vault/item/field
# Then runs: op run --env-file=temp -- command
op-env-manager run --vault "Prod" --item "app" -- npm start
```

**Consequences**:

*Positive*:
- ✅ No plaintext secrets on disk
- ✅ Secrets never in shell history
- ✅ Automatic cleanup (no temp files left behind)
- ✅ Faster (no file I/O overhead)
- ✅ More secure (secrets only in memory)
- ✅ Works with 1Password audit trail

*Negative*:
- ❌ Requires 1Password CLI 2.0+ (op run support)
- ❌ Slight overhead from 1Password API calls
- ❌ Command fails if 1Password unavailable

*Why not inject*:
- Inject creates .env files (security risk if not cleaned up)
- Files can accidentally be committed
- Harder to ensure proper cleanup on error

---

## ADR-005: Generate .env.op Template Files for Version Control

**Status**: Accepted

**Date**: 2024-12

**Context**:
- Teams need to know what environment variables are required
- `.env` files can't be committed (contain secrets)
- `.env.example` requires manual updates
- Need way to generate always-accurate templates

**Decision**:
Implement `template` command that generates `.env.op` files with `op://` references.

**Generated file format**:
```bash
# .env.op (safe to commit)
API_KEY=op://Production/myapp/API_KEY
DATABASE_URL=op://Production/myapp/DATABASE_URL
SECRET_KEY=op://Production/myapp/SECRET_KEY
```

**Consequences**:

*Positive*:
- ✅ Safe to commit (no secrets)
- ✅ Always accurate (generated from 1Password)
- ✅ Self-documenting (shows required variables)
- ✅ Can be used with `op run` directly
- ✅ CI/CD friendly

*Negative*:
- ❌ Two file formats to understand (.env and .env.op)
- ❌ Requires regeneration when variables change

*Use cases*:
- Onboarding: New devs see exactly what variables are needed
- Documentation: Template serves as variable documentation
- CI/CD: Can use .env.op with `op run` in pipelines

---

## ADR-006: Tag All Items with "op-env-manager" for Easy Filtering

**Status**: Accepted

**Date**: 2024-12

**Context**:
- 1Password vaults may contain many items (passwords, notes, etc.)
- Need to identify items created by op-env-manager
- Need to list only managed items, not all vault items

**Decision**:
Automatically tag all created/updated items with "op-env-manager" and item-specific tag.

**Implementation**:
```bash
# When pushing, tag with:
# - "op-env-manager" (tool identifier)
# - "{item-name}" (project identifier)

op item create ... --tags "op-env-manager,myapp"
```

**Consequences**:

*Positive*:
- ✅ Easy filtering: `op item list --tags "op-env-manager"`
- ✅ Identify managed items vs manual items
- ✅ Cleanup assistance (find all managed items)
- ✅ Audit trail (know which items are managed by tool)

*Negative*:
- ❌ Tags are visible to all vault users
- ❌ Manual items won't be tagged (unless user adds tag)

*Alternatives considered*:
- Custom fields to mark items: Too complex
- Naming conventions: Fragile, easy to break

---

## ADR-007: Use Modular Command Architecture with Dynamic Loading

**Status**: Accepted

**Date**: 2024-12

**Context**:
- Multiple commands: push, inject, run, convert, template
- Two approaches:
  1. **Monolithic script**: All commands in one file
  2. **Modular structure**: Separate file per command

**Decision**:
Modular structure with dynamic loading.

**Structure**:
```
bin/op-env-manager       # Dispatcher
lib/push.sh              # Push command
lib/inject.sh            # Inject command
lib/convert.sh           # Convert command
lib/template.sh          # Template utilities
lib/logger.sh            # Shared logging
```

**Loading mechanism**:
```bash
case "$command" in
    push)
        source "$LIB_DIR/push.sh"
        main "$@"
        ;;
esac
```

**Consequences**:

*Positive*:
- ✅ Maintainable (each command is separate)
- ✅ Testable (can test commands individually)
- ✅ Fast (only loads needed code)
- ✅ Extensible (easy to add new commands)
- ✅ Clear separation of concerns

*Negative*:
- ❌ More files to manage
- ❌ Symlink-aware installation needed
- ❌ Shared code requires careful design

*Rationale*:
- Monolithic script was becoming too large (>1000 lines)
- Hard to test individual commands
- Difficult to add new features without breaking existing ones

---

## ADR-008: Implement Dry-Run Mode for All Commands

**Status**: Accepted

**Date**: 2024-12

**Context**:
- Users need to preview operations before executing
- Especially important for production operations
- Prevents accidental overwrites or modifications

**Decision**:
All commands support `--dry-run` flag.

**Behavior**:
- Skip 1Password authentication checks
- Print what would be done (don't execute)
- Exit successfully (allow testing in CI/CD)

**Consequences**:

*Positive*:
- ✅ Safe testing before execution
- ✅ Validates command syntax
- ✅ Previews changes
- ✅ Helps with debugging
- ✅ CI/CD validation without authentication

*Negative*:
- ❌ Code duplication (dry-run logic in each command)
- ❌ Needs maintenance (keep dry-run behavior in sync)

*Implementation pattern*:
```bash
if [ "$DRY_RUN" = true ]; then
    log_info "[DRY RUN] Would create item: $item_title"
    return 0
fi

# Actual operation
op item create ...
```

---

## ADR-009: Use Google Shell Style Guide

**Status**: Accepted

**Date**: 2024-12

**Context**:
- Need consistent coding style across all scripts
- Multiple contributors may work on project
- Want readable, maintainable code

**Decision**:
Follow [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html).

**Key conventions**:
- Functions: lowercase_with_underscores
- Global variables: UPPERCASE
- Local variables: lowercase
- 2-space indentation
- `#!/usr/bin/env bash` shebang
- `set -eo pipefail` at script start

**Consequences**:

*Positive*:
- ✅ Industry-standard style
- ✅ Well-documented conventions
- ✅ Consistent across all scripts
- ✅ Easier for contributors

*Negative*:
- ❌ Learning curve for unfamiliar contributors
- ❌ Some conventions may feel verbose

---

## ADR-010: Convert Command for Legacy Migration

**Status**: Accepted

**Date**: 2024-12

**Context**:
- Users may have existing `.env` files with `op://` references
- Direct `op://` usage is common in 1Password documentation
- Need migration path from direct references to op-env-manager

**Decision**:
Implement `convert` command that:
1. Parses .env files with `op://` references
2. Resolves references using `op read`
3. Creates Secure Note with resolved values

**Consequences**:

*Positive*:
- ✅ Easy migration from direct `op://` usage
- ✅ No manual secret copying
- ✅ Validates references during conversion
- ✅ Creates properly structured items

*Negative*:
- ❌ Adds complexity to codebase
- ❌ Another workflow to document
- ❌ Users need to understand two formats

*Rationale*:
- Many 1Password users already use `op://` references directly
- Conversion tool lowers barrier to adoption
- Temporary tool (can be deprecated once adoption complete)

---

## ADR-011: MIT License for Maximum Openness

**Status**: Accepted

**Date**: 2024-12

**Context**:
- Need to choose open-source license
- Want maximum adoption and contribution
- No commercial restrictions desired

**Decision**:
Use MIT License.

**Consequences**:

*Positive*:
- ✅ Simple, permissive license
- ✅ No restrictions on commercial use
- ✅ Easy for companies to adopt
- ✅ Compatible with most other licenses
- ✅ Well-understood by legal teams

*Negative*:
- ❌ No copyleft protection
- ❌ Derivatives don't have to remain open source

*Alternatives considered*:
- GPL: Too restrictive for corporate adoption
- Apache 2.0: More complex, patent protection not needed
- Unlicense/Public Domain: Too permissive, less protection for contributors

---

## Future ADRs (Proposed)

### ADR-012: Automated Test Suite with bats (Proposed)

**Status**: Proposed

**Context**:
- Currently only manual testing
- Need automated tests for CI/CD
- Want fast, reliable test execution

**Proposal**:
Use bats (Bash Automated Testing System) for test suite.

**Next steps**:
- Evaluate bats vs other Bash testing frameworks
- Create test structure
- Write initial test suite

### ADR-013: Homebrew Distribution (Proposed)

**Status**: Proposed

**Context**:
- Current installation: git clone + manual install
- Users expect `brew install` on macOS
- Want easier installation and updates

**Proposal**:
Create Homebrew tap for op-env-manager.

**Next steps**:
- Create formula
- Set up tap repository
- Automate release process

---

## Revision History

| ADR | Date | Change |
|-----|------|--------|
| ADR-001 | 2024-12 | Initial: Bash as implementation language |
| ADR-002 | 2024-12 | Initial: Secure Note fields structure |
| ADR-003 | 2024-12 | Initial: Sections for multi-environment |
| ADR-004 | 2024-12 | Initial: Runtime injection with op run |
| ADR-005 | 2024-12 | Initial: Template file generation |
| ADR-006 | 2024-12 | Initial: Auto-tagging items |
| ADR-007 | 2024-12 | Initial: Modular command architecture |
| ADR-008 | 2024-12 | Initial: Dry-run mode |
| ADR-009 | 2024-12 | Initial: Google Shell Style Guide |
| ADR-010 | 2024-12 | Initial: Convert command for migration |
| ADR-011 | 2024-12 | Initial: MIT License |

---

## Questions or Feedback

Have questions about these decisions? Want to propose a new ADR?

- [Open an issue](https://github.com/matteocervelli/op-env-manager/issues)
- [Start a discussion](https://github.com/matteocervelli/op-env-manager/discussions)
