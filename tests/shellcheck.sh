#!/bin/bash

# Runs ShellCheck static analysis on all .sh files in the project
set -euo pipefail

# $1: first argument

MODE="${1:-1}"

if [[ "$MODE" == "0" ]]; then
  SEVERITY="error"
elif [[ "$MODE" == "1" ]]; then
  SEVERITY="warning"
else
  echo "Error: Invalid argument '$MODE'. Use 0 (CI/error) or 1 (dev/warning)."
  exit 1
fi

echo "=== Running ShellCheck on all .sh files ==="

# SC1091: not following sourced files 
# SC2034: unused variables
shellcheck \
  --severity="$SEVERITY" \
  --exclude=SC1091 \
  $(find . -name "*.sh" -not -path "./.git/*")

echo ""
echo "ShellCheck passed."