package main

import (
	"encoding/binary"
	"encoding/json"
	"log"
	"os"
	"time"

	"github.com/lirm/aeron-go/aeron"
	"github.com/lirm/aeron-go/aeron/atomic"
	"github.com/lirm/aeron-go/aeron/idlestrategy"
	"github.com/lirm/aeron-go/aeron/logbuffer"
	"github.com/lirm/aeron-go/cluster/client"
	"go.uber.org/zap/zapcore"
)

// How often should we publish a message
const messageFrequencyInMs = 1
const messageBatchCount = 1

type MsgType uint8

const (
	MsgType_txRequest MsgType = 0xF
)

var txID uint64 = 0

func main() {
	cfg, err := LoadConfig()
	if err != nil {
		panic(err)
	}
	Run(cfg)
}

func Run(cfg *Config) {
	// 1. Setup
	jsonConfig, err := json.Marshal(cfg)
	if err != nil {
		panic(err)
	}
	log.Println("Config: ", string(jsonConfig))

	setupEnv(cfg)

	// 2. Prepare the payload and publish here
	ticker := time.NewTicker(1 * time.Millisecond)
	defer ticker.Stop()

	// Starting a dummy client that send payload to the cluster periodically
	client := createClient(cfg)
	client.SendKeepAlive()
	offerCluster(client, genTxRequest(txID))
	txID++
	lastKeepAlive := time.Now()
	lastMsgTime := time.Now()
	for {
		<-ticker.C
		// VERY IMPORTANT, this line keep the client aware of all the changes in the cluster, eg: new leader, disconnection, etc...
		// It doesn't matter how often you poll, (10ms, 100ms, 2s, 5s are all fine) as long as you do it periodically
		client.Poll()
		if time.Since(lastKeepAlive).Seconds() > 2 {
			keepAliveOk := client.SendKeepAlive()
			if !keepAliveOk {
				continue
			}
			lastKeepAlive = time.Now()
		}
		duration := time.Since(lastMsgTime)
		if duration.Milliseconds() >= messageFrequencyInMs {
			connectToCluster(client, getClientOpts(cfg))
			for range messageBatchCount {
				offerCluster(client, genTxRequest(txID))
				log.Println("Sent txID: ", txID)
				txID++
			}
			lastMsgTime = time.Now()
		}
	}
}

func createClient(cfg *Config) *client.AeronCluster {
	ctx := aeron.NewContext()
	ctx.AeronDir(cfg.MemDir)
	opts := getClientOpts(cfg)
	client, err := client.NewAeronCluster(ctx, opts, &Listener{})
	if err != nil {
		panic(err)
	}

	return connectToCluster(client, opts)
}

func connectToCluster(client *client.AeronCluster, opts *client.Options) *client.AeronCluster {
	client.Poll()
	for !client.IsConnected() {
		opts.IdleStrategy.Idle(client.Poll())
	}
	return client
}

func offerCluster(client *client.AeronCluster, buf *atomic.Buffer) {
	log.Printf("Sending payload... isConnected=%v leaderMemberID=%d", client.IsConnected(), client.LeaderMemberId())
	success := false
	for i := 0; i < 3 && !success; i++ {
		r := client.Offer(buf, 0, buf.Capacity())
		if r >= 0 {
			log.Println("✅ Sending OK")
			return
		}
		client.Poll()
	}

	log.Println("❌ Sending FAILED")
}

func setupEnv(cfg *Config) {
	if _, err := os.Stat(cfg.MemDir); os.IsNotExist(err) {
		panic("MemDir does not exist: " + cfg.MemDir)
	}
}

func getClientOpts(cfg *Config) *client.Options {
	opts := client.NewOptions()
	opts.IdleStrategy = idlestrategy.NewDefaultBackoffIdleStrategy()
	opts.Loglevel = zapcore.DebugLevel
	opts.IngressChannel = cfg.IngressChannel
	opts.IngressEndpoints = cfg.IngressEndpoints
	opts.EgressChannel = cfg.EgressChannel
	return opts
}

type Listener struct {
}

func (ctx *Listener) OnConnect(ac *client.AeronCluster) {
	log.Printf("OnConnect, clusterSessionID=%d\n", ac.ClusterSessionId())
}

func (ctx *Listener) OnDisconnect(cluster *client.AeronCluster, details string) {
}

func (ctx *Listener) OnMessage(_ *client.AeronCluster, _ int64,
	_ *atomic.Buffer, offset int32, length int32, _ *logbuffer.Header) {
}

func (ctx *Listener) OnNewLeader(cluster *client.AeronCluster, _ int64, leaderMemberID int32) {
}

func (ctx *Listener) OnError(_ *client.AeronCluster, details string) {
	log.Println("OnError", details)
}

func genTxRequest(txID uint64) *atomic.Buffer {
	b := make([]byte, 9)
	b[0] = byte(MsgType_txRequest)
	binary.BigEndian.PutUint64(b[1:], txID)
	return atomic.MakeBuffer(b)
}
