#!/usr/bin/env bash
# Скрипт автоматического деплоя (репо клонируется с GitHub, пути к файлам — относительно каталога репо).
#
# Типичный сценарий:
#   1. На хосте: git clone <repo> /docker  (или любая папка)
#   2. Заполнить .env
#   3. ./deploy.sh  — деплой в /usr/local/bin/docker/${PROJECT_NAME}
#   4. cd /usr/local/bin/docker/${PROJECT_NAME} && docker compose up -d
#
# Запуск: ./deploy.sh  или  bash deploy.sh

set -e

# Каталог репо (все пути к файлам репо — относительно него)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ -f .env ]]; then
  set -a
  # shellcheck source=.env
  source .env
  set +a
else
  echo "Файл .env не найден. Используется PROJECT_NAME=radio по умолчанию."
  PROJECT_NAME="${PROJECT_NAME:-radio}"
fi

PROJECT_NAME="${PROJECT_NAME:-radio}"
# Базовый каталог — всегда /usr/local/bin/docker; проекты — подпапки внутри
BASE_DIR="/usr/local/bin/docker"
LOG_DIR="/var/log/docker"
TARGET_DIR="${BASE_DIR}/${PROJECT_NAME}"
LOG_PROJECT_DIR="${LOG_DIR}/${PROJECT_NAME}"
TARGET_LOG_ICECAST="${LOG_PROJECT_DIR}/icecast"
TARGET_LOG_NGINX="${LOG_PROJECT_DIR}/nginx"
# При запуске через sudo владелец — пользователь, вызвавший sudo
CURRENT_USER="${SUDO_USER:-$USER}"
CURRENT_GROUP="$CURRENT_USER"
if command -v id &>/dev/null; then
  CURRENT_GROUP="$(id -gn "$CURRENT_USER" 2>/dev/null)" || true
fi
[[ -z "$CURRENT_GROUP" ]] && CURRENT_GROUP="$CURRENT_USER"

echo "=== Деплой проекта: ${PROJECT_NAME} ==="
echo "Папка проекта: ${TARGET_DIR}"
echo "Папка логов:   ${LOG_PROJECT_DIR} (icecast, nginx)"
echo "Владелец:      ${CURRENT_USER}:${CURRENT_GROUP}"
echo ""

# Проверка Docker: при отсутствии — установка
ensure_docker() {
  if command -v docker &>/dev/null; then
    echo "Docker установлен. Проверка службы..."
    sudo systemctl start docker 2>/dev/null || true
    return 0
  fi
  echo "Docker не найден. Запуск установки..."
  if [[ -x "$SCRIPT_DIR/install-docker.sh" ]]; then
    sudo "$SCRIPT_DIR/install-docker.sh"
  else
    echo "Ошибка: скрипт install-docker.sh не найден или не исполняемый (chmod +x install-docker.sh)."
    exit 1
  fi
}

ensure_docker
echo ""

# Создание папок: /usr/local/bin/docker — всегда; если нет — создаём и даём права пользователю
create_dirs() {
  if [[ ! -d "$BASE_DIR" ]]; then
    echo "Создаю базовый каталог: ${BASE_DIR}"
    sudo mkdir -p "$BASE_DIR"
    sudo chown "${CURRENT_USER}:${CURRENT_GROUP}" "$BASE_DIR"
  else
    echo "Базовый каталог уже есть: ${BASE_DIR}"
  fi

  if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Создаю каталог проекта: ${TARGET_DIR}"
    sudo mkdir -p "$TARGET_DIR"
  else
    echo "Каталог проекта уже существует: ${TARGET_DIR}"
  fi

  if [[ ! -d "$TARGET_DIR/conf" ]]; then
    echo "Создаю каталог: ${TARGET_DIR}/conf"
    sudo mkdir -p "${TARGET_DIR}/conf"
  fi

  if [[ ! -d "$TARGET_LOG_ICECAST" ]]; then
    echo "Создаю каталог логов: ${TARGET_LOG_ICECAST}"
    sudo mkdir -p "$TARGET_LOG_ICECAST"
  else
    echo "Каталог логов icecast уже существует: ${TARGET_LOG_ICECAST}"
  fi
  if [[ ! -d "$TARGET_LOG_NGINX" ]]; then
    echo "Создаю каталог логов: ${TARGET_LOG_NGINX}"
    sudo mkdir -p "$TARGET_LOG_NGINX"
  else
    echo "Каталог логов nginx уже существует: ${TARGET_LOG_NGINX}"
  fi
}

# Назначение прав: проект — текущему пользователю; папка логов icecast — 1000:1000 (для контейнера)
set_ownership() {
  echo "Назначаю владельца ${CURRENT_USER}:${CURRENT_GROUP} для каталога проекта..."
  sudo chown -R "${CURRENT_USER}:${CURRENT_GROUP}" "$TARGET_DIR"
  echo "Назначаю владельца 1000:1000 для логов icecast..."
  sudo chown -R 1000:1000 "${TARGET_LOG_ICECAST}"
  echo "Права назначены."
}

create_dirs
set_ownership

# Копирование icecast_example.xml в conf/${PROJECT_NAME}.xml (имя совпадает с путём в docker-compose)
deploy_icecast_conf() {
  local src="$SCRIPT_DIR/conf/icecast_example.xml"
  local dest="${TARGET_DIR}/conf/${PROJECT_NAME}.xml"
  if [[ ! -f "$src" ]]; then
    echo "Пропуск: образец $src не найден."
    return 0
  fi
  # MAX_LISTENERS в шаблоне — подставляем LIMITS_CLIENTS, если не задан
  export MAX_LISTENERS="${MAX_LISTENERS:-$LIMITS_CLIENTS}"
  export PROJECT_NAME_ICECAST PROJECT_NAME_ICECAST_ADMIN LIMITS_CLIENTS LIMITS_SOURCES
  export SOURCE_PASSWORD RELAY_PASSWORD ADMIN_LOGIN ADMIN_PASSWORD PORT_ICECAST
  export NAME_MAIN_MOUNT STREAM_NAME STREAM_DESCRIPTION STREAM_GENRE STREAM_URL
  export NAME_FALLBACK_MOUNT IP_ADDRESS_GATEWAY
  if command -v envsubst &>/dev/null; then
    envsubst '$PROJECT_NAME_ICECAST $PROJECT_NAME_ICECAST_ADMIN $LIMITS_CLIENTS $LIMITS_SOURCES $SOURCE_PASSWORD $RELAY_PASSWORD $ADMIN_LOGIN $ADMIN_PASSWORD $PORT_ICECAST $NAME_MAIN_MOUNT $MAX_LISTENERS $STREAM_NAME $STREAM_DESCRIPTION $STREAM_GENRE $STREAM_URL $NAME_FALLBACK_MOUNT $IP_ADDRESS_GATEWAY' < "$src" > "$dest"
  else
    echo "envsubst не найден, копирую шалон без подстановки."
    cp "$src" "$dest"
  fi
  echo "Создан конфиг: ${dest} (монтируется в compose как conf/${PROJECT_NAME}.xml)"
}

deploy_icecast_conf

# Копирование docker-compose.yml в каталог деплоя (подстановка из .env)
deploy_compose() {
  if [[ -z "${IP_ADDRESS}" ]] || [[ -z "${IP_ADDRESS_GATEWAY}" ]]; then
    echo "Ошибка: в .env должны быть заданы IP_ADDRESS и IP_ADDRESS_GATEWAY для docker-compose."
    exit 1
  fi
  local src="$SCRIPT_DIR/conf/docker-compose.yml"
  local dest="${TARGET_DIR}/docker-compose.yml"
  if [[ ! -f "$src" ]]; then
    echo "Пропуск: $src не найден."
    return 0
  fi
  # SUBNET по умолчанию из IP_ADDRESS или фиксированное значение
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
  echo "Создан: ${dest}"
}

deploy_compose

echo ""
echo "Готово. Дальше:"
echo "  cd ${TARGET_DIR}"
echo "  docker compose up -d"
echo ""
echo "Если Docker только что установлен этим скриптом, сначала выполните:  newgrp docker"
echo "  (или выйдите из сессии и войдите снова — иначе «permission denied» при запуске compose)."
