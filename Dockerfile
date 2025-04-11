# Use BuildKit for better caching and parallel building
# syntax=docker/dockerfile:1.4

#############################################################################
# Stage 1: Base dependencies - Common foundation for all stages
#############################################################################
FROM ubuntu:22.04 AS base-deps

# Set shell to fail on errors for more robust scripts
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Version arguments for better maintenance
ARG PYTHON_VERSION="3.10.4"
ARG CONDA_VERSION="4.9.2"
ARG MINICONDA_VERSION="4.10.3"
ARG MINICONDA_MD5="122c8c9beb51e124ab32a0fa6426c656"
ARG NODE_VERSION="18.x"
ARG OPEN_RESTY_VERSION="1.19.3.2"
ARG TINI_VERSION="0.19.0"
ARG WORKSPACE_FLAVOR="full"
ARG VCS_REF="unknown"
ARG WORKSPACE_VERSION="unknown"
ARG BUILD_DATE="unknown"

# Common environment variables used across all stages
ENV DEBIAN_FRONTEND="noninteractive" \
    SHELL="/bin/bash" \
    HOME="/root" \
    NB_USER="root" \
    USER_GID=0 \
    RESOURCES_PATH="/resources" \
    SSL_RESOURCES_PATH="/resources/ssl" \
    WORKSPACE_HOME="/workspace" \
    XDG_CACHE_HOME="/root/.cache/" \
    XDG_RUNTIME_DIR="/tmp" \
    DISPLAY=":1" \
    TERM="xterm" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en" \
    LC_ALL="en_US.UTF-8" \
    WORKSPACE_FLAVOR="${WORKSPACE_FLAVOR}" \
    WORKSPACE_VERSION="${WORKSPACE_VERSION}"
WORKDIR $HOME

# Copy utility scripts early to use throughout the build
COPY resources/scripts/clean-layer.sh resources/scripts/fix-permissions.sh /usr/bin/
RUN chmod a+rx /usr/bin/clean-layer.sh /usr/bin/fix-permissions.sh

# Create directories, install basic dependencies, and configure the environment
RUN set -ex && \
    # Create directories with proper permissions
    mkdir -p $RESOURCES_PATH $WORKSPACE_HOME $SSL_RESOURCES_PATH && \
    chmod a+rwx $RESOURCES_PATH $WORKSPACE_HOME $SSL_RESOURCES_PATH && \
    \
    # Create non-root user for security
    groupadd -r appuser && \
    useradd -r -g appuser -d /home/appuser -m appuser && \
    \
    # Install core packages in a single layer
    apt-get update && \
    apt-get install -y --no-install-recommends \
        locales ca-certificates curl wget \
        apt-utils apt-transport-https gnupg2 \
        software-properties-common \
        build-essential pkg-config lsof net-tools \
        openssh-client openssh-server sslh autossh \
        openssl iproute2 psmisc tmux dpkg-sig uuid-dev \
        xclip time libssl-dev xz-utils gawk swig \
        graphviz libgraphviz-dev screen nano \
        sqlite3 xmlstarlet parallel libspatialindex-dev \
        yara less tree bash-completion iputils-ping \
        socat jq rsync libsqlite3-dev git subversion \
        libzmq3-dev protobuf-compiler autoconf automake \
        libtool cmake zip gzip unzip bzip2 lzop \
        libarchive-tools zlib1g-dev libbz2-dev liblzma-dev && \
    # Configure locales
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    update-locale LANG=en_US.UTF-8 && \
    \
    # Add git PPA for latest version
    add-apt-repository -y ppa:git-core/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends git && \
    \
    # Configure SSH 
    mkdir -p $HOME/.ssh/ && \
    touch $HOME/.ssh/config && \
    chmod 700 $HOME/.ssh && \
    printenv >> $HOME/.ssh/environment && \
    mkdir -p /var/run/sshd && chmod 400 /var/run/sshd && \
    \
    # Install Node.js (single installation for all stages)
    curl -sL https://deb.nodesource.com/setup_${NODE_VERSION} | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install -g npm yarn typescript webpack node-gyp && \
    npm cache clean --force && \
    \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    clean-layer.sh

# Add tini for proper signal handling
RUN set -ex && \
    wget --no-verbose https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini -O /tini && \
    chmod +x /tini

# Install OpenResty (nginx)
RUN set -ex && \
    # Install OpenResty dependencies
    apt-get update && \
    apt-get purge -y nginx nginx-common && \
    apt-get install -y --no-install-recommends libssl-dev libpcre3 libpcre3-dev apache2-utils && \
    \
    # Build and install OpenResty
    mkdir -p /tmp/openresty && \
    cd /tmp/openresty && \
    wget --no-verbose https://openresty.org/download/openresty-${OPEN_RESTY_VERSION}.tar.gz -O ./openresty.tar.gz && \
    tar xfz ./openresty.tar.gz && \
    cd ./openresty-${OPEN_RESTY_VERSION}/ && \
    ./configure --with-http_stub_status_module --with-http_sub_module > /dev/null && \
    make -j"$(nproc)" > /dev/null && \
    make install > /dev/null && \
    \
    # Setup nginx logs and directories
    mkdir -p /var/log/nginx/ && \
    touch /var/log/nginx/upstream.log && \
    \
    # Clean up
    cd / && \
    rm -rf /tmp/openresty && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    clean-layer.sh

# Update PATH for OpenResty
ENV PATH=/usr/local/openresty/nginx/sbin:$PATH \
    PATH=/opt/node/bin:$PATH

# Copy Nginx configuration
COPY resources/nginx/lua-extensions /etc/nginx/nginx_plugins

#############################################################################
# Stage 2: Python environment - Conda, Python, and pyenv setup
#############################################################################
FROM base-deps AS python-env

# Set Conda environment variables
ENV CONDA_DIR=/opt/conda \
    CONDA_ROOT=/opt/conda \
    CONDA_PYTHON_DIR=/opt/conda/lib/python3.10 \
    PATH=$PATH:/opt/conda/bin \
    LD_LIBRARY_PATH=/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:/opt/conda/lib

# Copy library requirements for installation
COPY resources/libraries ${RESOURCES_PATH}/libraries

# Install Miniconda and Python environment
RUN set -ex && \
    wget --no-verbose https://repo.anaconda.com/miniconda/Miniconda3-py38_${CONDA_VERSION}-Linux-x86_64.sh -O ~/miniconda.sh && \
    echo "${MINICONDA_MD5} *miniconda.sh" | md5sum -c - && \
    /bin/bash ~/miniconda.sh -b -p $CONDA_ROOT && \
    rm ~/miniconda.sh && \
    # Configure conda
    $CONDA_ROOT/bin/conda init bash && \
    $CONDA_ROOT/bin/conda update -y conda && \
    $CONDA_ROOT/bin/conda install -y python=${PYTHON_VERSION} pip conda-build && \
    # Create symlinks
    ln -s $CONDA_ROOT/bin/python /usr/local/bin/python && \
    ln -s $CONDA_ROOT/bin/conda /usr/bin/conda && \
    # Upgrade pip
    $CONDA_ROOT/bin/pip install --upgrade pip && \
    # Fix permissions
    fix-permissions.sh $CONDA_ROOT && \
    # Clean up
    $CONDA_ROOT/bin/conda clean -afy && \
    rm -rf $HOME/.cache/pip && \
    clean-layer.sh

# Install pyenv for managing Python versions
RUN set -ex && \
    apt-get update && \
    apt-get install -y --no-install-recommends libffi-dev && \
    git clone --depth 1 https://github.com/pyenv/pyenv.git $RESOURCES_PATH/.pyenv && \
    git clone --depth 1 https://github.com/pyenv/pyenv-virtualenv.git $RESOURCES_PATH/.pyenv/plugins/pyenv-virtualenv && \
    git clone --depth 1 https://github.com/pyenv/pyenv-doctor.git $RESOURCES_PATH/.pyenv/plugins/pyenv-doctor && \
    git clone --depth 1 https://github.com/pyenv/pyenv-update.git $RESOURCES_PATH/.pyenv/plugins/pyenv-update && \
    git clone --depth 1 https://github.com/pyenv/pyenv-which-ext.git $RESOURCES_PATH/.pyenv/plugins/pyenv-which-ext && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    fix-permissions.sh $RESOURCES_PATH/.pyenv && \
    clean-layer.sh

ENV PATH=$RESOURCES_PATH/.pyenv/shims:$RESOURCES_PATH/.pyenv/bin:$PATH \
    PYENV_ROOT=$RESOURCES_PATH/.pyenv

# Install pipx for isolated application installations
RUN pip install pipx && \
    python -m pipx ensurepath && \
    clean-layer.sh

ENV PATH=$HOME/.local/bin:$PATH

# Install main data science libraries
RUN set -ex && \
    ln -s -f $CONDA_ROOT/bin/python /usr/bin/python && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        libopenmpi-dev \
        openmpi-bin \
        liblapack-dev \
        libatlas-base-dev \
        libeigen3-dev \
        libblas-dev \
        libhdf5-dev \
        libtbb-dev \
        libtesseract-dev \
        libopenexr-dev \
        libgomp1 && \
    pip install --upgrade pip && \
    conda config --system --set channel_priority strict && \
    if [ "$WORKSPACE_FLAVOR" = "minimal" ]; then \
        conda install -y --update-all "python=$PYTHON_VERSION" nomkl && \
        pip install --no-cache-dir -r ${RESOURCES_PATH}/libraries/requirements-minimal.txt; \
    elif [ "$WORKSPACE_FLAVOR" != "full" ]; then \
        conda install -y --update-all "python=$PYTHON_VERSION" mkl-service mkl && \
        conda install -y --freeze-installed \
            boost \
            mkl-include && \
        conda install -y -c mingfeima mkldnn && \
        conda install -y -c pytorch "pytorch==1.10.*" cpuonly && \
        conda install -y --freeze-installed \
            'ipython' \
            'notebook' \
            'jupyterlab' \
            'nbconvert' \
            'yarl' \
            'scipy' \
            'numpy' \
            scikit-learn \
            numexpr && \
        pip install --no-cache-dir -r ${RESOURCES_PATH}/libraries/requirements-light.txt; \
    else \
        conda install -y --update-all "python=$PYTHON_VERSION" mkl-service mkl && \
        conda install -y --freeze-installed \
            boost \
            mkl-include \
            libjpeg-turbo && \
        conda install -y -c mingfeima mkldnn && \
        conda install -y -c pytorch "pytorch==1.10.*" cpuonly && \
        conda install -y --freeze-installed \
            'ipython' \
            'notebook' \
            'jupyterlab' \
            'nbconvert' \
            'yarl' \
            'scipy' \
            'numpy' \
            scikit-learn \
            numexpr && \
        conda install -y -c bioconda -c conda-forge snakemake-minimal && \
        conda install -y -c conda-forge mamba && \
        conda install -y --no-deps --freeze-installed faiss-cpu && \
        pip install --no-cache-dir --use-deprecated=legacy-resolver \
            -r ${RESOURCES_PATH}/libraries/requirements-full.txt && \
        python -m spacy download en; \
    fi && \
    # Fix conda version
    rm -f /opt/conda/bin/node && ln -s /usr/bin/node /opt/conda/bin/node && \
    rm -f /opt/conda/bin/npm && ln -s /usr/bin/npm /opt/conda/bin/npm && \
    # Clean up
    fix-permissions.sh $CONDA_ROOT && \
    $CONDA_ROOT/bin/conda clean -afy && \
    rm -rf $HOME/.cache/pip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    clean-layer.sh

#############################################################################
# Stage 3: Process tools - Supervisor installation and process management
#############################################################################
FROM python-env AS process-tools

# Install supervisor for process supervision
RUN set -ex && \
    apt-get update && \
    mkdir -p /var/run/sshd && chmod 400 /var/run/sshd && \
    apt-get install -y --no-install-recommends rsyslog && \
    pipx install supervisor && \
    pipx inject supervisor supervisor-stdout && \
    mkdir -p /var/log/supervisor/ && \
    # Clean up
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    clean-layer.sh

#############################################################################
# Stage 4: GUI tools - Desktop environment and GUI applications
#############################################################################
FROM process-tools AS gui-tools

ARG WORKSPACE_FLAVOR="full"
ENV WORKSPACE_FLAVOR=$WORKSPACE_FLAVOR

# Install GUI tools - xfce4, browsers, and other utilities
RUN set -ex && \
    apt-get update && \
    apt-get install -y xarchiver && \
    apt-get install -y --no-install-recommends sqlitebrowser && \
    apt-get install -y --no-install-recommends nautilus && \
    apt-get install -y --no-install-recommends gigolo && \
    apt-get install -y --no-install-recommends gftp && \
    add-apt-repository -y ppa:saiarcot895/chromium-beta && \
    apt-get update && \
    apt-get install -y --no-install-recommends chromium-browser chromium-browser-l10n chromium-codecs-ffmpeg && \
    ln -s /usr/bin/chromium-browser /usr/bin/google-chrome && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    clean-layer.sh
# Install Jupyter tools
COPY resources/jupyter/start.sh resources/jupyter/start-notebook.sh resources/jupyter/start-singleuser.sh /usr/local/bin/
COPY resources/jupyter/nbconfig /etc/jupyter/nbconfig
COPY resources/jupyter/jupyter_notebook_config.json /etc/jupyter/

# Install jupyter extensions
RUN set -ex && \
    mkdir -p $HOME/.jupyter/nbconfig/ && \
    printf "{\"load_extensions\": {}}" > $HOME/.jupyter/nbconfig/notebook.json && \
    jupyter contrib nbextension install --sys-prefix && \
    jupyter nbextensions_configurator enable --sys-prefix && \
    nbdime config-git --enable --global && \
    jupyter nbextension enable --py jupytext --sys-prefix && \
    jupyter nbextension enable skip-traceback/main --sys-prefix && \
    jupyter nbextension enable toc2/main --sys-prefix && \
    jupyter nbextension enable execute_time/ExecuteTime --sys-prefix && \
    jupyter nbextension enable collapsible_headings/main --sys-prefix && \
    jupyter nbextension enable codefolding/main --sys-prefix && \
    jupyter nbextension disable pydeck/extension && \
    pip install --no-cache-dir git+https://github.com/InfuseAI/jupyter_tensorboard.git && \
    jupyter tensorboard enable --sys-prefix && \
    cat $HOME/.jupyter/nbconfig/notebook.json | jq '.toc2={"moveMenuLeft": false,"widenNotebook": false,"skip_h1_title": false,"sideBar": true,"number_sections": false,"collapse_to_match_collapsible_headings": true}' > tmp.$$.json && mv tmp.$$.json $HOME/.jupyter/nbconfig/notebook.json && \
    \
    # Install additional extensions based on workspace flavor
    if [ "$WORKSPACE_FLAVOR" != "minimal" ]; then \
        jupyter nbextension install https://github.com/drillan/jupyter-black/archive/master.zip --sys-prefix && \
        jupyter nbextension enable jupyter-black-master/jupyter-black --sys-prefix && \
        # Install additional extensions for full flavor
        if [ "$WORKSPACE_FLAVOR" = "full" ]; then \
            jupyter labextension install @jupyter-widgets/jupyterlab-manager && \
            jupyter labextension install @jupyterlab/toc && \
            jupyter labextension install @aquirdturtle/collapsible_headings; \
        fi \
    fi && \
    fix-permissions.sh $CONDA_ROOT && \
    clean-layer.sh
# Copy scripts into workspace
COPY resources/scripts $RESOURCES_PATH/scripts

# Create Desktop Icons for Tooling
COPY resources/branding $RESOURCES_PATH/branding

# Configure Home folder (e.g. xfce)
COPY resources/home/ $HOME/

# Copy some configuration files
COPY resources/ssh/ssh_config resources/ssh/sshd_config  /etc/ssh/
COPY resources/nginx/nginx.conf /etc/nginx/nginx.conf
COPY resources/config/xrdp.ini /etc/xrdp/xrdp.ini

# Configure supervisor process
COPY resources/supervisor/supervisord.conf /etc/supervisor/supervisord.conf
# Copy all supervisor program definitions into workspace
COPY resources/supervisor/programs/ /etc/supervisor/conf.d/

# Assume yes to all apt commands, to avoid user confusion around stdin.
COPY resources/config/90assumeyes /etc/apt/apt.conf.d/

# Monkey Patching novnc: Styling and added clipboard support. All changed sections are marked with CUSTOM CODE
COPY resources/novnc/ $RESOURCES_PATH/novnc/

RUN set -ex && \
    ln -s $RESOURCES_PATH/novnc/vnc.html $RESOURCES_PATH/novnc/index.html && \
    # Clean up any temporary files
    clean-layer.sh

# Basic VNC Settings - no password
ENV \
    VNC_PW=vncpassword \
    VNC_RESOLUTION=1600x900 \
    VNC_COL_DEPTH=24

# Add tensorboard patch - use tensorboard jupyter plugin instead of the actual tensorboard magic
COPY resources/jupyter/tensorboard_notebook_patch.py $CONDA_PYTHON_DIR/site-packages/tensorboard/notebook.py

# Additional jupyter configuration
COPY resources/jupyter/jupyter_notebook_config.py /etc/jupyter/
COPY resources/jupyter/sidebar.jupyterlab-settings $HOME/.jupyter/lab/user-settings/@jupyterlab/application-extension/
COPY resources/jupyter/plugin.jupyterlab-settings $HOME/.jupyter/lab/user-settings/@jupyterlab/extensionmanager-extension/
COPY resources/jupyter/ipython_config.py /etc/ipython/ipython_config.py

# Branding of various components
RUN set -ex && \
    cp -f $RESOURCES_PATH/branding/logo.png $CONDA_PYTHON_DIR"/site-packages/notebook/static/base/images/logo.png" && \
    cp -f $RESOURCES_PATH/branding/favicon.ico $CONDA_PYTHON_DIR"/site-packages/notebook/static/base/images/favicon.ico" && \
    cp -f $RESOURCES_PATH/branding/favicon.ico $CONDA_PYTHON_DIR"/site-packages/notebook/static/favicon.ico" && \
    mkdir -p $RESOURCES_PATH"/filebrowser/img/icons/" && \
    cp -f $RESOURCES_PATH/branding/favicon.ico $RESOURCES_PATH"/filebrowser/img/icons/favicon.ico" && \
    cp -f $RESOURCES_PATH/branding/favicon.ico $RESOURCES_PATH"/filebrowser/img/icons/favicon-32x32.png" && \
    cp -f $RESOURCES_PATH/branding/favicon.ico $RESOURCES_PATH"/filebrowser/img/icons/favicon-16x16.png" && \
    cp -f $RESOURCES_PATH/branding/ml-workspace-logo.svg $RESOURCES_PATH"/filebrowser/img/logo.svg" && \
    # Clean up any temporary files
    clean-layer.sh

# Configure git
RUN set -ex && \
    git config --global core.fileMode false && \
    git config --global http.sslVerify false && \
    git config --global credential.helper 'cache --timeout=31540000' && \
    # Clean up any temporary files
    clean-layer.sh

# Configure netdata
COPY resources/netdata/ /etc/netdata/
COPY resources/netdata/cloud.conf /var/lib/netdata/cloud.d/cloud.conf

# Configure Matplotlib
RUN set -ex && \
    MPLBACKEND=Agg python -c "import matplotlib.pyplot" && \
    sed -i "s/^.*Matplotlib is building the font cache using fc-list.*$/# Warning removed/g" $CONDA_PYTHON_DIR/site-packages/matplotlib/font_manager.py && \
    # Clean up any temporary files
    clean-layer.sh

# Create Desktop Icons for Tooling
COPY resources/icons $RESOURCES_PATH/icons

    chmod +x /usr/share/applications/netdata.desktop && \
    echo "[Desktop Entry]\nVersion=1.0\nType=Link\nName=Glances\nComment=Hardware Monitoring\nCategories=System;Utility;\nIcon=/resources/icons/glances-icon.png\nURL=http://localhost:8092/tools/glances" > /usr/share/applications/glances.desktop && \
    chmod +x /usr/share/applications/glances.desktop && \
    rm /usr/share/applications/xfce4-mail-reader.desktop && \
    rm /usr/share/applications/xfce4-session-logout.desktop

# Copy resources into workspace
COPY resources/tools $RESOURCES_PATH/tools
COPY resources/tests $RESOURCES_PATH/tests
COPY resources/tutorials $RESOURCES_PATH/tutorials
COPY resources/licenses $RESOURCES_PATH/licenses
COPY resources/reports $RESOURCES_PATH/reports

# Various configurations
RUN \
    touch $HOME/.ssh/config && \
    chmod -R a+rwx $WORKSPACE_HOME && \
    chmod -R a+rwx $RESOURCES_PATH && \
    chmod -R a+rwx /usr/share/applications/ && \
    ln -s $RESOURCES_PATH/tools/ $HOME/Desktop/Tools && \
    ln -s $WORKSPACE_HOME $HOME/Desktop/workspace && \
    chmod a+rwx /usr/local/bin/start-notebook.sh && \
    chmod a+rwx /usr/local/bin/start.sh && \
    chmod a+rwx /usr/local/bin/start-singleuser.sh && \
    chown root:root /tmp && \
    chmod 1777 /tmp && \
    echo 'cd '$WORKSPACE_HOME >> $HOME/.bashrc

ENV KMP_DUPLICATE_LIB_OK="True" \
    KMP_AFFINITY="granularity=fine,compact,1,0" \
    KMP_BLOCKTIME=0 \
    MKL_THREADING_LAYER=GNU \
    ENABLE_IPC=1 \
    PYTHON_PRETTY_ERRORS_ISATTY_ONLY=1 \
    HDF5_USE_FILE_LOCKING=False

ENV CONFIG_BACKUP_ENABLED="true" \
    SHUTDOWN_INACTIVE_KERNELS="false" \
    SHARED_LINKS_ENABLED="true" \
    AUTHENTICATE_VIA_JUPYTER="false" \
    DATA_ENVIRONMENT=$WORKSPACE_HOME"/environment" \
    WORKSPACE_BASE_URL="/" \
    INCLUDE_TUTORIALS="true" \
    WORKSPACE_PORT="8080" \
    SHELL="/usr/bin/zsh" \
    MAX_NUM_THREADS="auto"

### END CONFIGURATION ###
ARG ARG_BUILD_DATE="unknown"
ARG ARG_VCS_REF="unknown"
ARG ARG_WORKSPACE_VERSION="unknown"
ENV WORKSPACE_VERSION=$ARG_WORKSPACE_VERSION


#############################################################################
# Stage 5: Runtime - Final stage with all components
#############################################################################
FROM gui-tools AS runtime

# Environment variables needed for runtime
ENV AUTHENTICATE_VIA_JUPYTER="false" \
    WORKSPACE_BASE_URL="/" \
    WORKSPACE_PORT="8080"

# Overwrite & add Labels
LABEL \
    "maintainer"="info@khulnasoft.com" \
    "workspace.version"=$WORKSPACE_VERSION \
    "workspace.flavor"=$WORKSPACE_FLAVOR \
    "io.k8s.description"="All-in-one web-based development environment for machine learning." \
    "io.k8s.display-name"="Machine Learning Workspace" \
    "io.openshift.expose-services"="8080:http, 5901:xvnc" \
    "io.openshift.non-scalable"="true" \
    "io.openshift.tags"="workspace, machine learning, vnc, ubuntu, xfce" \
    "io.openshift.min-memory"="1Gi" \
    "org.opencontainers.image.title"="Machine Learning Workspace" \
    "org.opencontainers.image.description"="All-in-one web-based development environment for machine learning." \
    "org.opencontainers.image.documentation"="https://github.com/khulnasoft/ml-workspace" \
    "org.opencontainers.image.url"="https://github.com/khulnasoft/ml-workspace" \
    "org.opencontainers.image.source"="https://github.com/khulnasoft/ml-workspace" \
    "org.opencontainers.image.version"=$WORKSPACE_VERSION \
    "org.opencontainers.image.vendor"="KhulnaSoft DevOps" \
    "org.opencontainers.image.authors"="Md Sulaiman & KhulnaSoft Lab" \
    "org.opencontainers.image.revision"=$ARG_VCS_REF \
    "org.opencontainers.image.created"=$ARG_BUILD_DATE \
    "org.label-schema.name"="Machine Learning Workspace" \
    "org.label-schema.description"="All-in-one web-based development environment for machine learning." \
    "org.label-schema.usage"="https://github.com/khulnasoft/ml-workspace" \
    "org.label-schema.url"="https://github.com/khulnasoft/ml-workspace" \
    "org.label-schema.vcs-url"="https://github.com/khulnasoft/ml-workspace" \
    "org.label-schema.vendor"="Khulnasoft DevOps" \
    "org.label-schema.version"=$WORKSPACE_VERSION \
    "org.label-schema.schema-version"="1.0" \
    "org.label-schema.vcs-ref"=$ARG_VCS_REF \
    "org.label-schema.build-date"=$ARG_BUILD_DATE

# Health check
HEALTHCHECK --interval=30s --timeout=5s CMD curl -f http://localhost:${WORKSPACE_PORT}/health || exit 1

ENTRYPOINT ["/tini", "-g", "--"]

CMD ["python", "/resources/docker-entrypoint.py"]

EXPOSE 8080
