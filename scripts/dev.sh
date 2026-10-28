#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
.venv/bin/uvicorn backend.app.main:app --host 0.0.0.0 --port 8000 &
BACKEND_PID=$!
trap 'kill "$BACKEND_PID" 2>/dev/null || true' EXIT INT TERM
npm --prefix frontend run dev
