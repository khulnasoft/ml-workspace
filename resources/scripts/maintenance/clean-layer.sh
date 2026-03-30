#!/usr/bin/env bash
# clean-layer.sh - Clean up package manager caches and temporary files
# Usage: clean-layer.sh [--all]

set -euo pipefail

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default cleanup options
CLEAN_APT=false
CLEAN_PIP=true
CLEAN_NPM=true
CLEAN_TEMP=true

# Detect platform
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)
            CLEAN_APT=true
            CLEAN_PIP=true
            CLEAN_NPM=true
            CLEAN_TEMP=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--all|--help]"
            echo "  --all    Clean all package caches"
            echo "  --help   Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

echo "Starting layer cleanup on $PLATFORM..."

# Clean package manager caches based on platform
case "$PLATFORM" in
    linux*)
        # Clean APT cache if enabled and available
        if [ "$CLEAN_APT" = true ] && command -v apt-get &> /dev/null; then
            echo "Cleaning APT cache..."
            sudo apt-get clean -y
            sudo rm -rf /var/lib/apt/lists/*
        fi
        
        # Clean YUM/DNF cache if available
        if [ "$CLEAN_APT" = true ] && command -v yum &> /dev/null; then
            echo "Cleaning YUM cache..."
            sudo yum clean all
            sudo rm -rf /var/cache/yum
        fi
        ;;
    darwin*)
        # Clean Homebrew cache if available
        if [ "$CLEAN_APT" = true ] && command -v brew &> /dev/null; then
            echo "Cleaning Homebrew cache..."
            brew cleanup -s
            rm -rf "$(brew --cache)"
        fi
        ;;
esac

# Clean pip cache if enabled
if [ "$CLEAN_PIP" = true ]; then
    echo "Cleaning pip cache..."
    if command -v pip3 &> /dev/null; then
        pip3 cache purge 2>/dev/null || true
    fi
    if command -v pip &> /dev/null; then
        pip cache purge 2>/dev/null || true
    fi
    rm -rf ~/.cache/pip/* 2>/dev/null || true
fi

# Clean npm cache if enabled and available
if [ "$CLEAN_NPM" = true ] && command -v npm &> /dev/null; then
    echo "Cleaning npm cache..."
    npm cache clean --force 2>/dev/null || true
    rm -rf ~/.npm/* 2>/dev/null || true
fi

# Clean temporary files if enabled
if [ "$CLEAN_TEMP" = true ]; then
    echo "Cleaning temporary files..."
    # Use platform-specific temp directories
    case "$PLATFORM" in
        linux*|darwin*)
            find /tmp -mindepth 1 -delete 2>/dev/null || true
            find /var/tmp -mindepth 1 -delete 2>/dev/null || true
            ;;
        msys*|cygwin*|mingw*)
            # Windows (Git Bash, Cygwin, etc.)
            find /tmp -mindepth 1 -delete 2>/dev/null || true
            find /var/tmp -mindepth 1 -delete 2>/dev/null || true
            ;;
    esac
    
    # Clean Python cache files
    find "$SCRIPT_DIR/../../" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$SCRIPT_DIR/../../" -type f -name "*.py[co]" -delete 2>/dev/null || true
fi

echo "Layer cleanup complete."
