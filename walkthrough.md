# Nuztrack Walkthrough

## Overview

This project is a Tauri rebuild of the original Electron-based Valorant Nuzlocke tracker. The app keeps the same plain HTML, CSS, and JavaScript frontend, but now uses Tauri as the desktop shell.

## Project layout

- `src/`
  Static frontend files loaded by Tauri.
- `src/index.html`
  Main app markup and layout.
- `src/style.css`
  Theme variables, layout, cards, tables, and sidebar styling.
- `src/renderer.js`
  Core application logic, rule processing, rendering, local storage, theme saving, import/export, and edit mode.
- `src/icon.jpeg`
  Frontend icon asset.
- `src-tauri/`
  Rust desktop wrapper and Tauri configuration.
- `src-tauri/src/main.rs`
  Minimal Tauri entrypoint that opens the application window.
- `src-tauri/tauri.conf.json`
  App metadata, window settings, static frontend path, and bundle config.
- `src-tauri/capabilities/default.json`
  Default capability for the main window.
- `src-tauri/icons/icon.ico`
  Windows icon used for bundling.

## Runtime flow

1. Tauri launches the Rust app from `src-tauri/src/main.rs`.
2. Tauri loads the static frontend from `src/`.
3. `src/index.html` loads `style.css` and `renderer.js`.
4. `renderer.js` restores state from `localStorage`, renders the UI, and attaches event listeners.

## App behavior

The tracker manages a custom Valorant challenge run:

- agents unlock on wins
- losses remove lives
- dead agents can be revived with tokens
- aces award tokens
- bot frags ban random weapons
- eco failures ban the selected eco weapon for the session
- history, notes, and theme settings are saved locally

## Persistence

The frontend stores its state in browser storage inside the Tauri webview:

- `valo_nuzlocke_state_v1`
- `valo_nuzlocke_theme_v1`

There is no backend or database. Save data remains local unless exported through the app's JSON backup flow.

## Development commands

Install dependencies:

```bash
npm install
```

Run in development:

```bash
npm run dev
```

Build desktop bundles:

```bash
npm run build
```

## Notes

- This repo was reconstructed from a packaged Electron app rather than the original source repository.
- Electron-specific files were dropped in favor of Tauri.
- The frontend is still framework-free, so most feature work will happen in `src/renderer.js`, `src/index.html`, and `src/style.css`.
