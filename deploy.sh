#!/usr/bin/env bash
# Automated deploy script (repo is cloned from GitHub; paths are relative to the repo directory).
#
# Typical workflow:
#   1. On host: git clone <repo> /docker  (or any directory)
#   2. Fill in .env
#   3. From the clone: ./deploy.sh  — copies to /usr/local/bin/docker/${PROJECT_NAME}
#      (conf/icecast-web/: vendored in git or auto-downloaded from xiph/Icecast-Server when missing)
#   4. cd /usr/local/bin/docker/${PROJECT_NAME} && docker compose up -d  (only if deploy did not start the stack)
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
# Base directory is always /usr/local/bin/docker; projects are subdirectories inside it; logs next to compose
BASE_DIR="/usr/local/bin/docker"
TARGET_DIR="${BASE_DIR}/${PROJECT_NAME}"
TARGET_LOG_ICECAST="${TARGET_DIR}/logs/icecast"
TARGET_LOG_NGINX="${TARGET_DIR}/logs/nginx"
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
fi

# --- Compact status output ---
echo "--- Deploy: ${PROJECT_NAME} (port ${PORT_ICECAST_EXTERNAL}, ${CURRENT_USER}) ---"
echo ""

# Check for Docker; install if missing
ensure_docker() {
  if command -v docker &>/dev/null; then
    sudo systemctl start docker 2>/dev/null || true
    echo "[OK] Docker is running"
    return 0
  fi
  echo "Docker not found, starting install..."
  if [[ -x "$SCRIPT_DIR/install-docker.sh" ]]; then
    sudo "$SCRIPT_DIR/install-docker.sh" 2>&1 | tail -5
    echo "[OK] Docker installed"
  else
    echo "Error: install-docker.sh not found or not executable (chmod +x install-docker.sh)."
    exit 1
  fi
}

ensure_docker
echo ""

# Optional: configure iptables rules for Docker bridge of this project
ensure_iptables() {
  command -v iptables &>/dev/null || return 1
  sudo iptables -L INPUT -n &>/dev/null || return 1
  return 0
}

add_project_iptables_rules() {
  local bridge="br-${PROJECT_NAME}"

  if ! ensure_iptables; then
    return 0
  fi

  if ! ip link show "$bridge" &>/dev/null; then
    return 0
  fi

  # iptables -C: avoid duplicate rules on repeated deploys
  if ! sudo iptables -C INPUT -i "$bridge" -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment "Allow established and related connections from docker" -j ACCEPT 2>/dev/null; then
    sudo iptables -I INPUT 3 -i "$bridge" -m conntrack --ctstate RELATED,ESTABLISHED -m comment --comment "Allow established and related connections from docker" -j ACCEPT 2>/dev/null || true
  fi
  if ! sudo iptables -C INPUT -i "$bridge" -m conntrack --ctstate NEW -m comment --comment "Allow new connections from docker" -j ACCEPT 2>/dev/null; then
    sudo iptables -I INPUT 4 -i "$bridge" -m conntrack --ctstate NEW -m comment --comment "Allow new connections from docker" -j ACCEPT 2>/dev/null || true
  fi
  echo "[OK] iptables rules for br-${PROJECT_NAME}"
}

# Create directories: /usr/local/bin/docker always; if missing, create and assign ownership to user
create_dirs() {
  if [[ ! -d "$BASE_DIR" ]]; then
    sudo mkdir -p "$BASE_DIR"
    sudo chown "${CURRENT_USER}:${CURRENT_GROUP}" "$BASE_DIR"
  fi
  sudo mkdir -p "$TARGET_DIR" "$TARGET_DIR/conf" "$TARGET_LOG_ICECAST" "$TARGET_LOG_NGINX" 2>/dev/null || true
  echo "[OK] Directories: ${TARGET_DIR}, logs ${TARGET_DIR}/logs"
}

# Set ownership: icecast log dir to 1000:1000 (for container). Project dir chown is done once at the end.
set_ownership() {
  sudo chown -R 1000:1000 "${TARGET_LOG_ICECAST}" 2>/dev/null || true
  echo "[OK] Icecast log dir owner: 1000:1000"
}

create_dirs
set_ownership

# Copy icecast_example.xml to conf/${PROJECT_NAME}.xml (name matches path in docker-compose)
deploy_icecast_conf() {
  local src="$SCRIPT_DIR/conf/icecast_example.xml"
  local dest="${TARGET_DIR}/conf/${PROJECT_NAME}.xml"
  if [[ ! -f "$src" ]]; then
    return 0
  fi
  [[ -d "$dest" ]] && sudo rm -rf "$dest"
  export MAX_LISTENERS="${MAX_LISTENERS:-$LIMITS_CLIENTS}"
  export LIMITS_MAX_BANDWIDTH="${LIMITS_MAX_BANDWIDTH:-200M}"
  export PROJECT_NAME_ICECAST PROJECT_NAME_ICECAST_ADMIN LIMITS_CLIENTS LIMITS_SOURCES
  export SOURCE_PASSWORD RELAY_PASSWORD ADMIN_LOGIN ADMIN_PASSWORD PORT_ICECAST
  export NAME_MAIN_MOUNT STREAM_NAME STREAM_DESCRIPTION STREAM_GENRE STREAM_URL
  export NAME_FALLBACK_MOUNT IP_ADDRESS_GATEWAY
  if command -v envsubst &>/dev/null; then
    envsubst '$PROJECT_NAME_ICECAST $PROJECT_NAME_ICECAST_ADMIN $LIMITS_CLIENTS $LIMITS_SOURCES $LIMITS_MAX_BANDWIDTH $SOURCE_PASSWORD $RELAY_PASSWORD $ADMIN_LOGIN $ADMIN_PASSWORD $PORT_ICECAST $NAME_MAIN_MOUNT $MAX_LISTENERS $STREAM_NAME $STREAM_DESCRIPTION $STREAM_GENRE $STREAM_URL $NAME_FALLBACK_MOUNT $IP_ADDRESS_GATEWAY' < "$src" > "$dest"
  else
    cp "$src" "$dest"
  fi
  echo "[OK] Icecast config: conf/${PROJECT_NAME}.xml"
}

deploy_icecast_conf

# Fetch a single file from Xiph Icecast-Server web/ into dest (writes via sudo).
icecast_web_download_xiph() {
  local url="$1" dest="$2"
  local tmp
  tmp="$(mktemp)" || return 1
  if command -v curl &>/dev/null && curl -fsSL "$url" -o "$tmp" 2>/dev/null; then
    sudo cp "$tmp" "$dest"
    rm -f "$tmp"
    return 0
  fi
  if command -v wget &>/dev/null && wget -qO "$tmp" "$url" 2>/dev/null; then
    sudo cp "$tmp" "$dest"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Icecast web: prefer ./conf/icecast-web/ from the repo; missing files are downloaded from xiph/Icecast-Server.
deploy_icecast_web() {
  local src_dir="$SCRIPT_DIR/conf/icecast-web"
  local dest_dir="${TARGET_DIR}/conf/icecast-web"
  local script_root target_root
  local xiph="https://raw.githubusercontent.com/xiph/Icecast-Server/master/web"
  script_root="$(cd "$SCRIPT_DIR" && pwd -P)"
  target_root="$(cd "$TARGET_DIR" && pwd -P)"

  sudo mkdir -p "$src_dir"

  for f in status-json.xsl xml2json.xslt; do
    if [[ -f "$src_dir/$f" ]]; then
      continue
    fi
    echo "[..] Downloading conf/icecast-web/$f from Xiph..."
    if ! icecast_web_download_xiph "${xiph}/${f}" "$src_dir/$f"; then
      echo "[FAIL] Could not download ${xiph}/${f} (need curl or wget and network). See conf/icecast-web/README.md."
      exit 1
    fi
  done

  # Same tree as deploy target: never rm+cp icecast-web (would delete sources).
  if [[ "$script_root" == "$target_root" ]]; then
    sudo chown -R "${CURRENT_USER}:${CURRENT_GROUP}" "$src_dir" 2>/dev/null || true
    echo "[OK] Icecast web overrides: conf/icecast-web (status-json.xsl, xml2json.xslt)"
    return 0
  fi

  sudo rm -rf "$dest_dir"
  sudo mkdir -p "$dest_dir"
  for f in status-json.xsl xml2json.xslt; do
    sudo cp "$src_dir/$f" "$dest_dir/$f"
  done
  sudo chown -R "${CURRENT_USER}:${CURRENT_GROUP}" "$dest_dir" 2>/dev/null || true
  echo "[OK] Icecast web overrides: conf/icecast-web (status-json.xsl, xml2json.xslt)"
}

deploy_icecast_web

# Copy nginx_example.conf to conf/${PROJECT_NAME_ICECAST}.conf with .env substitution
deploy_nginx_conf() {
  local name="${PROJECT_NAME_ICECAST:-$PROJECT_NAME}"
  local src="$SCRIPT_DIR/conf/nginx_example.conf"
  local dest="${TARGET_DIR}/conf/${name}.conf"
  if [[ ! -f "$src" ]]; then
    return 0
  fi
  [[ -f "$dest" ]] && sudo rm -f "$dest"
  export DOMAIN_NAME PROJECT_NAME NAME_MAIN_MOUNT NAME_FALLBACK_MOUNT PORT_ICECAST_EXTERNAL
  if command -v envsubst &>/dev/null; then
    envsubst '$DOMAIN_NAME $PROJECT_NAME $NAME_MAIN_MOUNT $NAME_FALLBACK_MOUNT $PORT_ICECAST_EXTERNAL' < "$src" > "$dest"
  else
    cp "$src" "$dest"
  fi
  echo "[OK] Nginx config: conf/${name}.conf"
}

deploy_nginx_conf

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
    return 0
  fi
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
  echo "[OK] docker-compose.yml"
}

deploy_compose

sudo chown -R "${CURRENT_USER}:${CURRENT_GROUP}" "$TARGET_DIR" 2>/dev/null || true
echo "[OK] Project owner: ${CURRENT_USER}"
echo ""

compose_out="$(docker compose -f "${TARGET_DIR}/docker-compose.yml" --project-directory "$TARGET_DIR" up -d 2>&1)" || compose_rc=$?
if [[ -z "${compose_rc:-}" ]]; then
  echo "[OK] Stack started"
  add_project_iptables_rules
else
  echo "[FAIL] Stack start failed. Docker output:"
  echo "$compose_out"
  echo "Often: no permission on the Docker socket — run: newgrp docker   or log out and back in; then: cd ${TARGET_DIR} && docker compose up -d"
fi
unset compose_rc 2>/dev/null || true

# One-line service check
SERVICE_URL="http://127.0.0.1:${PORT_ICECAST_EXTERNAL}"
if command -v curl &>/dev/null; then
  sleep 3
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$SERVICE_URL/" 2>/dev/null) || code=""
  if [[ -n "$code" && "$code" =~ ^[0-9]+$ ]]; then
    if [[ "$code" == "200" ]]; then
      CURL_RESULT="${SERVICE_URL} → 200 OK"
    else
      CURL_RESULT="${SERVICE_URL} → ${code}"
    fi
  else
    CURL_RESULT="${SERVICE_URL} → unreachable"
  fi
else
  CURL_RESULT="(curl not installed)"
fi

echo ""
echo "--- Done ---"
echo "  Project: ${TARGET_DIR}"
echo "  Service: ${CURL_RESULT}"
echo "  Logs:    cd ${TARGET_DIR} && docker compose logs -f"
echo ""
