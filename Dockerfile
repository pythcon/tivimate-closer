# TiviMate Closer - Docker Image
FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && apt-get install -y \
    android-tools-adb \
    bash \
    coreutils \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories
RUN mkdir -p /app /data /data/logs /root/.android

# Set working directory
WORKDIR /app

# Copy script
COPY tivimate-closer.sh /app/

# Make script executable
RUN chmod +x /app/tivimate-closer.sh

# Start ADB server on container start
RUN adb start-server 2>/dev/null || true

# Default environment variables
ENV DURATION=10800 \
    WAIT_TIME=30 \
    PACKAGE_NAME="ar.tvplayer.tv" \
    WARNING_MESSAGE="Are you still watching? (closing in 30 seconds)" \
    TRACKFILE="/data/onn_tracking.log" \
    LOG_DIR="/data/logs" \
    ADB_PORT=5555 \
    CHECK_INTERVAL=60 \
    SERVICE_MODE=true \
    ACTIVITY_RESUME_PATTERN="ResumedActivity" \
    DEVICE_IPS=""

# Health check
HEALTHCHECK --interval=60s --timeout=10s --start-period=10s --retries=3 \
    CMD pgrep -f tivimate-closer.sh || exit 1

# Run the service - script runs in service mode when SERVICE_MODE=true
# Device IPs are passed as arguments split from comma-separated DEVICE_IPS env var
CMD ["/bin/bash", "-c", "/app/tivimate-closer.sh -s ${DEVICE_IPS//,/ }"]
