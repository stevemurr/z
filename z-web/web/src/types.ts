// Message types from client to server
export type ClientMessage =
  | { type: 'input'; data: string }
  | { type: 'resize'; cols: number; rows: number }
  | { type: 'attach'; session: string; cols: number; rows: number }
  | { type: 'detach' }
  | { type: 'list' }
  | { type: 'create'; name?: string }
  | { type: 'stop'; session: string };

// Message types from server to client
export type ServerMessage =
  | { type: 'output'; data: string }
  | { type: 'sessions'; sessions: Session[] }
  | { type: 'attached'; session: string }
  | { type: 'detached' }
  | { type: 'error'; message: string };

// Session information
export interface Session {
  name: string;
  cwd: string;
  command: string;
  branch?: string;
  activity: number;
  clients: number;
}
