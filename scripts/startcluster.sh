#!/usr/bin/env bash

# RUN VALIDATIONS
. scripts/env.sh
if [ -f scripts/local.env.sh ]; then
    source scripts/local.env.sh
fi

# COPY FROM TUTORIAL
# https://github.com/real-logic/aeron/wiki/Cluster-Tutorial
# https://github.com/real-logic/aeron/blob/1.40.0_tutorial_patch/aeron-samples/src/main/java/io/aeron/samples/cluster/tutorial/BasicAuctionClusteredServiceNode.java

# tag::start_jvm[]
function calculatePort() {
    echo $((PORT_BASE + ${1} * PORTS_PER_NODE + ${2}))
}

function rawChannel() {
    echo "aeron:${1}"
}

function udpEndpoint() {
    echo "aeron:udp?endpoint=${HOSTS[${1}]}:$(calculatePort ${1} ${2})"
}

function getMemDir() {
    echo "${MEM_DIR}/aeron-cluster-${1}"
}

function getDiskDir() {
    echo "${DISK_DIR}/aeron-cluster-${1}"
}

function getArchiveDir() {
    echo "${ARCHIVE_DIR}/aeron-cluster-${1}"
}

function clusterMembers() {
    local members=""
    for i in "${!HOSTS[@]}"
    do
        members+=${i}
        members+=,${HOSTS[${i}]}:$(calculatePort ${i} ${CLIENT_FACING_PORT_OFFSET})
        members+=,${HOSTS[${i}]}:$(calculatePort ${i} ${MEMBER_FACING_PORT_OFFSET})
        members+=,${HOSTS[${i}]}:$(calculatePort ${i} ${LOG_PORT_OFFSET})
        members+=,${HOSTS[${i}]}:$(calculatePort ${i} ${TRANSFER_PORT_OFFSET})
        members+=,${HOSTS[${i}]}:$(calculatePort ${i} ${ARCHIVE_CONTROL_PORT_OFFSET})
        members+="|"
    done
    echo $members
}

function aeronBaseCmd() {
    echo ${JAVA_HOME}/bin/java -cp aeron-all-${VERSION}.jar \
    --add-opens java.base/sun.nio.ch=ALL-UNNAMED \
    -XX:+UnlockExperimentalVMOptions \
    -XX:+UseZGC \
    -XX:+HeapDumpOnOutOfMemoryError \
    $(javaHeapSize)
}

function debugOptions() {
    # Specific logs can be silenced in debug mode
    # -Daeron.event.cluster.log.disable=CANVASS_POSITION,APPEND_POSITION,COMMIT_POSITION \
    if [[ $DEBUG == 'true' ]]; then
        echo -javaagent:aeron-agent-${VERSION}.jar \
        -XX:+UnlockExperimentalVMOptions \
        -Daeron.event.cluster.log=all \
        -Daeron.print.configuration=${DEBUG}
    fi
}

function mediaDriverOptions() {
    echo -Daeron.dir=$(getMemDir ${1}) \
    -Daeron.threading.mode=${THREADING} \
    -XX:+UnlockExperimentalVMOptions \
    -Daeron.mtu.length=8192 \
    -Daeron.ipc.mtu.length=8192
}

function archiveOptions() {
    echo -Daeron.archive.control.channel=$(udpEndpoint ${1} ${ARCHIVE_CONTROL_PORT_OFFSET}) \
    -XX:+UnlockExperimentalVMOptions \
    -Daeron.archive.replication.channel=$(udpEndpoint ${1} 0) \
    -Daeron.archive.control.response.channel=$(udpEndpoint ${1} 0) \
    -Daeron.archive.dir=$(getArchiveDir ${1}) \
    -Daeron.archive.mark.file.dir=$(getDiskDir ${1})
}

function consensusOptions() {
    echo -Daeron.archive.dir=$(getArchiveDir ${1}) \
    -XX:+UnlockExperimentalVMOptions \
    -Daeron.cluster.appointed.leader.id=0 \
    -Daeron.cluster.member.id=${1} \
    -Daeron.cluster.id=0 \
    -Daeron.cluster.members=$(clusterMembers) \
    -Daeron.cluster.dir=$(getDiskDir ${1}) \
    -Daeron.cluster.mark.file.dir=$(getDiskDir ${1}) \
    -Daeron.cluster.ingress.channel=$(rawChannel udp) \
    -Daeron.cluster.replication.channel=$(udpEndpoint ${1} 0) \
    -Daeron.cluster.control.channel="aeron:ipc?term-length=128k|alias=service-control" \
    -Daeron.cluster.service.count=${SERVICE_COUNT} \
    -Daeron.cluster.timer.service.supplier=io.aeron.cluster.WheelTimerServiceSupplier \
    -Daeron.cluster.wheel.tick.resolution=4000000 \
    -Daeron.cluster.ticks.per.wheel=8 \
    -Daeron.cluster.clock=io.aeron.cluster.NanosecondClusterClock
}

function javaHeapSize() {
    if [ "${THREADING}" = "DEDICATED" ]; then
        echo -Xms2g -Xmx2g
    else
        echo -Xms300m -Xmx300m
    fi
}

function startMediaDriver() {
    $(aeronBaseCmd) \
    $(debugOptions) \
    $(mediaDriverOptions ${1}) \
    -Daeron.mdtag=${1} \
    -XX:+UnlockExperimentalVMOptions \
    io.aeron.driver.MediaDriver & disown
}

function startArchive() {
    $(aeronBaseCmd) \
    $(debugOptions) \
    $(mediaDriverOptions ${1}) \
    $(archiveOptions ${1}) \
    -Daeron.archivetag=${1} \
    -XX:+UnlockExperimentalVMOptions \
    io.aeron.archive.Archive & disown
}

function startConsensusModule() {
    $(aeronBaseCmd) \
    $(debugOptions) \
    $(mediaDriverOptions ${1}) \
    $(archiveOptions ${1}) \
    $(consensusOptions ${1}) \
    -Daeron.consensustag=${1} \
    -XX:+UnlockExperimentalVMOptions \
    io.aeron.cluster.ConsensusModule & disown
}

function startNode() {
    while pgrep -f "mdtag=${1}|archivetag=${1}" >/dev/null 2>&1; do
        echo "🔴 MD/ARCHIVE ${1} is running, waiting for it to shutdown"
        sleep 0.5
    done
    startMediaDriver ${1}
    startArchive ${1}
}

function threadingModeOptions() {
    if [ "${THREADING}" = "DEDICATED" ]; then
        echo -Daeron.conductor.idle.strategy=org.agrona.concurrent.BusySpinIdleStrategy \
        -XX:+UnlockExperimentalVMOptions \
        -Daeron.sender.idle.strategy=org.agrona.concurrent.NoOpIdleStrategy \
        -Daeron.receiver.idle.strategy=org.agrona.concurrent.NoOpIdleStrategy
    else
        echo -Daeron.conductor.idle.strategy=org.agrona.concurrent.BackoffIdleStrategy \
        -XX:+UnlockExperimentalVMOptions \
        -Daeron.sender.idle.strategy=org.agrona.concurrent.BackoffIdleStrategy \
        -Daeron.receiver.idle.strategy=org.agrona.concurrent.BackoffIdleStrategy
    fi
}

function startAll() {
    echo "starting full cluster"
    startNode 0
    startNode 1
    startNode 2
}

# Give a second for logs to be created before tailing
# sleep 1
# tail -n 100 -F ${DISK_DIR}/aeron-cluster-*/*.log
