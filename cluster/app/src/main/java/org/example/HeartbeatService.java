package org.example;

import java.nio.ByteOrder;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import org.agrona.DirectBuffer;
import org.agrona.ExpandableArrayBuffer;
import org.agrona.collections.MutableBoolean;
import org.agrona.concurrent.IdleStrategy;

import io.aeron.ExclusivePublication;
import io.aeron.Image;
import io.aeron.cluster.codecs.CloseReason;
import io.aeron.cluster.service.ClientSession;
import io.aeron.cluster.service.Cluster;
import io.aeron.cluster.service.ClusteredService;
import io.aeron.logbuffer.FragmentHandler;
import io.aeron.logbuffer.Header;

class HeartbeatService implements ClusteredService {
    private FileLogger logger;

    // Global sequence number for incoming messages from aeron client
    private static final byte MSG_TYPE_TX_REQUEST = 0xF;

    // Each service only handle messages with the MSG_TYPE that matches its
    // serviceID
    // ie: Service 0 handles 0x00, 1 handles 0x01, 2 handles 0x02
    private static final byte MSG_TYPE_TX_RESPONSE_0 = 0x00;
    private static final byte MSG_TYPE_TX_RESPONSE_1 = 0x01;
    private static final byte MSG_TYPE_TX_RESPONSE_2 = 0x02;

    protected Cluster cluster;
    protected IdleStrategy idleStrategy;
    private final int serviceID;
    private final int nodeID;

    // State
    private long lastRequestTxID = 0;
    private static final Map<Long, Long> lastResponseTxIDMap = new HashMap<>();
    private final Set<Long> seenRequestTxIDs = new HashSet<Long>();

    private static final int SNAPSHOT_MESSAGE_LENGTH = 32;

    public HeartbeatService(int serviceID, int nodeID, String logDir) {
        this.serviceID = serviceID;
        this.nodeID = nodeID;
        logger = new FileLogger(logDir, nodeID, serviceID);
        lastResponseTxIDMap.put((long) MSG_TYPE_TX_RESPONSE_0, 0L);
        lastResponseTxIDMap.put((long) MSG_TYPE_TX_RESPONSE_1, 0L);
        lastResponseTxIDMap.put((long) MSG_TYPE_TX_RESPONSE_2, 0L);
    }

    public void onStart(final Cluster cluster, final Image snapshotImage) {
        logger.info("🟠 onStart, serviceID = {}, nodeID = {}", serviceID, nodeID);
        this.cluster = cluster;
        idleStrategy = cluster.idleStrategy();
        if (snapshotImage != null) {
            logger.info("📸 onStart, loading snapshot");
            loadSnapshot(snapshotImage);
        }
    }

    private void loadSnapshot(final Image snapshotImage) {
        final MutableBoolean isAllDataLoaded = new MutableBoolean(false);
        final FragmentHandler fragmentHandler = (buffer, offset, length, header) -> {
            assert length >= SNAPSHOT_MESSAGE_LENGTH;
            final long txID0 = buffer.getLong(offset);
            final long txID1 = buffer.getLong(offset + 8);
            final long txID2 = buffer.getLong(offset + 16);
            final long txID = buffer.getLong(offset + 24);
            logger.info("📸 onTakeSnapshot, txID0 = {}, txID1 = {}, txID2 = {}, lastRequestTxID = {}", txID0, txID1,
                    txID2, txID);
            lastResponseTxIDMap.put((long) MSG_TYPE_TX_RESPONSE_0, txID0);
            lastResponseTxIDMap.put((long) MSG_TYPE_TX_RESPONSE_1, txID1);
            lastResponseTxIDMap.put((long) MSG_TYPE_TX_RESPONSE_2, txID2);
            lastRequestTxID = txID;

            isAllDataLoaded.set(true);
        };

        while (!snapshotImage.isEndOfStream()) {
            final int fragmentsPolled = snapshotImage.poll(fragmentHandler, 1);

            if (isAllDataLoaded.value) {
                break;
            }

            idleStrategy.idle(fragmentsPolled);
        }
    }

    public void onSessionOpen(final ClientSession session, final long timestamp) {
        logger.info("🟠 onSessionOpen");
    }

    public void onSessionClose(final ClientSession session, final long timestamp, final CloseReason closeReason) {
        logger.info("🟠 onSessionClose");
    }

    public void onSessionMessage(
            final ClientSession session,
            final long timestamp,
            final DirectBuffer buffer,
            final int offset,
            final int length,
            final Header header) {
        final byte typ = buffer.getByte(offset);

        switch (typ) {
            case MSG_TYPE_TX_REQUEST:
                handleClientMessage();
                break;
            case MSG_TYPE_TX_RESPONSE_0:
            case MSG_TYPE_TX_RESPONSE_1:
            case MSG_TYPE_TX_RESPONSE_2:
                handleClusterMessage(buffer, offset, length, typ);
                break;
        }
    }

    private void offerCluster(final DirectBuffer buffer, final int offset, final int length) {
        idleStrategy.reset();
        while (cluster.offer(buffer, offset, length) < 0) {
            idleStrategy.idle();
        }
    }

    // For each incoming message from aeron client, increment the sequence number
    // and offer it to the cluster
    private void handleClientMessage() {
        lastRequestTxID++;
        offerCluster(getTxResponse((byte) serviceID, lastRequestTxID), 0, 9);
    }

    private DirectBuffer getTxResponse(byte typ, long txID) {
        final ExpandableArrayBuffer msgBuffer = new ExpandableArrayBuffer(9);
        msgBuffer.putByte(0, typ);
        msgBuffer.putLong(1, txID, ByteOrder.BIG_ENDIAN);
        return msgBuffer;
    }

    // Helper function to read long in big-endian order using bit manipulation
    private long readLongBE(final DirectBuffer buffer, final int offset) {
        long value = 0L;
        // Read 8 bytes and shift them into position
        for (int i = 0; i < 8; i++) {
            // Read each byte and mask with 0xFF to handle signed/unsigned conversion
            long byteVal = buffer.getByte(offset + i) & 0xFF;
            // Shift the byte to its position (leftmost byte is most significant)
            value |= byteVal << ((7 - i) * 8);
        }
        return value;
    }

    // Handle cluster-to-cluster messages, verifying that we receive messages with
    // the correct sequence number.
    // 1. No duplicate: message sequence number must not be seen in the past, during
    // the same run
    // 2. No skipped message: message sequence number must be consecutive
    private void handleClusterMessage(final DirectBuffer buffer, final int offset, final int length,
            final byte txResponseType) {
        if (serviceID != txResponseType) {
            return;
        }
        long newTxID = readLongBE(buffer, offset + 1);
        checkIfSeen(newTxID);
        logger.info("🔵 Received TxResponse{}: txID = {}", txResponseType, newTxID);
        long lastTxID = lastResponseTxIDMap.get((long) txResponseType);
        if (newTxID > lastTxID + 1) {
            logger.warn("🔴💀🔴 TxResponse{} skipped message: expected = {}, actual = {}", txResponseType, lastTxID + 1,
                    newTxID);
        }
        lastResponseTxIDMap.put((long) txResponseType, newTxID);
    }

    public void onTimerEvent(final long correlationId, final long timestamp) {
    }

    public void onTakeSnapshot(final ExclusivePublication pub) {
        logger.info("📸 onTakeSnapshot");
        final ExpandableArrayBuffer buffer = new ExpandableArrayBuffer(32);
        buffer.putLong(0, lastResponseTxIDMap.get((long) MSG_TYPE_TX_RESPONSE_0), ByteOrder.BIG_ENDIAN);
        buffer.putLong(8, lastResponseTxIDMap.get((long) MSG_TYPE_TX_RESPONSE_1), ByteOrder.BIG_ENDIAN);
        buffer.putLong(16, lastResponseTxIDMap.get((long) MSG_TYPE_TX_RESPONSE_2), ByteOrder.BIG_ENDIAN);
        buffer.putLong(24, lastRequestTxID, ByteOrder.BIG_ENDIAN);

        idleStrategy.reset();
        while (pub.offer(buffer, 0, buffer.capacity()) <= 0) {
            idleStrategy.idle();
        }
    }

    public void onRoleChange(final Cluster.Role newRole) {
        logger.info("🟠 onRoleChange: " + newRole.toString());
    }

    public void onTerminate(final Cluster cluster) {
        logger.info("✋ onTerminate");
    }

    public void checkIfSeen(long txID) {
        if (seenRequestTxIDs.contains(txID)) {
            logger.warn("🔴 TxResponse duplicate: txID = {}", txID);
        }
        seenRequestTxIDs.add(txID);
    }
}
