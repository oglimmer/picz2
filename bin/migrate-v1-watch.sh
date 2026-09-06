#!/usr/bin/env bash
# Read-only health check while a picz v1 -> v2 migration chunk runs.
#
#   bin/migrate-v1-watch.sh          # print once
#   bin/migrate-v1-watch.sh 30       # repeat every 30 seconds
#
# It never touches the picz-migrate Job. Running bin/migrate-v1-run.sh would
# DELETE a chunk that is still running -- use this instead while one is in flight.

set -euo pipefail

NAMESPACE="${NAMESPACE:-default}"
MINIO_NS="${MINIO_NS:-minio}"
INTERVAL="${1:-0}"

minio_node() {
  kubectl -n "$MINIO_NS" get pods -l app=minio -o jsonpath='{.items[0].spec.nodeName}' 2>/dev/null \
    || kubectl -n "$MINIO_NS" get pods -o jsonpath='{.items[0].spec.nodeName}'
}

report() {
  echo "=== $(date '+%F %T') ==="

  local node
  node="$(minio_node)"
  echo "-- MinIO volume (node $node)"
  kubectl get --raw "/api/v1/nodes/$node/proxy/stats/summary" 2>/dev/null |
    jq -r '.pods[] | select(.podRef.namespace=="'"$MINIO_NS"'") | .volume[]?
           | select(.name=="export")
           | "   used \(.usedBytes/1073741824*10|floor/10) GiB   free \(.availableBytes/1073741824*10|floor/10) GiB   of \(.capacityBytes/1073741824*10|floor/10) GiB"'

  echo "-- Nodes"
  kubectl top nodes 2>/dev/null | sed 's/^/   /'

  echo "-- picz2 pods"
  kubectl -n "$NAMESPACE" top pods --no-headers 2>/dev/null |
    grep -E 'photo-upload|picz-migrate' | sed 's/^/   /' || echo "   (no metrics)"

  echo "-- migrate job"
  kubectl -n "$NAMESPACE" get job picz-migrate --no-headers 2>/dev/null | sed 's/^/   /' || echo "   (none)"
  echo
}

if [ "$INTERVAL" -eq 0 ]; then
  report
else
  while true; do
    report
    sleep "$INTERVAL"
  done
fi
