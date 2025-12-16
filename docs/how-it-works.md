# How It Works

This document explains the key mechanisms that make nvim-gemini-cli work from a user's perspective. For detailed technical architecture, see [architecture.md](architecture.md).

## Discovery: How Gemini CLI Finds Neovim

The plugin uses **discovery files** to allow Gemini CLI to automatically find and connect to your Neovim instance.

### Two Ways to Connect

**1. From Neovim's `:terminal`** (PID-based)
- Gemini CLI detects it's running inside Neovim
- Automatically connects to the parent Neovim process

**2. From any terminal** (Workspace-based) ⭐
- Run `gemini-cli` from your project directory
- Automatically finds Neovim editing the same project

```bash
# Terminal 1: Neovim
cd /path/to/your/project
nvim

# Terminal 2: Gemini CLI (different window/app)
cd /path/to/your/project
gemini-cli  # ✅ Automatically connects!
```

**How workspace discovery works:**
- Plugin creates a discovery file based on your project path
- Gemini CLI looks for the same project path
- Connection established automatically

> **Note**: Discovery files are stored in `/tmp/gemini/ide/` and contain connection info (port, auth token).

## Context Sharing: Keeping Gemini Aware

The plugin automatically shares your editing context with Gemini CLI:

**What's shared:**
- Open files in your workspace
- Current file and cursor position
- Selected text (if any)

**When it's shared:**
- When you move the cursor
- When you switch files
- When you select text
- When you edit content

**Performance:**
Updates are debounced (50ms default) to avoid flooding the system. This means even if you move the cursor rapidly, updates are sent at most ~20 times per second.

## Diff Workflow: Reviewing AI Suggestions

When Gemini suggests code changes, you see them in a side-by-side diff view.

### The Diff View

```
┌─────────────────────┬─────────────────────┐
│ Original Code       │ Suggested Changes   │
│ (Read-only)         │ (Editable)          │
├─────────────────────┼─────────────────────┤
│ function login() {  │ function login() {  │
│   user.auth()       │   try {             │
│ }                   │     user.auth()     │
│                     │   } catch (e) {     │
│                     │     log.error(e)    │
│                     │   }                 │
│                     │ }                   │
└─────────────────────┴─────────────────────┘
```

**You can:**
- Review the changes side-by-side
- Edit the suggested code before accepting
- See exactly what will change

### Accepting or Rejecting Changes

**Option 1: Accept via `:w` in Neovim**

If you've set `allow_w_to_accept = true`:
1. Review the changes in the diff window
2. Edit if needed
3. Press `:w` to accept and save

**Option 2: Accept via Gemini CLI**

1. Review the changes in Neovim
2. Return to Gemini CLI terminal
3. Press `1` to accept or `2` to reject

**What happens when you accept:**
1. Changes are applied to your file
2. File is saved automatically
3. Diff windows close
4. Gemini CLI is notified

**What happens when you reject:**
1. Changes are discarded
2. Diff windows close
3. Original file remains unchanged

## Communication: How Components Talk

The system uses two communication channels:

### Neovim ↔ Go Server
- **Method**: RPC over Unix socket
- **Speed**: Very fast (local)
- **Purpose**: UI operations (open diff, apply changes)

### Gemini CLI ↔ Go Server
- **Method**: HTTP with MCP protocol
- **Speed**: Fast (localhost)
- **Purpose**: AI tool integration
- **Notifications**: Server-Sent Events (SSE) for real-time updates

> **For developers**: See [neovim-communication.md](neovim-communication.md) and [gemini-communication.md](gemini-communication.md) for protocol details.

## Security

**Authentication:**
- Every connection requires a unique token
- Token is randomly generated per Neovim session
- Token is stored in the discovery file

**Why it's secure:**
- Server only listens on `localhost` (not accessible from network)
- Discovery files are only readable by your user account
- Each Neovim session gets a different token

## Related Documentation

- **[Architecture](architecture.md)** - Detailed technical architecture and implementation
- **[Development](development.md)** - Building, testing, and contributing
- **[Troubleshooting](troubleshooting.md)** - Common issues and solutions
- **[Gemini Communication](gemini-communication.md)** - HTTP/MCP protocol details
- **[Neovim Communication](neovim-communication.md)** - RPC protocol details
