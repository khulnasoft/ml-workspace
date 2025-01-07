ARG ARG_WORKSPACE_BASE_IMAGE="khulnasoft/ml-workspace:latest"
# Build from full flavor of workspace with same version
FROM $ARG_WORKSPACE_BASE_IMAGE AS build

ARG ARG_WORKSPACE_FLAVOR="gpu"
ENV WORKSPACE_FLAVOR=$ARG_WORKSPACE_FLAVOR

USER root

### NVIDIA CUDA BASE ###
# Install NVIDIA CUDA base libraries and tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg2 curl ca-certificates && \
    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64/7fa2af80.pub | apt-key add - && \
    echo "deb https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2004/x86_64 /" > /etc/apt/sources.list.d/cuda.list && \
    echo "deb https://developer.download.nvidia.com/compute/machine-learning/repos/ubuntu2004/x86_64 /" > /etc/apt/sources.list.d/nvidia-ml.list && \
    apt-get clean && \
    rm -rf $HOME/.cache/* && \
    rm -rf /tmp/* && \
    rm -rf /var/lib/apt/lists/*

ENV CUDA_VERSION 11.2.2

# Install CUDA runtime libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    cuda-cudart-11-2=11.2.152-1 \
    cuda-compat-11-2 \
    && ln -s cuda-11.2 /usr/local/cuda && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean && \
    rm -rf $HOME/.cache/* && \
    rm -rf /tmp/* && \
    rm -rf /var/lib/apt/lists/*

# Required for nvidia-docker v1
RUN echo "/usr/local/nvidia/lib" >> /etc/ld.so.conf.d/nvidia.conf \
    && echo "/usr/local/nvidia/lib64" >> /etc/ld.so.conf.d/nvidia.conf

ENV PATH /usr/local/nvidia/bin:/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH /usr/local/nvidia/lib:/usr/local/nvidia/lib64

# nvidia-container-runtime
ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES compute,utility
ENV NVIDIA_REQUIRE_CUDA "cuda>=11.2 brand=tesla,driver>=418,driver<419 brand=tesla,driver>=440,driver<441 driver>=450"

### CUDA RUNTIME ###
# Install CUDA runtime libraries
ENV NCCL_VERSION 2.8.4

RUN apt-get update && apt-get install -y --no-install-recommends \
    cuda-libraries-11-2=11.2.2-1 \
    libnpp-11-2=11.3.2.152-1 \
    cuda-nvtx-11-2=11.2.152-1 \
    libcublas-11-2=11.4.1.1043-1 \
    libcusparse-11-2=11.4.1.1152-1 \
    libnccl2=$NCCL_VERSION-1+cuda11.2 \
    && rm -rf /var/lib/apt/lists/* && \
    apt-get clean && \
    rm -rf $HOME/.cache/* && \
    rm -rf /tmp/* && \
    rm -rf /var/lib/apt/lists/*

RUN apt-mark hold libcublas-11-2 libnccl2

### CUDA DEVEL ###
# Install CUDA development libraries and tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    libtinfo5 libncursesw5 \
    cuda-cudart-dev-11-2=11.2.152-1 \
    cuda-command-line-tools-11-2=11.2.2-1 \
    cuda-minimal-build-11-2=11.2.2-1 \
    cuda-libraries-dev-11-2=11.2.2-1 \
    cuda-nvml-dev-11-2=11.2.152-1 \
    libnpp-dev-11-2=11.3.2.152-1 \
    libnccl-dev=2.8.4-1+cuda11.2 \
    libcublas-dev-11-2=11.4.1.1043-1 \
    libcusparse-dev-11-2=11.4.1.1152-1 && \
    apt-get clean && \
    rm -rf $HOME/.cache/* && \
    rm -rf /tmp/* && \
    rm -rf /var/lib/apt/lists/*

RUN apt-mark hold libcublas-dev-11-2 libnccl-dev
ENV LIBRARY_PATH /usr/local/cuda/lib64/stubs

### CUDANN8 DEVEL ###
# Install cuDNN libraries and tools
ENV CUDNN_VERSION 8.1.1.33
LABEL com.nvidia.cudnn.version="${CUDNN_VERSION}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    libcudnn8=$CUDNN_VERSION-1+cuda11.2 \
    libcudnn8-dev=$CUDNN_VERSION-1+cuda11.2 \
    && apt-mark hold libcudnn8 && \
    apt-get clean && \
    rm -rf /root/.cache/* && \
    rm -rf /tmp/* && \
    rm -rf /var/lib/apt/lists/*

# Link Cupti:
ENV LD_LIBRARY_PATH ${LD_LIBRARY_PATH}:/usr/local/cuda/extras/CUPTI/lib64

### GPU DATA SCIENCE LIBRARIES ###
# Install GPU data science libraries
RUN apt-get update && apt-get install -y libomp-dev libopenblas-base && \
    conda remove --force -y pytorch cpuonly && \
    conda install cudatoolkit=11.2 -c pytorch -c nvidia && \
    pip install --no-cache-dir torch==1.9.0+cu111 torchvision==0.10.0+cu111 torchaudio==0.9.0 -f https://download.pytorch.org/whl/torch_stable.html && \
    pip install --no-cache-dir cupy-cuda112==9.6.0 && \
    pip install --no-cache-dir pycuda==2021.1 && \
    pip install --no-cache-dir gpustat==0.6.0 py3nvml==0.2.6 gputil==1.4.0 && \
    pip install --no-cache-dir scikit-cuda==0.5.3 && \
    pip uninstall -y tensorflow tensorflow-cpu intel-tensorflow && \
    pip install --no-cache-dir tensorflow-gpu==2.5.0 && \
    pip uninstall -y onnxruntime && \
    pip install --no-cache-dir onnxruntime-gpu==1.8.0 onnxruntime-training==1.8.0 && \
    pip uninstall -y mxnet-mkl && \
    pip install --no-cache-dir mxnet-cu112==1.8.0 && \
    pip install --upgrade jax[cuda111]==0.2.12 -f https://storage.googleapis.com/jax-releases/jax_releases.html && \
    conda install -y pygpu && \
    pip uninstall -y lightgbm && \
    pip install lightgbm==3.2.1 --install-option=--gpu --install-option="--opencl-include-dir=/usr/local/cuda/include/" --install-option="--opencl-library=/usr/local/cuda/lib64/libOpenCL.so"  && \
    pip install --upgrade --force-reinstall nvidia-ml-py3==11.450.51 && \
    pip install --no-cache-dir SpeedTorch==0.1.0 && \
    pip install --no-cache-dir ipyexperiments==0.8.0 && \
    clean-layer.sh

ENV TF_FORCE_GPU_ALLOW_GROWTH true

### CONFIGURATION ###
# Configuration and labels
ARG ARG_WORKSPACE_VERSION="latest"
ENV WORKSPACE_VERSION=$ARG_WORKSPACE_VERSION

ARG ARG_BUILD_DATE="unknown"
ARG ARG_VCS_REF="unknown"

LABEL \
    "workspace.version"=$WORKSPACE_VERSION \
    "workspace.flavor"=$WORKSPACE_FLAVOR \
    "workspace.baseimage"=$ARG_WORKSPACE_BASE_IMAGE \
    "org.opencontainers.image.version"=$WORKSPACE_VERSION \
    "org.opencontainers.image.revision"=$ARG_VCS_REF \
    "org.opencontainers.image.created"=$ARG_BUILD_DATE \
    "org.label-schema.version"=$WORKSPACE_VERSION \
    "org.label-schema.vcs-ref"=$ARG_VCS_REF \
    "org.label-schema.build-date"=$ARG_BUILD_DATE

# Use a multi-stage build to reduce the image size
FROM build AS final

# Add a health check to monitor the container's status
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 CMD curl -f http://localhost:8080/ || exit 1

# Specify a non-root user for running the container
RUN useradd -m -s /bin/bash nonrootuser
USER nonrootuser
