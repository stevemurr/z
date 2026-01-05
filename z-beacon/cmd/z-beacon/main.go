package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strings"
)

// BeaconResponse is returned by the /z-beacon endpoint
type BeaconResponse struct {
	Name        string `json:"name"`
	Version     string `json:"version"`
	TailscaleIP string `json:"tailscale_ip"`
}

func main() {
	port := flag.Int("port", 7681, "Port to listen on")
	flag.Parse()

	// Get Tailscale IP
	tsIP := getTailscaleIP()
	if tsIP == "" {
		log.Fatal("Tailscale not available or not connected")
	}

	// Get machine name from z sys
	machineName := getMachineName()

	// Set up HTTP handler
	http.HandleFunc("/z-beacon", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(BeaconResponse{
			Name:        machineName,
			Version:     "1.0.0",
			TailscaleIP: tsIP,
		})
	})

	// Bind to Tailscale IP only (security via tailnet)
	addr := fmt.Sprintf("%s:%d", tsIP, *port)
	fmt.Printf("z-beacon listening on http://%s\n", addr)

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal("Server error:", err)
	}
}

// getTailscaleIP returns the IPv4 Tailscale address
func getTailscaleIP() string {
	cmd := exec.Command("tailscale", "ip", "-4")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(output))
}

// getMachineName gets the machine name from z sys or falls back to hostname
func getMachineName() string {
	// Try to read from z's machines.json
	home, err := os.UserHomeDir()
	if err != nil {
		return getHostname()
	}

	machinesFile := home + "/.z/sys/machines.json"
	data, err := os.ReadFile(machinesFile)
	if err != nil {
		return getHostname()
	}

	// Simple JSON parsing for this_machine field
	var config struct {
		ThisMachine string `json:"this_machine"`
	}
	if err := json.Unmarshal(data, &config); err != nil {
		return getHostname()
	}

	if config.ThisMachine != "" {
		return config.ThisMachine
	}
	return getHostname()
}

// getHostname returns the system hostname
func getHostname() string {
	hostname, err := os.Hostname()
	if err != nil {
		return "unknown"
	}
	// Remove domain suffix if present
	if idx := strings.Index(hostname, "."); idx != -1 {
		hostname = hostname[:idx]
	}
	return hostname
}
