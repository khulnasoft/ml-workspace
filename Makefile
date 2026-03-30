# Makefile for local development and CI/CD operations

# Define environment variables
ACT ?= act
DOCKER_IMAGE ?= ml-workspace
BUILD_ARGS ?= "--make"
VERSION ?= "v1.0.0"
GITHUB_TOKEN ?= $(shell echo $GITHUB_TOKEN)
PYTHON ?= python3

# Project paths
BUILD_DIR := build
RESOURCES_DIR := resources
POLICIES_DIR := policies

.PHONY: help build lint test check setup format clean sbom scan audit security-scan

# Default target (help)
help:
	@echo "Available targets:"
	@echo "  setup                - Install local development dependencies"
	@echo "  format               - Format code using ruff"
	@echo "  lint                 - Run linting checks using ruff"
	@echo "  test                 - Run unit tests using pytest"
	@echo "  build                - Build the Docker image"
	@echo "  check                - Run lint, format check, and tests"
	@echo "  sbom                 - Generate Software Bill of Materials (SBOM)"
	@echo "  scan                 - Scan image for vulnerabilities using Trivy"
	@echo "  audit                - Audit image config using OPA/Conftest"
	@echo "  security-scan        - Run all security checks (SBOM, Scan, Audit)"
	@echo "  clean                - Clean up build artifacts"

# Setup environment
setup:
	@echo "Installing build requirements..."
	$(PYTHON) -m pip install -r build_requirements.txt

# Formatting and Linting
format:
	ruff format .
	ruff check --fix .

lint:
	ruff check .
	ruff format --check .

# Testing (runs integration tests using build.py to manage container lifecycle)
test:
	$(PYTHON) build.py --flavor=minimal --test

# Run pytest directly (requires a running workspace on localhost:8080)
test-local:
	pytest $(RESOURCES_DIR)/tests

# Build Docker image
build:
	$(PYTHON) build.py --flavor=minimal --make

# Run all checks
check: lint test

# Security tools
sbom:
	@echo "Generating SBOM..."
	@mkdir -p $(BUILD_DIR)
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v $(PWD)/$(BUILD_DIR):/out \
		anchore/syft:latest $(DOCKER_IMAGE)-minimal:$(VERSION) -o json --file /out/sbom.json

scan:
	@echo "Scanning for vulnerabilities..."
	@docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
		-v $${HOME}/.cache:/root/.cache \
		aquasec/trivy:latest image --severity HIGH,CRITICAL $(DOCKER_IMAGE)-minimal:$(VERSION)

audit:
	@echo "Auditing image configuration..."
	@mkdir -p $(BUILD_DIR)
	@docker inspect $(DOCKER_IMAGE)-minimal:$(VERSION) > $(BUILD_DIR)/inspect.json
	@docker run --rm -v $(PWD):/project -w /project openpolicyagent/conftest test $(BUILD_DIR)/inspect.json -p $(POLICIES_DIR)/

security-scan: sbom scan audit

# Cleaning
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)

# Legacy act support (optional)
act-build:
	$(ACT) -b -s BUILD_ARGS="--make" -j build
