# Contributing to op-env-manager

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Code of Conduct

Be respectful, inclusive, and collaborative. We're all here to build something useful.

## How to Contribute

### Reporting Bugs

1. Check if the issue already exists in [GitHub Issues](https://github.com/matteocervelli/op-env-manager/issues)
2. If not, create a new issue with:
   - Clear title describing the bug
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment (OS, bash version, 1Password CLI version)
   - Error messages or logs

### Suggesting Features

1. Open a [GitHub Issue](https://github.com/matteocervelli/op-env-manager/issues) with:
   - Clear description of the feature
   - Use case and motivation
   - Proposed implementation (if you have ideas)
   - Any alternatives you've considered

### Pull Requests

1. **Fork** the repository
2. **Clone** your fork locally
3. **Create a branch** for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   # or
   git checkout -b fix/your-bug-fix
   ```
4. **Make your changes**:
   - Follow existing code style
   - Add comments for complex logic
   - Update documentation if needed
5. **Test your changes**:
   ```bash
   # Test basic functionality
   ./bin/op-env-manager --version
   ./bin/op-env-manager --help

   # Test with example
   ./bin/op-env-manager push --vault "Test" --env examples/.env.example --dry-run
   ```
6. **Commit your changes**:
   ```bash
   git add .
   git commit -m "feat: add your feature description"
   # or
   git commit -m "fix: fix your bug description"
   ```
7. **Push** to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```
8. **Create a Pull Request** on GitHub

## Development Guidelines

### Code Style

- **Bash**: Follow [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- **Indentation**: 4 spaces (no tabs)
- **Line length**: 100 characters max
- **Functions**: Comment purpose and parameters
- **Error handling**: Use `set -eo pipefail` and proper error messages

### File Organization

- `bin/` - Main executable
- `lib/` - Library functions (push, inject, utilities)
- `docs/` - Documentation
- `examples/` - Example files
- Root - README, LICENSE, installer

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` New feature
- `fix:` Bug fix
- `docs:` Documentation changes
- `style:` Code style (formatting, no logic change)
- `refactor:` Code refactoring
- `test:` Adding or updating tests
- `chore:` Maintenance tasks

**Examples**:
```
feat: add diff command to compare local vs 1Password
fix: handle spaces in vault names correctly
docs: update installation instructions for Linux
```

### Testing Checklist

Before submitting a PR, verify:

- [ ] `./bin/op-env-manager --version` works
- [ ] `./bin/op-env-manager --help` shows correct help
- [ ] `push --dry-run` works without errors
- [ ] `inject --dry-run` works without errors
- [ ] All shell scripts are executable (`chmod +x`)
- [ ] No secrets or credentials in code
- [ ] Documentation updated if needed
- [ ] CHANGELOG.md updated for significant changes

### Adding New Commands

When adding a new command:

1. Create `lib/your-command.sh` with:
   - Usage function
   - Argument parsing
   - Main function
   - Dry-run support
2. Update `bin/op-env-manager` to dispatch the command
3. Add help text and examples
4. Update `README.md` and `docs/QUICKSTART.md`
5. Add entry to `CHANGELOG.md` under `[Unreleased]`

### Security Considerations

- **Never commit secrets** - Add to `.gitignore`
- **Validate user input** - Check vault names, file paths, etc.
- **Use `op` safely** - Avoid command injection
- **File permissions** - Set `.env` files to 600
- **Dry-run first** - Always support `--dry-run`

## Documentation

When updating documentation:

- Keep README.md high-level and friendly
- Add detailed examples to docs/QUICKSTART.md
- Technical details go in docs/1PASSWORD_SETUP.md
- Migration guides go in MIGRATION.md
- Keep CHANGELOG.md up to date

## Release Process

(For maintainers)

1. Update `VERSION` file
2. Update `CHANGELOG.md` with release notes
3. Update version in `bin/op-env-manager`
4. Commit changes:
   ```bash
   git commit -am "chore: bump version to X.Y.Z"
   ```
5. Create tag:
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z"
   ```
6. Push:
   ```bash
   git push origin main --tags
   ```
7. Create GitHub release with notes

## Questions?

- Open a [GitHub Discussion](https://github.com/matteocervelli/op-env-manager/discussions)
- Check existing [Issues](https://github.com/matteocervelli/op-env-manager/issues)
- Read the [Documentation](README.md)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing! 🙏
