# ML Space Libraries

This directory contains dependency specifications for the ML Space project.

## Dependency Management

We use a modern Python packaging approach with `pyproject.toml` as the central configuration file.

### Key Files

- `pyproject.toml`: Main dependency specification with optional extras
- `.python-version`: Specifies the Python version (managed by pyenv)
- `.tool-versions`: Specifies tool versions (managed by asdf)

### Dependency Groups

The project uses optional dependency groups that can be installed as needed:

```bash
# Install core dependencies (required)
pip install -e .

# Install development dependencies
pip install -e ".[dev]"

# Install ML-specific dependencies
pip install -e ".[ml]"

# Install deep learning dependencies
pip install -e ".[dl]"

# Install data processing dependencies
pip install -e ".[data]"

# Install all dependencies
pip install -e ".[dev,ml,dl,data]"
```

### Versioning Policy

- **Patch versions** (`1.2.x`): Allow compatible updates (bug fixes)
- **Minor versions** (`1.x.0`): Allow compatible updates (new features)
- **Major versions** (`x.0.0`): Require manual review

### Updating Dependencies

1. Update versions in `pyproject.toml`
2. Run `pip-compile` to update lock files
3. Test the changes
4. Submit a pull request with version updates

### Security Scanning

Regularly scan for vulnerabilities:

```bash
# Install security tools
pip install safety pip-audit

# Check for known vulnerabilities
safety check
pip-audit
```

### Legacy Requirements Files

For backward compatibility, we maintain these files:

- `requirements-minimal.txt`: Minimal working environment
- `requirements-light.txt`: Additional ML libraries
- `requirements-full.txt`: Complete environment with all optional dependencies

These are generated from `pyproject.toml` using:

```bash
pip-compile --output-file=requirements.txt
pip-compile --extra=dev --output-file=requirements-dev.txt
```

## Best Practices

1. **Pin Dependencies**: Always specify version constraints
2. **Use Extras**: Group related dependencies as extras
3. **Regular Updates**: Update dependencies regularly
4. **Security Scans**: Run security scans in CI/CD
5. **Document Changes**: Keep changelog updated with dependency changes
