# syntax=docker/dockerfile:1.4
# Use a more recent Ubuntu LTS as a base image for better security and newer packages.
# Ubuntu 22.04 (Jammy Jellyfish) is the current LTS.
FROM ubuntu:22.04

# Best practice: Do not run as root unnecessarily after initial setup.
# However, given the extensive system-level installations, it's maintained for now.
# If possible, switch to a non-root user later in the Dockerfile.
USER root

### BASE CONFIGURATION & ENVIRONMENT ###
# Use ARG for build-time variables and ENV for runtime variables.
# Group related ENV variables for readability.
ENV \
    SHELL="/bin/bash" \
    HOME="/root" \
    NB_USER="root" \
    USER_GID=0 \
    XDG_CACHE_HOME="/root/.cache/" \
    XDG_RUNTIME_DIR="/tmp" \
    DISPLAY=":1" \
    TERM="xterm" \
    DEBIAN_FRONTEND="noninteractive" \
    RESOURCES_PATH="/resources" \
    SSL_RESOURCES_PATH="/resources/ssl" \
    WORKSPACE_HOME="/workspace" \
    LC_ALL="en_US.UTF-8" \
    LANG="en_US.UTF-8" \
    LANGUAGE="en_US:en"

WORKDIR ${HOME}

# Create directories with a single RUN command and correct permissions.
# Use --parents for mkdir -p.
RUN mkdir -p ${RESOURCES_PATH} ${WORKSPACE_HOME} ${SSL_RESOURCES_PATH} && \
    chmod a+rwx ${RESOURCES_PATH} ${WORKSPACE_HOME} ${SSL_RESOURCES_PATH}

# Copy scripts and make them executable in one go.
COPY resources/scripts/clean-layer.sh /usr/bin/
COPY resources/scripts/fix-permissions.sh /usr/bin/
RUN chmod +x /usr/bin/clean-layer.sh /usr/bin/fix-permissions.sh

# Install locales in a single RUN command.
# Use apt-get clean and rm -rf /var/lib/apt/lists/* immediately after apt-get install.
RUN apt-get update && \
    apt-get install -y locales && \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    # No need for dpkg-reconfigure with DEBIAN_FRONTEND="noninteractive"
    update-locale LANG=en_US.UTF-8 && \
    clean-layer.sh

# Add tini - use a specific, recent version.
# Current Tini LTS is 0.19.0, but newer stable versions are available. Let's use 0.19.0 as in original.
RUN wget --no-verbose https://github.com/krallin/tini/releases/download/v0.19.0/tini -O /tini && \
    chmod +x /tini

---
### SYSTEM-WIDE PACKAGES ###

# Install basic packages. Group related packages and use --no-install-recommends.
# Consolidate apt-get update calls.
# `apt-get upgrade -y` is generally discouraged in Dockerfiles as it can lead to
# non-reproducible builds. Pinning versions or adding specific upgrades is better.
# For simplicity, removed `apt-get upgrade -y` here.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    sudo apt-utils apt-transport-https gnupg-agent gpg-agent gnupg2 ca-certificates \
    build-essential pkg-config software-properties-common lsof net-tools libcurl4 curl wget cron openssl iproute2 \
    psmisc tmux dpkg-sig uuid-dev csh xclip clinfo time libssl-dev libgdbm-dev libncurses5-dev libncursesw5-dev \
    libreadline-dev libedit-dev xz-utils gawk swig graphviz libgraphviz-dev screen nano locate sqlite3 xmlstarlet \
    parallel libspatialindex-dev yara libhiredis-dev libpq-dev libmysqlclient-dev libleptonica-dev libgeos-dev \
    less tree bash-completion iputils-ping socat jq rsync libsqlite3-dev git subversion jed unixodbc unixodbc-dev \
    libtiff-dev libjpeg-dev libpng-dev libglib2.0-0 libxext6 libsm6 libxext-dev libxrender1 libzmq3-dev \
    protobuf-compiler libprotobuf-dev libprotoc-dev autoconf automake libtool cmake fonts-liberation \
    google-perftools zip gzip unzip bzip2 lzop libarchive-tools zlibc unp libbz2-dev liblzma-dev zlib1g-dev && \
    # Update git to newest version from PPA
    add-apt-repository -y ppa:git-core/ppa && \
    apt-get update && \
    apt-get install -y --no-install-recommends git && \
    # Fix execution permissions for /usr/local/bin (often not needed for apt installs)
    chmod -R a+rwx /usr/local/bin/ && \
    ldconfig && \
    fix-permissions.sh ${HOME} && \
    clean-layer.sh

# Prepare SSH for inter-container communication.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    openssh-client openssh-server sslh autossh mussh && \
    chmod go-w ${HOME} && \
    mkdir -p ${HOME}/.ssh/ && \
    touch ${HOME}/.ssh/config && \
    # Use sudo when switching user contexts, or ensure NB_USER has permissions
    chown -R ${NB_USER}:${NB_USER} ${HOME}/.ssh && \
    chmod 700 ${HOME}/.ssh && \
    # printenv adds all current env vars, might be too much. Consider explicit ones.
    printenv >> ${HOME}/.ssh/environment && \
    chmod -R a+rwx /usr/local/bin/ && \
    fix-permissions.sh ${HOME} && \
    clean-layer.sh

# Install OpenResty. Use a more recent stable version if available.
# 1.19.3.2 is old; 1.25.3.1 (LTS as of 2024-05) is much newer.
ENV OPEN_RESTY_VERSION="1.25.3.1"
RUN mkdir -p ${RESOURCES_PATH}/openresty && \
    cd ${RESOURCES_PATH}/openresty && \
    apt-get update && \
    apt-get purge -y nginx nginx-common || true && \
    apt-get install -y --no-install-recommends libssl-dev libpcre3 libpcre3-dev apache2-utils && \
    wget --no-verbose https://openresty.org/download/openresty-${OPEN_RESTY_VERSION}.tar.gz -O ./openresty.tar.gz && \
    tar xfz ./openresty.tar.gz && \
    rm ./openresty.tar.gz && \
    cd ./openresty-${OPEN_RESTY_VERSION}/ && \
    ./configure --with-http_stub_status_module --with-http_sub_module --with-http_v2_module --with-http_realip_module > /dev/null && \
    make -j$(nproc) > /dev/null && \
    make install > /dev/null && \
    mkdir -p /var/log/nginx/ && \
    touch /var/log/nginx/upstream.log && \
    cd ${RESOURCES_PATH} && \
    rm -r ${RESOURCES_PATH}/openresty && \
    chmod -R a+rwx ${RESOURCES_PATH} && \
    clean-layer.sh

ENV PATH="/usr/local/openresty/nginx/sbin:${PATH}"
COPY resources/nginx/lua-extensions /etc/nginx/nginx_plugins

---
### RUNTIMES - CONDA & PYTHON ###

# Use a more recent Miniconda version and Python.
# Always refer to the official Miniconda release page for the latest installers and their MD5/SHA256 checksums.
# As of current date, Miniconda3-py310_24.3.0-0-Linux-x86_64.sh is more typical.
# Using fixed versions is critical for reproducibility.
ENV \
    CONDA_DIR="/opt/conda" \
    CONDA_ROOT="/opt/conda" \
    PYTHON_VERSION="3.10.13" \
    MINICONDA_VERSION="24.3.0-0" \
    MINICONDA_SHA256="4e892c2196bc5d58f000b0dd38e07248010626359bc2985175d045c711765c92" \
    CONDA_VERSION="24.3.0" \
    PATH="${CONDA_ROOT}/bin:${PATH}" \
    LD_LIBRARY_PATH="${CONDA_ROOT}/lib"

# Install Miniconda and configure it.
# Use `source` for activating conda in the current shell.
RUN wget --no-verbose "https://repo.anaconda.com/miniconda/Miniconda3-py310_${MINICONDA_VERSION}-Linux-x86_64.sh" -O ~/miniconda.sh && \
    echo "${MINICONDA_SHA256} *miniconda.sh" | sha256sum -c - && \
    /bin/bash ~/miniconda.sh -b -p ${CONDA_ROOT} && \
    rm ~/miniconda.sh && \
    # Initialize conda in bash (for non-interactive use)
    eval "$(conda shell.bash hook)" && \
    # Configure conda channels and settings
    conda config --system --add channels conda-forge && \
    conda config --system --set auto_update_conda False && \
    conda config --system --set show_channel_urls True && \
    conda config --system --set channel_priority strict && \
    conda config --system --set pip_interop_enabled false && \
    # Update conda and install core packages
    conda update -y -n base -c defaults conda && \
    conda install -y setuptools conda-build && \
    conda install -y python=${PYTHON_VERSION} && \
    # Link Conda binaries to /usr/local/bin for global accessibility
    ln -s ${CONDA_ROOT}/bin/python /usr/local/bin/python || true && \
    ln -s ${CONDA_ROOT}/bin/conda /usr/bin/conda || true && \
    # Update pip
    conda install -y pip && \
    pip install --upgrade pip && \
    # Cleanup conda cache aggressively
    conda clean -y --all && \
    conda build purge-all && \
    fix-permissions.sh ${CONDA_ROOT} && \
    clean-layer.sh

# Install pyenv.
RUN git clone https://github.com/pyenv/pyenv.git ${RESOURCES_PATH}/.pyenv && \
    git clone https://github.com/pyenv/pyenv-virtualenv.git ${RESOURCES_PATH}/.pyenv/plugins/pyenv-virtualenv && \
    git clone https://github.com/pyenv/pyenv-doctor.git ${RESOURCES_PATH}/.pyenv/plugins/pyenv-doctor && \
    git clone https://github.com/pyenv/pyenv-update.git ${RESOURCES_PATH}/.pyenv/plugins/pyenv-update && \
    git clone https://github.com/pyenv/pyenv-which-ext.git ${RESOURCES_PATH}/.pyenv/plugins/pyenv-which-ext && \
    apt-get update && \
    # libffi-dev is already in basic installs, but good to ensure.
    apt-get install -y --no-install-recommends libffi-dev && \
    clean-layer.sh

ENV PATH="${RESOURCES_PATH}/.pyenv/shims:${RESOURCES_PATH}/.pyenv/bin:${PATH}" \
    PYENV_ROOT="${RESOURCES_PATH}/.pyenv"

# Install pipx.
RUN pip install pipx && \
    python -m pipx ensurepath && \
    clean-layer.sh
ENV PATH="${HOME}/.local/bin:${PATH}"

# Install Node.js - using NodeSource's recommended setup for LTS.
# Node 14.x is quite old. Node 20.x (LTS) or 22.x (current) are better.
ENV NODE_VERSION="20.x" # Or "22.x" for latest stable
RUN apt-get update && \
    curl -sL "https://deb.nodesource.com/setup_${NODE_VERSION}" | bash - && \
    apt-get install -y nodejs && \
    # Re-link conda node/npm to system-wide installations (if they were installed by conda)
    rm -f ${CONDA_ROOT}/bin/node && ln -s /usr/bin/node ${CONDA_ROOT}/bin/node || true && \
    rm -f ${CONDA_ROOT}/bin/npm && ln -s /usr/bin/npm ${CONDA_ROOT}/bin/npm || true && \
    # Ensure proper permissions
    chmod +x /usr/bin/node /usr/bin/npm && \
    # Create /opt/node/bin and link (redundant if PATH is set correctly to /usr/bin)
    # This step is a bit redundant if /usr/bin is already in PATH. Removing.
    # mkdir -p /opt/node/bin && \
    # ln -s /usr/bin/node /opt/node/bin/node && \
    # ln -s /usr/bin/npm /opt/node/bin/npm && \
    npm install -g yarn typescript webpack node-gyp && \
    clean-layer.sh

ENV PATH="/usr/bin:${PATH}" # Ensure /usr/bin is in PATH for node, npm, etc.

---
### PROCESS & GUI TOOLS ###

# Install supervisor and rsyslog.
RUN apt-get update && \
    # Create sshd run directory with appropriate permissions (only owner writeable)
    mkdir -p /var/run/sshd && chmod 755 /var/run/sshd && \
    apt-get install -y --no-install-recommends rsyslog && \
    pipx install supervisor && \
    pipx inject supervisor supervisor-stdout && \
    mkdir -p /var/log/supervisor/ && \
    clean-layer.sh

# Install xfce4 & GUI tools.
# Consolidate installations.
ARG ARG_WORKSPACE_FLAVOR="full"
ENV WORKSPACE_FLAVOR=$ARG_WORKSPACE_FLAVOR

# Use multi-stage build or better layering for flavor-specific installs if size is critical.
# For now, keeping the conditional logic but improving the install step.
RUN apt-get update && \
    add-apt-repository -y ppa:xubuntu-dev/staging && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    xfce4 xfce4-terminal xfce4-clipman xterm xfce4-taskmanager \
    gconf2 xauth xinit dbus-x11 gdebi catfish font-manager thunar-vcs-plugin \
    libqt5concurrent5 libqt5widgets5 libqt5xml5 baobab mousepad vim htop \
    p7zip p7zip-rar thunar-archive-plugin xarchiver sqlitebrowser \
    nautilus gvfs-backends gigolo gvfs-bin gftp && \
    # Install klogg
    wget --no-verbose https://github.com/variar/klogg/releases/download/v20.12/klogg-20.12.0.813-Linux.deb -O ${RESOURCES_PATH}/klogg.deb && \
    dpkg -i ${RESOURCES_PATH}/klogg.deb || apt-get install -yf && \
    rm ${RESOURCES_PATH}/klogg.deb && \
    # Install Chromium
    add-apt-repository ppa:saiarcot895/chromium-beta && \
    apt-get update && \
    apt-get install -y chromium-browser chromium-browser-l10n chromium-codecs-ffmpeg && \
    ln -s /usr/bin/chromium-browser /usr/bin/google-chrome || true && \
    # Cleanup unnecessary packages
    apt-get purge -y pm-utils xscreensaver* app-install-data gnome-user-guide || true && \
    apt-get autoremove -y && \
    clean-layer.sh

# Ensure LD_LIBRARY_PATH includes necessary paths for shared libraries.
# Order matters: conda lib should come first if it's expected to override system libs.
ENV LD_LIBRARY_PATH="/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu:${CONDA_ROOT}/lib"

# Install VNC components.
# Use a more recent TigerVNC and noVNC version.
# TigerVNC 1.13.1 is current stable, noVNC 1.4.0 is current stable.
ENV TIGER_VNC_VERSION="1.13.1" \
    NOVNC_VERSION="1.4.0" \
    WEBSOCKIFY_VERSION="0.11.0" # Match with noVNC for compatibility
RUN apt-get update && \
    # Install Python 3 for websockify (already available via conda)
    cd ${RESOURCES_PATH} && \
    wget -qO- "https://github.com/TigerVNC/tigervnc/releases/download/v${TIGER_VNC_VERSION}/tigervnc-${TIGER_VNC_VERSION}.x86_64.tar.gz" | tar xz --strip 1 -C / && \
    mkdir -p ./novnc/utils/websockify && \
    wget -qO- https://github.com/novnc/noVNC/archive/v${NOVNC_VERSION}.tar.gz | tar xz --strip 1 -C ./novnc && \
    wget -qO- https://github.com/novnc/websockify/archive/v${WEBSOCKIFY_VERSION}.tar.gz | tar xz --strip 1 -C ./novnc/utils/websockify && \
    chmod +x -v ./novnc/utils/*.sh && \
    mkdir -p ${HOME}/.vnc && \
    fix-permissions.sh ${RESOURCES_PATH} && \
    clean-layer.sh

# Install Web Tools conditionally based on flavor.
COPY resources/tools/vs-code-server.sh ${RESOURCES_PATH}/tools/vs-code-server.sh
COPY resources/tools/ungit.sh ${RESOURCES_PATH}/tools/ungit.sh
COPY resources/tools/netdata.sh ${RESOURCES_PATH}/tools/netdata.sh
COPY resources/tools/filebrowser.sh ${RESOURCES_PATH}/tools/filebrowser.sh
COPY resources/tools/vs-code-desktop.sh ${RESOURCES_PATH}/tools/vs-code-desktop.sh
COPY resources/tools/firefox.sh ${RESOURCES_PATH}/tools/firefox.sh

RUN \
    # VS Code Server
    /bin/bash ${RESOURCES_PATH}/tools/vs-code-server.sh --install && \
    clean-layer.sh && \
    # Ungit
    /bin/bash ${RESOURCES_PATH}/tools/ungit.sh --install && \
    clean-layer.sh && \
    # Netdata
    /bin/bash ${RESOURCES_PATH}/tools/netdata.sh --install && \
    clean-layer.sh && \
    # Filebrowser
    /bin/bash ${RESOURCES_PATH}/tools/filebrowser.sh --install && \
    clean-layer.sh && \
    # VS Code Desktop (conditional)
    if [ "${WORKSPACE_FLAVOR}" = "full" ]; then \
        /bin/bash ${RESOURCES_PATH}/tools/vs-code-desktop.sh --install && \
        clean-layer.sh; \
    fi && \
    # Firefox (conditional)
    if [ "${WORKSPACE_FLAVOR}" = "full" ]; then \
        /bin/bash ${RESOURCES_PATH}/tools/firefox.sh --install && \
        clean-layer.sh; \
    fi

---
### DATA SCIENCE & JUPYTER ###

COPY resources/libraries ${RESOURCES_PATH}/libraries

# Use a consistent conda update and configuration.
# Install packages in groups to minimize layers but keep them logical.
RUN eval "$(conda shell.bash hook)" && \
    conda update -n base -c defaults conda && \
    conda config --system --set channel_priority strict && \
    conda install -y 'python=${PYTHON_VERSION}' 'ipython=8.*' 'notebook=7.*' 'jupyterlab=4.*' 'nbconvert' && \
    # Pinning yarl, scipy, numpy is not usually necessary unless specific compatibility is required.
    # Using more flexible versioning (e.g., `scipy` instead of `scipy==1.7.*`) is generally better.
    # Current versions of these might be much newer.
    conda install -y scipy numpy scikit-learn numexpr && \
    conda config --system --set channel_priority false && \
    # Install full requirements via pip
    pip install --no-cache-dir --upgrade --upgrade-strategy only-if-needed --use-deprecated=legacy-resolver -r ${RESOURCES_PATH}/libraries/requirements-full.txt && \
    python -m spacy download en && \
    fix-permissions.sh ${CONDA_ROOT} && \
    conda clean -y --all && \
    clean-layer.sh

# Re-link conda node/npm (already done after nodejs install, but as a safeguard)
RUN rm -f ${CONDA_ROOT}/bin/node && ln -s /usr/bin/node ${CONDA_ROOT}/bin/node || true && \
    rm -f ${CONDA_ROOT}/bin/npm && ln -s /usr/bin/npm ${CONDA_ROOT}/bin/npm || true

### JUPYTER CONFIGURATION ###
COPY resources/jupyter/start.sh /usr/local/bin/
COPY resources/jupyter/start-notebook.sh /usr/local/bin/
COPY resources/jupyter/start-singleuser.sh /usr/local/bin/

COPY resources/jupyter/nbconfig /etc/jupyter/nbconfig
COPY resources/jupyter/jupyter_notebook_config.json /etc/jupyter/

RUN mkdir -p ${HOME}/.jupyter/nbconfig/ && \
    printf '{"load_extensions": {}}' > ${HOME}/.jupyter/nbconfig/notebook.json && \
    # Use jupyter-nbextension for old notebook extensions, jupyter labextension for JupyterLab
    jupyter contrib nbextension install --sys-prefix && \
    jupyter nbextensions_configurator enable --sys-prefix && \
    nbdime config-git --enable --global && \
    jupyter nbextension enable --py jupytext --sys-prefix && \
    jupyter nbextension enable skip-traceback/main --sys-prefix && \
    jupyter nbextension enable toc2/main --sys-prefix && \
    jupyter nbextension enable execute_time/ExecuteTime --sys-prefix && \
    jupyter nbextension enable collapsible_headings/main --sys-prefix && \
    jupyter nbextension enable codefolding/main --sys-prefix && \
    jupyter nbextension disable pydeck/extension || true && \
    pip install --no-cache-dir git+https://github.com/InfuseAI/jupyter_tensorboard.git && \
    jupyter tensorboard enable --sys-prefix && \
    jq '.toc2={"moveMenuLeft": false,"widenNotebook": false,"skip_h1_title": false,"sideBar": true,"number_sections": false,"collapse_to_match_collapsible_headings": true}' ${HOME}/.jupyter/nbconfig/notebook.json > tmp.$$.json && mv tmp.$$.json ${HOME}/.jupyter/nbconfig/notebook.json && \
    if [ "${WORKSPACE_FLAVOR}" != "minimal" ]; then \
        jupyter nbextension install https://github.com/drillan/jupyter-black/archive/master.zip --sys-prefix && \
        jupyter nbextension enable jupyter-black-master/jupyter-black --sys-prefix; \
    fi && \
    if [ "${WORKSPACE_FLAVOR}" = "full" ]; then \
        pip install witwidget && \
        jupyter nbextension install --py --symlink --sys-prefix witwidget && \
        jupyter nbextension enable --py --sys-prefix witwidget && \
        jupyter nbextension enable --py --sys-prefix qgrid && \
        # jupyter serverextension enable voila --sys-prefix && # Requires `voila` package
        ipcluster nbextension enable; \
    fi && \
    clean-layer.sh

# Install JupyterLab extensions.
RUN npm install -g es6-promise && \
    jupyter lab build --dev-build=False --minimize=True --debug-log-path=/dev/stdout --log-level=WARN && \
    LAB_EXT_INSTALL='jupyter labextension install -y --debug-log-path=/dev/stdout --log-level=WARN --minimize=False --no-build' && \
    ${LAB_EXT_INSTALL} @jupyter-widgets/jupyterlab-manager && \
    if [ "${WORKSPACE_FLAVOR}" != "minimal" ]; then \
        ${LAB_EXT_INSTALL} @jupyterlab/toc && \
        pip install git+https://github.com/chaoleili/jupyterlab_tensorboard.git && \
        pip install jupyterlab-git; \
        # jupyter serverextension enable --py jupyterlab_git; # Moved to jupyterlab-git package
    fi && \
    if [ "${WORKSPACE_FLAVOR}" = "full" ]; then \
        # ${LAB_EXT_INSTALL} jupyter-matplotlib && # Already installed via pip in data science basics, no separate labext needed for new versions
        pip install jupyterlab-lsp==3.11.0 jupyter-lsp==1.5.0 && \
        ${LAB_EXT_INSTALL} jupyterlab-plotly && \
        ${LAB_EXT_INSTALL} @jupyter-widgets/jupyterlab-manager plotlywidget && \
        ${LAB_EXT_INSTALL} jupyterlab-chart-editor && \
        pip install lckr-jupyterlab-variableinspector && \
        ${LAB_EXT_INSTALL} @ryantam626/jupyterlab_code_formatter && \
        pip install jupyterlab_code_formatter && \
        jupyter serverextension enable --py jupyterlab_code_formatter; \
    fi && \
    # Final build after all extensions are installed
    jupyter lab build --dev-build=False --minimize=True --debug-log-path=/dev/stdout --log-level=WARN && \
    jupyter lab clean --all && \
    jlpm cache clean && \
    rm -rf ${CONDA_ROOT}/share/jupyter/lab/staging && \
    clean-layer.sh

# Install Jupyter Tooling Extension
COPY resources/jupyter/extensions ${RESOURCES_PATH}/jupyter-extensions
RUN pip install --no-cache-dir ${RESOURCES_PATH}/jupyter-extensions/tooling-extension/ && \
    clean-layer.sh

# Install and activate ZSH & Git LFS
COPY resources/tools/oh-my-zsh.sh ${RESOURCES_PATH}/tools/oh-my-zsh.sh
COPY resources/tools/git-lfs.sh ${RESOURCES_PATH}/tools/git-lfs.sh

RUN /bin/bash ${RESOURCES_PATH}/tools/oh-my-zsh.sh --install && \
    conda init zsh && \
    chsh -s $(which zsh) ${NB_USER} && \
    curl -s "https://get.sdkman.io" | bash && \
    clean-layer.sh && \
    /bin/bash ${RESOURCES_PATH}/tools/git-lfs.sh --install && \
    clean-layer.sh

### VSCODE EXTENSIONS ###
RUN \
    if [ "${WORKSPACE_FLAVOR}" != "minimal" ]; then \
        mkdir -p ${HOME}/.vscode/extensions/ && \
        # Use updated versions for VS Code extensions (check Marketplace for latest)
        # Jupyter Extension
        VS_JUPYTER_VERSION="2024.3.0" && \
        wget --no-verbose "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-toolsai/vsextensions/jupyter/${VS_JUPYTER_VERSION}/vspackage" -O ms-toolsai.jupyter-${VS_JUPYTER_VERSION}.vsix && \
        bsdtar -xf ms-toolsai.jupyter-${VS_JUPYTER_VERSION}.vsix extension && \
        rm ms-toolsai.jupyter-${VS_JUPYTER_VERSION}.vsix && \
        mv extension ${HOME}/.vscode/extensions/ms-toolsai.jupyter-${VS_JUPYTER_VERSION} && \
        # Python Extension
        VS_PYTHON_VERSION="2024.4.1" && \
        wget --no-verbose "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/ms-python/vsextensions/python/${VS_PYTHON_VERSION}/vspackage" -O ms-python.python-${VS_PYTHON_VERSION}.vsix && \
        bsdtar -xf ms-python.python-${VS_PYTHON_VERSION}.vsix extension && \
        rm ms-python.python-${VS_PYTHON_VERSION}.vsix && \
        mv extension ${HOME}/.vscode/extensions/ms-python.python-${VS_PYTHON_VERSION}; \
    fi && \
    if [ "${WORKSPACE_FLAVOR}" = "full" ]; then \
        # Prettier
        PRETTIER_VERSION="10.2.0" && \
        wget --no-verbose "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/esbenp/vsextensions/prettier-vscode/${PRETTIER_VERSION}/vspackage" -O esbenp.prettier-vscode-${PRETTIER_VERSION}.vsix && \
        bsdtar -xf esbenp.prettier-vscode-${PRETTIER_VERSION}.vsix extension && \
        rm esbenp.prettier-vscode-${PRETTIER_VERSION}.vsix && \
        mv extension ${HOME}/.vscode/extensions/esbenp.prettier-vscode-${PRETTIER_VERSION} && \
        # Code Runner
        VS_CODE_RUNNER_VERSION="0.12.0" && \
        wget --no-verbose "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/formulahendry/vsextensions/code-runner/${VS_CODE_RUNNER_VERSION}/vspackage" -O formulahendry.code-runner-${VS_CODE_RUNNER_VERSION}.vsix && \
        bsdtar -xf formulahendry.code-runner-${VS_CODE_RUNNER_VERSION}.vsix extension && \
        rm formulahendry.code-runner-${VS_CODE_RUNNER_VERSION}.vsix && \
        mv extension ${HOME}/.vscode/extensions/formulahendry.code-runner-${VS_CODE_RUNNER_VERSION} && \
        # ESLint
        VS_ESLINT_VERSION="3.0.0" && \
        wget --no-verbose "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/dbaeumer/vsextensions/vscode-eslint/${VS_ESLINT_VERSION}/vspackage" -O dbaeumer.vscode-eslint-${VS_ESLINT_VERSION}.vsix && \
        bsdtar -xf dbaeumer.vscode-eslint-${VS_ESLINT_VERSION}.vsix extension && \
        rm dbaeumer.vscode-eslint-${VS_ESLINT_VERSION}.vsix && \
        mv extension ${HOME}/.vscode/extensions/dbaeumer.vscode-eslint-${VS_ESLINT_VERSION}; \
    fi && \
    clean-layer.sh

# The `SLEEP_TIMER` for VS Code extension downloads is usually not needed when
# directly downloading .vsix files via `wget`. It was more common with `code-server --install-extension`
# which could hit rate limits or require time for the server to spin up.

# Final cleanup before finishing
RUN apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set the default command for the container
CMD ["/usr/local/bin/start.sh"]
