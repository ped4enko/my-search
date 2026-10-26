#!/usr/bin/env bash
# Bootstrap "My Search" (SearXNG) on a Linux VPS.
#
# Idempotent: safe to re-run. Never prints or commits secrets.
#
# Usage (as root or a user in the docker group):
#   DOMAIN=search.example.com ACME_EMAIL=you@example.com \
#     bash scripts/bootstrap-vps.sh
#
# Optional env:
#   REPO_URL   git remote (default: https://github.com/ped4enko/my-search.git)
#   REPO_DIR   clone path (default: /opt/my-search)
#   BRANCH     git branch  (default: master)
#   SKIP_PULL  set to 1 to skip git clone/pull
#   COMPOSE_PROFILES  default: tls

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/ped4enko/my-search.git}"
REPO_DIR="${REPO_DIR:-/opt/my-search}"
BRANCH="${BRANCH:-master}"
COMPOSE_PROFILES="${COMPOSE_PROFILES:-tls}"
DEPLOY_DIR=""

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker and Compose already installed"
    return 0
  fi

  log "Installing Docker Engine + Compose plugin"
  need_cmd curl
  need_cmd sh

  # Official convenience script; installs docker + compose plugin on common distros.
  curl -fsSL https://get.docker.com | sh

  if command -v systemctl >/dev/null 2>&1; then
    systemctl enable --now docker || true
  fi

  command -v docker >/dev/null 2>&1 || die "docker install failed"
  docker compose version >/dev/null 2>&1 || die "docker compose plugin missing after install"
}

ensure_repo() {
  if [[ "${SKIP_PULL:-0}" == "1" ]]; then
    [[ -d "$REPO_DIR/.git" ]] || die "SKIP_PULL=1 but $REPO_DIR is not a git checkout"
    log "Skipping git pull (SKIP_PULL=1)"
    return 0
  fi

  need_cmd git

  if [[ -d "$REPO_DIR/.git" ]]; then
    log "Updating existing checkout at $REPO_DIR"
    git -C "$REPO_DIR" fetch --prune origin
    git -C "$REPO_DIR" checkout "$BRANCH"
    # Prefer fast-forward only so local edits are not discarded silently.
    git -C "$REPO_DIR" pull --ff-only origin "$BRANCH"
  else
    if [[ -e "$REPO_DIR" ]]; then
      die "$REPO_DIR exists but is not a git repository"
    fi
    log "Cloning $REPO_URL → $REPO_DIR (branch $BRANCH)"
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone --branch "$BRANCH" --single-branch "$REPO_URL" "$REPO_DIR"
  fi
}

resolve_deploy_dir() {
  if [[ -f "$REPO_DIR/deploy/my-search/docker-compose.yml" ]]; then
    DEPLOY_DIR="$REPO_DIR/deploy/my-search"
  elif [[ -f "$REPO_DIR/docker-compose.yml" && -d "$REPO_DIR/searxng" ]]; then
    DEPLOY_DIR="$REPO_DIR"
  else
    die "could not find deploy bundle under $REPO_DIR (expected deploy/my-search/)"
  fi
  log "Deploy directory: $DEPLOY_DIR"
}

prompt_if_empty() {
  # $1=var name, $2=prompt
  local name="$1" prompt="$2" current=""
  eval "current=\${$name-}"
  if [[ -n "$current" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    die "$name is required (set the env var; stdin is not a TTY)"
  fi
  printf '%s: ' "$prompt" >&2
  read -r current
  [[ -n "$current" ]] || die "$name must not be empty"
  printf -v "$name" '%s' "$current"
}

ensure_env() {
  local env_file="$DEPLOY_DIR/.env"
  local example="$DEPLOY_DIR/.env.example"
  local secret=""

  [[ -f "$example" ]] || die "missing $example"

  if [[ ! -f "$env_file" ]]; then
    log "Creating .env from .env.example"
    cp "$example" "$env_file"
    chmod 600 "$env_file"
  else
    log ".env already exists — updating DOMAIN / ACME_EMAIL / BASE_URL only"
    chmod 600 "$env_file" 2>/dev/null || true
  fi

  # Generate secret only when still the placeholder.
  if grep -qE '^SEARXNG_SECRET=(CHANGE_ME)?[[:space:]]*$' "$env_file" \
    || grep -qE '^SEARXNG_SECRET=CHANGE_ME\b' "$env_file"; then
    need_cmd openssl
    secret="$(openssl rand -hex 32)"
    # Avoid echoing the secret; write via a temp file + sed.
    sed -i "s|^SEARXNG_SECRET=.*|SEARXNG_SECRET=${secret}|" "$env_file"
    log "Generated SEARXNG_SECRET"
    unset secret
  else
    log "SEARXNG_SECRET already set — leaving unchanged"
  fi

  prompt_if_empty DOMAIN "Public domain (e.g. search.example.com)"
  prompt_if_empty ACME_EMAIL "Let's Encrypt email"

  # DOMAIN / ACME_EMAIL: upsert without printing values beyond confirmation.
  if grep -qE '^DOMAIN=' "$env_file"; then
    sed -i "s|^DOMAIN=.*|DOMAIN=${DOMAIN}|" "$env_file"
  else
    printf 'DOMAIN=%s\n' "$DOMAIN" >>"$env_file"
  fi
  if grep -qE '^ACME_EMAIL=' "$env_file"; then
    sed -i "s|^ACME_EMAIL=.*|ACME_EMAIL=${ACME_EMAIL}|" "$env_file"
  else
    printf 'ACME_EMAIL=%s\n' "$ACME_EMAIL" >>"$env_file"
  fi

  sed -i "s|^SEARXNG_BASE_URL=.*|SEARXNG_BASE_URL=https://${DOMAIN}/|" "$env_file"

  log "Configured DOMAIN=${DOMAIN} and ACME_EMAIL (value not shown)"
}

start_stack() {
  need_cmd docker
  log "Starting stack with profile '${COMPOSE_PROFILES}'"
  (
    cd "$DEPLOY_DIR"
    # shellcheck disable=SC2086
    docker compose --profile ${COMPOSE_PROFILES} up -d
  )
  log "Done. Check: docker compose -f ${DEPLOY_DIR}/docker-compose.yml ps"
  log "Health (local): curl -fsS http://127.0.0.1:8080/healthz"
}

main() {
  if [[ "$(id -u)" -ne 0 ]] && ! groups | grep -qw docker; then
    log "warning: not root and not in docker group — docker commands may fail"
  fi

  install_docker
  ensure_repo
  resolve_deploy_dir
  ensure_env
  start_stack
}

main "$@"
