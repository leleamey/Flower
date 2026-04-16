#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"

log() {
  printf '\033[1;34m[deploy]\033[0m %s\n' "$*"
}

err() {
  printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "Required command not found: $1"
    exit 1
  }
}

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f "$COMPOSE_FILE" "$@"
  else
    err "Neither 'docker compose' nor 'docker-compose' is available."
    exit 1
  fi
}

ensure_prereqs() {
  require_cmd docker
  [[ -f "$COMPOSE_FILE" ]] || {
    err "Missing $COMPOSE_FILE"
    exit 1
  }
}

start() {
  ensure_prereqs
  log "Starting ITSM stack (db, backend, frontend)"
  compose up --build -d
  log "Deployment complete"
  log "Frontend: http://localhost:3000"
  log "Backend:  http://localhost:8000"
  log "Health:   http://localhost:8000/health"
}

stop() {
  ensure_prereqs
  log "Stopping ITSM stack"
  compose down
}

restart() {
  stop
  start
}

status() {
  ensure_prereqs
  compose ps
}

logs() {
  ensure_prereqs
  compose logs -f --tail=100
}

usage() {
  cat <<USAGE
Usage: ./deploy.sh [start|stop|restart|status|logs]

Commands:
  start    Build and start db + backend + frontend
  stop     Stop and remove services
  restart  Restart all services
  status   Show service status
  logs     Tail service logs
USAGE
}

main() {
  case "${1:-start}" in
    start) start ;;
    stop) stop ;;
    restart) restart ;;
    status) status ;;
    logs) logs ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
