#!/bin/bash
while true; do
  git pull origin main >/dev/null 2>&1
  if [ -f gcc-output.log ]; then
    cat gcc-output.log
    break
  fi
  sleep 5
done
