import { TerminalWrapper } from './terminal';
import { WebSocketClient } from './websocket';
import type { Session, ServerMessage } from './types';

// State
let terminal: TerminalWrapper | null = null;
let ws: WebSocketClient;
let sessions: Session[] = [];
let currentSession: string | null = null;

// DOM Elements
const terminalEl = document.getElementById('terminal')!;
const welcomeEl = document.getElementById('welcome')!;
const sessionListEl = document.getElementById('session-list')!;
const newBtn = document.getElementById('new-btn') as HTMLButtonElement;
const detachBtn = document.getElementById('detach-btn') as HTMLButtonElement;
const sessionChip = document.getElementById('session-chip')!;
const sessionNameEl = document.getElementById('session-name')!;
const pickerEl = document.getElementById('session-picker')!;
const pickerListEl = document.getElementById('picker-list')!;
const pickerCloseBtn = document.getElementById('picker-close')!;
const pickerNewBtn = document.getElementById('picker-new')!;
const pickerDetachBtn = document.getElementById('picker-detach') as HTMLButtonElement;
const overlayEl = document.getElementById('overlay')!;
const modalEl = document.getElementById('new-session-modal')!;
const newSessionNameInput = document.getElementById('new-session-name') as HTMLInputElement;
const modalCancelBtn = document.getElementById('modal-cancel')!;
const modalCreateBtn = document.getElementById('modal-create')!;

// Initialize
async function init(): Promise<void> {
  // Set up event listeners
  setupEventListeners();

  // Connect WebSocket
  ws = new WebSocketClient();
  ws.onMessage(handleMessage);

  try {
    await ws.connect();
  } catch (e) {
    console.error('Failed to connect WebSocket:', e);
    showError('Failed to connect to server');
  }
}

function setupEventListeners(): void {
  // New session button - use touchend for iOS Safari
  newBtn.addEventListener('click', showNewSessionModal);
  newBtn.addEventListener('touchend', (e) => {
    e.preventDefault();
    showNewSessionModal();
  });

  // Session chip - open picker
  sessionChip.addEventListener('click', showPicker);
  sessionChip.addEventListener('touchend', (e) => {
    e.preventDefault();
    showPicker();
  });

  // Detach button
  detachBtn.addEventListener('click', detach);
  detachBtn.addEventListener('touchend', (e) => {
    e.preventDefault();
    detach();
  });

  // Picker
  pickerCloseBtn.addEventListener('click', hidePicker);
  overlayEl.addEventListener('click', hidePicker);
  pickerNewBtn.addEventListener('click', () => {
    hidePicker();
    showNewSessionModal();
  });
  pickerDetachBtn.addEventListener('click', () => {
    hidePicker();
    detach();
  });

  // Modal
  modalCancelBtn.addEventListener('click', hideNewSessionModal);
  modalCreateBtn.addEventListener('click', createSession);
  newSessionNameInput.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      createSession();
    }
  });
}

function handleMessage(msg: ServerMessage): void {
  console.log('Received message:', msg.type, msg);
  switch (msg.type) {
    case 'sessions':
      sessions = msg.sessions || [];
      console.log('Sessions received:', sessions.length, sessions);
      renderSessions();
      break;

    case 'attached':
      currentSession = msg.session;
      showTerminal();
      updateUI();
      break;

    case 'detached':
      currentSession = null;
      showWelcome();
      updateUI();
      break;

    case 'output':
      if (terminal) {
        terminal.write(msg.data);
      }
      break;

    case 'error':
      showError(msg.message);
      break;
  }
}

function renderSessions(): void {
  // Welcome screen session list
  sessionListEl.innerHTML = '';

  if (sessions.length === 0) {
    sessionListEl.innerHTML = `
      <div class="session-item new-session" data-action="new">
        + New Session
      </div>
    `;
  } else {
    sessions.forEach((session) => {
      const item = document.createElement('div');
      item.className = 'session-item';
      item.dataset.session = session.name;
      item.innerHTML = `
        <span class="name">${escapeHtml(session.name)}</span>
        <span class="cwd">${escapeHtml(session.cwd)}</span>
      `;
      sessionListEl.appendChild(item);
    });

    const newItem = document.createElement('div');
    newItem.className = 'session-item new-session';
    newItem.dataset.action = 'new';
    newItem.textContent = '+ New Session';
    sessionListEl.appendChild(newItem);
  }

  // Add click handlers
  sessionListEl.querySelectorAll('.session-item').forEach((item) => {
    item.addEventListener('click', () => {
      const sessionName = (item as HTMLElement).dataset.session;
      const action = (item as HTMLElement).dataset.action;

      if (action === 'new') {
        showNewSessionModal();
      } else if (sessionName) {
        attachToSession(sessionName);
      }
    });
  });

  // Picker list
  pickerListEl.innerHTML = '';

  if (sessions.length === 0) {
    pickerListEl.innerHTML = '<div class="empty-state">No sessions</div>';
  } else {
    sessions.forEach((session) => {
      const item = document.createElement('div');
      item.className = 'picker-item' + (session.name === currentSession ? ' active' : '');
      item.dataset.session = session.name;
      item.innerHTML = `
        <div class="indicator"></div>
        <div class="info">
          <div class="name">${escapeHtml(session.name)}</div>
          <div class="cwd">${escapeHtml(session.cwd)}</div>
        </div>
      `;
      item.addEventListener('click', () => {
        hidePicker();
        if (session.name !== currentSession) {
          attachToSession(session.name);
        }
      });
      pickerListEl.appendChild(item);
    });
  }
}

function attachToSession(name: string): void {
  if (!terminal) {
    initTerminal();
  }

  const { cols, rows } = terminal!.getDimensions();
  ws.attach(name, cols, rows);
}

function initTerminal(): void {
  terminal = new TerminalWrapper(terminalEl);

  // Handle resize
  terminal.onResize((cols, rows) => {
    if (currentSession) {
      ws.resize(cols, rows);
    }
  });

  // Handle direct keyboard input (when terminal is focused)
  terminal.onData((data) => {
    if (currentSession) {
      ws.input(data);
    }
  });
}

function showTerminal(): void {
  welcomeEl.classList.add('hidden');
  terminalEl.classList.add('active');

  if (terminal) {
    terminal.clear();
    terminal.fit();
    terminal.focus();
  }
}

function showWelcome(): void {
  terminalEl.classList.remove('active');
  welcomeEl.classList.remove('hidden');
}

function updateUI(): void {
  const hasSession = currentSession !== null;

  detachBtn.disabled = !hasSession;
  pickerDetachBtn.disabled = !hasSession;
  sessionNameEl.textContent = currentSession || 'No session';
}

function detach(): void {
  ws.detach();
}

function showPicker(): void {
  renderSessions(); // Refresh
  pickerEl.classList.remove('hidden');
  overlayEl.classList.remove('hidden');
}

function hidePicker(): void {
  pickerEl.classList.add('hidden');
  overlayEl.classList.add('hidden');
}

function showNewSessionModal(): void {
  newSessionNameInput.value = '';
  modalEl.classList.remove('hidden');
  newSessionNameInput.focus();
}

function hideNewSessionModal(): void {
  modalEl.classList.add('hidden');
}

function createSession(): void {
  const name = newSessionNameInput.value.trim() || undefined;
  ws.createSession(name);
  hideNewSessionModal();
}

function showError(message: string): void {
  // Simple alert for now, could be improved with toast
  console.error(message);
  alert(message);
}

function escapeHtml(str: string): string {
  const div = document.createElement('div');
  div.textContent = str;
  return div.innerHTML;
}

// Start
init();
