#!/usr/bin/env bash
# Install Docker (Ubuntu) from the official repository
# Run: sudo ./install-docker.sh

set -e

if [[ $EUID -ne 0 ]]; then
  echo "Run this script as root: sudo $0"
  exit 1
fi

echo "=== Installing Docker ==="

# Check: already installed?
if command -v docker &>/dev/null && docker --version &>/dev/null; then
  echo "Docker is already installed: $(docker --version)"
  docker compose version 2>/dev/null || true
  exit 0
fi

echo "Updating packages and installing dependencies..."
apt update
apt install -y ca-certificates curl gnupg

echo "Adding Docker key and repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Installing Docker packages..."
apt update
apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

echo "Adding user ${SUDO_USER:-$USER} to group docker..."
usermod -aG docker "${SUDO_USER:-$USER}"

echo "Starting and enabling Docker service..."
systemctl start docker
systemctl enable docker

echo ""
echo "Docker installed: $(docker --version)"
docker compose version 2>/dev/null || true
echo ""
echo "To use docker without sudo, either:"
echo "  - log out and log back in, or"
echo "  - run: newgrp docker"
