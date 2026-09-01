#!/usr/bin/env bash
# Run bin/migrate_v1.py as a one-shot Job inside the cluster.
#
# In-cluster because the job talks to mariadb and MinIO over cluster DNS, and pulls ~6 GB
# out of AWS S3 -- doing that through a laptop port-forward is slow and fragile.
#
#   bin/migrate-v1-run.sh --email oglimmer@gmail.com --phase upload --dry-run
#   bin/migrate-v1-run.sh --email oglimmer@gmail.com --phase upload
#   bin/migrate-v1-run.sh --email oglimmer@gmail.com --phase status
#   bin/migrate-v1-run.sh --email oglimmer@gmail.com --phase finalize
#
# Every argument is forwarded to migrate_v1.py verbatim.

set -euo pipefail

NAMESPACE="${NAMESPACE:-default}"
JOB=picz-migrate
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -eq 0 ]; then
  echo "usage: $0 --email <address> [--phase upload|finalize|status] [--dry-run] [--limit N]" >&2
  exit 2
fi

# Quote each argument for the shell inside the container.
ARGS=""
for arg in "$@"; do
  ARGS="$ARGS $(printf '%q' "$arg")"
done

kubectl -n "$NAMESPACE" delete job "$JOB" --ignore-not-found --wait=true

kubectl -n "$NAMESPACE" create configmap "$JOB-script" \
  --from-file=migrate_v1.py="$SCRIPT_DIR/migrate_v1.py" \
  --dry-run=client -o yaml | kubectl -n "$NAMESPACE" apply -f -

kubectl -n "$NAMESPACE" apply -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: $JOB
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 86400
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: python:3.12-slim
          command: ["sh", "-c"]
          args:
            - |
              set -e
              pip install --quiet --no-cache-dir pymysql boto3
              exec python /script/migrate_v1.py$ARGS
          volumeMounts:
            - name: script
              mountPath: /script
          resources:
            requests: { cpu: 100m, memory: 256Mi }
            limits: { cpu: "2", memory: 1Gi }
          env:
            # ---- v1 (picz) -------------------------------------------------
            - { name: V1_DB_HOST, value: mariadb }
            - { name: V1_DB_NAME, value: picz_prod }
            - { name: V1_DB_USER, value: picz-app }
            - name: V1_DB_PASSWORD
              valueFrom: { secretKeyRef: { name: picz-api-env, key: SPRING_DATASOURCE_PASSWORD } }
            - { name: V1_S3_BUCKET, value: picz-images-bucket }
            - { name: V1_S3_REGION, value: eu-central-1 }
            - { name: V1_S3_PREFIX, value: "images/" }
            - name: AWS_ACCESS_KEY_ID
              valueFrom: { secretKeyRef: { name: picz-api-env, key: AWS_ACCESS_KEY_ID } }
            - name: AWS_SECRET_ACCESS_KEY
              valueFrom: { secretKeyRef: { name: picz-api-env, key: AWS_SECRET_ACCESS_KEY } }
            # ---- v2 (photo-upload) -----------------------------------------
            - name: V2_DB_HOST
              valueFrom: { configMapKeyRef: { name: photo-upload-config, key: database.host } }
            - name: V2_DB_PORT
              valueFrom: { configMapKeyRef: { name: photo-upload-config, key: database.port } }
            - name: V2_DB_NAME
              valueFrom: { configMapKeyRef: { name: photo-upload-config, key: database.name } }
            - name: V2_DB_USER
              valueFrom: { secretKeyRef: { name: photo-upload-secret, key: database.user } }
            - name: V2_DB_PASSWORD
              valueFrom: { secretKeyRef: { name: photo-upload-secret, key: database.password } }
            - name: V2_S3_ENDPOINT
              valueFrom: { configMapKeyRef: { name: photo-upload-config, key: objectStorage.endpoint } }
            - name: V2_S3_BUCKET
              valueFrom: { configMapKeyRef: { name: photo-upload-config, key: objectStorage.bucket } }
            - name: V2_S3_REGION
              valueFrom: { configMapKeyRef: { name: photo-upload-config, key: objectStorage.region } }
            - name: V2_S3_ACCESS_KEY
              valueFrom: { secretKeyRef: { name: photo-upload-secret, key: objectStorage.accessKey } }
            - name: V2_S3_SECRET_KEY
              valueFrom: { secretKeyRef: { name: photo-upload-secret, key: objectStorage.secretKey } }
      volumes:
        - name: script
          configMap: { name: $JOB-script }
YAML

echo "waiting for pod ..."
kubectl -n "$NAMESPACE" wait --for=condition=ready pod -l job-name="$JOB" --timeout=180s || true
kubectl -n "$NAMESPACE" logs -f "job/$JOB"
