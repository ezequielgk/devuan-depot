#!/bin/bash
while true; do
  git fetch origin patched-ftm >/dev/null 2>&1
  git checkout origin/patched-ftm >/dev/null 2>&1
  LAST_MSG=$(git log -1 --pretty=%s)
  if [ "$LAST_MSG" == "Upload make log 2" ] && [ "$(git log -2 --pretty=%s | grep -v 'Upload make log 2')" == "chore: fix compiler error broken undeclared" ]; then
    cat make.log
    break
  fi
  sleep 5
done
