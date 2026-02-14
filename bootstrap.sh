#!/usr/bin/env bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for f in \
  env_vars.sh \
  combine-files.sh \
  dockersummary.sh \
  user_secrets.sh \
  filesummary.sh
do
  [ -f "$BASE_DIR/$f" ] && source "$BASE_DIR/$f"
done
