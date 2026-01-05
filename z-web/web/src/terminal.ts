import { Terminal } from 'xterm';
import { FitAddon } from 'xterm-addon-fit';
import 'xterm/css/xterm.css';

export class TerminalWrapper {
  private terminal: Terminal;
  private fitAddon: FitAddon;
  private container: HTMLElement;
  private resizeObserver: ResizeObserver;

  constructor(container: HTMLElement) {
    this.container = container;

    this.terminal = new Terminal({
      cursorBlink: true,
      fontSize: 14,
      fontFamily: 'Menlo, Monaco, "Courier New", monospace',
      theme: {
        background: '#1a1a1a',
        foreground: '#e0e0e0',
        cursor: '#e0e0e0',
        cursorAccent: '#1a1a1a',
        selectionBackground: '#4a9eff50',
      },
      allowProposedApi: true,
    });

    this.fitAddon = new FitAddon();
    this.terminal.loadAddon(this.fitAddon);

    this.terminal.open(container);
    this.fit();

    // Handle resize
    this.resizeObserver = new ResizeObserver(() => {
      this.fit();
    });
    this.resizeObserver.observe(container);
  }

  fit(): void {
    try {
      this.fitAddon.fit();
    } catch (e) {
      // Ignore fit errors during initialization
    }
  }

  write(data: string): void {
    this.terminal.write(data);
  }

  clear(): void {
    this.terminal.clear();
  }

  focus(): void {
    this.terminal.focus();
  }

  getDimensions(): { cols: number; rows: number } {
    return {
      cols: this.terminal.cols,
      rows: this.terminal.rows,
    };
  }

  onResize(callback: (cols: number, rows: number) => void): void {
    this.terminal.onResize(({ cols, rows }) => {
      callback(cols, rows);
    });
  }

  // For handling keyboard input directly (optional, we use separate input)
  onData(callback: (data: string) => void): void {
    this.terminal.onData(callback);
  }

  dispose(): void {
    this.resizeObserver.disconnect();
    this.terminal.dispose();
  }
}
