import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    outDir: '../cmd/z-web/dist',
    emptyOutDir: true,
  },
  server: {
    proxy: {
      '/ws': {
        target: 'ws://localhost:7680',
        ws: true,
      },
      '/api': {
        target: 'http://localhost:7680',
      },
    },
  },
});
