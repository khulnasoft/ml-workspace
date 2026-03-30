#!/bin/bash

# --- Configuration & Setup ---

# Exit immediately if a command exits with a non-zero status.
set -e
# Print commands and their arguments as they are executed.
set -x

# Set default build arguments if not already provided.
# These variables seem to be related to a 'docknet' service.
export DOCKNET_ENDPOINT="http://${_HOST_IP:-localhost}:30010" # Use a default for _HOST_IP if not set
export DOCKNET_ROOT_PATH="/api" # Nginx will handle requests at this root path

# Install Python build requirements.
# Ensure GITHUB_WORKSPACE is correctly set in your CI environment.
echo "Installing Python build requirements..."
pip install -r "${GITHUB_WORKSPACE}/build_requirements.txt"

# --- Build Arguments & Authentication ---

echo "Preparing build arguments and authentication..."

# Initialize BUILD_ARGS.
BUILD_ARGS="${INPUT_BUILD_ARGS}"

# Set default build arguments if INPUT_BUILD_ARGS is empty.
if [[ -z "${BUILD_ARGS}" ]]; then
    BUILD_ARGS="--check --make --test"
fi

# Configure Git for GitHub authentication if a token is provided.
if [[ -n "${GITHUB_TOKEN}" ]]; then
    echo "GitHub Token provided. Configuring Git for authentication."
    # Using 'insteadOf' is a robust way to handle authentication for Git operations.
    git config --global url."https://api:${GITHUB_TOKEN}@github.com/".insteadOf "https://github.com/"
    git config --global url."https://ssh:${GITHUB_TOKEN}@github.com/".insteadOf "ssh://git@github.com/"
    git config --global url."https://git:${GITHUB_TOKEN}@github.com/".insteadOf "git@github.com:"
    BUILD_ARGS+=" --github-token=${GITHUB_TOKEN}"
fi

# Log in to the container registry if credentials are provided.
if [[ -n "${INPUT_CONTAINER_REGISTRY_USERNAME}" && -n "${INPUT_CONTAINER_REGISTRY_PASSWORD}" ]]; then
    echo "Container registry credentials provided. Logging in to registry."
    # Use default for URL if not provided, though it's better for it to be explicitly set.
    docker login "${INPUT_CONTAINER_REGISTRY_URL:-}" -u "${INPUT_CONTAINER_REGISTRY_USERNAME}" -p "${INPUT_CONTAINER_REGISTRY_PASSWORD}"

    # Append registry details to BUILD_ARGS.
    # It's good practice to ensure these are always passed if credentials are present.
    BUILD_ARGS+=" --container-registry-username=${INPUT_CONTAINER_REGISTRY_USERNAME}"
    BUILD_ARGS+=" --container-registry-password=${INPUT_CONTAINER_REGISTRY_PASSWORD}"
    if [[ -n "${INPUT_CONTAINER_REGISTRY_URL}" ]]; then
        BUILD_ARGS+=" --container-registry-url=${INPUT_CONTAINER_REGISTRY_URL}"
    fi
fi

# --- Execution ---

echo "Navigating to working directory and running build.py..."

# Navigate to the specified working directory or default to GITHUB_WORKSPACE.
if [[ -n "${INPUT_WORKING_DIRECTORY}" ]]; then
    cd "${INPUT_WORKING_DIRECTORY}"
else
    cd "${GITHUB_WORKSPACE}"
fi

# Run the build script.
# Disable 'set -e' temporarily to ensure cleanup runs even if build.py fails.
set +e
python -u build.py ${BUILD_ARGS}
EXIT_CODE=$?
set -e # Re-enable 'set -e'

# --- Cleanup ---

echo "Starting cleanup phase..."

# The commented-out 'kind' cluster and docker-compose cleanup suggests these are conditional
# on a '--test' argument. If you re-enable them, make sure the conditions are robust.
# Example of how you might re-enable with clear conditions:
# if [[ "${INPUT_BUILD_ARGS}" == *"--test"* ]]; then
#    echo "Cleaning up test environment (kind cluster, docker-compose)..."
#    # The '|| true' ensures cleanup steps don't fail the entire pipeline
#    kind delete cluster --name "${kind_cluster_name}" || true
#    docker volume rm "${kube_config_volume}" || true
#    if [[ -d "test_deployment" ]]; then
#        (cd test_deployment && docker-compose down) || true
#    fi
# fi

# Exit with the exit code from build.py.
exit ${EXIT_CODE}
