# Milvus Setup (DDEV)

## Overview
- Milvus v2.6.4 installs automatically via `.devpanel/custom_package_installer.sh`.
- We run Milvus in standalone mode with external etcd for reliability in containers.
- Supervisor config is available for monitoring/restart (autostart=false).

## Startup Model
- **etcd**: started via `setsid` during installer; detached daemon on `127.0.0.1:2379`.
- **Milvus**: started via `setsid` during installer: `MILVUSCONF=/etc/milvus/configs/ /usr/bin/milvus run standalone`.
- **Supervisor**: Optional monitoring layer (autostart=false); can be used to restart Milvus if needed.
- Health: `http://127.0.0.1:9091/healthz` returns `OK` when all components are ready.

## Ports
- `19530`: Milvus gRPC
- `9091`: Milvus HTTP mgmt
- `2379`: etcd

## Verify
```bash
ddev exec -u root -- bash -c 'curl -s http://127.0.0.1:9091/healthz && echo && ss -ltnp | grep -E "2379|19530|9091" && echo "---Processes---" && ps aux | grep -E "[e]tcd|[m]ilvus run"'
```

Expected:
- Health: `OK`
- Ports: 19530/9091/2379 listening
- Processes: `etcd` and `/usr/bin/milvus run standalone`

## Logs
```bash
ddev exec tail -n 100 /var/log/etcd.log
ddev exec tail -n 100 /var/log/milvus.out.log
ddev exec tail -n 100 /var/log/milvus.err.log
```

## Restart Procedures
```bash
# Manual restart (recommended)
ddev exec -u root pkill -f milvus
ddev exec -u root -- bash -c 'cd / && sudo setsid bash -c "MILVUSCONF=/etc/milvus/configs/ /usr/bin/milvus run standalone" </dev/null >/var/log/milvus.out.log 2>/var/log/milvus.err.log &'

# Using Supervisor (if needed for monitoring)
ddev exec -u root supervisorctl stop milvus || true
ddev exec -u root supervisorctl start milvus

# Check status
ddev exec curl -s http://127.0.0.1:9091/healthz

# If you need to restart etcd as well
ddev exec -u root pkill -f etcd || true
ddev exec -u root -- bash -c 'sudo setsid etcd --data-dir=/var/lib/etcd \
  --listen-client-urls=http://127.0.0.1:2379 \
  --advertise-client-urls=http://127.0.0.1:2379 \
  --listen-peer-urls=http://127.0.0.1:2380 </dev/null >/var/log/etcd.log 2>&1 &'
# Then restart Milvus
ddev exec -u root -- bash -c 'cd / && sudo setsid bash -c "MILVUSCONF=/etc/milvus/configs/ /usr/bin/milvus run standalone" </dev/null >/var/log/milvus.out.log 2>/var/log/milvus.err.log &'
```

## Why External etcd?
- Embedded etcd can panic if Milvus detects a distributed deployment.
- External etcd avoids that detection path and is robust in containerized environments.
- Production deployments commonly use external etcd; this mirrors that model.

## Why setsid Instead of Supervisor?
- Supervisor in DDEV starts *before* the installer runs, so `autostart=true` doesn't fire for programs added mid-flight.
- `setsid` reliably detaches processes from the init script session, ensuring they persist after installer exits.
- Supervisor remains available as a monitoring/restart tool (`supervisorctl start/stop/restart milvus`).

## Installer Details
- Pre-stages config in `/etc/milvus/configs/` (sets `embed: false`, `localRPCEnabled: true`).
- Installs Milvus deb noninteractively (preserves staged config).
- Starts etcd via `setsid` for persistent background daemon.
- Starts Milvus via `setsid` for persistent background daemon.
- Copies Supervisor config from `.devpanel/milvus/milvus.conf` to `/etc/supervisor/conf.d/` (autostart=false, for optional monitoring/restart).
- Waits for health check (`/healthz`) before completing.

## Common Troubleshooting
- **Health shows `Not all components are healthy, 3/5`**:
  - Wait 30–60s; components finish initialization.
  - Check `/var/log/milvus.err.log` for etcd client retries; ensure etcd is up.
- **`panic: failed to create etcd client: context deadline exceeded`**:
  - etcd wasn't running/ready; restart etcd first, then Milvus.
- **Process not found after restart**:
  - Verify with `ps aux | grep -E "[e]tcd|[m]ilvus run"`.
  - Check logs: `tail -f /var/log/milvus.err.log` or `/var/log/etcd.log`.
- **Supervisor shows errors**:
  - Normal if `autostart=false`; Supervisor is for manual restart only.
  - Use `supervisorctl start milvus` if you want Supervisor to manage the process.

## References
- Config: `/etc/milvus/configs/milvus.yaml`
- Data: `/var/lib/milvus/`, `/var/lib/etcd/`
- Supervisor: `/etc/supervisor/conf.d/milvus.conf`
