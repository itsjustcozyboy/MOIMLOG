#!/usr/bin/env bash
set -e
cd "$(dirname "$0")/.."
python -m venv .venv
.venv/bin/pip install -r backend/requirements.txt
npm --prefix frontend ci
if ! command -v ffprobe >/dev/null; then
  echo '음성 검증을 위해 sudo apt-get update && sudo apt-get install -y ffmpeg 를 실행하세요. TXT 기능에는 필요하지 않습니다.'
fi
if [ ! -f .env ]; then cp .env.example .env; fi
