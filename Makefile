# Makefile for local development with Act, Docker, and setup for dependencies

# Define environment variables
ACT ?= act
DOCKER_COMPOSE ?= docker-compose
DOCKER_IMAGE ?= ml-buildkit-image
BUILD_ARGS ?= "--make"
VERSION ?= "v1.0.0"
GITHUB_TOKEN ?= $(shell echo $${GITHUB_TOKEN})
DEPENDENCY_INSTALL ?= true
PYTHON ?= python3
PIP ?= pip3
WORKDIR ?= $(shell pwd)

# Colors
GREEN  := $(shell tput -Txterm setaf 2)
YELLOW := $(shell tput -Txterm setaf 3)
WHITE  := $(shell tput -Txterm setaf 7)
RESET  := $(shell tput -Txterm sgr0)

# Add empty line before help
define NEWLINE


endef

# Default target (help)
.PHONY: help
help:
	@echo '${NEWLINE}${YELLOW}Makefile for ML Workspace Development${RESET}'
	@echo '${GREEN}Available targets:${RESET}'
	@echo ''
	@echo '${YELLOW}Setup:${RESET}'
	@echo '  ${WHITE}setup${RESET}              - Setup development environment'
	@echo '  ${WHITE}install-deps${RESET}       - Install Python and system dependencies'
	@echo '  ${WHITE}env-file${RESET}           - Create .env file if not exists'
	@echo ''
	@echo '${YELLOW}Build:${RESET}'
	@echo '  ${WHITE}build${RESET}              - Build all components'
	@echo '  ${WHITE}build-subcomponent${RESET} - Build a specific subcomponent (e.g., docs)'
	@echo ''
	@echo '${YELLOW}Test & Lint:${RESET}'
	@echo '  ${WHITE}test${RESET}               - Run unit and integration tests'
	@echo '  ${WHITE}lint${RESET}               - Run linting and code style checks'
	@echo '  ${WHITE}check${RESET}              - Run linting, style checks, and tests'
	@echo ''
	@echo '${YELLOW}Release:${RESET}'
	@echo '  ${WHITE}release${RESET}            - Trigger release pipeline'
	@echo '  ${WHITE}release-local${RESET}      - Trigger release process locally'
	@echo '  ${WHITE}bump-version${RESET}       - Bump version (use VERSION=x.y.z)'
	@echo ''
	@echo '${YELLOW}Docker:${RESET}'
	@echo '  ${WHITE}docker-build${RESET}       - Build Docker image'
	@echo '  ${WHITE}docker-push${RESET}        - Push Docker image to registry'
	@echo '  ${WHITE}docker-clean${RESET}       - Remove Docker containers and images'
	@echo ''
	@echo '${YELLOW}Cleanup:${RESET}'
	@echo '  ${WHITE}clean${RESET}              - Clean build artifacts'
	@echo '  ${WHITE}clean-all${RESET}          - Clean everything (including Docker)'

# Check for required commands
.PHONY: check-requirements
check-requirements:
	@command -v docker >/dev/null 2>&1 || { echo >&2 "Docker is required but not installed. Aborting."; exit 1; }
	@command -v $(ACT) >/dev/null 2>&1 || { echo >&2 "Act is required but not installed. Install with: brew install act"; exit 1; }

# Setup environment
.PHONY: setup
setup: check-requirements env-file
	@echo "${YELLOW}Setting up the environment...${RESET}"
	@docker build -t $(DOCKER_IMAGE) .
	@if [ "$(DEPENDENCY_INSTALL)" = "true" ]; then \
		$(MAKE) install-deps; \
	fi

# Create .env file if not exists
.PHONY: env-file
env-file:
	@if [ ! -f .env ]; then \
		echo "${YELLOW}Creating .env file...${RESET}"; \
		cp .env.example .env; \
		echo "${GREEN}Created .env file from example${RESET}"; \
	fi

# Install dependencies
.PHONY: install-deps
install-deps:
	@echo "${YELLOW}Installing dependencies...${RESET}"
	@$(PIP) install -r requirements-dev.txt
	@docker run --rm -v $(WORKDIR):/workspace $(DOCKER_IMAGE) make install

# Build all components
.PHONY: build
build: setup
	$(ACT) -b -s BUILD_ARGS="--make" -j build

# Build a specific sub-component
.PHONY: build-subcomponent
build-subcomponent: setup
	$(ACT) -b -s BUILD_ARGS="--make" -s WORKING_DIRECTORY="./docs" -j build

# Run tests
.PHONY: test
test: setup
	$(ACT) -b -s BUILD_ARGS="--test" -j build

# Run specific test type (unit, integration, etc.)
.PHONY: test-%
test-%: setup
	$(ACT) -b -s BUILD_ARGS="--test $*" -j build

# Run linting
.PHONY: lint
lint: setup
	$(ACT) -b -s BUILD_ARGS="--check" -j build

# Run checks (lint + test)
.PHONY: check
check: lint test

# Release targets
.PHONY: release
release: check
	$(ACT) -b -s VERSION="$(VERSION)" -s GITHUB_TOKEN="$(GITHUB_TOKEN)" -j release

.PHONY: release-local
release-local: check
	$(ACT) -b -s VERSION="$(VERSION)" -s GITHUB_TOKEN="$(GITHUB_TOKEN)" -j release

# Bump version
.PHONY: bump-version
bump-version:
	@if [ -z "$(VERSION)" ]; then \
		echo "Error: VERSION is not set. Usage: make bump-version VERSION=x.y.z"; \
		exit 1; \
	fi
	@echo "Bumping version to $(VERSION)"
	@echo "$(VERSION)" > VERSION
	@git add VERSION
	@git commit -m "Bump version to $(VERSION)"
	@git tag -a v$(VERSION) -m "Version $(VERSION)"
	@echo "Version bumped to $(VERSION), committed and tagged"

# Docker operations
.PHONY: docker-build
docker-build:
	docker build -t $(DOCKER_IMAGE) .

.PHONY: docker-push
docker-push: docker-build
	docker push $(DOCKER_IMAGE)

.PHONY: docker-clean
docker-clean:
	docker system prune -f
	docker volume prune -f

# Cleanup
.PHONY: clean
clean:
	@echo "${YELLOW}Cleaning build artifacts...${RESET}"
	@rm -rf build/ dist/ *.egg-info/ .pytest_cache/ .mypy_cache/ .coverage htmlcov/
	@find . -type d -name '__pycache__' -exec rm -rf {} +
	@find . -type f -name '*.py[co]' -delete

.PHONY: clean-all
clean-all: clean docker-clean
	@echo "${YELLOW}Removing Docker images...${RESET}"
	@docker rmi -f $(docker images -q $(DOCKER_IMAGE) 2>/dev/null) 2>/dev/null || true

# Include custom Makefile if exists
-include Makefile.local

# Print help by default
.DEFAULT_GOAL := help