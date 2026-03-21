# Nuztrack

A Valorant Nuzlocke tracker rebuilt as a Tauri desktop app.

## Structure

- `src/`: static frontend assets
- `src-tauri/`: Rust desktop shell and Tauri config

## Development

Install dependencies:

```bash
npm install
```

Run the desktop app in development:

```bash
npm run dev
```

Create a production build:

```bash
npm run build
```

## Notes

This project was reconstructed from a packaged Electron app. The frontend logic is still plain HTML, CSS, and JavaScript, but the desktop wrapper now targets Tauri instead of Electron.
