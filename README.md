## Overview
A minimal setup consists of
- Aeron modules (archive/media-driver/consensus)
- AeronViewer services (3 replicas)
- AeronViewer client (1 instance)

## Update Environment variables
- Add `scripts/local.env.sh` with the following content (do tailor for your system)
```
#!/usr/bin/env bash
DATA_DIR=/tmp/aerongrvt
ARCHIVE_DIR=${DATA_DIR}/archive
MEM_DIR=${DATA_DIR}/memdir
DISK_DIR=${DATA_DIR}/diskdir
```

## Start Aeron modules
```
make platform
```

## Start AeronViewer services in background
```
make startall
```

## Start AeronViewer client to start sending message to services
```
make run-client
```

## Sending telemetry
Visit `localhost:8080/test` to generate a heartbeat telemetry

## Test node bounce and rehydration
```
make kill-by-id NODE_ID=1
make start-cluster-and-service-by-id NODE_ID=1
```

## Logs
Service logs are located in `${DATA_DIR}/logs/echo` directory

## To shutdown
- `make clean`: this will shutdown all Go and Java processes, cleanup all logs and snapshot files

All cluster file/logs/snapshot are stored in `~/logs` directory. Right now this is hardcoded
