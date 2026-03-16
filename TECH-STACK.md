# Tech Stack — op-env-manager

## Runtime

| Component       | Technology           | Notes                                                 |
| --------------- | -------------------- | ----------------------------------------------------- |
| Shell           | Bash 4.0+            | macOS ships Bash 3.x; users must install via Homebrew |
| JSON processing | jq                   | Required external dependency                          |
| Secret storage  | 1Password CLI (`op`) | Required external dependency                          |

## Architecture

```
bin/op-env-manager          # Main dispatcher (command routing, global flags)
lib/
  logger.sh                 # log_header/log_step/log_info/log_success/log_error
  error_helpers.sh          # Actionable error messages, op CLI diagnostics
  retry.sh                  # Exponential backoff wrapper for op item calls
  progress.sh               # ASCII progress bars (auto-detect TTY/CI)
  push.sh                   # parse_env_file → op item create/edit
  inject.sh                 # op item get → write .env (chmod 600)
  diff.sh                   # Local .env ↔ 1Password field comparison
  sync.sh                   # Three-way merge with state tracking (.op-env-manager.state)
  convert.sh                # Migrate op:// reference files to op-env-manager format
  template.sh               # Generate .env.op with op:// references
  init.sh                   # Interactive setup wizard
```

## External Dependencies

| Dependency           | Version | Install                                            | Purpose                                 |
| -------------------- | ------- | -------------------------------------------------- | --------------------------------------- |
| `jq`                 | 1.6+    | `brew install jq`                                  | JSON parsing of 1Password API responses |
| `op` (1Password CLI) | 2.x     | [docs/1PASSWORD_SETUP.md](docs/1PASSWORD_SETUP.md) | Vault API                               |

## Test Stack

| Component              | Technology                                          | Notes                            |
| ---------------------- | --------------------------------------------------- | -------------------------------- |
| Unit/integration tests | [bats-core](https://github.com/bats-core/bats-core) | Bash Automated Testing System    |
| Test helpers           | bats-support, bats-assert                           | `tests/test_helper/`             |
| Security tests         | bats                                                | Secret masking, file permissions |
| Performance tests      | bats                                                | Large file benchmarks            |

```
tests/
  unit/            # Function-level tests
  integration/     # Push/inject/sync workflow tests
  security/        # Secret masking, chmod validation
  performance/     # 500+ variable benchmarks
  test_helper/     # bats-support, bats-assert
  fixtures/        # Sample .env files
```

## CI/CD

| Component      | Status           |
| -------------- | ---------------- |
| GitHub Actions | Planned (v0.4.0) |
| Test matrix    | Ubuntu + macOS   |

## Packaging / Distribution

| Channel                         | Status           |
| ------------------------------- | ---------------- |
| Direct install (`./install.sh`) | ✅ Stable        |
| Homebrew tap                    | Planned (v0.4.0) |
| Shell installer (curl pipe)     | Planned (v0.4.0) |
| Docker image                    | Planned (v0.4.0) |
| GitHub Action                   | Planned (v0.4.0) |

## State & Storage

| Artifact      | Path                    | Purpose                              |
| ------------- | ----------------------- | ------------------------------------ |
| Sync state    | `.op-env-manager.state` | SHA256 checksums for three-way merge |
| Injected .env | configurable            | chmod 600, deleted by trap on errors |
| Temp files    | `mktemp`                | Cleaned via EXIT trap                |

## Compatibility

| Platform                | Support              |
| ----------------------- | -------------------- |
| macOS (arm64/x86_64)    | ✅ Primary           |
| Linux (Ubuntu/Debian)   | ✅ Supported         |
| Windows (WSL2/Git Bash) | ⚠️ Community support |
