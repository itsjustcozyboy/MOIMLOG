#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DATA_DIR
DATA_DIR=$(mktemp -d)
export DATABASE_URL="sqlite:///$DATA_DIR/e2e.db" GROQ_API_KEY='' COOKIE_SECURE=false
export MOIMLOG_E2E_ORIGIN=http://127.0.0.1:18765
npm run build
.venv/bin/python -c "from backend.app.bootstrap_admin import bootstrap; bootstrap('e2e-admin@example.test', 'local-test-admin-123')"
.venv/bin/python -m uvicorn backend.app.main:app --host 127.0.0.1 --port 18765 &
backend_pid=$!
trap 'kill "$backend_pid" 2>/dev/null || true' EXIT
for attempt in {1..50}; do
  if curl -fsS "$MOIMLOG_E2E_ORIGIN/api/config" >/dev/null 2>&1; then break; fi
  sleep .2
done
curl -fsS "$MOIMLOG_E2E_ORIGIN/api/config" >/dev/null
npm --prefix frontend run test:e2e "$@"
