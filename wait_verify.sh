#!/bin/bash
while true; do
  git pull origin main >/dev/null 2>&1
  if [ -f verify.log ]; then
    cat verify.log
    break
  fi
  sleep 5
done
