# claudecodemobile-bridge

Lightweight bridge between Claude Code CLI and Claude Code Mobile via Supabase.

**The CLI bridge that connects Claude Code Mobile (iOS) to your Claude Code CLI on macOS, Linux, and Windows.**

iOS app: *Claude Code Mobile* (coming soon on App Store)

Control your coding sessions from iPhone: send prompts, receive replies, and keep your workspace synced remotely.

This npm package runs as a local background bridge process.  
Users usually start it from the connection page flow:

- `https://luch.dev/claude?token=...&id=...`

---

## How It Works

The bridge connects three layers:

1. **Claude Code Mobile (iOS)** -> sends prompts via Supabase
2. **claudecodemobile-bridge (this package)** -> receives prompts, runs `claude -p`, sends replies
3. **Claude Code Mobile (iOS)** -> receives replies and keeps history synchronized

## Pairing flow (one project at a time)

Only **one** bridge process and **one** active `bridge_sessions` row per device pair. To work in another folder: disconnect the project in the iOS app (Sessions), press Ctrl+C on the Mac bridge, `cd` to the new folder, run the bridge again, then Connect from the web page.

1. Install/open *Claude Code Mobile* on iPhone.
2. Open the mobile-generated link on your computer:
   - `https://luch.dev/claude?token=...&id=...`
3. Install Claude Code CLI if needed:
   - macOS/Linux: `curl -fsSL https://claude.ai/install.sh | bash`
   - Windows: `irm https://claude.ai/install.ps1 | iex`
4. Sign in if needed:
   - `claude auth login`
5. In Terminal, `cd` to the **project directory** you want Claude Code to use.
6. Start the bridge (stop any other bridge on this machine first):
   - `npx @uladluch/claudecodemobile-bridge@latest`
7. Click **Connect** in the web page.

## Requirements

- **Node.js** >= 18
- **Claude Code CLI** installed and authenticated
  - Requires Claude Pro/Max subscription or Anthropic Console account
- Claude Code Mobile app (iOS)
- Supabase project configured for bridge tables:
  - `messages`
  - `device_pairs`
  - `bridge_sessions`
  - `ide_presence`

## Quick Start

```bash
# 1. Install Claude Code CLI
curl -fsSL https://claude.ai/install.sh | bash
claude auth login

# 2. Go to your project
cd /path/to/your-project

# 3. Run the bridge
npx @uladluch/claudecodemobile-bridge@latest
```

## Local Development

```bash
cd bridge
npm install
npm run dev -- --path /absolute/path/to/workspace
```

For production-style local run:

```bash
npm run build
node dist/index.js --path /absolute/path/to/workspace
```

## Environment Variables

| Variable | Description | Default |
|---|---|---|
| `CLAUDE_CLI_PATH` | Override Claude CLI path | auto-detect |
| `CLAUDE_MODEL` | Default model | (CLI default) |
| `CLAUDE_MAX_TURNS` | Max agentic turns per message | unlimited |
| `CLAUDE_MAX_BUDGET_USD` | Budget limit per message | unlimited |
| `CLAUDE_EXTRA_ARGS` | Extra CLI flags | (none) |
| `CLAUDE_BRIDGE_TIMEOUT_MS` | Wall-clock kill timeout | disabled |
| `SUPABASE_URL` | Supabase project URL | built-in |
| `SUPABASE_ANON_KEY` | Supabase anon key | built-in |

---

## License

Proprietary - see the [Software License EULA](https://experts-draw-9pm.craft.me/wXq3wh2N50ahi0).

© 2026 Ulad Luch. All rights reserved.
