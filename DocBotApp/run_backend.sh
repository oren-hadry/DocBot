#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="${ROOT_DIR}/backend"

cd "${BACKEND_DIR}"

PYTHON_BIN=""
if command -v python3.11 >/dev/null 2>&1; then
  PYTHON_BIN="python3.11"
elif command -v python3.10 >/dev/null 2>&1; then
  PYTHON_BIN="python3.10"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_BIN="python3"
fi

if [ -z "${PYTHON_BIN}" ]; then
  echo "Python 3.11+ is required. Please install Python 3.11."
  exit 1
fi

PYTHON_VERSION="$(${PYTHON_BIN} -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
if [ "${PYTHON_VERSION}" != "3.11" ] && [ "${PYTHON_VERSION}" != "3.12" ] && [ "${PYTHON_VERSION}" != "3.13" ]; then
  echo "Python 3.11+ is required. Found ${PYTHON_VERSION}."
  exit 1
fi

if [ ! -d ".venv" ]; then
  "${PYTHON_BIN}" -m venv .venv
else
  VENV_PY_VERSION="$(.venv/bin/python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
  if [ "${VENV_PY_VERSION}" != "${PYTHON_VERSION}" ]; then
    echo "Existing .venv uses Python ${VENV_PY_VERSION}. Please remove .venv to recreate with ${PYTHON_VERSION}."
    exit 1
  fi
fi

source .venv/bin/activate
python -m pip install -r requirements.txt --upgrade
uvicorn api.main:app --reload --port 8000 --app-dir . --log-level warning --no-access-log
