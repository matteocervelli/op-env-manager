# op-env-manager — User Guide

Bidirectional `.env` sync with 1Password. CLI tool for individuals and teams.

## Guides

| Guide                                          | Description                                   |
| ---------------------------------------------- | --------------------------------------------- |
| [Getting Started](getting-started.md)          | Install, configure, and run your first sync   |
| [1Password Setup](../1PASSWORD_SETUP.md)       | Detailed 1Password CLI configuration          |
| [Quick Reference](../QUICKSTART.md)            | Common commands cheat sheet                   |
| [CI/CD Examples](../CI_CD_EXAMPLES.md)         | GitHub Actions, GitLab CI, Docker integration |
| [Team Collaboration](../TEAM_COLLABORATION.md) | Multi-user vault sharing workflows            |
| [Convert Feature](../CONVERT_FEATURE.md)       | Migrate from legacy `op://` references        |
| [1Password Formats](../1password-formats.md)   | Field formats, sections, multiline values     |
| [Performance](../PERFORMANCE.md)               | Benchmarks and optimization config            |

## Commands

| Command    | Description                                 |
| ---------- | ------------------------------------------- |
| `init`     | Interactive setup wizard (~2 min)           |
| `push`     | Upload `.env` to 1Password                  |
| `inject`   | Download secrets to local `.env`            |
| `run`      | Execute command with secrets (no plaintext) |
| `diff`     | Compare local `.env` vs 1Password           |
| `sync`     | Bidirectional sync with conflict resolution |
| `convert`  | Migrate legacy `op://` references           |
| `template` | Generate `.env.op` for version control      |

## Dev Docs

- [Architecture Decisions](../development/ARCHITECTURE_DECISIONS.md)
- [Testing Guide](../development/TESTING.md)
