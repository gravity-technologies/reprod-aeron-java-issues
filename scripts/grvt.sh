#!/usr/bin/env bash

source scripts/env.sh
if [ -f scripts/local.env.sh ]; then
    source scripts/local.env.sh
fi


function startNode() {
    make consensus node=${1}
    startJavaService ${1}
}

function kill() {
    pkill -f consensustag=${1}
    pkill -f zamp=${1}
    pkill -f svc${1}
}

function killall() {
    kill 0
    kill 1
    kill 2
}

function startJavaService() {
    mkdir -p ${MEM_DIR}/aeron-cluster-${1}/
    mkdir -p ${ARCHIVE_DIR}/aeron-cluster-${1}/
    mkdir -p ${DISK_DIR}/aeron-cluster-${1}/
    mkdir -p log/javasvc

    echo "🟠 starting Java service ${1}"
    MEM_DIR=${MEM_DIR} \
    ARCHIVE_DIR=${ARCHIVE_DIR} \
    DISK_DIR=${DISK_DIR} \
    java -cp ./java/app/build/libs/app.jar \
    -javaagent:./aeron-agent-${VERSION}.jar \
    -Daeron.cluster.member.id=${1} \
    -Daeron.mdtag=${1} \
    -Dheartbeat.log.dir=${DATA_DIR}/javasvc/ \
    org.example.Container & disown
}

