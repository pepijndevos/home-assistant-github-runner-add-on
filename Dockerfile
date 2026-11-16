ARG BUILD_FROM

# Build openFPGALoader from source: Debian's 0.13.1 cannot select between
# several DirtyJTAG probes. Pinned to trabucayre/openFPGALoader#762.
FROM $BUILD_FROM AS openfpgaloader
ARG OPENFPGALOADER_REPO=https://github.com/pepijndevos/openFPGALoader.git
ARG OPENFPGALOADER_REF=e905ec1f28de3b9bebe8d388d6a02cd49be7008c
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates git cmake g++ make pkg-config \
    libftdi1-dev libusb-1.0-0-dev libhidapi-dev libudev-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
RUN git clone "$OPENFPGALOADER_REPO" /src \
    && git -C /src checkout "$OPENFPGALOADER_REF" \
    && cmake -S /src -B /build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local \
    && cmake --build /build -j"$(nproc)" \
    && DESTDIR=/out cmake --install /build

FROM $BUILD_FROM

# Set shell
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    curl \
    git \
    jq \
    tar \
    unzip \
    sudo \
    ca-certificates \
    python3 \
    python3-pip \
    python3-venv \
    nodejs \
    npm \
    # HIL test dependencies
    make \
    libftdi1-2 \
    libusb-1.0-0 \
    libhidapi-libusb0 \
    libudev1 \
    gawk \
    coreutils \
    usbutils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=openfpgaloader /out/usr/local/ /usr/local/
RUN openFPGALoader --help | grep -q usb-serial-num

# Create a non-root user for running the GitHub Actions runner
# Add to plugdev/dialout for USB and serial device access (openFPGALoader, UART)
RUN useradd -m -u 1000 -G plugdev,dialout runner

# Set up runner directory
RUN mkdir -p /runner && chmod 755 /runner
WORKDIR /runner

# Download and install GitHub Actions Runner
ARG BUILD_ARCH
RUN RUNNER_VERSION=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r '.tag_name' | sed 's/v//') && \
    if [ "$BUILD_ARCH" = "amd64" ]; then \
        RUNNER_ARCH="x64"; \
    elif [ "$BUILD_ARCH" = "aarch64" ]; then \
        RUNNER_ARCH="arm64"; \
    elif [ "$BUILD_ARCH" = "armv7" ] || [ "$BUILD_ARCH" = "armhf" ]; then \
        RUNNER_ARCH="arm"; \
    else \
        RUNNER_ARCH="x64"; \
    fi && \
    echo "Downloading runner for architecture: ${RUNNER_ARCH}" && \
    curl -o actions-runner.tar.gz -L "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz" && \
    tar xzf actions-runner.tar.gz && \
    rm actions-runner.tar.gz && \
    ./bin/installdependencies.sh && \
    chown -R runner:runner /runner

# Copy run script
COPY run.sh /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
