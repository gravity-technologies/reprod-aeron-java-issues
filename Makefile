SHELL := /bin/bash
.PHONY: help

# Default target when no arguments are provided
.DEFAULT_GOAL := help

# Import environment variables and configurations
include scripts/env.sh

# Import local environment overrides if they exist
ifneq ($(wildcard scripts/local.env.sh),)
	include scripts/local.env.sh
endif

# Display help information for all make targets
.PHONY: help
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-30s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ''

# Check if required environment variables are set
.PHONY: check-env
check-env:
	@if [ -z "$(DATA_DIR)" ]; then \
		echo "⛔️ ERROR: DATA_DIR is not set. This is required for storing cluster data and logs."; \
		echo "Please set DATA_DIR in scripts/env.sh or scripts/local.env.sh"; \
		exit 1; \
	fi
	@if [ ! -d "$(DATA_DIR)" ]; then \
		echo "⚠️  Warning: DATA_DIR ($(DATA_DIR)) does not exist. Creating it now..."; \
		mkdir -p "$(DATA_DIR)"; \
	fi

# =================== GRVT Services Section ===================
.PHONY: build
build: check-env ## Build all Java-based cluster services using Gradle
	cd cluster && gradle build

.PHONY: run-client
run-client: check-env ## Start the Aeron client for Java services with configured memory directory
	MEM_DIR=${MEM_DIR}/aeron-cluster-0 go run client/*.go

.PHONY: start
start: check-env ## Start a specific cluster node (use with node=X parameter)
	source scripts/grvt.sh && startNode ${node}

.PHONY: start-cluster-and-service-by-id
start-cluster-and-service-by-id: check-env ## Start both cluster and service components for a specific node ID
	@echo "🟢 Starting node $(NODE_ID)"
	source scripts/startcluster.sh && startNode $(NODE_ID)
	sleep 2
	source scripts/grvt.sh && startNode $(NODE_ID)

.PHONY: kill-by-id
kill-by-id: check-env ## Terminate a specific node by its ID (use with NODE_ID=X parameter)
	@echo "🔴 Killing node $(NODE_ID)"
	@pkill -f "mdtag=$(NODE_ID)" || true

.PHONY: find-leader
find-leader: check-env ## Identify and store the current cluster leader ID
	@echo "🟢 Finding leader... ${DISK_DIR}"
	LEADER_ID=$(shell java -cp aeron-all-${VERSION}.jar io.aeron.cluster.ClusterTool ${DISK_DIR}/aeron-cluster-0 list-members | sed -n "s/.*activeMembers=\[\(.*\)\],.*/\1/p" | grep -oE "ClusterMember\{[^}]*isLeader=true[^}]*\}" | sed -n "s/.*id=\([0-9]*\),.*/\1/p"); \
	echo $$LEADER_ID > ${DISK_DIR}/leader_id.txt

.PHONY: startall
startall: check-env ## Initialize and start all cluster nodes (0, 1, and 2)
	source scripts/grvt.sh && startNode 0
	source scripts/grvt.sh && startNode 1
	source scripts/grvt.sh && startNode 2

.PHONY: reset
reset: check-env ## Perform a complete cluster reset: clean, rebuild platform, and restart all services
	make clean || true
	sleep 1
	make platform || true
	sleep 1
	make startall || true
	sleep 3
	make find-leader 

.PHONY: dupe
dupe: check-env ## Simulate message duplication by forcing leader failures and restarts
	sleep 5
	make kill-by-id NODE_ID=$(NODE_ID)
	sleep 10
	@make start-cluster-and-service-by-id NODE_ID=$(NODE_ID)
	sleep 3.5
	@make kill-by-id NODE_ID=$(NODE_ID)
	sleep 10
	@make start-cluster-and-service-by-id NODE_ID=$(NODE_ID)
	sleep 15

.PHONY: killall
killall: check-env ## Terminate all running cluster services
	source scripts/grvt.sh && killall

# =================== Aeron Platform Section ===================
.PHONY: platform
platform: check-env ## Initialize and run the Golang benchmark cluster with required dependencies
	bash scripts/getjars.sh
	bash scripts/startclient.sh &
	source scripts/startcluster.sh && startAll

.PHONY: clean
clean: check-env ## Clean up all Aeron cluster artifacts (processes, disk, memory, and data directories)
	@rm -rf ./time*
	@rm -rf ${ARCHIVE_DIR}/*
	@rm -rf ${MEM_DIR}/*
	@rm -rf ${DISK_DIR}/*
	@rm -rf ${DATA_DIR}/javasvc/*
	@rm -rf ${DATA_DIR}/viewer/*
	-@pkill -f aeron-all || true
	@source scripts/grvt.sh && killall || true
	@pkill -f org.example.Container || true
	@killall -9 tail || true
	@pkill -f main.go || true

.PHONY: kill
kill: check-env ## Terminate a specific node (use with node=X parameter)
	. scripts/grvt.sh && kill ${node}

.PHONY: consensus
consensus: check-env ## Start the consensus module for a specific node (use with node=X parameter)
	source scripts/startcluster.sh && startConsensusModule ${node}

# Ensure help is the default target
.DEFAULT_GOAL := help
