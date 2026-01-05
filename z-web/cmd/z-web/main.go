package main

import (
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	"github.com/stevemurr/z/z-web/internal/server"
)

//go:embed all:dist
var staticFiles embed.FS

func main() {
	port := flag.Int("port", 7680, "Port to listen on")
	host := flag.String("host", "tailscale", "Host to bind to (tailscale, localhost, or IP)")
	flag.Parse()

	// Create server
	srv := server.New()

	// Set up routes
	mux := http.NewServeMux()

	// WebSocket endpoint
	mux.HandleFunc("/ws", srv.HandleWebSocket)

	// API endpoints
	mux.HandleFunc("/api/sessions", srv.HandleSessions)
	mux.HandleFunc("/api/sessions/create", srv.HandleCreateSession)

	// Static files (frontend)
	staticFS, err := fs.Sub(staticFiles, "dist")
	if err != nil {
		log.Fatal("Failed to load static files:", err)
	}
	mux.Handle("/", http.FileServer(http.FS(staticFS)))

	// Start server based on host mode
	if *host == "localhost" {
		// Local development mode - HTTP only
		addr := fmt.Sprintf("127.0.0.1:%d", *port)
		fmt.Printf("z-web server starting (HTTP mode)...\n")
		fmt.Printf("  Local: http://%s\n", addr)
		fmt.Println()
		fmt.Println("Press Ctrl+C to stop")

		if err := http.ListenAndServe(addr, mux); err != nil {
			log.Fatal("Server error:", err)
		}
	} else {
		// Tailscale mode - HTTPS required
		hostname, certFile, keyFile, err := setupTailscaleCerts()
		if err != nil {
			log.Fatal("Failed to setup Tailscale certs: ", err)
		}

		addr := fmt.Sprintf(":%d", *port)
		fmt.Printf("z-web server starting (HTTPS mode)...\n")
		fmt.Printf("  URL: https://%s:%d\n", hostname, *port)
		fmt.Println()
		fmt.Println("Press Ctrl+C to stop")

		if err := http.ListenAndServeTLS(addr, certFile, keyFile, mux); err != nil {
			log.Fatal("Server error:", err)
		}
	}
}

// setupTailscaleCerts gets the Tailscale hostname and provisions TLS certificates
// Returns: hostname, certFile, keyFile, error
func setupTailscaleCerts() (string, string, string, error) {
	// Get Tailscale status to find our DNS name
	cmd := exec.Command("tailscale", "status", "--json")
	output, err := cmd.Output()
	if err != nil {
		return "", "", "", fmt.Errorf("failed to get tailscale status: %w", err)
	}

	var status struct {
		Self struct {
			DNSName string `json:"DNSName"`
		} `json:"Self"`
	}
	if err := json.Unmarshal(output, &status); err != nil {
		return "", "", "", fmt.Errorf("failed to parse tailscale status: %w", err)
	}

	hostname := strings.TrimSuffix(status.Self.DNSName, ".")
	if hostname == "" {
		return "", "", "", fmt.Errorf("tailscale DNS name not found (is MagicDNS enabled?)")
	}

	// Determine cert directory
	certDir, err := getCertDir()
	if err != nil {
		return "", "", "", fmt.Errorf("failed to get cert directory: %w", err)
	}

	certFile := filepath.Join(certDir, hostname+".crt")
	keyFile := filepath.Join(certDir, hostname+".key")

	// Provision certificates using tailscale cert
	cmd = exec.Command("tailscale", "cert",
		"--cert-file", certFile,
		"--key-file", keyFile,
		hostname)
	if output, err := cmd.CombinedOutput(); err != nil {
		return "", "", "", fmt.Errorf("failed to provision certs: %w\n%s", err, output)
	}

	return hostname, certFile, keyFile, nil
}

// getCertDir returns the directory for storing certificates
func getCertDir() (string, error) {
	// Use ~/.config/z-web/certs
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}

	certDir := filepath.Join(home, ".config", "z-web", "certs")
	if err := os.MkdirAll(certDir, 0700); err != nil {
		return "", err
	}

	return certDir, nil
}
