# op-env-manager Roadmap

This document outlines the planned features, improvements, and long-term vision for op-env-manager.

**Current Version**: 0.3.0
**Last Updated**: 2025-01-14

---

## Overview

op-env-manager aims to be the simplest, most secure way to manage environment variables for development teams using 1Password. Our roadmap focuses on three key areas:

1. **Stability** - Automated testing and reliability
2. **Features** - Core commands for common workflows
3. **Distribution** - Easy installation and integration

---

## Phase 1: Stability & Testing (Priority: HIGH)

**Timeline**: 1-2 weeks
**Status**: 🟡 Planned

### Goals
- Establish automated test suite
- Improve reliability and error handling
- Performance optimization

### Tasks

#### 1.1 Automated Testing
- [ ] Install and configure bats (Bash Automated Testing System)
- [ ] Create test suite structure (`tests/` directory)
- [ ] Write unit tests:
  - [ ] .env parsing with various formats (quotes, comments, spaces)
  - [ ] op:// reference extraction (embedded in URLs, etc.)
  - [ ] Template generation logic
  - [ ] Error handling paths
- [ ] Write integration tests:
  - [ ] Push/inject cycle with test vault
  - [ ] Convert command end-to-end
  - [ ] Multi-environment scenarios
  - [ ] Section handling
- [ ] Set up GitHub Actions CI/CD pipeline:
  - [ ] Run tests on push
  - [ ] Test on multiple platforms (Ubuntu, macOS)
  - [ ] Coverage reporting

#### 1.2 Bug Fixes and Edge Cases
- [ ] Multiline .env value support
- [ ] Better error messages with actionable next steps
- [ ] Retry logic for network errors (1Password API timeouts)
- [ ] Handle special characters in variable names/values

#### 1.3 Performance Improvements
- [ ] Optimize batch field operations in push command
- [ ] Add progress indicators for large files (100+ variables)
- [ ] Benchmark and document performance characteristics

**Success Criteria**:
- ✅ 80%+ test coverage
- ✅ All tests passing in CI/CD
- ✅ Performance benchmarks documented

---

## Phase 2: Enhanced Documentation (Priority: HIGH)

**Timeline**: 1 week (concurrent with Phase 1)
**Status**: ✅ Complete

### Completed

#### 2.1 Core Documentation
- ✅ Enhanced CLAUDE.md with Testing, Debugging, Performance sections
- ✅ Updated README.md with architecture diagram and comparison table
- ✅ Added support/coffee link integration

#### 2.2 Advanced Guides
- ✅ CI/CD Examples (GitHub Actions, GitLab CI, Jenkins)
- ✅ Team Collaboration best practices
- ✅ Architecture Decision Records (ADRs)

#### 2.3 Content Marketing (Local)
- ✅ Blog post outlines (5 articles)
- ✅ Video scripts (4 videos)
- ✅ Social media content calendar

**Next Steps**:
- [ ] Create video tutorials
- [ ] Publish blog posts
- [ ] Launch social media presence

---

## Phase 3: Core Commands (Priority: MEDIUM)

**Timeline**: 2-3 weeks
**Status**: 🟢 In Progress (1/3 commands complete)

### 3.1 `init` Command - Interactive Setup Wizard

**Status**: ✅ Complete (v0.3.0)

**Functionality**:
```bash
op-env-manager init
```

**Interactive prompts**:
- Vault selection or creation
- Item naming
- Environment configuration (dev/staging/prod)
- Initial .env push
- Template generation
- Git configuration

**Benefits**:
- Zero to working in 2 minutes
- Guided onboarding for new users
- Best practices by default

**Implementation**:
- ✅ Design interactive prompt flow
- ✅ Implement vault creation/selection
- ✅ Add multi-environment setup (separate items vs. sections)
- ✅ Integration with push and template commands
- ✅ Write tests (70+ unit tests, 30+ integration tests)
- ✅ Update documentation

**Features Delivered**:
- ✅ Auto-detection of .env files in current directory
- ✅ Vault creation support (with permissions check)
- ✅ Smart item naming with sensible defaults
- ✅ Multi-environment strategies (items vs. sections)
- ✅ Dry-run mode support
- ✅ Success summary with actionable next steps
- ✅ Completes in <2 minutes for most setups

### 3.2 `diff` Command - Compare Local vs 1Password

**Status**: 🟡 Planned (v0.4.0)

**Functionality**:
```bash
# Compare local .env with 1Password
op-env-manager diff --vault "Personal" --env .env

# Output:
# + NEW_VAR=value (only in 1Password)
# - OLD_VAR=value (only in local)
# ± CHANGED=old_value → new_value (different values)
```

**Use Cases**:
- Detect secret drift
- Verify synchronization
- Preview inject/push operations

**Implementation**:
- [ ] Fetch fields from 1Password
- [ ] Parse local .env file
- [ ] Compare and categorize differences
- [ ] Colorized diff output
- [ ] Support for sections
- [ ] Exit codes (0 = same, 1 = different)
- [ ] Write tests
- [ ] Update documentation

### 3.3 `sync` Command - Bidirectional Synchronization

**Status**: 🟡 Planned (v0.4.0)

**Functionality**:
```bash
# Interactive sync with conflict resolution
op-env-manager sync --vault "Personal" --env .env

# Conflict resolution strategies:
# - Interactive (default): Prompt for each conflict
# - ours: Use local values
# - theirs: Use 1Password values
# - newest: Use most recently modified
```

**Use Cases**:
- Team collaboration
- Multi-machine development
- Keeping environments in sync

**Implementation**:
- [ ] Implement diff logic (reuse from 3.2)
- [ ] Design conflict resolution strategies
- [ ] Interactive prompt for conflicts
- [ ] Merge logic with three-way merge
- [ ] Backup before sync
- [ ] State file management
- [ ] Write tests
- [ ] Update documentation

### 3.4 `rotate` Command - Secret Rotation

**Functionality**:
```bash
# Rotate specific secret
op-env-manager rotate --vault "Personal" --key "API_KEY"

# Generate new value, update 1Password, optionally deploy
```

**Use Cases**:
- Quarterly secret rotation
- Compromised secret response
- Compliance requirements

**Implementation**:
- [ ] Secret generation (configurable complexity)
- [ ] Update in 1Password
- [ ] Optional deployment hook
- [ ] Rotation history/audit log
- [ ] Write tests
- [ ] Update documentation

**Note**: Lower priority, depends on team feedback

---

## Phase 4: Distribution & Integration (Priority: MEDIUM)

**Timeline**: 2-3 weeks
**Status**: 🟡 Planned

### 4.1 Homebrew Tap

**Goal**: `brew install matteocervelli/tap/op-env-manager`

**Tasks**:
- [ ] Create Homebrew formula
- [ ] Set up tap repository (`homebrew-tap`)
- [ ] Automate release process (GitHub Actions)
- [ ] Test installation on clean macOS
- [ ] Document installation in README

**Benefits**:
- Native macOS installation
- Automatic updates via brew
- Familiar developer workflow

### 4.2 Shell Installer (curl | bash)

**Goal**: `curl -sSL https://op-env-manager.sh | bash`

**Tasks**:
- [ ] Create installation script
- [ ] Host on GitHub Pages or CDN
- [ ] Support Linux and macOS
- [ ] Version selection support
- [ ] Update documentation

**Benefits**:
- One-line installation
- Works on any Unix-like system
- CI/CD friendly

### 4.3 Docker Image

**Goal**: `docker run --rm -it op-env-manager [command]`

**Use Cases**:
- CI/CD pipelines without 1Password CLI installation
- Isolated execution
- Version pinning

**Tasks**:
- [ ] Create Dockerfile (multi-stage build)
- [ ] Push to Docker Hub / GitHub Container Registry
- [ ] Automate builds on release
- [ ] Document Docker usage
- [ ] Add examples for CI/CD

### 4.4 GitHub Action

**Goal**: Native GitHub Actions integration

```yaml
- uses: matteocervelli/op-env-manager-action@v1
  with:
    vault: Production
    item: myapp
    command: npm run deploy
```

**Tasks**:
- [ ] Create GitHub Action wrapper
- [ ] Publish to GitHub Marketplace
- [ ] Add comprehensive examples
- [ ] Document in CI/CD guide

---

## Phase 5: Advanced Features (Priority: LOW)

**Timeline**: 2-4 weeks
**Status**: 🔵 Future

### 5.1 `.env.schema` Validation

**Functionality**:
```bash
# Define required variables and types
cat .env.schema
# REQUIRED: API_KEY (string, pattern: ^sk_[a-z0-9]+$)
# REQUIRED: PORT (integer, min: 1024, max: 65535)
# OPTIONAL: DEBUG (boolean, default: false)

# Validate before push
op-env-manager push --validate
```

**Benefits**:
- Catch missing variables early
- Type checking
- Documentation in code

### 5.2 Multi-Vault Injection

**Functionality**:
```bash
# Merge secrets from multiple vaults
op-env-manager inject \
  --vault "Shared:database" \
  --vault "MyApp:secrets" \
  --output .env.local
```

**Use Cases**:
- Shared credentials (database, cache)
- Project-specific secrets
- Microservices architecture

### 5.3 Secret Expiration Tracking

**Functionality**:
- Set expiration dates on secrets
- Warning notifications before expiration
- Automated rotation reminders

**Integration**:
- Use 1Password item metadata
- CLI warnings
- Optional webhook notifications

### 5.4 Audit Logging

**Functionality**:
- Local audit log of all operations
- Who accessed what, when
- Export to SIEM/logging systems

**Use Cases**:
- Compliance (SOC2, ISO 27001)
- Security monitoring
- Incident investigation

### 5.5 VSCode Extension

**Goal**: Native IDE integration

**Features**:
- Inject secrets from command palette
- View available vaults/items
- Push changes on save
- Inline secret preview (masked)

### 5.6 GUI/TUI Wrapper

**Goal**: User-friendly interface for non-CLI users

**Options**:
- Terminal UI (using `gum` or similar)
- Electron-based GUI
- Web dashboard (local server)

---

## Version Milestones

### v0.2.0 - Stability Release
**Target**: Q1 2025

- ✅ Automated test suite (80%+ coverage)
- ✅ CI/CD pipeline
- ✅ Performance optimizations
- ✅ Bug fixes and edge cases

### v0.3.0 - Core Commands Release
**Target**: Q2 2025

- ✅ `init` command (interactive setup)
- ✅ `diff` command (compare local vs 1Password)
- ✅ Improved documentation

### v0.4.0 - Distribution Release
**Target**: Q2 2025

- ✅ Homebrew tap
- ✅ Shell installer (curl | bash)
- ✅ Docker image
- ✅ GitHub Action

### v0.5.0 - Advanced Commands Release
**Target**: Q3 2025

- ✅ `sync` command (bidirectional sync)
- ✅ `rotate` command (secret rotation)

### v1.0.0 - Stable Release
**Target**: Q4 2025

- ✅ All core features complete
- ✅ Comprehensive test coverage
- ✅ Production-ready for enterprise
- ✅ `.env.schema` validation
- ✅ Multi-vault support

---

## Community & Ecosystem

### Short-term
- [ ] Set up GitHub Discussions
- [ ] Create contribution guidelines
- [ ] Add issue templates (already done ✅)
- [ ] Establish code of conduct
- [ ] Weekly office hours (if community grows)

### Long-term
- [ ] Plugin system for custom commands
- [ ] Third-party integrations (Terraform, Ansible, etc.)
- [ ] Conference talks and workshops
- [ ] Community-contributed examples
- [ ] Translation to other languages (when needed)

---

## Non-Goals

Things we explicitly **won't** do:

❌ **Compete with 1Password** - We complement 1Password, not replace it
❌ **Support non-1Password backends** - Stay focused on one integration done well
❌ **Implement secret storage** - Let 1Password handle encryption and storage
❌ **Windows native support** - WSL/Git Bash is sufficient, native Windows adds complexity
❌ **GUI-first approach** - CLI-first philosophy, GUI is optional enhancement

---

## How to Contribute

Want to help? Here's how:

### 1. Use it and provide feedback
- Open issues for bugs
- Request features via Discussions
- Share your use cases

### 2. Contribute code
- Pick an issue labeled `good first issue`
- Implement roadmap items
- Improve documentation

### 3. Spread the word
- Star the repository
- Write blog posts about your experience
- Share on social media

### 4. Financial support
Support development: [☕ Buy me a coffee](https://adli.men/coffee)

---

## Questions or Suggestions?

- **Discuss**: [GitHub Discussions](https://github.com/matteocervelli/op-env-manager/discussions)
- **Issues**: [GitHub Issues](https://github.com/matteocervelli/op-env-manager/issues)
- **Contact**: [@matteocervelli](https://github.com/matteocervelli)

---

**Note**: This roadmap is aspirational and subject to change based on community feedback, adoption, and available development time. Priorities may shift as we learn from real-world usage.

*Last updated: 2024-12*
