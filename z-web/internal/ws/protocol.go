package ws

// ClientMessage represents messages from the browser
type ClientMessage struct {
	Type    string `json:"type"`
	Data    string `json:"data,omitempty"`    // For input
	Session string `json:"session,omitempty"` // For attach/stop
	Name    string `json:"name,omitempty"`    // For create
	Cols    int    `json:"cols,omitempty"`    // For resize
	Rows    int    `json:"rows,omitempty"`    // For resize
}

// Message types from client
const (
	MsgTypeInput   = "input"   // Terminal input
	MsgTypeResize  = "resize"  // Terminal resize
	MsgTypeAttach  = "attach"  // Attach to session
	MsgTypeDetach  = "detach"  // Detach from session
	MsgTypeList    = "list"    // List sessions
	MsgTypeCreate  = "create"  // Create new session
	MsgTypeStop    = "stop"    // Stop session
)

// ServerMessage represents messages to the browser
type ServerMessage struct {
	Type     string    `json:"type"`
	Data     string    `json:"data,omitempty"`     // For output (base64)
	Session  string    `json:"session,omitempty"`  // For attached
	Sessions []Session `json:"sessions,omitempty"` // For sessions list
	Message  string    `json:"message,omitempty"`  // For error
}

// Message types to client
const (
	MsgTypeOutput   = "output"   // Terminal output
	MsgTypeSessions = "sessions" // Session list
	MsgTypeAttached = "attached" // Attached to session
	MsgTypeDetached = "detached" // Detached from session
	MsgTypeError    = "error"    // Error message
)

// Session represents a z term session
type Session struct {
	Name     string `json:"name"`
	Cwd      string `json:"cwd"`
	Command  string `json:"command"`
	Branch   string `json:"branch,omitempty"`
	Activity int64  `json:"activity"` // Unix timestamp
	Clients  int    `json:"clients"`
}
