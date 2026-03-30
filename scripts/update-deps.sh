#!/usr/bin/env bash

# Update project dependencies

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check for required tools
check_requirements() {
    local missing=0
    for cmd in pip pip-compile pip-sync; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}Error: $cmd is not installed${NC}"
            missing=1
        fi
    done
    
    if [ $missing -ne 0 ]; then
        echo -e "\nInstall missing tools with:"
        echo "pip install pip-tools"
        exit 1
    fi
}

# Update requirements files
update_requirements() {
    echo -e "${GREEN}Updating requirements files...${NC}"
    
    # Core requirements
    echo -e "\n${YELLOW}Generating core requirements...${NC}"
    pip-compile --upgrade --output-file=requirements.txt pyproject.toml
    
    # Dev requirements
    echo -e "\n${YELLOW}Generating dev requirements...${NC}"
    pip-compile --extra=dev --upgrade --output-file=requirements-dev.txt pyproject.toml
    
    # ML requirements
    echo -e "\n${YELLOW}Generating ML requirements...${NC}"
    pip-compile --extra=ml --upgrade --output-file=requirements-ml.txt pyproject.toml
    
    # DL requirements
    echo -e "\n${YELLOW}Generating DL requirements...${NC}"
    pip-compile --extra=dl --upgrade --output-file=requirements-dl.txt pyproject.toml
    
    # Data requirements
    echo -e "\n${YELLOW}Generating data requirements...${NC}"
    pip-compile --extra=data --upgrade --output-file=requirements-data.txt pyproject.toml
    
    # Full requirements (all extras)
    echo -e "\n${YELLOW}Generating full requirements...${NC}"
    pip-compile --extra=dev --extra=ml --extra=dl --extra=data --upgrade --output-file=requirements-full.txt pyproject.toml
}

# Check for outdated packages
check_outdated() {
    echo -e "\n${GREEN}Checking for outdated packages...${NC}"
    pip list --outdated
}

# Check for security vulnerabilities
check_security() {
    echo -e "\n${GREEN}Checking for security vulnerabilities...${NC}"
    
    if ! command -v safety &> /dev/null; then
        echo "Installing safety..."
        pip install safety
    fi
    
    if ! command -v pip-audit &> /dev/null; then
        echo "Installing pip-audit..."
        pip install pip-audit
    fi
    
    echo -e "\n${YELLOW}Running safety check...${NC}"
    safety check || true
    
    echo -e "\n${YELLOW}Running pip-audit...${NC}"
    pip-audit || true
}

# Main function
main() {
    check_requirements
    update_requirements
    check_outdated
    check_security
    
    echo -e "\n${GREEN}Done!${NC} Review the changes and commit them to version control."
}

# Run main function
main "$@"
