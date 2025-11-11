# Convert Command: Feature Documentation

## Summary

The `convert` command enables migration from 1Password's native secret reference format (`op://vault/item/field`) to op-env-manager's Secure Note format. This bridges the gap between two common 1Password CLI workflows.

## What We Learned

### 1. Two Distinct 1Password Workflows Exist

**Native op:// Reference Format**:
- Used with `op run` and `op inject` commands
- `.env` files contain `op://vault/item/field` URIs
- Secrets stored in manually-created 1Password items
- References resolved at runtime
- Common in legacy projects and CI/CD pipelines

**op-env-manager Format**:
- Automated Secure Note creation with all variables as fields
- Bidirectional sync (push/inject)
- Single item per environment (optionally with sections)
- Team-friendly organization
- Easier to visualize all variables in 1Password UI

### 2. Why Both Formats Matter

**Teams often have**:
- Legacy projects using `op://` references
- New projects wanting automated management
- Desire to standardize but can't migrate everything at once

**Solution**: The `convert` command allows:
- Incremental migration from `op://` to op-env-manager
- Both formats to coexist
- Teams to evaluate both approaches with real data

### 3. Technical Challenges Addressed

**Challenge 1: Resolving Secret References Without Plaintext Files**
- ❌ Initial idea: `op inject` to temp file, then push
- ✅ Better: Parse line-by-line, use `op read` for each reference
- **Result**: No temporary plaintext files, more secure

**Challenge 2: Embedded References in Strings**
- Example: `DATABASE_URL=postgresql://user:op://vault/item/field@host/db`
- Solution: Regex detection and substitution preserves surrounding text
- **Result**: Complex connection strings work correctly

**Challenge 3: Handling Non-Secret Variables**
- Challenge: Not all variables have `op://` references
- Example: `APP_NAME=MyApp`, `DEBUG=true`
- Solution: Include non-secret variables as-is
- **Result**: Complete environment preserved, not just secrets

### 4. Implementation Patterns

**Modular Command Structure**:
```
lib/convert.sh    # Standalone command module
bin/op-env-manager # Dispatcher loads module
```

**Shared Code Reuse**:
- Uses same push logic from `lib/push.sh` patterns
- Reuses logger utilities
- Follows established argument parsing conventions

**Dry-Run Support**:
- Always implement `--dry-run` first
- Preview operations before executing
- Critical for migration commands (irreversible)

**Error Handling**:
- Gracefully handle missing references
- Continue on single-field failures (with warnings)
- Validate authentication before processing

## Use Cases

### Use Case 1: Legacy Project Migration

**Scenario**: Project uses `.env.template` with `op://` references, team wants op-env-manager benefits

**Before**:
```bash
# .env.template (in git)
API_KEY=op://Production/api-keys/stripe_key
DB_PASS=op://Production/db-creds/postgres_pass

# Team workflow
op inject -i .env.template -o .env
# or
op run --env-file=.env.template -- docker compose up
```

**After**:
```bash
# One-time conversion
op-env-manager convert \
  --env .env.template \
  --vault "Production" \
  --item "myapp"

# New team workflow
op-env-manager run --vault "Production" --item "myapp" -- docker compose up
op-env-manager inject --vault "Production" --item "myapp"

# Old workflow still works (backwards compatible)
op run --env-file=.env.template -- docker compose up
```

### Use Case 2: Multi-Environment Standardization

**Scenario**: Different teams use different formats, want unified approach

**Solution**:
```bash
# Convert dev (uses op://)
op-env-manager convert \
  --env .env.dev.template \
  --vault "MyApp" \
  --item "myapp" \
  --section "dev"

# Convert prod (uses op://)
op-env-manager convert \
  --env .env.prod.template \
  --vault "MyApp" \
  --item "myapp" \
  --section "prod"

# Result: Single Secure Note "myapp" with "dev" and "prod" sections
# Consistent structure across environments
```

### Use Case 3: Evaluating op-env-manager

**Scenario**: Team wants to try op-env-manager without abandoning current workflow

**Approach**:
```bash
# Convert current secrets to evaluate
op-env-manager convert --env .env.template --vault "Test" --item "trial" --dry-run

# Test the new workflow
op-env-manager run --vault "Test" --item "trial" -- docker compose up

# Compare with old workflow
op run --env-file=.env.template -- docker compose up

# Decision: Keep both, migrate some, or stick with op://
```

## Design Decisions

### Decision 1: No Temporary Files

**Options considered**:
1. `op inject` to temp file → `op-env-manager push` (simple)
2. Parse line-by-line with `op read` (secure)

**Chosen**: Option 2
**Rationale**:
- Security: No plaintext secrets on disk
- Atomic: Single operation, no cleanup needed
- Consistency: Matches `run` command philosophy

### Decision 2: Include Non-Secret Variables

**Options considered**:
1. Only convert variables with `op://` references
2. Include all variables from source file

**Chosen**: Option 2
**Rationale**:
- Completeness: Entire environment captured
- Convenience: No need to merge secret/non-secret files
- Transparency: See all config in one place

### Decision 3: Preserve Embedded References

**Options considered**:
1. Only support `VAR=op://...` (full line)
2. Support embedded like `VAR=prefix:op://...:suffix`

**Chosen**: Option 2
**Rationale**:
- Real-world usage: Connection strings often embed secrets
- Flexibility: Works with complex configurations
- Compatibility: Matches `op inject` behavior

## Testing Strategy

### Unit-Level Testing (Manual)

Test individual components:
```bash
# Test op:// detection
has_op_reference "op://vault/item/field"  # Should return true
has_op_reference "plain_text"              # Should return false

# Test reference extraction
extract_op_reference "prefix:op://v/i/f:suffix"  # Should return "op://v/i/f"

# Test resolution (requires real 1Password items)
resolve_op_reference "op://Personal/test/password"
```

### Integration Testing

Full workflow test:
1. Create test items in 1Password
2. Create `.env.template` with references
3. Test dry-run (preview)
4. Run actual conversion
5. Verify Secure Note created correctly
6. Test inject/run with converted item
7. Clean up test data

**See**: [docs/CONVERT_TESTING.md](./CONVERT_TESTING.md)

### Edge Cases to Test

- ✅ Empty `.env` file
- ✅ File with only comments
- ✅ Mixed secret/non-secret variables
- ✅ Embedded references in strings
- ✅ Invalid/missing references
- ✅ References to different vaults
- ✅ Multiline values (should skip or error gracefully)
- ✅ Special characters in values

## Documentation Strategy

### 1. Feature Documentation (This File)
- Technical overview
- Design decisions
- Lessons learned
- For developers/contributors

### 2. Format Comparison Guide
- **File**: `docs/1password-formats.md`
- **Audience**: Users choosing between workflows
- **Content**: Side-by-side comparison, migration paths, use cases

### 3. Testing Guide
- **File**: `docs/CONVERT_TESTING.md`
- **Audience**: Users wanting to test/verify
- **Content**: Step-by-step test procedure, expected outputs

### 4. User Documentation
- **File**: `README.md`
- **Audience**: All users
- **Content**: Quick start, examples, common workflows

## Future Enhancements

### Enhancement 1: Bidirectional Conversion

**Current**: `op://` → op-env-manager only

**Future**: op-env-manager → `op://` generation
```bash
op-env-manager export \
  --vault "Personal" \
  --item "myapp" \
  --format "op-references" \
  --output .env.template
```

**Use case**: Generate `.env.template` for CI/CD from Secure Note

### Enhancement 2: Bulk Conversion

**Current**: One file at a time

**Future**: Convert multiple files/environments
```bash
op-env-manager convert \
  --vault "MyApp" \
  --item "myapp" \
  --bulk \
  --dev .env.dev.template \
  --staging .env.staging.template \
  --prod .env.prod.template
```

**Use case**: Migrate entire project at once

### Enhancement 3: Conflict Detection

**Current**: Overwrites existing items

**Future**: Detect conflicts, offer merge/skip
```bash
op-env-manager convert \
  --env .env.template \
  --vault "Personal" \
  --item "myapp" \
  --on-conflict merge  # or skip, overwrite, prompt
```

**Use case**: Safer incremental migrations

### Enhancement 4: Validation

**Future**: Validate references before conversion
```bash
op-env-manager convert \
  --env .env.template \
  --vault "Personal" \
  --validate-only
```

**Output**: List of valid/invalid references
**Use case**: Pre-flight check before migration

## Metrics & Success Criteria

### Adoption Metrics
- Number of `convert` command uses
- Projects migrated from `op://` to op-env-manager
- User feedback on GitHub issues/discussions

### Success Criteria
- ✅ Command executes without errors for valid inputs
- ✅ All `op://` references resolved correctly
- ✅ Non-secret variables preserved
- ✅ Embedded references handled properly
- ✅ Dry-run mode accurate preview
- ✅ No temporary plaintext files created
- ✅ Documentation clear for users
- ✅ Zero security regressions

## Security Considerations

### Threat: Plaintext Secrets on Disk

**Mitigation**: Parse line-by-line, use `op read` directly, no temp files

### Threat: Logging Sensitive Values

**Mitigation**:
- Never log resolved secret values
- Mask in dry-run output: `[RESOLVED:op://...]`
- Use truncation for display: `${value:0:20}...`

### Threat: Invalid Reference Resolution

**Mitigation**:
- Validate reference format with regex
- Handle `op read` failures gracefully
- Skip invalid references with warnings
- Continue processing (don't fail entire conversion)

### Threat: Cross-Vault Reference Confusion

**Mitigation**:
- Document that references can point to different vaults
- Warn user if references span multiple vaults
- Consider `--strict` mode requiring single vault

## Key Takeaways

1. **Two workflows coexist**: `op://` references and op-env-manager format serve different needs
2. **Migration shouldn't be forced**: Convert command enables evaluation and incremental adoption
3. **Security first**: No temporary plaintext files, even during conversion
4. **Preserve everything**: Include non-secret variables for complete environment capture
5. **User experience matters**: Dry-run mode builds confidence for irreversible operations
6. **Documentation is critical**: Format comparison guide helps users make informed decisions

## References

- Implementation: `lib/convert.sh`
- Format guide: `docs/1password-formats.md`
- Testing guide: `docs/CONVERT_TESTING.md`
- User docs: `README.md` (convert section)
- 1Password docs: https://developer.1password.com/docs/cli/secret-references

## Questions & Answers

**Q: Why not just use `op inject` to a temp file then push?**
A: Security. Creating temporary plaintext files increases attack surface. Direct `op read` keeps secrets in memory.

**Q: What if my `.env` has both `op://` and plaintext secrets?**
A: Both are supported. `op://` references are resolved, plaintext values are included as-is.

**Q: Can I convert back from op-env-manager to `op://` format?**
A: Not yet. This is a planned enhancement. You can manually create references or use `inject` + manual editing.

**Q: Does this work with 1Password Service Accounts in CI/CD?**
A: Yes! Service accounts support both `op read` and op-env-manager commands.

**Q: What happens if a reference is invalid?**
A: The variable is skipped with a warning, conversion continues for other variables.

---

**Document version**: 1.0
**Last updated**: 2025-11-11
**Author**: Matteo Cervelli
