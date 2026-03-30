#!/bin/bash

# Stops script execution if a command has an error
set -e
# Print command
set -x

# set default build args if not provided
export DOCKNET_ENDPOINT=http://"$_HOST_IP":30010
export DOCKNET_ROOT_PATH="/api"

# Install build requirements if present
if [ -f "$GITHUB_WORKSPACE/build_requirements.txt" ]; then
    pip install -r "$GITHUB_WORKSPACE/build_requirements.txt"
fi

# Disable immediate stop so that the cleanup phase can run even if entrypoint-sh fails
set +e

echo "Run build.py"
BUILD_ARGS="$INPUT_BUILD_ARGS"
if [ -z "$BUILD_ARGS" ]; then
    BUILD_ARGS="--check --make --test"
fi

if [ -n "$GITHUB_TOKEN" ]; then
    echo "GitHub Token provided. Setting up GitHub URLs..."
    git config --global url."https://api:$GITHUB_TOKEN@github.com/".insteadOf "https://github.com/"
    git config --global url."https://ssh:$GITHUB_TOKEN@github.com/".insteadOf "ssh://git@github.com/"
    git config --global url."https://git:$GITHUB_TOKEN@github.com/".insteadOf "git@github.com:"

    BUILD_ARGS="$BUILD_ARGS --github-token=$GITHUB_TOKEN"
fi

if [ -n "$INPUT_CONTAINER_REGISTRY_USERNAME" ] && [ -n "$INPUT_CONTAINER_REGISTRY_PASSWORD" ]; then
    echo "Container registry credentials provided. Logging in to registry..."
    echo "$INPUT_CONTAINER_REGISTRY_PASSWORD" | docker login "$INPUT_CONTAINER_REGISTRY_URL" -u "$INPUT_CONTAINER_REGISTRY_USERNAME" --password-stdin

    if [ -n "$INPUT_CONTAINER_REGISTRY_URL" ]; then
        BUILD_ARGS="$BUILD_ARGS --container-registry-url=$INPUT_CONTAINER_REGISTRY_URL"
    fi

    export CONTAINER_REGISTRY_USERNAME="$INPUT_CONTAINER_REGISTRY_USERNAME"
    export CONTAINER_REGISTRY_PASSWORD="$INPUT_CONTAINER_REGISTRY_PASSWORD"
fi

# Navigate to working directory, if provided
if [ -n "$INPUT_WORKING_DIRECTORY" ]; then
    cd "$INPUT_WORKING_DIRECTORY"
else
    cd "$GITHUB_WORKSPACE"
fi

# Execute the build script
python -u build.py $BUILD_ARGS
exit_code=$?

echo "Build process completed with exit code: $exit_code"
exit $exit_code
