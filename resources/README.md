# ML Workspace Resources

This directory contains all resource files required for the ML Workspace, including configuration files, scripts, and assets.

## Directory Structure

```
resources/
├── branding/            # Branding assets (logos, icons, etc.)
├── config/              # System-wide configuration files
├── home/                # User home directory templates
├── icons/               # Application icons
├── jupyter/             # Jupyter configuration and extensions
│   ├── config.d/        # Split configuration files
│   ├── extensions/      # Jupyter extensions
│   └── templates/       # Configuration templates
├── libraries/           # Custom libraries
├── licenses/            # License files
├── netdata/             # Netdata configuration
├── nginx/               # Nginx configuration and Lua extensions
├── novnc/               # NoVNC configuration
├── scripts/             # Utility scripts
│   ├── jupyter/        # Jupyter-specific scripts
│   ├── maintenance/    # System maintenance scripts
│   └── system/         # System setup scripts
├── ssh/                 # SSH configuration
├── supervisor/          # Supervisor process configuration
├── tests/               # Test files and fixtures
├── tools/               # Development tools
└── tutorials/           # Tutorial materials
```

## Configuration

### Jupyter Configuration

Jupyter configuration is split into multiple files in `jupyter/config.d/` for better organization:

- `00-base.py`: Base configuration
- `10-security.py`: Security-related settings
- `20-extensions.py`: Extension configuration (if any)

### Environment Variables

Key environment variables for configuration:

| Variable | Default | Description |
|----------|---------|-------------|
| `JUPYTER_PORT` | 8090 | Port for Jupyter to listen on |
| `JUPYTER_ALLOW_ROOT` | true | Allow running as root |
| `JUPYTER_TOKEN` | (random) | Authentication token |
| `JUPYTER_PASSWORD` | (none) | Password for authentication (hashed) |
| `JUPYTER_SSL_ENABLED` | false | Enable SSL/TLS |
| `JUPYTER_SSL_CERT` | /etc/ssl/jupyter.crt | SSL certificate file |
| `JUPYTER_SSL_KEY` | /etc/ssl/jupyter.key | SSL private key file |

## Scripts

### Maintenance Scripts

- `clean-layer.sh`: Clean up package caches and temporary files
  ```bash
  # Basic cleanup
  ./scripts/maintenance/clean-layer.sh
  
  # Full cleanup (more aggressive)
  ./scripts/maintenance/clean-layer.sh --all
  ```

- `fix-permissions.sh`: Set secure file permissions
  ```bash
  # Basic permission fix
  ./scripts/maintenance/fix-permissions.sh
  
  # Strict mode (more restrictive)
  ./scripts/maintenance/fix-permissions.sh --strict
  ```

## Security

- All configuration files have secure default permissions
- Sensitive files (keys, passwords) are not included in version control
- Security headers are set by default
- Rate limiting is enabled to prevent abuse

## Contributing

1. Add new configuration files to the appropriate directory
2. Follow the naming convention for configuration files (`##-purpose.py`)
3. Document new environment variables in this README
4. Test your changes in a development environment

## License

This project is licensed under the terms of the MIT license. See the LICENSE file for more details.
