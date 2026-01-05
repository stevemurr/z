package main

import (
	"embed"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"strings"

	"github.com/stevemurr/z/z-web/internal/server"
)

//go:embed all:dist
var staticFiles embed.FS

func main() {
	port := flag.Int("port", 7680, "Port to listen on")
	host := flag.String("host", "tailscale", "Host to bind to (tailscale, localhost, or IP)")
	flag.Parse()

	// Resolve host
	bindAddr := resolveHost(*host)
	addr := fmt.Sprintf("%s:%d", bindAddr, *port)

	// Create server
	srv := server.New()

	// Set up routes
	mux := http.NewServeMux()

	// WebSocket endpoint
	mux.HandleFunc("/ws", srv.HandleWebSocket)

	// API endpoints
	mux.HandleFunc("/api/sessions", srv.HandleSessions)

	// Static files (frontend)
	staticFS, err := fs.Sub(staticFiles, "dist")
	if err != nil {
		log.Fatal("Failed to load static files:", err)
	}
	mux.Handle("/", http.FileServer(http.FS(staticFS)))

	// Start server
	fmt.Printf("z-web server starting...\n")
	fmt.Printf("  Local:   http://%s\n", addr)
	if bindAddr != "127.0.0.1" && bindAddr != "localhost" {
		fmt.Printf("  Network: http://%s:%d\n", getOutboundIP(), *port)
	}
	fmt.Println()
	fmt.Println("Press Ctrl+C to stop")

	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal("Server error:", err)
	}
}

// resolveHost converts host flag to actual bind address
func resolveHost(host string) string {
	switch host {
	case "localhost":
		return "127.0.0.1"
	case "tailscale":
		// Try to get Tailscale IP
		if ip := getTailscaleIP(); ip != "" {
			return ip
		}
		fmt.Println("Warning: Could not detect Tailscale IP, binding to localhost")
		return "127.0.0.1"
	default:
		return host
	}
}

// getTailscaleIP tries to get the Tailscale IP address
func getTailscaleIP() string {
	// Try tailscale CLI first
	cmd := exec.Command("tailscale", "ip", "-4")
	output, err := cmd.Output()
	if err == nil {
		ip := strings.TrimSpace(string(output))
		if ip != "" {
			return ip
		}
	}

	// Fallback: look for tailscale interface
	interfaces, err := net.Interfaces()
	if err != nil {
		return ""
	}

	for _, iface := range interfaces {
		if strings.HasPrefix(iface.Name, "tailscale") || iface.Name == "utun" {
			addrs, err := iface.Addrs()
			if err != nil {
				continue
			}
			for _, addr := range addrs {
				if ipnet, ok := addr.(*net.IPNet); ok && ipnet.IP.To4() != nil {
					if strings.HasPrefix(ipnet.IP.String(), "100.") {
						return ipnet.IP.String()
					}
				}
			}
		}
	}

	return ""
}

// getOutboundIP gets the preferred outbound IP
func getOutboundIP() string {
	conn, err := net.Dial("udp", "8.8.8.8:80")
	if err != nil {
		return "unknown"
	}
	defer conn.Close()
	localAddr := conn.LocalAddr().(*net.UDPAddr)
	return localAddr.IP.String()
}
