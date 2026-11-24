#!/usr/bin/env bash
# Generate traffic so Prometheus has data for canary analysis. Usage: ./scripts/traffic.sh [env] [rps]
ENV="${1:-prod}"; RPS="${2:-10}"
echo "Hitting http://shop-${ENV}.localtest.me (Ctrl-C to stop)"
while true; do
  curl -s -o /dev/null -w "%{http_code} " "http://shop-${ENV}.localtest.me/" || true
  sleep "$(awk "BEGIN{print 1/${RPS}}")"
done
