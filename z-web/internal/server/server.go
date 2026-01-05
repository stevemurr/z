package server

import (
	"encoding/json"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"sync"

	"github.com/gorilla/websocket"
	"github.com/stevemurr/z/z-web/internal/session"
	"github.com/stevemurr/z/z-web/internal/ws"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins (Tailscale provides security)
	},
}

// Server handles HTTP and WebSocket connections
type Server struct {
	sessions *session.Manager
}

// New creates a new server
func New() *Server {
	return &Server{
		sessions: session.NewManager(),
	}
}

// HandleSessions handles GET /api/sessions
func (s *Server) HandleSessions(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	sessions, err := s.sessions.List()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(sessions)
}

// HandleWebSocket handles WebSocket connections
func (s *Server) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("WebSocket upgrade error: %v", err)
		return
	}
	defer conn.Close()

	client := &Client{
		conn:     conn,
		server:   s,
		writeMu:  sync.Mutex{},
	}

	// Send initial session list
	if err := client.sendSessionList(); err != nil {
		log.Printf("Failed to send session list: %v", err)
		return
	}

	// Handle messages
	client.readLoop()
}

// Client represents a WebSocket client
type Client struct {
	conn    *websocket.Conn
	server  *Server
	writeMu sync.Mutex

	// Current attached session
	attachedSession string
	pty             *os.File
	cmd             *exec.Cmd
	stopChan        chan struct{}
}

// sendJSON sends a JSON message to the client
func (c *Client) sendJSON(msg ws.ServerMessage) error {
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	return c.conn.WriteJSON(msg)
}

// sendSessionList sends the current session list to the client
func (c *Client) sendSessionList() error {
	sessions, err := c.server.sessions.List()
	if err != nil {
		return err
	}

	return c.sendJSON(ws.ServerMessage{
		Type:     ws.MsgTypeSessions,
		Sessions: sessions,
	})
}

// readLoop reads messages from the WebSocket
func (c *Client) readLoop() {
	defer c.cleanup()

	for {
		var msg ws.ClientMessage
		if err := c.conn.ReadJSON(&msg); err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error: %v", err)
			}
			return
		}

		c.handleMessage(msg)
	}
}

// handleMessage handles a client message
func (c *Client) handleMessage(msg ws.ClientMessage) {
	switch msg.Type {
	case ws.MsgTypeList:
		c.sendSessionList()

	case ws.MsgTypeAttach:
		c.handleAttach(msg.Session, msg.Cols, msg.Rows)

	case ws.MsgTypeDetach:
		c.handleDetach()

	case ws.MsgTypeInput:
		c.handleInput(msg.Data)

	case ws.MsgTypeResize:
		c.handleResize(msg.Cols, msg.Rows)

	case ws.MsgTypeCreate:
		c.handleCreate(msg.Name)

	case ws.MsgTypeStop:
		c.handleStop(msg.Session)

	default:
		c.sendJSON(ws.ServerMessage{
			Type:    ws.MsgTypeError,
			Message: "Unknown message type",
		})
	}
}

// handleAttach attaches to a tmux session
func (c *Client) handleAttach(sessionName string, cols, rows int) {
	// Detach from current session first
	c.handleDetach()

	// Set defaults
	if cols == 0 {
		cols = 80
	}
	if rows == 0 {
		rows = 24
	}

	// Attach to session
	ptmx, cmd, err := c.server.sessions.Attach(sessionName, uint16(cols), uint16(rows))
	if err != nil {
		c.sendJSON(ws.ServerMessage{
			Type:    ws.MsgTypeError,
			Message: err.Error(),
		})
		return
	}

	c.attachedSession = sessionName
	c.pty = ptmx
	c.cmd = cmd
	c.stopChan = make(chan struct{})

	// Notify client
	c.sendJSON(ws.ServerMessage{
		Type:    ws.MsgTypeAttached,
		Session: sessionName,
	})

	// Start reading PTY output
	go c.readPTY()
}

// handleDetach detaches from the current session
func (c *Client) handleDetach() {
	if c.pty == nil {
		return
	}

	// Signal stop
	if c.stopChan != nil {
		close(c.stopChan)
		c.stopChan = nil
	}

	// Send detach command to tmux (Ctrl-B d)
	c.pty.Write([]byte{0x02, 'd'}) // Ctrl-B, d

	// Close PTY
	c.pty.Close()
	c.pty = nil

	// Wait for command to finish
	if c.cmd != nil {
		c.cmd.Wait()
		c.cmd = nil
	}

	c.attachedSession = ""

	// Notify client
	c.sendJSON(ws.ServerMessage{
		Type: ws.MsgTypeDetached,
	})

	// Send updated session list
	c.sendSessionList()
}

// handleInput sends input to the PTY
func (c *Client) handleInput(data string) {
	if c.pty == nil {
		return
	}

	c.pty.Write([]byte(data))
}

// handleResize resizes the PTY
func (c *Client) handleResize(cols, rows int) {
	if c.pty == nil {
		return
	}

	c.server.sessions.Resize(c.pty, uint16(cols), uint16(rows))
}

// handleCreate creates a new session
func (c *Client) handleCreate(name string) {
	newName, err := c.server.sessions.Create(name)
	if err != nil {
		c.sendJSON(ws.ServerMessage{
			Type:    ws.MsgTypeError,
			Message: err.Error(),
		})
		return
	}

	// Send updated session list
	c.sendSessionList()

	// Auto-attach to new session
	c.handleAttach(newName, 80, 24)
}

// handleStop stops a session
func (c *Client) handleStop(sessionName string) {
	// Detach if we're attached to this session
	if c.attachedSession == sessionName {
		c.handleDetach()
	}

	if err := c.server.sessions.Stop(sessionName); err != nil {
		c.sendJSON(ws.ServerMessage{
			Type:    ws.MsgTypeError,
			Message: err.Error(),
		})
		return
	}

	// Send updated session list
	c.sendSessionList()
}

// readPTY reads output from the PTY and sends to client
func (c *Client) readPTY() {
	buf := make([]byte, 4096)

	for {
		select {
		case <-c.stopChan:
			return
		default:
		}

		n, err := c.pty.Read(buf)
		if err != nil {
			if err != io.EOF {
				log.Printf("PTY read error: %v", err)
			}
			// Session ended, notify client
			c.sendJSON(ws.ServerMessage{
				Type: ws.MsgTypeDetached,
			})
			c.attachedSession = ""
			c.pty = nil
			c.cmd = nil
			c.sendSessionList()
			return
		}

		if n > 0 {
			c.sendJSON(ws.ServerMessage{
				Type: ws.MsgTypeOutput,
				Data: string(buf[:n]),
			})
		}
	}
}

// cleanup cleans up client resources
func (c *Client) cleanup() {
	c.handleDetach()
}
