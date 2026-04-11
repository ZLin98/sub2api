#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"

APP_NAME="${APP_NAME:-sub2api}"
DEPLOY_DIR="${DEPLOY_DIR:-/home/lin/depoly/${APP_NAME}}"
LOG_DIR="${LOG_DIR:-/home/log/${APP_NAME}}"
ENV_FILE="${ENV_FILE:-${DEPLOY_DIR}/.env}"

green() { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red() { printf '\033[31m%s\033[0m\n' "$*"; }
blue() { printf '\033[36m%s\033[0m\n' "$*"; }

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        red "Missing required command: $1"
        exit 1
    fi
}

generate_secret() {
    openssl rand -hex 32
}

generate_password() {
    openssl rand -base64 24 | tr -d '\n'
}

write_default_env() {
    local compose_project_name image_name image_tag app_host_port app_domain
    local postgres_user postgres_db admin_email server_mode run_mode timezone
    local frontend_url postgres_password jwt_secret totp_key admin_password

    compose_project_name="${COMPOSE_PROJECT_NAME:-${APP_NAME}-prod}"
    image_name="${IMAGE_NAME:-${APP_NAME}}"
    image_tag="${IMAGE_TAG:-local}"
    app_host_port="${APP_HOST_PORT:-18080}"
    app_domain="${APP_DOMAIN:-}"
    postgres_user="${POSTGRES_USER:-sub2api}"
    postgres_db="${POSTGRES_DB:-sub2api}"
    admin_email="${ADMIN_EMAIL:-admin@${APP_NAME}.local}"
    server_mode="${SERVER_MODE:-release}"
    run_mode="${RUN_MODE:-standard}"
    timezone="${TZ:-Asia/Shanghai}"

    if [[ -n "${app_domain}" ]]; then
        frontend_url="https://${app_domain}"
    else
        frontend_url=""
    fi

    postgres_password="$(generate_secret)"
    jwt_secret="$(generate_secret)"
    totp_key="$(generate_secret)"
    admin_password="$(generate_password)"

    mkdir -p "${DEPLOY_DIR}"

    cat >"${ENV_FILE}" <<EOF
APP_NAME=${APP_NAME}
COMPOSE_PROJECT_NAME=${compose_project_name}
DEPLOY_DIR=${DEPLOY_DIR}
LOG_DIR=${LOG_DIR}
APP_DOMAIN=${app_domain}
SERVER_FRONTEND_URL=${frontend_url}
APP_HOST_PORT=${app_host_port}
IMAGE_NAME=${image_name}
IMAGE_TAG=${image_tag}
SERVER_MODE=${server_mode}
RUN_MODE=${run_mode}
TZ=${timezone}
POSTGRES_USER=${postgres_user}
POSTGRES_PASSWORD=${postgres_password}
POSTGRES_DB=${postgres_db}
DATABASE_SSLMODE=disable
DATABASE_MAX_OPEN_CONNS=50
DATABASE_MAX_IDLE_CONNS=10
DATABASE_CONN_MAX_LIFETIME_MINUTES=30
DATABASE_CONN_MAX_IDLE_TIME_MINUTES=5
REDIS_PASSWORD=
REDIS_DB=0
REDIS_POOL_SIZE=1024
REDIS_MIN_IDLE_CONNS=10
REDIS_ENABLE_TLS=false
ADMIN_EMAIL=${admin_email}
ADMIN_PASSWORD=${admin_password}
JWT_SECRET=${jwt_secret}
JWT_EXPIRE_HOUR=24
TOTP_ENCRYPTION_KEY=${totp_key}
LOG_LEVEL=info
LOG_FORMAT=json
LOG_ENV=production
LOG_CALLER=true
LOG_STACKTRACE_LEVEL=error
LOG_OUTPUT_TO_STDOUT=true
LOG_OUTPUT_TO_FILE=true
LOG_ROTATION_MAX_SIZE_MB=100
LOG_ROTATION_MAX_BACKUPS=10
LOG_ROTATION_MAX_AGE_DAYS=7
LOG_ROTATION_COMPRESS=true
LOG_ROTATION_LOCAL_TIME=true
SECURITY_URL_ALLOWLIST_ENABLED=false
SECURITY_URL_ALLOWLIST_ALLOW_PRIVATE_HOSTS=false
SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP=false
SECURITY_URL_ALLOWLIST_UPSTREAM_HOSTS=
UPDATE_PROXY_URL=
GOPROXY=https://goproxy.cn,direct
GOSUMDB=sum.golang.google.cn
EOF

    chmod 600 "${ENV_FILE}"

    yellow "Created ${ENV_FILE}"
    yellow "Generated initial credentials:"
    printf '  ADMIN_EMAIL=%s\n' "${admin_email}"
    printf '  ADMIN_PASSWORD=%s\n' "${admin_password}"
    printf '  POSTGRES_PASSWORD=%s\n' "${postgres_password}"
    printf '  JWT_SECRET=%s\n' "${jwt_secret}"
    printf '  TOTP_ENCRYPTION_KEY=%s\n' "${totp_key}"
    if [[ -z "${app_domain}" ]]; then
        yellow "APP_DOMAIN was empty. Set APP_DOMAIN or SERVER_FRONTEND_URL in ${ENV_FILE} if you need password reset links."
    fi
}

load_env_file() {
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
}

prepare_dirs() {
    APP_DATA_DIR="${DEPLOY_DIR}/data"
    POSTGRES_DATA_DIR="${DEPLOY_DIR}/postgres_data"
    REDIS_DATA_DIR="${DEPLOY_DIR}/redis_data"
    BACKUP_DIR="${DEPLOY_DIR}/backup"
    APP_LOG_DIR="${LOG_DIR}/app"
    NGINX_LOG_DIR="${LOG_DIR}/nginx"

    export REPO_DIR
    export APP_DATA_DIR
    export POSTGRES_DATA_DIR
    export REDIS_DATA_DIR
    export BACKUP_DIR
    export APP_LOG_DIR
    export NGINX_LOG_DIR

    mkdir -p \
        "${APP_DATA_DIR}" \
        "${POSTGRES_DATA_DIR}" \
        "${REDIS_DATA_DIR}" \
        "${BACKUP_DIR}" \
        "${APP_LOG_DIR}" \
        "${NGINX_LOG_DIR}"

    chmod 755 "${DEPLOY_DIR}" "${LOG_DIR}" "${APP_LOG_DIR}" "${NGINX_LOG_DIR}" || true

    if [[ "$(id -u)" -eq 0 ]]; then
        chown -R 1000:1000 "${APP_LOG_DIR}" || true
    fi
}

run_compose() {
    docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" "$@"
}

wait_for_health() {
    local url="http://127.0.0.1:${APP_HOST_PORT}/health"
    local attempt=1
    local max_attempts=30

    while (( attempt <= max_attempts )); do
        if command -v curl >/dev/null 2>&1; then
            if curl -fsS --max-time 5 "${url}" >/dev/null 2>&1; then
                green "Health check passed: ${url}"
                return 0
            fi
        elif command -v wget >/dev/null 2>&1; then
            if wget -q -T 5 -O /dev/null "${url}" >/dev/null 2>&1; then
                green "Health check passed: ${url}"
                return 0
            fi
        else
            yellow "curl/wget not found, skip active health check."
            return 0
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    red "Health check failed: ${url}"
    return 1
}

main() {
    require_cmd docker
    require_cmd openssl

    if [[ ! -f "${ENV_FILE}" ]]; then
        write_default_env
    fi

    load_env_file
    prepare_dirs

    blue "Repo dir: ${REPO_DIR}"
    blue "Deploy dir: ${DEPLOY_DIR}"
    blue "Log dir: ${LOG_DIR}"
    blue "Compose file: ${COMPOSE_FILE}"

    run_compose config -q

    blue "Building new image before stopping old containers..."
    run_compose build --pull

    blue "Stopping previous containers..."
    run_compose down --remove-orphans

    blue "Starting new containers..."
    run_compose up -d --remove-orphans

    wait_for_health

    green "Deployment finished."
    printf '  Local upstream: http://127.0.0.1:%s\n' "${APP_HOST_PORT}"
    printf '  App logs: %s/%s.log\n' "${APP_LOG_DIR}" "${APP_NAME}"
    printf '  Docker status: docker compose --env-file %s -f %s ps\n' "${ENV_FILE}" "${COMPOSE_FILE}"
}

main "$@"
