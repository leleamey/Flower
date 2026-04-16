#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$PROJECT_ROOT/backend"
FRONTEND_DIR="$PROJECT_ROOT/frontend"
RUN_DIR="$PROJECT_ROOT/.run"
VENV_DIR="$PROJECT_ROOT/.venv"
LOG_DIR="$PROJECT_ROOT/.logs"
BACKEND_PID_FILE="$RUN_DIR/backend.pid"
FRONTEND_PID_FILE="$RUN_DIR/frontend.pid"

BACKEND_PORT="${BACKEND_PORT:-8000}"
FRONTEND_PORT="${FRONTEND_PORT:-3000}"

mkdir -p "$RUN_DIR" "$LOG_DIR"

log() {
  printf '\033[1;34m[deploy]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[warn]\033[0m %s\n' "$*"
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

kill_if_running() {
  local pid_file="$1"
  local name="$2"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid="$(cat "$pid_file")"
    if [[ -n "$pid" ]] && kill -0 "$pid" >/dev/null 2>&1; then
      log "Stopping $name (PID: $pid)"
      kill "$pid" >/dev/null 2>&1 || true
      wait "$pid" 2>/dev/null || true
    fi
    rm -f "$pid_file"
  fi
}

bootstrap_backend() {
  require_cmd python3

  if [[ ! -d "$VENV_DIR" ]]; then
    log "Creating Python virtual environment"
    python3 -m venv "$VENV_DIR"
  fi

  # shellcheck source=/dev/null
  source "$VENV_DIR/bin/activate"
  log "Installing backend dependencies"
  pip install --upgrade pip >/dev/null
  pip install fastapi "uvicorn[standard]" sqlalchemy psycopg2-binary python-jose passlib bcrypt email-validator >/dev/null
}

bootstrap_frontend() {
  require_cmd npm
  if [[ ! -f "$FRONTEND_DIR/package.json" ]]; then
    err "Missing $FRONTEND_DIR/package.json. Frontend project files are incomplete."
    exit 1
  fi

  log "Installing frontend dependencies"
  (cd "$FRONTEND_DIR" && npm install --silent)
}

start_backend() {
  # shellcheck source=/dev/null
  source "$VENV_DIR/bin/activate"
  log "Starting backend on port $BACKEND_PORT"
  (
    cd "$BACKEND_DIR"
    uvicorn app.main:app --host 0.0.0.0 --port "$BACKEND_PORT" >"$LOG_DIR/backend.log" 2>&1
  ) &
  echo $! >"$BACKEND_PID_FILE"
}

start_frontend() {
  log "Starting frontend on port $FRONTEND_PORT"
  (
    cd "$FRONTEND_DIR"
    PORT="$FRONTEND_PORT" npm start >"$LOG_DIR/frontend.log" 2>&1
  ) &
  echo $! >"$FRONTEND_PID_FILE"
}

status() {
  local backend_status="stopped"
  local frontend_status="stopped"

  if [[ -f "$BACKEND_PID_FILE" ]] && kill -0 "$(cat "$BACKEND_PID_FILE")" >/dev/null 2>&1; then
    backend_status="running (PID $(cat "$BACKEND_PID_FILE"))"
  fi

  if [[ -f "$FRONTEND_PID_FILE" ]] && kill -0 "$(cat "$FRONTEND_PID_FILE")" >/dev/null 2>&1; then
    frontend_status="running (PID $(cat "$FRONTEND_PID_FILE"))"
  fi

  log "Backend:  $backend_status"
  log "Frontend: $frontend_status"
  log "Logs:     $LOG_DIR"
}

start() {
  require_cmd bash

  kill_if_running "$BACKEND_PID_FILE" "backend"
  kill_if_running "$FRONTEND_PID_FILE" "frontend"

  bootstrap_backend
  bootstrap_frontend
  start_backend
  start_frontend

  log "Deployment complete"
  log "Backend URL:  http://localhost:$BACKEND_PORT"
  log "Frontend URL: http://localhost:$FRONTEND_PORT"
  log "Backend log:  $LOG_DIR/backend.log"
  log "Frontend log: $LOG_DIR/frontend.log"
}

stop() {
  kill_if_running "$BACKEND_PID_FILE" "backend"
  kill_if_running "$FRONTEND_PID_FILE" "frontend"
  log "All services stopped"
}

usage() {
  cat <<USAGE
Usage: ./deploy.sh [start|stop|restart|status]

Commands:
  start    Install dependencies and start backend + frontend
  stop     Stop backend + frontend started by this script
  restart  Restart backend + frontend
  status   Show running status
USAGE
}

main() {
  local action="${1:-start}"
  case "$action" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    status) status ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"
