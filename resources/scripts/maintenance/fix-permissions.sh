#!/bin/bash
# fix-permissions.sh - Set secure file permissions for the ML Workspace
# Usage: fix-permissions.sh [--strict]

set -euo pipefail

# Default mode (0=loose, 1=strict)
MODE=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --strict)
            MODE=1
            shift
            ;;
        --help)
            echo "Usage: $0 [--strict|--help]"
            echo "  --strict  Apply strict permissions (more restrictive)"
            echo "  --help    Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

echo "Setting file permissions..."

# Common directories
SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
CONFIG_DIR="$SCRIPTS_DIR/../../config"

# Set directory permissions
echo "Setting directory permissions..."
find "$SCRIPTS_DIR" -type d -exec chmod 750 {} \;
find "$CONFIG_DIR" -type d -exec chmod 750 {} \;

# Set file permissions
echo "Setting file permissions..."
find "$SCRIPTS_DIR" -type f -name "*.sh" -exec chmod 750 {} \;
find "$CONFIG_DIR" -type f -exec chmod 640 {} \;

# Special permissions for sensitive files
chmod 600 "$CONFIG_DIR"/*.key 2>/dev/null || true
chmod 644 "$CONFIG_DIR"/*.crt 2>/dev/null || true

# If strict mode, apply additional restrictions
if [ "$MODE" -eq 1 ]; then
    echo "Applying strict permissions..."
    # Remove world-writable permissions
    find / -xdev -type d -perm -0002 ! -path "/proc/*" -exec chmod o-w {} +
    find / -xdev -type f -perm -0002 ! -path "/proc/*" -exec chmod o-w {} +
    
    # Set secure umask
    umask 0027
fi

# Fix ownership if running as root
if [ "$(id -u)" -eq 0 ]; then
    echo "Fixing ownership..."
    chown -R root:root "$SCRIPTS_DIR"
    chown -R root:root "$CONFIG_DIR"
fi

echo "Permission fixes complete."
