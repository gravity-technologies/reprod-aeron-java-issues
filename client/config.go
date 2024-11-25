package main

import (
	"fmt"
	"os"
)

type Config struct {
	MemDir           string
	EgressChannel    string
	IngressChannel   string
	IngressEndpoints string
}

// LoadConfig loads configuration from environment variables.
func LoadConfig() (*Config, error) {
	cfg := &Config{
		MemDir:           os.Getenv("MEM_DIR"),
		EgressChannel:    "aeron:udp?alias=heartbeat-client-response|endpoint=localhost:0",
		IngressChannel:   "aeron:udp?alias=heartbeat-client-request",
		IngressEndpoints: "0=localhost:9002,1=localhost:9102,2=localhost:9202",
	}

	// Validate required fields
	if cfg.MemDir == "" {
		return nil, fmt.Errorf("MEM_DIR environment variable is required")
	}

	return cfg, nil
}
