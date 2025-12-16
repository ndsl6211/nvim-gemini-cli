# System Architecture

This document provides a detailed explanation of the entire nvim-gemini-cli system architecture.

## High-Level Overview

```
┌─────────────────────────────────────────────────────────────┐
│                       User's Machine                        │
│                                                             │
│  ┌──────────────────┐         ┌─────────────────────────┐  │
│  │  Terminal A      │         │  Terminal B             │  │
│  │  ┌────────────┐  │         │  ┌──────────────────┐   │  │
│  │  │ Neovim     │  │         │  │  Gemini CLI      │   │  │
│  │  │            │  │         │  │                  │   │  │
│  │  │ ┌────────┐ │  │         │  │  - Asks user     │   │  │
│  │  │ │ Lua    │ │  │         │  │  - Calls AI      │   │  │
│  │  │ │ Plugin │ │  │         │  │  - Uses tools    │   │  │
│  │  │ └───┬────┘ │  │         │  └────────┬─────────┘   │  │
│  │  └─────┼──────┘  │         └───────────┼─────────────┘  │
│  │        │ RPC     │                     │ HTTP           │
│  │        │ (Unix   │                     │ (MCP)          │
│  │        │ Socket) │                     │                │
│  │  ┌─────▼──────┐  │         ┌───────────▼─────────────┐  │
│  │  │ Go Server  │◄─┼─────────┤  Discovery File         │  │
│  │  │            │  │         │  /tmp/gemini/ide/       │  │
│  │  │ - MCP HTTP │  │         │  - PID-based            │  │
│  │  │ - Auth     │  │         │  - Workspace-based      │  │
│  │  │ - SSE      │  │         └─────────────────────────┘  │
│  │  └────────────┘  │                                      │
│  └──────────────────┘                                      │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ External Services                                    │  │
│  │ - Google AI (Gemini API)                            │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Component Breakdown

### 1. Neovim Lua Plugin

**Location**: `lua/gemini-cli/`

**Responsibilities**:
- Monitor user's editing activity
- Manage diff UI
- Communicate with Go server via RPC

**Key Modules**:

#### `init.lua`
- Plugin configuration
- Setup commands (`:GeminiStatus`, `:GeminiRestart`, `:GeminiStop`)
- Entry point for plugin

#### `server.lua`
- Starts/stops Go server process
- Creates discovery files
- Manages server lifecycle

**Startup sequence**:
1. Neovim loads plugin
2. `server.lua` creates Unix socket address
3. Starts Go server with socket path as argument
4. Creates discovery files in `/tmp/gemini/ide/`

#### `context.lua`
- Watches cursor movement, file changes, selections
- Debounces updates (default 50ms)
- Notifies Go server via RPC

**Context tracking**:
```lua
-- On CursorMoved, BufEnter, etc.
vim.api.nvim_create_autocmd({'CursorMoved', 'BufEnter'}, {
    callback = function()
        debounced_update()  -- Sends context to Go server
    end
})
```

#### `diff.lua`
- Creates split views for code comparison
- Handles user acceptance/rejection
- Manages active diff state

**Diff workflow**:
1. Receives `open_diff` RPC call from Go server
2. Creates vertical split with original and new content
3. Enables diff mode
4. Sets up `:w` handler (if `allow_w_to_accept` enabled)

#### `log.lua`
- Centralized logging
- Respects `log_level` configuration
- Uses `vim.notify` for output

### 2. Go MCP Server

**Location**: `server/`

**Responsibilities**:
- HTTP server for Gemini CLI
- RPC client for Neovim
- Translate between MCP protocol and Neovim RPC

**Key Components**:

#### `main.go`
- Entry point
- Parses command-line arguments
- Sets up connections

**Initialization**:
```go
func main() {
    // 1. Parse flags (-nvim, -workspace, -pid, -log-level)
    // 2. Connect to Neovim socket
    // 3. Start Neovim RPC Serve() goroutine
    // 4. Create MCP server
    // 5. Create discovery files
    // 6. Start HTTP server
}
```

#### `mcp/server.go`
- MCP protocol handler
- Tool registration
- Request routing

**HTTP Endpoints**:
- `POST /mcp` - MCP requests (with auth)
- `GET /events` - SSE for notifications (with auth)
- `GET /health` - Health check (no auth)

**MCP Methods Handled**:
- `initialize` - Handshake
- `tools/list` - Return available tools
- `tools/call` - Execute a tool

#### `mcp/sse.go`
- Server-Sent Events manager
- Maintains connections to all CLI clients
- Broadcasts notifications

**SSE Flow**:
```
Client connects → Add to clients list
Event occurs → Broadcast to all clients
Client disconnects → Remove from list
```

#### `nvim/client.go`
- Wrapper around `go-client/nvim`
- Provides high-level methods
- Handles RPC calls to Neovim

**Key Methods**:
```go
OpenDiff(path, content)   // Lua: open_diff()
CloseDiff(path)           // Lua: close_diff()
AcceptDiff(path)          // Lua: accept_diff()
RejectDiff(path)          // Lua: reject_diff()
```

#### `logger/logger.go`
- Configurable log levels (debug, info, warn, error)
- Consistent logging across Go code
- Respects `-log-level` flag

### 3. Gemini CLI

**Not part of this repo**, but important to understand:

**Responsibilities**:
- Chat interface with user
- Call Google's Gemini API
- Use MCP tools to interact with editor

**Workflow**:
1. User types a request
2. CLI sends to Gemini API
3. Gemini returns response (possibly with tool calls)
4. CLI executes MCP tool calls
5. CLI shows results to user

## Data Flow Examples

### Example 1: User Asks Gemini to Edit Code

```
User: "Add error handling to the login function"
  │
  ▼
[Gemini CLI]
  │ 1. Send to Gemini API
  ▼
[Google AI]
  │ 2. Response: "call openDiff tool with changes"
  ▼
[Gemini CLI]
  │ 3. POST /mcp with tools/call(openDiff, ...)
  ▼
[Go Server]
  │ 4. ExecLua('open_diff(...)')
  ▼
[Neovim]
  │ 5. Creates diff view
  │ 6. Returns success
  ▼
[Go Server]
  │ 7. Returns success to CLI
  ▼
[Gemini CLI]
  │ 8. "Diff opened, please review"
  ▼
User sees diff in Neovim
```

### Example 2: User Accepts Diff via :w

```
User presses :w in diff window
  │
  ▼
[Neovim Lua]
  │ 1. BufWriteCmd fires
  │ 2. Checks allow_w_to_accept config
  │ 3. Calls accept_diff()
  │ 4. Applies changes to file
  │ 5. RPC notify → Go server
  ▼
[Go Server]
  │ 6. Receives diff accepted notification
  │ 7. Broadcasts SSE event
  ▼
[Gemini CLI]
  │ 8. Receives SSE event
  │ 9. Continues workflow
  ▼
User sees "Changes applied" in CLI
```

### Example 3: Cursor Movement Context Update

```
User moves cursor in Neovim
  │
  ▼
[Neovim Lua - context.lua]
  │ 1. CursorMoved event
  │ 2. Debounce timer (50ms)
  │ 3. Collect context data
  │ 4. RPC notify → Go server
  ▼
[Go Server]
  │ 5. Receives context update
  │ 6. Broadcasts SSE event
  ▼
[Gemini CLI]
  │ 7. Receives context
  │ 8. Updates internal state
  │ 9. Includes in next API call
  ▼
Gemini AI gets current cursor position
```

## MCP Tools Deep Dive

### openDiff Tool

**When used**: Gemini wants to show code changes

**Input Schema**:
```json
{
  "type": "object",
  "properties": {
    "filePath": {"type": "string"},
    "newContent": {"type": "string"}
  },
  "required": ["filePath", "newContent"]
}
```

**Processing**:
1. Validate arguments
2. Call `nvimClient.OpenDiff(filePath, newContent)`
3. Neovim creates diff UI
4. Return success/error

**Error handling**:
- File doesn't exist → Create new file
- Neovim RPC timeout → Return error to CLI
- Invalid path → Return error

### closeDiff Tool

**When used**: Get final content after user reviews

**Input Schema**:
```json
{
  "type": "object",
  "properties": {
    "filePath": {"type": "string"},
    "suppressNotification": {"type": "boolean"}
  },
  "required": ["filePath"]
}
```

**Processing**:
1. Call `nvimClient.CloseDiff(filePath)`
2. Neovim returns final content from diff
3. Return content to CLI
4. If not suppressed, send SSE notification

**Use case**:
- CLI calls this after user confirms in CLI prompt
- Gets actual content user wants (might have edited the diff)

### acceptDiff Tool

**When used**: Apply changes to file

**Processing**:
1. Call `nvimClient.AcceptDiff(filePath)`
2. Neovim copies content from diff to original
3. Writes to file
4. Closes diff windows
5. Sends SSE notification

**Notification prevents race**:
- Without it, CLI might call closeDiff before accept finishes
- SSE tells CLI "diff accepted externally"

### rejectDiff Tool

**When used**: Discard changes

**Processing**:
1. Call `nvimClient.RejectDiff(filePath)`
2. Neovim closes diff without applying
3. Sends SSE notification

## Discovery Mechanism

### Why Discovery Files?

**Problem**: How does `gemini-cli` find the server?

**Solutions**:

#### Option 1: Environment Variable
```bash
export GEMINI_CLI_IDE_SERVER_PORT=51234
```
- ❌ Doesn't work across different terminals
- ❌ User might forget to export

#### Option 2: Fixed Port
```bash
# Always use port 8080
```
- ❌ Port conflicts if multiple Neovim instances
- ❌ Not flexible

#### Option 3: Discovery Files ✅
```bash
# Server creates file with its info
/tmp/gemini/ide/gemini-ide-server-<PID>-<PORT>.json
```
- ✅ Unique per Neovim instance
- ✅ Contains all needed info
- ✅ Supports multiple discovery methods

### Discovery File Structure

```json
{
  "port": 51234,
  "workspacePath": "/home/user/my-project",
  "authToken": "uuid-here",
  "ideInfo": {
    "name": "vscodefork",
    "displayName": "IDE"
  }
}
```

### PID-based Discovery

**File**: `gemini-ide-server-12345-51234.json`

**How it works**:
1. `gemini-cli` gets its parent PID
2. Looks for file matching that PID
3. Reads port and token
4. Connects

**When it works**:
- Running from Neovim's `:terminal`
- Terminal is a child process of Neovim

### Workspace-based Discovery

**File**: `workspace-a3f5c9d1-latest.json` (symlink)

**How it works**:
1. Server calculates workspace hash
2. Creates symlink to PID file
3. `gemini-cli` calculates same hash
4. Follows symlink to actual file

**When it works**:
- Running from ANY terminal
- Must be in same workspace directory

## Security Model

### Authentication

Every HTTP request requires:
```
Authorization: Bearer <token>
```

Token is randomly generated UUID per server instance.

### Why This Works

1. **Local only**: Server listens on `127.0.0.1` (localhost)
2. **Random tokens**: Different token per Neovim session
3. **File permissions**: Discovery files are readable by user only

### Attack Scenarios

**Q**: Can another user's process connect?
**A**: No, discovery files are in user's `/tmp`, not readable by others

**Q**: Can a malicious website connect?
**A**: No, browser CORS prevents localhost connections

**Q**: What if someone steals the token?
**A**: They'd need local access already, at which point they have bigger problems

## Performance Considerations

### Context Updates

**Challenge**: Every cursor movement could send an update

**Solution**: Debouncing

```lua
-- Only send after 50ms of no movement
local debounce_timer = vim.loop.new_timer()
debounce_timer:start(50, 0, function()
    send_context_update()
end)
```

**Result**: ~20 updates/second maximum instead of hundreds

### Diff Operations

**Challenge**: Large files could slow down diff creation

**Current**: No optimization, creates diff directly

**Future opportunities**:
- Limit diff to visible lines
- Progressive rendering for large files
- Virtual text for changes instead of full split

### HTTP Connections

**Challenge**: Each MCP request creates overhead

**Mitigation**:
- Keep-Alive headers (Go's default)
- SSE keeps one connection open
- Local networking is very fast

## Error Handling

### Neovim Crashes

**What happens**:
1. RPC connection breaks
2. Go server's `Serve()` goroutine exits
3. HTTP server keeps running but tools fail

**Recovery**:
- Restart Neovim
- Plugin auto-starts server
- New discovery files created

### Go Server Crashes

**What happens**:
1. Gemini CLI loses connection
2. Discovery file still exists (stale)

**Recovery**:
- `:GeminiRestart` in Neovim
- New server starts
- Discovery files updated

### Gemini CLI Disconnects

**What happens**:
1. SSE connection closes
2. Server removes client from list

**Impact**:
- None! Neovim and Go server keep running
- CLI can reconnect anytime

## Testing Strategy

### Unit Tests (Go)

Location: `server/*_test.go`

Test:
- Tool handlers
- Authentication
- Discovery file creation

### Integration Tests (Manual)

1. Start Neovim
2. Check `:GeminiStatus`
3. Run `gemini-cli`
4. Ask for code change
5. Verify diff opens
6. Accept/reject
7. Verify changes applied

### Debugging Checklist

1. **Server running?** → `:GeminiStatus`
2. **Discovery file exists?** → `ls /tmp/gemini/ide/`
3. **Correct port?** → `cat discovery-file.json`
4. **RPC working?** → `:lua require('gemini-cli.diff').open_diff(...)`
5. **HTTP working?** → `curl localhost:<port>/health`
6. **Auth working?** → `curl -H "Authorization: Bearer <token>" ...`

## Future Enhancements

### Planned

- [ ] WebSocket support (alternative to SSE)
- [ ] Multi-workspace support
- [ ] Performance metrics
- [ ] Replay/undo for diffs

### Ideas

- Integration with other AI providers
- Custom tool definitions
- Diff history viewer
- Collaborative editing support
