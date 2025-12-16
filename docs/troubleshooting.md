# Troubleshooting

This guide helps you diagnose and fix common issues with nvim-gemini-cli.

## Connection Issues

### Gemini CLI Doesn't Connect

**Symptoms**: Running `gemini-cli` shows "No IDE server found" or similar error

**Diagnostic Steps**:

1. **Check server status in Neovim**:
   ```vim
   :GeminiStatus
   ```
   This should show the server is running and display the port number.

2. **Verify discovery file exists**:
   ```bash
   ls -la /tmp/gemini/ide/
   ```
   You should see files like:
   - `gemini-ide-server-<PID>-<PORT>.json`
   - `workspace-<HASH>-latest.json` (symlink)

3. **Check discovery file content**:
   ```bash
   cat /tmp/gemini/ide/gemini-ide-server-*.json
   ```
   Verify it contains valid JSON with `port`, `authToken`, and `workspacePath`.

4. **Verify workspace hash matches**:
   ```bash
   # In your project directory
   echo -n "/path/to/project" | sha256sum | cut -c1-8
   ```
   This should match the hash in the workspace symlink filename.

**Solutions**:

- **Server not running**: Restart with `:GeminiRestart`
- **Discovery file missing**: Check Neovim logs with `:messages` for errors
- **Wrong workspace**: Make sure you're running `gemini-cli` from the same directory where Neovim was started
- **Stale discovery file**: Remove old files: `rm /tmp/gemini/ide/*` and restart Neovim

### Connection Refused Error

**Symptoms**: `curl: (7) Failed to connect to 127.0.0.1 port XXXXX: Connection refused`

**Causes**:
- Server crashed after creating discovery file
- Port conflict
- Firewall blocking localhost connections (rare)

**Solutions**:

1. Check if server is actually running:
   ```vim
   :GeminiStatus
   ```

2. Restart the server:
   ```vim
   :GeminiRestart
   ```

3. Check Neovim logs for crash messages:
   ```vim
   :messages
   ```

### 401 Unauthorized Error

**Symptoms**: HTTP requests return 401 status

**Causes**:
- Wrong auth token
- Token mismatch between discovery file and request

**Solutions**:

1. Verify token in discovery file:
   ```bash
   jq -r '.authToken' /tmp/gemini/ide/gemini-ide-server-*.json
   ```

2. Restart both Neovim and Gemini CLI to get fresh token

## Diff Issues

### Diff Window Doesn't Open

**Symptoms**: Gemini CLI says "Diff opened" but nothing appears in Neovim

**Diagnostic Steps**:

1. **Check Neovim version**:
   ```vim
   :version
   ```
   Needs >= 0.9.0

2. **Test diff manually**:
   ```vim
   :lua require('gemini-cli.diff').open_diff('/tmp/test.txt', 'test content')
   ```

3. **Check for errors**:
   ```vim
   :messages
   ```

**Solutions**:

- **Neovim too old**: Upgrade to >= 0.9.0
- **RPC timeout**: See [RPC Timeout Errors](#rpc-timeout-errors)
- **File doesn't exist**: The plugin should create it, but check file permissions
- **Conflicting plugins**: Disable other diff-related plugins temporarily

### Diff Looks Wrong or Corrupted

**Symptoms**: Diff view has strange layout, missing content, or incorrect highlighting

**Causes**:
- Window layout conflicts
- Buffer issues
- Diff mode not properly set

**Solutions**:

1. Close all diff windows:
   ```vim
   :lua require('gemini-cli.diff').close_diff('/path/to/file')
   ```

2. Try opening diff again

3. Check for conflicting autocmds:
   ```vim
   :autocmd BufEnter
   :autocmd BufWriteCmd
   ```

### Diff Acceptance Doesn't Work

**Symptoms**: Pressing `:w` in diff window doesn't accept changes

**Diagnostic Steps**:

1. **Check configuration**:
   ```vim
   :lua print(vim.inspect(require('gemini-cli').get_config()))
   ```
   Verify `allow_w_to_accept` is `true`

2. **Check if in correct buffer**:
   Make sure you're in the right-side diff window (the one with new content)

**Solutions**:

- **`allow_w_to_accept` is false**: Either enable it in config or accept via CLI prompt
- **Wrong buffer**: Switch to the right-side diff window
- **Try CLI acceptance**: Press `1` in Gemini CLI prompt instead

## RPC Issues

### RPC Timeout Errors

**Symptoms**: Errors like "RPC timeout" or "context deadline exceeded" in logs

**Causes**:
- `Serve()` goroutine not running in Go server
- Lua code stuck in infinite loop
- Using `vim.schedule()` in RPC handler (causes deadlock)

**Solutions**:

1. **Restart Neovim completely** (not just `:GeminiRestart`):
   ```vim
   :qa
   ```
   Then start Neovim again

2. **Rebuild the Go server**:
   ```bash
   cd server
   go build -o ../bin/gemini-mcp-server
   ```

3. **Check for conflicting plugins** that might interfere with RPC

### Connection to Neovim Socket Failed

**Symptoms**: Go server can't connect to Neovim socket

**Causes**:
- Socket doesn't exist
- Wrong socket path
- Permission issues

**Solutions**:

1. **Verify socket exists**:
   ```vim
   :echo v:servername
   ```

2. **Check socket file**:
   ```bash
   ls -la $(nvim --headless -c 'echo v:servername' -c 'quit' 2>&1)
   ```

3. **Restart Neovim** to create fresh socket

## Performance Issues

### Slow or Laggy Cursor Movement

**Symptoms**: Neovim feels sluggish when moving cursor

**Causes**:
- Context updates happening too frequently
- Debounce time too short

**Solutions**:

Increase debounce time in configuration:
```lua
require('gemini-cli').setup({
  context_debounce_ms = 100,  -- Default is 50ms
})
```

### High CPU Usage

**Symptoms**: Go server or Neovim using excessive CPU

**Causes**:
- Too many context updates
- Large files causing slow diff operations
- SSE connection issues

**Solutions**:

1. **Increase debounce time** (see above)

2. **Reduce max open files**:
   ```lua
   require('gemini-cli').setup({
     max_open_files = 5,  -- Default is 10
   })
   ```

3. **Check for SSE connection leaks**:
   ```bash
   # Count open connections to server
   lsof -i :$(jq -r '.port' /tmp/gemini/ide/gemini-ide-server-*.json)
   ```

## Server Issues

### Server Won't Start

**Symptoms**: `:GeminiStatus` shows server is not running

**Diagnostic Steps**:

1. **Check Neovim logs**:
   ```vim
   :messages
   ```

2. **Try manual start**:
   ```vim
   :lua require('gemini-cli.server').start()
   ```

3. **Check if binary exists**:
   ```bash
   ls -la ~/.config/nvim/pack/plugins/start/nvim-gemini-cli/bin/gemini-mcp-server
   ```

**Solutions**:

- **Binary missing**: Build it: `cd server && go build -o ../bin/gemini-mcp-server`
- **Binary not executable**: `chmod +x bin/gemini-mcp-server`
- **Port conflict**: Server will auto-select a different port, check logs

### Server Crashes Repeatedly

**Symptoms**: Server starts but crashes immediately

**Diagnostic Steps**:

1. **Check Neovim logs** for crash messages:
   ```vim
   :messages
   ```

2. **Run server manually** to see error output:
   ```bash
   cd /path/to/nvim-gemini-cli
   ./bin/gemini-mcp-server -nvim=/path/to/nvim/socket -workspace=$(pwd) -pid=$$
   ```

**Solutions**:

- **Rebuild server**: `cd server && go build -o ../bin/gemini-mcp-server`
- **Check Go version**: Needs >= 1.21
- **Report bug**: If crashes persist, file an issue with crash logs

## Debugging Checklist

Use this checklist to systematically diagnose issues:

- [ ] **Server running?** → `:GeminiStatus`
- [ ] **Discovery file exists?** → `ls /tmp/gemini/ide/`
- [ ] **Correct port?** → `cat /tmp/gemini/ide/gemini-ide-server-*.json`
- [ ] **RPC working?** → `:lua require('gemini-cli.diff').open_diff('/tmp/test', 'test')`
- [ ] **HTTP working?** → `curl http://localhost:<PORT>/health`
- [ ] **Auth working?** → `curl -H "Authorization: Bearer <TOKEN>" http://localhost:<PORT>/mcp`
- [ ] **Neovim version?** → `:version` (needs >= 0.9.0)
- [ ] **Go version?** → `go version` (needs >= 1.21)
- [ ] **Recent logs?** → `:messages`

## Getting Help

If you're still experiencing issues:

1. **Enable debug logging**:
   ```lua
   require('gemini-cli').setup({
     log_level = 'debug',
   })
   ```

2. **Collect diagnostic information**:
   - Neovim version: `:version`
   - Plugin version: `git log -1` in plugin directory
   - Server logs: `:messages`
   - Discovery file: `cat /tmp/gemini/ide/gemini-ide-server-*.json`

3. **File an issue** on GitHub with:
   - Description of the problem
   - Steps to reproduce
   - Diagnostic information from above
   - Relevant log excerpts

## Related Documentation

- [How It Works](how-it-works.md) - Understanding the mechanisms
- [Development](development.md) - Development and debugging tips
- [Architecture](architecture.md) - System architecture details
