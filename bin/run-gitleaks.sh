#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE=".gitleaks.toml"
REPORT_FILE="gitleaks-report.json"

if command -v gitleaks >/dev/null 2>&1; then
  echo "Running gitleaks (local binary)"
  gitleaks detect --source . --redact --config "$CONFIG_FILE" --report-format json --report-path "$REPORT_FILE"
  echo "Report written to $REPORT_FILE"
  exit 0
fi

if command -v docker >/dev/null 2>&1; then
  echo "Running gitleaks via Docker"
  docker run --rm -v "$(pwd)":/repo -w /repo zricethezav/gitleaks:latest \
    detect --source . --redact --config "$CONFIG_FILE" --report-format json --report-path "$REPORT_FILE"
  echo "Report written to $REPORT_FILE"
  exit 0
fi

echo "gitleaks not found and docker not available. Install gitleaks or docker."
exit 2
