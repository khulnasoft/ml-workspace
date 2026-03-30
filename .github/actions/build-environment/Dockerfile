# syntax=docker/dockerfile:1.4

# =============================================================================
# MULTI-STAGE BUILD: Improved Build Environment
# =============================================================================

# Stage 1: Base system setup with security-focused base image
FROM khulnasoft/build-environment:0.6.18 AS base-system

# Install security updates and essential packages
RUN set -eux; \
    apt-get update; \
    apt-get upgrade -y; \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        gnupg \
        lsb-release \
        software-properties-common; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Stage 2: Java runtime installation
FROM base-system AS java-runtime

# Install Java 21 LTS (latest LTS as of July 2025)
ENV JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"
RUN set -eux; \
    add-apt-repository ppa:openjdk-r/ppa -y; \
    apt-get update; \
    apt-get install -y openjdk-21-jdk; \
    # Verify Java installation
    java -version; \
    javac -version; \
    # Cleanup
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Stage 3: Container tools installation
FROM java-runtime AS container-tools

# Install docker-compose (V2, which is now the standard)
# V2 is installed as a Docker CLI plugin, usually found at ~/.docker/cli-plugins/docker-compose
ENV DOCKER_COMPOSE_VERSION="v2.24.5"
RUN set -eux; \
    DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}; \
    mkdir -p $DOCKER_CONFIG/cli-plugins; \
    curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o $DOCKER_CONFIG/cli-plugins/docker-compose; \
    chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose; \
    # Make globally available
    ln -sf $DOCKER_CONFIG/cli-plugins/docker-compose /usr/local/bin/docker-compose; \
    # Verify installation
    docker-compose version || echo "Docker Compose will be available when Docker is running"

# Install Kind for Kubernetes testing
RUN set -eux; \
    curl -Lo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"; \
    chmod +x /usr/local/bin/kind; \
    # Verify installation
    kind version

COPY kind-config.yaml /kind-config.yaml

# Install kubectl (updated to a recent stable version, matching Kind if possible or a common version like 1.30.x)
# Always try to match kubectl version with the Kubernetes cluster version (kind) if possible.
# For simplicity, let's pick a recent stable client.
ENV KUBECTL_VERSION="v1.30.2"
RUN set -eux; \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; \
    curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256"; \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check; \
    chmod +x ./kubectl; \
    mv ./kubectl /usr/local/bin/kubectl; \
    rm kubectl.sha256; \
    # Verify installation
    kubectl version --client

# Install Helm
RUN set -eux; \
    curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz | tar -xz; \
    mv linux-amd64/helm /usr/local/bin/helm; \
    rm -rf linux-amd64; \
    # Verify installation
    helm version

# Stage 4: Development tools and Node.js
FROM container-tools AS dev-tools

# Install development dependencies
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libpq-dev \
        build-essential \
        pkg-config \
        git \
        vim \
        jq \
        unzip; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# Install Node.js 22.x LTS (latest LTS as of July 2025) and modern package managers
ENV NODE_MAJOR_VERSION="22" \
    PNPM_VERSION="9.5.0" \
    YARN_VERSION="4.3.1"

RUN set -eux; \
    # Install Node.js from NodeSource
    curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR_VERSION}.x | bash -; \
    apt-get install -y --no-install-recommends nodejs; \
    # Install modern package managers
    npm install -g pnpm@${PNPM_VERSION}; \
    npm install -g yarn@${YARN_VERSION}; \
    # Install essential build tools
    npm install -g typescript webpack node-gyp; \
    # Verify installations
    node -v; \
    npm -v; \
    pnpm -v; \
    yarn -v; \
    # Cleanup
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /root/.npm

# Stage 5: Final production stage
FROM dev-tools AS final

# Copy configuration files
COPY kind-config.yaml /kind-config.yaml
COPY extended-entrypoint.sh /extended-entrypoint.sh

# Set proper permissions
RUN chmod +x /extended-entrypoint.sh

# Create non-root user for better security
RUN groupadd -r builduser && useradd -r -g builduser builduser

# Set up environment for the build user
RUN mkdir -p /home/builduser && \
    chown -R builduser:builduser /home/builduser

# Add build tools to PATH
ENV PATH="/usr/local/bin:${PATH}"

# Health check to ensure essential tools are available
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD java -version && node -v && kubectl version --client || exit 1

# Set working directory
WORKDIR /workspace

# Switch to non-root user for security (can be overridden if root access needed)
USER builduser

# ENTRYPOINT: Use tini for proper signal handling
ENTRYPOINT ["/tini", "-g", "--", "/extended-entrypoint.sh"]
