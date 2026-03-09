#!/usr/bin/env bash
# Automated deploy script (repo is cloned from GitHub; paths are relative to the repo directory).
#
# Typical workflow:
#   1. On host: git clone <repo> /docker  (or any directory)
#   2. Fill in .env
#   3. ./deploy.sh  — deploy to /usr/local/bin/docker/${PROJECT_NAME}
#   4. cd /usr/local/bin/docker/${PROJECT_NAME} && docker compose up -d
#
# Run: ./deploy.sh  or  bash deploy.sh

set -e

# Repo directory (all paths to repo files are relative to it)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck source=.env
  source .env
  set +a
else
  echo "File .env not found. Using PROJECT_NAME=radio by default."
  PROJECT_NAME="${PROJECT_NAME:-radio}"
fi

PROJECT_NAME="${PROJECT_NAME:-radio}"
# Base directory is always /usr/local/bin/docker; projects are subdirectories inside it
BASE_DIR="/usr/local/bin/docker"
LOG_DIR="/var/log/docker"
TARGET_DIR="${BASE_DIR}/${PROJECT_NAME}"
LOG_PROJECT_DIR="${LOG_DIR}/${PROJECT_NAME}"
TARGET_LOG_ICECAST="${LOG_PROJECT_DIR}/icecast"
TARGET_LOG_NGINX="${LOG_PROJECT_DIR}/nginx"
# When run with sudo, owner is the user who invoked sudo
CURRENT_USER="${SUDO_USER:-$USER}"
CURRENT_GROUP="$CURRENT_USER"
if command -v id &>/dev/null; then
  CURRENT_GROUP="$(id -gn "$CURRENT_USER" 2>/dev/null)" || true
fi
[[ -z "$CURRENT_GROUP" ]] && CURRENT_GROUP="$CURRENT_USER"

# Check if port is in use and find first available for external Icecast access
is_port_free() {
  local port="$1"
  if command -v ss &>/dev/null; then
    ! ss -tuln 2>/dev/null | grep -qE ":${port}([^0-9]|$)"
  elif command -v netstat &>/dev/null; then
    ! netstat -tuln 2>/dev/null | grep -qE ":${port}([^0-9]|$)"
  else
    return 0
  fi
}

find_available_port() {
  local start="${1:-38000}"
  local port="$start"
  while ! is_port_free "$port"; do
    ((port++))
    [[ $port -gt 65535 ]] && { echo -n ""; return 1; }
  done
  echo -n "$port"
}

PORT_ICECAST_EXTERNAL="${PORT_ICECAST_EXTERNAL:-38000}"
if ! is_port_free "$PORT_ICECAST_EXTERNAL"; then
  found=$(find_available_port $((PORT_ICECAST_EXTERNAL + 1)))
  if [[ -z "$found" ]]; then
    echo "Error: could not find a free port (searched from $((PORT_ICECAST_EXTERNAL + 1)) to 65535)."
    exit 1
  fi
  PORT_ICECAST_EXTERNAL="$found"
  echo "Port from .env is in use; using first available: ${PORT_ICECAST_EXTERNAL}"
  echo ""
fi

echo "=== Deploying project: ${PROJECT_NAME} ==="
echo "Project dir:   ${TARGET_DIR}"
echo "Log dir:       ${LOG_PROJECT_DIR} (icecast, nginx)"
echo "External port: ${PORT_ICECAST_EXTERNAL} (host → Icecast)"
echo "Owner:         ${CURRENT_USER}:${CURRENT_GROUP}"
echo ""

# Check for Docker; install if missing
ensure_docker() {
  if command -v docker &>/dev/null; then
    echo "Docker is installed. Checking service..."
    sudo systemctl start docker 2>/dev/null || true
    return 0
  fi
  echo "Docker not found. Running installer..."
  if [[ -x "$SCRIPT_DIR/install-docker.sh" ]]; then
    sudo "$SCRIPT_DIR/install-docker.sh"
  else
    echo "Error: install-docker.sh not found or not executable (chmod +x install-docker.sh)."
    exit 1
  fi
}

ensure_docker
echo ""

# Create directories: /usr/local/bin/docker always; if missing, create and assign ownership to user
create_dirs() {
  if [[ ! -d "$BASE_DIR" ]]; then
    echo "Creating base directory: ${BASE_DIR}"
    sudo mkdir -p "$BASE_DIR"
    sudo chown "${CURRENT_USER}:${CURRENT_GROUP}" "$BASE_DIR"
  else
    echo "Base directory already exists: ${BASE_DIR}"
  fi

  if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Creating project directory: ${TARGET_DIR}"
    sudo mkdir -p "$TARGET_DIR"
  else
    echo "Project directory already exists: ${TARGET_DIR}"
  fi

  if [[ ! -d "$TARGET_DIR/conf" ]]; then
    echo "Creating directory: ${TARGET_DIR}/conf"
    sudo mkdir -p "${TARGET_DIR}/conf"
  fi

  if [[ ! -d "$TARGET_LOG_ICECAST" ]]; then
    echo "Creating log directory: ${TARGET_LOG_ICECAST}"
    sudo mkdir -p "$TARGET_LOG_ICECAST"
  else
    echo "Icecast log directory already exists: ${TARGET_LOG_ICECAST}"
  fi
  if [[ ! -d "$TARGET_LOG_NGINX" ]]; then
    echo "Creating log directory: ${TARGET_LOG_NGINX}"
    sudo mkdir -p "$TARGET_LOG_NGINX"
  else
    echo "Nginx log directory already exists: ${TARGET_LOG_NGINX}"
  fi
}

# Set ownership: icecast log dir to 1000:1000 (for container). Project dir chown is done once at the end.
set_ownership() {
  echo "Setting owner 1000:1000 for icecast logs..."
  sudo chown -R 1000:1000 "${TARGET_LOG_ICECAST}"
}

create_dirs
set_ownership

# Copy icecast_example.xml to conf/${PROJECT_NAME}.xml (name matches path in docker-compose)
deploy_icecast_conf() {
  local src="$SCRIPT_DIR/conf/icecast_example.xml"
  local dest="${TARGET_DIR}/conf/${PROJECT_NAME}.xml"
  if [[ ! -f "$src" ]]; then
    echo "Skipping: template $src not found."
    return 0
  fi
  # If dest exists as a directory (e.g. from a previous error), remove it so we can create the file
  [[ -d "$dest" ]] && sudo rm -rf "$dest"
  # MAX_LISTENERS in template — use LIMITS_CLIENTS if not set
  export MAX_LISTENERS="${MAX_LISTENERS:-$LIMITS_CLIENTS}"
  export LIMITS_MAX_BANDWIDTH="${LIMITS_MAX_BANDWIDTH:-200M}"
  export PROJECT_NAME_ICECAST PROJECT_NAME_ICECAST_ADMIN LIMITS_CLIENTS LIMITS_SOURCES
  export SOURCE_PASSWORD RELAY_PASSWORD ADMIN_LOGIN ADMIN_PASSWORD PORT_ICECAST
  export NAME_MAIN_MOUNT STREAM_NAME STREAM_DESCRIPTION STREAM_GENRE STREAM_URL
  export NAME_FALLBACK_MOUNT IP_ADDRESS_GATEWAY
  if command -v envsubst &>/dev/null; then
    envsubst '$PROJECT_NAME_ICECAST $PROJECT_NAME_ICECAST_ADMIN $LIMITS_CLIENTS $LIMITS_SOURCES $LIMITS_MAX_BANDWIDTH $SOURCE_PASSWORD $RELAY_PASSWORD $ADMIN_LOGIN $ADMIN_PASSWORD $PORT_ICECAST $NAME_MAIN_MOUNT $MAX_LISTENERS $STREAM_NAME $STREAM_DESCRIPTION $STREAM_GENRE $STREAM_URL $NAME_FALLBACK_MOUNT $IP_ADDRESS_GATEWAY' < "$src" > "$dest"
  else
    echo "envsubst not found; copying template without substitution."
    cp "$src" "$dest"
  fi
  echo "Created config: ${dest} (mounted in compose as conf/${PROJECT_NAME}.xml)"
}

deploy_icecast_conf

# Copy docker-compose.yml to deploy directory (substitution from .env)
deploy_compose() {
  if [[ -z "${IP_ADDRESS}" ]] || [[ -z "${IP_ADDRESS_GATEWAY}" ]]; then
    echo "Error: .env must define IP_ADDRESS and IP_ADDRESS_GATEWAY for docker-compose."
    exit 1
  fi
  local src="$SCRIPT_DIR/conf/docker-compose.yml"
  local dest="${TARGET_DIR}/docker-compose.yml"
  [[ -d "$dest" ]] && sudo rm -rf "$dest"
  if [[ ! -f "$src" ]]; then
    echo "Skipping: $src not found."
    return 0
  fi
  # SUBNET default from IP_ADDRESS or fixed value
  if [[ -n "${SUBNET}" ]]; then
    export SUBNET
  elif [[ -n "${IP_ADDRESS}" ]]; then
    export SUBNET="${IP_ADDRESS%.*}.0/24"
  else
    export SUBNET="172.29.10.0/24"
  fi
  export PROJECT_NAME PORT_ICECAST_EXTERNAL PORT_ICECAST IP_ADDRESS IP_ADDRESS_GATEWAY
  if command -v envsubst &>/dev/null; then
    envsubst '$PROJECT_NAME $PORT_ICECAST_EXTERNAL $PORT_ICECAST $IP_ADDRESS $IP_ADDRESS_GATEWAY $SUBNET' < "$src" > "$dest"
  else
    cp "$src" "$dest"
  fi
  echo "Created: ${dest}"
}

deploy_compose

# Single place: chown -R project dir to current user (so no sudo needed for edits)
echo "Setting owner ${CURRENT_USER}:${CURRENT_GROUP} for /usr/local/bin/docker/${PROJECT_NAME}..."
sudo chown -R "${CURRENT_USER}:${CURRENT_GROUP}" "$TARGET_DIR"

echo ""
echo "Starting stack: docker compose up -d in ${TARGET_DIR}..."
if docker compose -f "${TARGET_DIR}/docker-compose.yml" --project-directory "$TARGET_DIR" up -d; then
  echo "Stack started."
else
  echo "Failed to start (e.g. permission denied). Run: newgrp docker   then: cd ${TARGET_DIR} && docker compose up -d"
fi
echo ""
echo "Done. Manage: cd ${TARGET_DIR} && docker compose logs -f"
