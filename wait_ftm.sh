#!/bin/bash
while true; do
  git fetch origin patched-ftm >/dev/null 2>&1
  git checkout origin/patched-ftm >/dev/null 2>&1
  if [ -f dwl-headless-ftm.log ]; then
    cat dwl-headless-ftm.log
    break
  fi
  sleep 5
done
