#!/usr/bin/env bash
# Установка Docker (Ubuntu) из официального репозитория
# Запуск: sudo ./install-docker.sh

set -e

if [[ $EUID -ne 0 ]]; then
  echo "Запустите скрипт с правами root: sudo $0"
  exit 1
fi

echo "=== Установка Docker ==="

# Проверка: уже установлен?
if command -v docker &>/dev/null && docker --version &>/dev/null; then
  echo "Docker уже установлен: $(docker --version)"
  docker compose version 2>/dev/null || true
  exit 0
fi

echo "Обновление пакетов и установка зависимостей..."
apt update
apt install -y ca-certificates curl gnupg

echo "Добавление ключа и репозитория Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "Установка пакетов Docker..."
apt update
apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

echo "Добавление пользователя ${SUDO_USER:-$USER} в группу docker..."
usermod -aG docker "${SUDO_USER:-$USER}"

echo "Запуск и включение службы Docker..."
systemctl start docker
systemctl enable docker

echo ""
echo "Docker установлен: $(docker --version)"
docker compose version 2>/dev/null || true
echo ""
echo "Чтобы использовать docker без sudo, выполните один из вариантов:"
echo "  - выйти из сессии и войти снова;"
echo "  - или выполнить: newgrp docker"
