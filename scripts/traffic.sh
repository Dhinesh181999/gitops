#!/usr/bin/env bash
set -euo pipefail

ENV="${1:-prod}"
case "$ENV" in
  dev|staging|prod) ;;
  *) echo "environment must be dev, staging, or prod" >&2; exit 1 ;;
esac

URL="http://demo-${ENV}.localtest.me/"
echo "Sending requests to ${URL}; press Ctrl-C to stop."
while true; do
  curl -sS -o /dev/null -w '%{http_code}\n' "$URL"
  sleep 1
done
