# Development Guide

This guide is for developers who want to contribute to nvim-gemini-cli or understand its implementation details.

## Project Structure

```
nvim-gemini-cli/
├── server/                 # Golang MCP server
│   ├── main.go            # Entry point, starts HTTP server
│   ├── mcp/
│   │   ├── server.go      # MCP protocol implementation
│   │   └── sse.go         # Server-Sent Events for notifications
│   ├── nvim/
│   │   └── client.go      # Neovim RPC client wrapper
│   └── types/
│       └── types.go       # Type definitions
├── lua/
│   └── gemini-cli/
│       ├── init.lua       # Main API and configuration
│       ├── server.lua     # Server lifecycle management
│       ├── context.lua    # Context tracking and updates
│       ├── diff.lua       # Diff UI and operations
│       └── log.lua        # Logging utilities
├── plugin/
│   └── gemini-cli.lua     # Plugin initialization
├── docs/                  # Documentation
└── bin/
    └── gemini-mcp-server  # Compiled binary
```

## Building from Source

### Prerequisites

- Go >= 1.21
- Neovim >= 0.9.0

### Build Steps

```bash
cd server
go build -o ../bin/gemini-mcp-server
```

The compiled binary will be placed in the `bin/` directory.

### Development Build

For development with debug symbols:

```bash
cd server
go build -gcflags="all=-N -l" -o ../bin/gemini-mcp-server
```

## Running Tests

### Go Tests

```bash
cd server
go test ./...
```

Run with verbose output:

```bash
go test -v ./...
```

Run specific tests:

```bash
go test -v -run TestFunctionName ./...
```

### Manual Integration Testing

1. Start Neovim with the plugin
2. Check server status: `:GeminiStatus`
3. Run `gemini-cli` in a terminal
4. Ask for code changes
5. Verify diff opens correctly
6. Test accept/reject workflows

## Key Technical Details

### RPC Communication

The Go server communicates with Neovim via RPC over a Unix socket:

- Uses `github.com/neovim/go-client/nvim` for RPC
- **Critical**: Must call `nvim.Serve()` in a goroutine to handle bidirectional RPC
- Uses `nvim.ExecLua()` to execute Lua code (not `Call("nvim_exec_lua")`)

Example:

```go
// Connect to Neovim
v, err := nvimclient.New(conn, conn, conn, nil)
if err != nil {
    log.Fatal(err)
}

// CRITICAL: Start serving RPC messages
go func() {
    if err := v.Serve(); err != nil {
        log.Fatalf("Neovim client serve error: %v", err)
    }
}()

// Now you can call Lua functions
var result string
err = v.ExecLua(`return require('gemini-cli.diff').open_diff(...)`, &result, filePath, content)
```

### RPC Communication Best Practices

The Go server communicates with Neovim via RPC over a Unix socket using `nvim.ExecLua()`:

```go
// Example: Calling a Lua function from Go
var result string
err = v.ExecLua(`return require('gemini-cli.diff').open_diff(...)`, &result, filePath, content)
```

**Key points:**

1. **Use `nvim.ExecLua()` to call Lua functions** - This is the recommended method from the `go-client/nvim` package
2. **Lua functions execute synchronously** - The Go server waits for the Lua function to return
3. **Keep operations simple** - Perform the required work and return the result

**Example Lua function called via RPC:**

```lua
function M.open_diff(file_path, new_content)
    -- Perform the required operations
    vim.cmd('split')
    create_diff_buffers(file_path, new_content)
    
    -- Return result
    return true
end
```

**For asynchronous notifications from Neovim to Go:**

```lua
-- Send notification without waiting for response
vim.fn.rpcnotify(0, 'event_name', arg1, arg2)
```

The Go server registers handlers for these notifications using `nvim.RegisterHandler()`.


### MCP Server Implementation

The Go server implements the Model Context Protocol:

```go
// Server initialization
func main() {
    // 1. Parse flags (-nvim, -workspace, -pid, -log-level)
    // 2. Connect to Neovim socket
    // 3. Start Neovim RPC Serve() goroutine
    // 4. Create MCP server
    // 5. Create discovery files
    // 6. Start HTTP server
}
```

**HTTP Endpoints**:
- `POST /mcp` - MCP requests (with auth)
- `GET /events` - SSE for notifications (with auth)
- `GET /health` - Health check (no auth)

**MCP Methods Handled**:
- `initialize` - Handshake
- `tools/list` - Return available tools
- `tools/call` - Execute a tool

### Server-Sent Events (SSE)

SSE is used to push notifications from the server to Gemini CLI:

```go
// SSE Flow
Client connects → Add to clients list
Event occurs → Broadcast to all clients
Client disconnects → Remove from list
```

Events sent:
- `notifications/context-update` - Cursor/file changes
- `notifications/ide/diffAccepted` - User accepted diff
- `notifications/ide/diffRejected` - User rejected diff

## Development Workflow

### Setting Up Development Environment

1. Clone the repository
2. Build the server: `cd server && go build -o ../bin/gemini-mcp-server`
3. Link the plugin to your Neovim config (or use a plugin manager in dev mode)
4. Set `log_level = 'debug'` in your config

### Debugging Tips

#### Enable Debug Logging

```lua
require('gemini-cli').setup({
  log_level = 'debug',
})
```

#### View Logs

In Neovim:
```vim
:messages
```

#### Test RPC Calls Manually

```vim
:lua require('gemini-cli.diff').open_diff('/tmp/test.txt', 'test content')
```

#### Check Discovery Files

```bash
ls -la /tmp/gemini/ide/
cat /tmp/gemini/ide/gemini-ide-server-*.json
```

#### Test HTTP Endpoints

```bash
# Get token from discovery file
TOKEN=$(jq -r '.authToken' /tmp/gemini/ide/gemini-ide-server-*.json)
PORT=$(jq -r '.port' /tmp/gemini/ide/gemini-ide-server-*.json)

# Test health endpoint
curl http://127.0.0.1:$PORT/health

# Test MCP endpoint
curl -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
     http://127.0.0.1:$PORT/mcp

# Monitor SSE
curl -N -H "Authorization: Bearer $TOKEN" \
     http://127.0.0.1:$PORT/events
```

### Common Development Tasks

#### Adding a New MCP Tool

1. Define the tool in `server/mcp/server.go`:
   ```go
   {
       Name:        "myNewTool",
       Description: "Description of what it does",
       InputSchema: map[string]interface{}{
           "type": "object",
           "properties": map[string]interface{}{
               "param1": map[string]interface{}{
                   "type": "string",
               },
           },
           "required": []string{"param1"},
       },
   }
   ```

2. Add handler in the `tools/call` switch statement
3. Implement Lua function if needed in `lua/gemini-cli/`
4. Test with Gemini CLI

#### Modifying Context Tracking

Edit `lua/gemini-cli/context.lua`:
- Add new autocmd events to track
- Update context data structure
- Adjust debounce timing if needed

#### Changing Diff Behavior

Edit `lua/gemini-cli/diff.lua`:
- Modify window layout
- Change diff mode settings
- Update accept/reject logic

## Contributing

### Code Style

**Lua**:
- Use 2 spaces for indentation
- Follow Neovim Lua style guide
- Add comments for non-obvious logic

**Go**:
- Run `gofmt` before committing
- Follow standard Go conventions
- Add godoc comments for exported functions

### Commit Messages

Follow conventional commits format:
```
feat: add new feature
fix: fix bug
docs: update documentation
refactor: refactor code
test: add tests
```

### Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request with clear description

## Troubleshooting Development Issues

### RPC Timeout Errors

**Symptoms**: `RPC timeout` errors in logs

**Causes**:
- `Serve()` goroutine not running
- Lua code stuck in infinite loop
- Using `vim.schedule()` in RPC handler

**Solutions**:
1. Verify `Serve()` is called in a goroutine
2. Check Lua code for infinite loops
3. Remove `vim.schedule()` from RPC-called functions

### Discovery File Not Created

**Symptoms**: Gemini CLI can't find server

**Causes**:
- `/tmp/gemini/ide/` directory doesn't exist
- Permission issues
- Server crashed during startup

**Solutions**:
1. Check server logs in `:messages`
2. Manually create directory: `mkdir -p /tmp/gemini/ide`
3. Restart Neovim

### Diff Window Issues

**Symptoms**: Diff doesn't open or looks wrong

**Causes**:
- Neovim version too old
- Window layout conflicts
- Buffer issues

**Solutions**:
1. Check Neovim version: `:version` (needs >= 0.9.0)
2. Test manually: `:lua require('gemini-cli.diff').open_diff(...)`
3. Check for conflicting plugins

## Related Documentation

- [Architecture](architecture.md) - System architecture overview
- [How It Works](how-it-works.md) - Key mechanisms explained
- [Gemini Communication](gemini-communication.md) - HTTP/MCP protocol
- [Neovim Communication](neovim-communication.md) - RPC protocol
- [Troubleshooting](troubleshooting.md) - Common issues
