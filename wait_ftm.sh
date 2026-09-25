#!/bin/bash
while true; do
  git fetch origin patched-ftm >/dev/null 2>&1
  git checkout origin/patched-ftm >/dev/null 2>&1
  LAST_MSG=$(git log -1 --pretty=%s)
  if [[ "$LAST_MSG" == *"Upload headless ftm log 3"* ]]; then
    cat dwl-headless-ftm.log
    break
  fi
  sleep 5
done
