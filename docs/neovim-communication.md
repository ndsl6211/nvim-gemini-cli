# Neovim Communication

This document explains how the Go MCP server communicates with Neovim.

## Overview

The Go server and Neovim communicate using **Remote Procedure Call (RPC)** over a Unix socket. This is a bidirectional channel that allows both sides to call functions on the other.

## Connection Setup

### 1. Socket Creation

When Neovim starts, it creates a Unix socket for RPC communication. You can find this socket path with:

```vim
:echo v:servername
```

This typically returns something like `/tmp/nvim.user.socket` or `/run/user/1000/nvim.12345.0`.

### 2. Server Connection

When our plugin starts the Go server, it:

1. Gets the socket path from Neovim
2. Passes it as a command-line argument: `-nvim=/path/to/socket`
3. Go server connects to this socket using `net.Dial("unix", socketPath)`

### 3. Bidirectional Setup

The Go server creates a Neovim client:

```go
v, err := nvimclient.New(conn, conn, conn, nil)
```

**Critical**: The server must start a goroutine to handle RPC messages:

```go
go func() {
    if err := v.Serve(); err != nil {
        log.Fatalf("Neovim client serve error: %v", err)
    }
}()
```

Without `Serve()`, all RPC calls will hang forever because there's no goroutine reading responses from Neovim.

## Communication Patterns

### Go → Neovim (Calling Lua)

When the Go server needs to execute Lua code in Neovim:

```go
// Execute Lua and get result
var result string
err := nvimClient.ExecLua(`return require('gemini-cli.diff').open_diff(...)`, &result, filePath, newContent)
```

**How it works:**
1. Go encodes the Lua code and arguments using MessagePack
2. Sends via the Unix socket
3. Waits for Neovim to respond
4. Neovim executes the Lua code
5. Neovim sends the result back
6. Go decodes the result

### Neovim → Go (Notifications)

Neovim can also notify the Go server about events:

```lua
-- In Neovim Lua
vim.fn.rpcnotify(channel_id, 'notification_name', arg1, arg2)
```

The Go server registers handlers for these notifications:

```go
nvimClient.RegisterCallbacks(
    func(context *types.IdeContext) {
        // Handle context updates
    },
    func(filePath, content string) {
        // Handle diff accepted
    },
)
```

## Why This Design?

### Unix Sockets
- Fast: No network overhead
- Secure: Only accessible on the same machine
- Efficient: Direct process-to-process communication

### RPC Protocol
- Type-safe: Both sides know what data to expect
- Synchronous: Go can wait for Lua to finish
- Bidirectional: Both sides can initiate communication

## Common Operations

### Opening a Diff

1. Gemini CLI → Go server: "Please open a diff"
2. Go server → Neovim: `ExecLua('require("gemini-cli.diff").open_diff(...)')`
3. Neovim Lua: Creates diff windows
4. Neovim → Go server: Returns `true` (success)
5. Go server → Gemini CLI: "Diff opened successfully"

### Getting Editor Context

1. Neovim detects cursor movement
2. Neovim Lua → Go server: `rpcnotify(channel, 'context_update', context_data)`
3. Go server receives notification
4. Go server → Gemini CLI: Sends context via HTTP

## Avoiding Deadlocks

### The `vim.schedule()` Problem

**Don't do this:**

```lua
function open_diff(path, content)
    vim.schedule(function()
        -- Do diff operations
    end)
    return true
end
```

**Why it fails:**
1. RPC call starts
2. Lua queues operation with `vim.schedule()`
3. Lua returns `true` immediately
4. RPC handler finishes
5. BUT: Neovim's event loop is blocked waiting for RPC to complete
6. `vim.schedule()` callback never runs
7. Deadlock!

**Do this instead:**

```lua
function open_diff(path, content)
    -- Do diff operations directly
    vim.cmd('split')
    -- ... more operations
    return true
end
```

All operations execute synchronously during the RPC call, so the event loop doesn't get blocked.

## Debugging RPC Issues

### Check Connection

```vim
:lua print(vim.v.servername)
```

### Test RPC Manually

```vim
:lua require('gemini-cli.diff').open_diff('/tmp/test.txt', 'test content')
```

If this works but the Go server can't call it, the issue is with the Go client setup.

### Common Errors

**Error: Connection refused**
- Neovim socket doesn't exist
- Wrong socket path

**Error: Timeout**
- `Serve()` goroutine not running
- Lua code is stuck in infinite loop

**Error: Unknown function**
- Using wrong RPC method (use `ExecLua()`, not `Call("nvim_exec_lua")`)
