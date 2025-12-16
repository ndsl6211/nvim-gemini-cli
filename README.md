# nvim-gemini-cli

A Neovim plugin that enables seamless integration with [Google's Gemini CLI](https://github.com/google-gemini/gemini-cli) IDE mode.

## Features

- 🔄 **Real-time Context Awareness**: Automatically shares your current file, cursor position, and selection with Gemini CLI
- 📝 **Native Diff Support**: Review and apply AI-suggested code changes directly in Neovim with side-by-side diff view
- ⌨️ **Flexible Acceptance**: Accept diffs via `:w` in Neovim or through Gemini CLI prompts
- 🚀 **Standard MCP Protocol**: Built on the Model Context Protocol over HTTP
- 🔒 **Secure**: Token-based authentication for all communications
- 🌐 **Workspace Discovery**: Connect from any terminal, not just Neovim's `:terminal`

## Overview

This plugin integrates Neovim with Gemini CLI using the Model Context Protocol (MCP). It consists of:

- **Neovim Lua Plugin**: Monitors your editing activity and manages the diff UI
- **Golang MCP Server**: Bridges communication between Neovim and Gemini CLI

For detailed architecture information, see [docs/architecture.md](docs/architecture.md).

## Requirements

- Neovim >= 0.9.0
- Go >= 1.21
- [Gemini CLI](https://github.com/google-gemini/gemini-cli)

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'nvim-gemini-cli',
  dir = '/path/to/nvim-gemini-cli',
  build = 'cd server && go build -o ../bin/gemini-mcp-server',
  config = function()
    require('gemini-cli').setup({
      -- Optional configuration
      allow_w_to_accept = false,  -- Set to true to accept diffs with :w
      log_level = 'info',
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'nvim-gemini-cli',
  config = function()
    require('gemini-cli').setup()
  end,
  run = 'cd server && go build -o ../bin/gemini-mcp-server'
}
```

### Manual Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/nvim-gemini-cli.git ~/.config/nvim/pack/plugins/start/nvim-gemini-cli
   ```

2. Build the MCP server:
   ```bash
   cd ~/.config/nvim/pack/plugins/start/nvim-gemini-cli/server
   go build -o ../bin/gemini-mcp-server
   ```

3. Add to your `init.lua`:
   ```lua
   require('gemini-cli').setup()
   ```

## Usage

### Basic Workflow

1. Start Neovim
2. The plugin automatically starts the MCP server in the background
3. Open a terminal (in Neovim with `:terminal` or in a separate terminal window)
4. Run `gemini-cli` - it will automatically detect and connect to your Neovim instance
5. Ask Gemini to edit code - changes will appear as a diff in Neovim

### Working with Diffs

When Gemini CLI suggests code changes:

1. **Diff window opens automatically** in Neovim showing:
   - Left side: Original code
   - Right side: Suggested changes (editable)

2. **Review and edit** the suggested changes in the diff window

3. **Accept changes** using one of two methods:
   - **Option A**: Press `:w` in the diff window (if `allow_w_to_accept = true`)
   - **Option B**: Press `1` in the Gemini CLI prompt to accept

4. **Reject changes**: Press `2` in the Gemini CLI prompt

### Commands

- `:GeminiStatus` - Show MCP server connection status and port
- `:GeminiRestart` - Restart the MCP server
- `:GeminiStop` - Stop the MCP server
- `:GeminiChat` - Toggle Gemini chat terminal (opens a terminal running `gemini`)

> **Tip**: After opening `:GeminiChat` for the first time, run `/ide enable` in Gemini to automatically connect to Neovim on future sessions.

## Configuration

Full configuration options:

```lua
require('gemini-cli').setup({
  -- Auto-start server when Neovim starts
  auto_start = true,
  
  -- Log level: 'debug', 'info', 'warn', 'error'
  log_level = 'info',
  
  -- Debounce time for context updates (ms)
  context_debounce_ms = 50,
  
  -- Maximum number of open files to track
  max_open_files = 10,
  
  -- Allow :w in diff window to accept changes
  -- If false, you must accept via CLI prompt
  allow_w_to_accept = false,
})
```

### Configuration Details

#### `allow_w_to_accept`

Controls how you accept diff changes:

- `false` (default): You must go back to the Gemini CLI terminal and press `1` to accept
- `true`: Pressing `:w` in the diff window automatically accepts and applies changes

Choose based on your workflow:
- Set to `false` if you want explicit control via CLI
- Set to `true` for a streamlined Neovim-centric workflow

## How It Works

For a detailed explanation of the discovery mechanism, context sharing, and diff implementation, see [docs/how-it-works.md](docs/how-it-works.md).

## Development

For information on building from source, running tests, and contributing, see [docs/development.md](docs/development.md).

## Troubleshooting

For common issues and solutions, see [docs/troubleshooting.md](docs/troubleshooting.md).

## Documentation

For detailed documentation, see the [docs/](docs/) directory:

- **[How It Works](docs/how-it-works.md)** - Discovery mechanism, context sharing, and diff implementation
- **[Development Guide](docs/development.md)** - Building, testing, and contributing
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions
- **[Architecture](docs/architecture.md)** - Detailed system architecture
- **[Neovim Communication](docs/neovim-communication.md)** - RPC protocol details
- **[Gemini Communication](docs/gemini-communication.md)** - HTTP/MCP protocol details

## Contributing

Contributions are welcome! Please see [docs/development.md](docs/development.md) for:

- Development setup and workflow
- Building from source
- Running tests
- Code style guidelines
- How to submit pull requests

## License

MIT

## Related Projects

- [Gemini CLI](https://github.com/google-gemini/gemini-cli)
- [Model Context Protocol](https://modelcontextprotocol.io/)
