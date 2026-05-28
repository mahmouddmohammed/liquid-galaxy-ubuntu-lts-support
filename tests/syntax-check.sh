#!/bin/bash

# Checks bash syntax of all .sh files in the project

set -euo pipefail

echo "=== Checking syntax of all bash files ==="

FAILED=0

while IFS= read -r -d '' file; do
  if ! bash -n "$file" 2>&1; then
    echo "SYNTAX ERROR in: $file"
    FAILED=1
  else
    echo "OK: $file"
  fi
done < <(find . -name "*.sh" -not -path "./.git/*" -print0)

echo ""

if [ "$FAILED" -ne 0 ]; then
  echo "One or more scripts have syntax errors."
  exit 1
fi

echo "All scripts passed syntax check."
