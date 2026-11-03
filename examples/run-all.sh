#!/usr/bin/env bash
# Runs every examples/NN-topic/*.sh script and fails if any of them fails.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

status=0
for script in [0-9][0-9]-*/*.sh; do
  [[ -e "$script" ]] || continue
  echo "== $script"
  if ! bash "$script"; then
    status=1
  fi
done

if [[ "$status" -eq 0 ]]; then echo "All examples passed."; else echo "Some examples failed."; fi
exit "$status"
