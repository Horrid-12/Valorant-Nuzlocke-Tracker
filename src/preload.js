const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('electronAPI', {
  // We can add safe IPC calls here if needed later
  // For now, we'll just expose a simple version for identification
  version: '1.0.0'
});
