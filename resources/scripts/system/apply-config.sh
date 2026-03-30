#!/bin/bash
# apply-config.sh - Apply configuration templates and set up the environment
# Usage: apply-config.sh [--clean]

set -euo pipefail

# Parse command line arguments
CLEAN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--clean] [--help]"
            echo "  --clean  Remove existing configuration before applying new"
            echo "  --help   Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Configuration directories
JUPYTER_DIR="$SCRIPT_DIR/jupyter"
CONFIG_TEMPLATE_DIR="$JUPYTER_DIR/templates"
CONFIG_OUTPUT_DIR="$JUPYTER_DIR"

# Create output directory if it doesn't exist
mkdir -p "$CONFIG_OUTPUT_DIR"

# Clean up old configuration if requested
if [ "$CLEAN" = true ]; then
    echo "Cleaning up old configuration..."
    rm -f "$CONFIG_OUTPUT_DIR/jupyter_notebook_config.py"
    rm -f "$CONFIG_OUTPUT_DIR/jupyter_notebook_config.json"
fi

# Apply Jupyter configuration
echo "Applying Jupyter configuration..."
if [ -f "$CONFIG_TEMPLATE_DIR/jupyter_notebook_config.py.j2" ]; then
        # Create a virtual environment if it doesn't exist
    VENV_DIR="$SCRIPT_DIR/../../.venv"
    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating virtual environment..."
        python3 -m venv "$VENV_DIR"
        source "$VENV_DIR/bin/activate"
        pip install --upgrade pip
        pip install jinja2
    else
        source "$VENV_DIR/bin/activate"
    fi

    # Use Python to render the template with environment variables
    python3 -c '
import os
import sys
from jinja2 import Environment, FileSystemLoader

# Set up Jinja2 environment
env = Environment(
    loader=FileSystemLoader("'$CONFIG_TEMPLATE_DIR'")
)

# Render the template
template = env.get_template("jupyter_notebook_config.py.j2")
rendered = template.render(env=dict(os.environ))

# Write the output
with open(os.path.join("'$CONFIG_OUTPUT_DIR'", "jupyter_notebook_config.py"), "w") as f:
    f.write(rendered)
'
    echo "Jupyter configuration applied to $CONFIG_OUTPUT_DIR/jupyter_notebook_config.py"
else
    echo "Warning: Jupyter configuration template not found at $CONFIG_TEMPLATE_DIR/jupyter_notebook_config.py.j2"
fi

# Set permissions
echo "Setting file permissions..."
chmod 750 "$JUPYTER_DIR"
find "$JUPYTER_DIR" -type d -exec chmod 750 {} \;
find "$JUPYTER_DIR" -type f -name "*.py" -exec chmod 640 {} \;
find "$JUPYTER_DIR" -type f -name "*.json" -exec chmod 640 {} \;

# Run fix-permissions if available
if [ -f "/resources/scripts/maintenance/fix-permissions.sh" ]; then
    echo "Running fix-permissions..."
    /resources/scripts/maintenance/fix-permissions.sh
fi

echo "Configuration applied successfully."
