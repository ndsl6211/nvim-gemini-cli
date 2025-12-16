# Gemini CLI Communication

This document explains how the Go MCP server communicates with Gemini CLI.

## Overview

The Go server and Gemini CLI communicate using **HTTP** with the **Model Context Protocol (MCP)**. The server also uses **Server-Sent Events (SSE)** to push notifications to the CLI.

## Connection Setup

### Discovery Process

Gemini CLI finds the MCP server using discovery files stored in `/tmp/gemini/ide/`. The plugin supports two discovery methods:

- **PID-based**: When running from Neovim's `:terminal`
- **Workspace-based**: When running from any terminal in the same project directory

> **For detailed explanation** of how discovery works, see [architecture.md#discovery-mechanism](architecture.md#discovery-mechanism).

The discovery file contains the server port and authentication token needed to connect.

### HTTP Connection

Once discovered, Gemini CLI connects to:
- **MCP endpoint**: `http://127.0.0.1:<PORT>/mcp`
- **SSE endpoint**: `http://127.0.0.1:<PORT>/events`

All requests include the auth token in the `Authorization` header.

## Communication Patterns

### Request-Response (HTTP)

Gemini CLI makes HTTP POST requests to the `/mcp` endpoint:

```
POST http://127.0.0.1:51234/mcp
Authorization: Bearer a1b2c3d4-e5f6-...
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "1.0",
    "clientInfo": { ... }
  }
}
```

The server responds:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "protocolVersion": "1.0",
    "serverInfo": { ... }
  }
}
```

### Notifications (Server-Sent Events)

The server can push notifications to Gemini CLI using SSE:

```
GET http://127.0.0.1:51234/events
Authorization: Bearer a1b2c3d4-e5f6-...
```

The connection stays open, and the server sends events:

```
data: {"jsonrpc":"2.0","method":"notifications/context-update","params":{...}}

data: {"jsonrpc":"2.0","method":"notifications/ide/diffAccepted","params":{...}}
```

## MCP Protocol

MCP (Model Context Protocol) defines a standard way for AI tools to interact with development environments.

### Core Methods

#### 1. `initialize`

**When**: First connection
**Purpose**: Handshake and capability exchange

```json
{
  "method": "initialize",
  "params": {
    "protocolVersion": "1.0",
    "clientInfo": {
      "name": "gemini-cli",
      "version": "0.20.0"
    }
  }
}
```

#### 2. `tools/list`

**When**: After initialization
**Purpose**: Get available tools

Response includes all tools the server provides:

```json
{
  "result": {
    "tools": [
      {
        "name": "openDiff",
        "description": "Open a diff view for code changes",
        "inputSchema": { ... }
      },
      {
        "name": "closeDiff",
        "description": "Close diff and get final content",
        "inputSchema": { ... }
      }
    ]
  }
}
```

#### 3. `tools/call`

**When**: Gemini wants to use a tool
**Purpose**: Execute a specific tool

```json
{
  "method": "tools/call",
  "params": {
    "name": "openDiff",
    "arguments": {
      "filePath": "/path/to/file.js",
      "newContent": "console.log('new code');"
    }
  }
}
```

## Available Tools

### 1. openDiff

**Purpose**: Show code changes to the user

**Flow**:
1. Gemini suggests code changes
2. CLI calls `openDiff` tool
3. Server tells Neovim to open diff view
4. User sees side-by-side comparison

**Arguments**:
- `filePath`: Full path to the file
- `newContent`: Suggested new content

**Returns**: Success/failure

### 2. closeDiff

**Purpose**: Get the final content after user review

**Flow**:
1. User finishes reviewing diff
2. CLI calls `closeDiff` tool
3. Server asks Neovim for final content
4. Returns content to CLI

**Arguments**:
- `filePath`: Full path to the file
- `suppressNotification`: Don't send notification event

**Returns**: Final content of the file

### 3. acceptDiff

**Purpose**: Accept and apply changes

**Flow**:
1. User accepts diff (via CLI or `:w`)
2. Server applies changes to file
3. Notifies CLI via SSE

**Arguments**:
- `filePath`: Full path to the file

**Returns**: Success/failure

### 4. rejectDiff

**Purpose**: Discard changes

**Flow**:
1. User rejects diff
2. Server closes diff without applying
3. Notifies CLI via SSE

**Arguments**:
- `filePath`: Full path to the file

**Returns**: Success/failure

## Notification Events

The server pushes these events to Gemini CLI:

### 1. `notifications/context-update`

**When**: User moves cursor, changes files, selects text
**Purpose**: Keep Gemini aware of editing context

**Data**:
```json
{
  "openFiles": [
    {"path": "/path/to/file1.js", "timestamp": 1234567890},
    {"path": "/path/to/file2.js", "timestamp": 1234567891}
  ],
  "activeFile": {
    "path": "/path/to/file1.js",
    "cursorPosition": {"line": 42, "character": 10},
    "selection": "selected text"
  }
}
```

### 2. `notifications/ide/diffAccepted`

**When**: User accepts diff via `:w` in Neovim
**Purpose**: Tell CLI the diff was accepted externally

**Data**:
```json
{
  "filePath": "/path/to/file.js",
  "content": "final content after accept"
}
```

### 3. `notifications/ide/diffRejected`

**When**: User rejects diff in Neovim
**Purpose**: Tell CLI the diff was rejected externally

**Data**:
```json
{
  "filePath": "/path/to/file.js"
}
```

## Authentication

All HTTP requests must include the auth token:

```
Authorization: Bearer <token>
```

The server validates this on every request. Invalid tokens get a 401 response.

## Why This Design?

### HTTP + MCP
- **Standard**: MCP is a standardized protocol
- **Language-agnostic**: Works with any HTTP client
- **Firewall-friendly**: Uses standard HTTP ports

### Server-Sent Events
- **Push notifications**: Server can notify CLI immediately
- **Simple**: Easier than WebSockets for one-way push
- **Reliable**: Browser-standard technology

### Discovery Files
- **Simple**: Just a JSON file
- **Flexible**: Supports multiple discovery methods
- **Debuggable**: Easy to inspect and troubleshoot

## Debugging

### Check Discovery File

```bash
ls -la /tmp/gemini/ide/
cat /tmp/gemini/ide/gemini-ide-server-*.json
```

### Test MCP Endpoint

```bash
curl -H "Authorization: Bearer <token>" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
     http://127.0.0.1:<PORT>/mcp
```

### Monitor SSE

```bash
curl -N -H "Authorization: Bearer <token>" \
     http://127.0.0.1:<PORT>/events
```

### Common Issues

**Error: Connection refused**
- Server not running
- Wrong port number

**Error: 401 Unauthorized**
- Wrong auth token
- Token mismatch between discovery file and environment

**Error: Timeout**
- Server hung or crashed
- Check Neovim messages: `:messages`
