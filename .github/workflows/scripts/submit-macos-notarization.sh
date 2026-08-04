#!/usr/bin/env bash

set -euo pipefail

artifact_path="${1:?Usage: submit-macos-notarization.sh <artifact>}"
max_attempts="${NOTARY_SUBMIT_ATTEMPTS:-3}"

for ((attempt = 1; attempt <= max_attempts; attempt++)); do
  set +e
  output="$(xcrun notarytool submit "$artifact_path" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --output-format json \
    --wait 2>&1)"
  status=$?
  set -e

  submission_id=""
  if [[ $status -eq 0 && -n "$output" ]]; then
    submission_id="$(printf '%s' "$output" | python3 -c \
      'import json, sys; print(json.load(sys.stdin).get("id", ""))' \
      2>/dev/null || true)"
  fi

  if [[ -n "$submission_id" && "$submission_id" != "null" ]]; then
    printf '%s\n' "$submission_id"
    exit 0
  fi

  printf 'notarytool submission attempt %d/%d failed (exit %d).\n' \
    "$attempt" "$max_attempts" "$status" >&2
  if [[ -n "$output" ]]; then
    printf '%s\n' "$output" >&2
  else
    printf 'notarytool returned no output.\n' >&2
  fi

  if ((attempt < max_attempts)); then
    sleep $((attempt * 15))
  fi
done

exit 1
