#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"

run_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f "$COMPOSE_FILE" "$@"
  else
    echo "[ERROR] Docker Compose is not installed. Please install Docker Desktop / Docker Compose." >&2
    exit 1
  fi
}

if ! command -v docker >/dev/null 2>&1; then
  echo "[ERROR] Docker is not installed. Please install Docker first." >&2
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "[ERROR] Missing docker-compose.yml at $COMPOSE_FILE" >&2
  exit 1
fi

echo "[INFO] Starting ITSM stack (db + backend + frontend)..."
run_compose up --build -d

echo "[INFO] Services status:"
run_compose ps

echo ""
echo "[SUCCESS] ITSM is running"
echo "Frontend: http://localhost:3000"
echo "Backend:  http://localhost:8000"
echo "Health:   http://localhost:8000/health"
echo ""
echo "To stop everything later:"
echo "  docker compose -f docker-compose.yml down"
