#!/bin/bash
set -e

check_etcd() {
  echo "Checking etcd health..."
  for i in {1..60}; do
    if etcdctl --endpoints=http://127.0.0.1:2379 endpoint health >/dev/null 2>&1; then
      echo "✓ etcd is healthy"
      return 0
    fi
    if [ $i -eq 60 ]; then
      echo "✗ etcd health check failed after 60 attempts"
      return 1
    fi
    sleep 1
  done
}

check_minio() {
  echo "Checking MinIO health..."
  for i in {1..60}; do
    if curl -f http://127.0.0.1:9000/minio/health/live >/dev/null 2>&1; then
      echo "✓ MinIO is healthy"
      return 0
    fi
    if [ $i -eq 60 ]; then
      echo "✗ MinIO health check failed after 60 attempts"
      return 1
    fi
    sleep 1
  done
}

check_milvus() {
  echo "Checking Milvus health..."
  for i in {1..90}; do
    if curl -f http://127.0.0.1:9091/healthz >/dev/null 2>&1; then
      echo "✓ Milvus is healthy"
      return 0
    fi
    if [ $i -eq 90 ]; then
      echo "✗ Milvus health check failed after 90 attempts"
      return 1
    fi
    sleep 1
  done
}

# Run all health checks in parallel
check_etcd &
PID1=$!
check_minio &
PID2=$!
check_milvus &
PID3=$!

# Wait for all checks to complete and collect exit codes
wait $PID1
RESULT1=$?
wait $PID2
RESULT2=$?
wait $PID3
RESULT3=$?

# Exit with failure if any check failed
if [ $RESULT1 -ne 0 ] || [ $RESULT2 -ne 0 ] || [ $RESULT3 -ne 0 ]; then
  echo "One or more services failed health checks"
  exit 1
fi

echo "All services are healthy!"
