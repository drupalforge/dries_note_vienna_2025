#!/bin/bash
set -e

echo "=== Starting service health checks ===" >&2
echo "Current time: $(date)" >&2

# Wait for supervisord to be ready
echo "=== Waiting for supervisord to be ready ===" >&2
for i in {1..30}; do
  if [ -e /var/run/supervisor.sock ]; then
    echo "✓ Supervisor socket found after $i seconds" >&2
    break
  fi
  echo "  Waiting for supervisor socket... ($i/30)" >&2
  if [ $i -eq 30 ]; then
    echo "✗ Supervisor socket not found after 30 seconds" >&2
    echo "Checking for supervisord process:" >&2
    ps aux | grep supervisor >&2 || echo "No supervisor process found" >&2
    echo "Checking /var/run:" >&2
    ls -la /var/run/ >&2 || echo "Cannot list /var/run" >&2
    exit 1
  fi
  sleep 1
done

# Show supervisord status first
echo "=== Checking supervisord status ===" >&2
sudo supervisorctl status || echo "supervisorctl failed" >&2

# Show process list
echo "=== Process list ===" >&2
ps aux | grep -E '(etcd|minio|milvus|attu|supervisor)' || echo "No service processes found" >&2

# Show network listeners
echo "=== Network listeners ===" >&2
sudo netstat -tlnp 2>/dev/null | grep -E '(2379|9000|9091|19530|3000)' || echo "No service ports listening" >&2

# Show /etc/hosts
echo "=== /etc/hosts content ===" >&2
cat /etc/hosts || echo "Cannot read /etc/hosts" >&2

check_etcd() {
  echo "Checking etcd health..." >&2
  for i in {1..60}; do
    if etcdctl --endpoints=http://127.0.0.1:2379 endpoint health >/dev/null 2>&1; then
      echo "✓ etcd is healthy (attempt $i)" >&2
      return 0
    fi
    if [ $i -eq 60 ]; then
      echo "✗ etcd health check failed after 60 attempts" >&2
      echo "Final etcd process check:" >&2
      ps aux | grep etcd >&2
      echo "Final etcd logs:" >&2
      sudo tail -50 /var/log/etcd.*.log 2>&1 >&2 || echo "No etcd logs found" >&2
      return 1
    fi
    sleep 1
  done
}

check_minio() {
  echo "Checking MinIO health..." >&2
  for i in {1..60}; do
    if curl -s -f http://127.0.0.1:9000/minio/health/live >/dev/null 2>&1; then
      echo "✓ MinIO is healthy (attempt $i)" >&2
      return 0
    fi
    if [ $i -eq 60 ]; then
      echo "✗ MinIO health check failed after 60 attempts" >&2
      echo "Final minio process check:" >&2
      ps aux | grep minio >&2
      echo "Final minio logs:" >&2
      sudo tail -50 /var/log/minio.*.log 2>&1 >&2 || echo "No minio logs found" >&2
      return 1
    fi
    sleep 1
  done
}

check_milvus() {
  echo "Checking Milvus health..." >&2
  for i in {1..90}; do
    if curl -s -f http://127.0.0.1:9091/healthz >/dev/null 2>&1; then
      echo "✓ Milvus is healthy (attempt $i)" >&2
      return 0
    fi
    if [ $i -eq 90 ]; then
      echo "✗ Milvus health check failed after 90 attempts" >&2
      echo "Final milvus process check:" >&2
      ps aux | grep milvus >&2
      echo "Final milvus logs:" >&2
      sudo tail -50 /var/log/milvus.*.log 2>&1 >&2 || echo "No milvus logs found" >&2
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
  echo "One or more services failed health checks" >&2
  echo "=== Final supervisord status ===" >&2
  sudo supervisorctl status >&2 || echo "supervisorctl failed" >&2
  exit 1
fi

echo "All services are healthy!" >&2
