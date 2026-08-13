# =============================================================================
# Single-stage: copy pre-built JS artifacts, install production deps in container
# No compilation — JS files are cross-platform, native addons are installed
# inside the container (Linux) via pnpm install --prod.
# =============================================================================
FROM node:22-bookworm-slim

# Build tools for node-pty native addon compilation (node-gyp needs python3 + make + g++)
# Runtime python3 is also needed for the sandbox runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Enable corepack and install pinned pnpm version
RUN corepack enable && corepack prepare pnpm@11.7.0 --activate

# Create a non-root user for security
RUN groupadd -r dsh && useradd -r -g dsh -m -d /home/dsh dsh

WORKDIR /app

# Copy pre-built JS artifacts from local build context
# These are produced by running `pnpm run build` on a local dev machine.
# JS files are cross-platform; native addons are installed below.
COPY apps/cli/lib/ apps/cli/lib/
COPY apps/cli/config/ apps/cli/config/
COPY apps/cli/package.json apps/cli/package.json
COPY apps/web/dist/ apps/web/dist/
COPY apps/web/package.json apps/web/package.json
COPY packages/ packages/

# Copy vendor, patches and manifests for dependency installation
COPY vendor/ vendor/
COPY patches/ patches/
COPY pnpm-lock.yaml pnpm-workspace.yaml package.json ./

# Proxy support (pass via --build-arg)
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

# Limit Node.js memory to prevent OOM on low-memory servers
ENV NODE_OPTIONS="--max-old-space-size=1024"

# Install production dependencies only (no devDependencies, no build)
# This ensures native addons (node-pty, etc.) are compiled for Linux
# inside the container, not Windows.
# --child-concurrency=1: run one install script at a time (reduces memory)
# --network-concurrency=4: limit parallel downloads (reduces memory, slower)
RUN if [ -n "$HTTP_PROXY" ]; then \
        export HTTP_PROXY="$HTTP_PROXY" && \
        export HTTPS_PROXY="$HTTPS_PROXY" && \
        export http_proxy="$HTTP_PROXY" && \
        export https_proxy="$HTTPS_PROXY" && \
        export NO_PROXY="$NO_PROXY"; \
    fi && \
    pnpm install --prod --frozen-lockfile \
      --child-concurrency=1 \
      --network-concurrency=4

# Copy entrypoint and patch file
COPY docker/entrypoint.sh /usr/local/bin/dsh-entrypoint
COPY docker/dsh.patch.yml /app/docker/dsh.patch.yml
RUN chmod +x /usr/local/bin/dsh-entrypoint

# Environment
ENV DSH_HOME=/home/dsh/.dsh
ENV DSH_TELEMETRY_DISABLED=1

EXPOSE 3000

USER dsh
WORKDIR /home/dsh

ENTRYPOINT ["dsh-entrypoint"]
