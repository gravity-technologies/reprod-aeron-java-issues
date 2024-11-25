# Aeron Cluster Message Duplication Issue

This repository demonstrates a message duplication issue in Aeron Cluster during leader failover scenarios.

## System Architecture

The test setup consists of:

- **Aeron Core Components**
  - Media Driver
  - Archive
  - Consensus Module
- **Application Components** 
  - 3 Heartbeat Service replicas running in a cluster
  - 1 Aeron client instance

## Message Flow

1. Client sends messages (type `0xF`) to the cluster
2. Each service:
   - Maintains a global sequence number for incoming messages
   - Sends an acknowledgement to the cluster with:
     - Same sequence number
     - Type matching the service ID (e.g. service 0 uses type `0x0`)
   - Validates received acknowledgements are in order (no duplicates or gaps)

## Issue Description

### Test Scenario
1. Node 0 is designated as leader
2. Kill leader (node 0)
3. Restart leader
4. Kill leader again
5. Restart leader again

### Reproduction Steps

1. Configure Environment
   - Create `scripts/local.env.sh` with the following content:
   ```bash
   #!/usr/bin/env bash
   # Replace <repo-path> with absolute path to your local repository
   DATA_DIR=<repo-path>/log
   ARCHIVE_DIR=${DATA_DIR}/archive 
   MEM_DIR=${DATA_DIR}/memdir
   DISK_DIR=${DATA_DIR}/diskdir
   ```

2. Build and Start Services
   ```bash
   # Build Java services and start 3-node cluster
   make build && make reset
   
   # In a separate terminal, start the test client
   make run-client
   ```

3. Trigger Failover Scenario
   ```bash
   # Kill and restart node 0 twice to reproduce issue
   make dupe NODE_ID=0
   ```

4. Verify Issue
   - Check logs in `${DATA_DIR}/logs/javasvc/`
   - Example log pattern indicating duplication:
        ```
        23:07:30.032 INFO  🟠 onRoleChange: LEADER
        23:07:30.697 WARN  🔴 TxResponse duplicate: txID = 34992
        23:07:30.697 INFO  🔵 Received TxResponse1: txID = 34992
        23:07:30.697 WARN  🔴 TxResponse duplicate: txID = 34993
        23:07:30.697 INFO  🔵 Received TxResponse1: txID = 34993
        23:07:30.697 INFO  🔵 Received TxResponse1: txID = 34994
        ```

### Expected Behavior
- Acknowledgement messages should be received in strict sequential order

### Actual Behavior 
- Duplicate acknowledgement messages are observed

### Questions
- Is this a bug or intended behavior?

## Prerequisites

- Java 17
- Gradle
- Go 1.23
