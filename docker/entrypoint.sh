#!/bin/sh
# =============================================================================
# dsh container entrypoint
# =============================================================================
set -e

# Ensure DSH_HOME and required subdirectories exist
mkdir -p "${DSH_HOME}/profiles"
mkdir -p "${DSH_HOME}/plugins"

# Initialize the web profile if it doesn't exist
if [ ! -f "${DSH_HOME}/profiles/web/cordis.yml" ]; then
  echo "Initializing web profile..."
  node /app/apps/cli/lib/bin.js --profile web --dump-default-config > /dev/null 2>&1 || true
fi

# Start the dsh web server.
# --port 3000: mapped to host via docker-compose ports.
# --patch: override webserver host to 0.0.0.0 (the CLI rejects --host 0.0.0.0
#   for safety, but in a container we use port mapping so it's intentional).
echo "Starting dsh web server..."
exec node /app/apps/cli/lib/bin.js web \
  --port 3000 \
  --patch /app/docker/dsh.patch.yml \
  "$@"