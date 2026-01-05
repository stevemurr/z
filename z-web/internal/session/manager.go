package session

import (
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"

	"github.com/creack/pty"
	"github.com/stevemurr/z/z-web/internal/ws"
)

const (
	SessionPrefix = "z-"
)

// Manager handles tmux session operations
type Manager struct {
	mu sync.Mutex
}

// NewManager creates a new session manager
func NewManager() *Manager {
	return &Manager{}
}

// List returns all z- prefixed tmux sessions
func (m *Manager) List() ([]ws.Session, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Get session list from tmux
	// Format: session_name|activity_timestamp|attached_clients
	cmd := exec.Command("tmux", "list-sessions", "-F", "#{session_name}|#{session_activity}|#{session_attached}")
	output, err := cmd.Output()
	if err != nil {
		// No sessions or tmux not running
		if exitErr, ok := err.(*exec.ExitError); ok && exitErr.ExitCode() == 1 {
			return []ws.Session{}, nil
		}
		return nil, fmt.Errorf("failed to list sessions: %w", err)
	}

	var sessions []ws.Session
	lines := strings.Split(strings.TrimSpace(string(output)), "\n")

	for _, line := range lines {
		if line == "" {
			continue
		}

		parts := strings.Split(line, "|")
		if len(parts) < 3 {
			continue
		}

		sessionName := parts[0]

		// Only include z- prefixed sessions
		if !strings.HasPrefix(sessionName, SessionPrefix) {
			continue
		}

		activity, _ := strconv.ParseInt(parts[1], 10, 64)
		clients, _ := strconv.Atoi(parts[2])

		// Get pane info for cwd and command
		cwd, command := m.getPaneInfo(sessionName)

		// Get git branch
		branch := m.getGitBranch(cwd)

		sessions = append(sessions, ws.Session{
			Name:     strings.TrimPrefix(sessionName, SessionPrefix),
			Cwd:      shortenPath(cwd),
			Command:  command,
			Branch:   branch,
			Activity: activity,
			Clients:  clients,
		})
	}

	return sessions, nil
}

// getPaneInfo gets the current working directory and command for a session
func (m *Manager) getPaneInfo(sessionName string) (cwd, command string) {
	cmd := exec.Command("tmux", "list-panes", "-t", sessionName, "-F", "#{pane_current_path}|#{pane_current_command}")
	output, err := cmd.Output()
	if err != nil {
		return "", ""
	}

	line := strings.TrimSpace(string(output))
	parts := strings.SplitN(line, "|", 2)
	if len(parts) >= 1 {
		cwd = parts[0]
	}
	if len(parts) >= 2 {
		command = parts[1]
	}
	return
}

// getGitBranch gets the current git branch for a directory
func (m *Manager) getGitBranch(dir string) string {
	if dir == "" {
		return ""
	}

	cmd := exec.Command("git", "-C", dir, "branch", "--show-current")
	output, err := cmd.Output()
	if err != nil {
		return ""
	}

	return strings.TrimSpace(string(output))
}

// Create creates a new tmux session
func (m *Manager) Create(name string) (string, error) {
	m.mu.Lock()
	defer m.mu.Unlock()

	// Generate name if not provided
	if name == "" {
		name = fmt.Sprintf("web-%d", os.Getpid())
	}

	sessionName := SessionPrefix + name

	// Check if session already exists
	cmd := exec.Command("tmux", "has-session", "-t", sessionName)
	if err := cmd.Run(); err == nil {
		return "", fmt.Errorf("session '%s' already exists", name)
	}

	// Create new session
	cwd, _ := os.Getwd()
	cmd = exec.Command("tmux", "new-session", "-d", "-s", sessionName, "-c", cwd)
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("failed to create session: %w", err)
	}

	return name, nil
}

// Stop stops a tmux session
func (m *Manager) Stop(name string) error {
	m.mu.Lock()
	defer m.mu.Unlock()

	sessionName := SessionPrefix + name

	cmd := exec.Command("tmux", "kill-session", "-t", sessionName)
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to stop session: %w", err)
	}

	return nil
}

// Attach returns a PTY attached to the tmux session
func (m *Manager) Attach(name string, cols, rows uint16) (*os.File, *exec.Cmd, error) {
	sessionName := SessionPrefix + name

	// Verify session exists
	checkCmd := exec.Command("tmux", "has-session", "-t", sessionName)
	if err := checkCmd.Run(); err != nil {
		return nil, nil, fmt.Errorf("session '%s' not found", name)
	}

	// Attach to session via PTY
	cmd := exec.Command("tmux", "attach-session", "-t", sessionName)
	cmd.Env = append(os.Environ(),
		fmt.Sprintf("TERM=xterm-256color"),
	)

	// Start with PTY
	ptmx, err := pty.StartWithSize(cmd, &pty.Winsize{
		Rows: rows,
		Cols: cols,
	})
	if err != nil {
		return nil, nil, fmt.Errorf("failed to attach: %w", err)
	}

	return ptmx, cmd, nil
}

// Resize resizes the PTY
func (m *Manager) Resize(ptmx *os.File, cols, rows uint16) error {
	return pty.Setsize(ptmx, &pty.Winsize{
		Rows: rows,
		Cols: cols,
	})
}

// shortenPath shortens a path for display
func shortenPath(path string) string {
	home := os.Getenv("HOME")
	if home != "" && strings.HasPrefix(path, home) {
		path = "~" + strings.TrimPrefix(path, home)
	}
	return path
}
