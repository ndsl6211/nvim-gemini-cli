# nvim-gemini-cli

A Neovim plugin that enables seamless integration with [Google's Gemini CLI](https://github.com/google-gemini/gemini-cli) IDE mode.

## Features

- 🔄 **Real-time Context Awareness**: Automatically shares your current file, cursor position, and selection with Gemini CLI
- 🪟 **Floating Window Support**: Toggle chat in a native Neovim floating window or a traditional side split
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
      -- Auto-setup default keymaps (<leader>gc, <leader>gs)
      setup_keymaps = true,
      -- Set to true to accept diffs with :w in the diff window
      allow_w_to_accept = true,
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

## Keymaps

The plugin provides customizable keymaps via `<Plug>` mappings and Lua functions.

### Default Keymaps

If `setup_keymaps = true` (default), the following mappings are created:

- `<leader>gc` : Toggle Gemini Chat terminal (Split)
- `<leader>gf` : Toggle Gemini Chat terminal (Float)
- `<leader>ga` : Send current file or selection to Gemini (Send/Append)
- `<leader>gs` : Show Gemini Status

### Customizing Keymaps

You can manually map keys to the provided `<Plug>` mappings or Lua functions:

**Using Lua Functions (Telescope Style):**

```lua
-- Normal mode mapping
vim.keymap.set('n', '<leader>ff', function() require('gemini-cli.terminal').toggle() end)
```

**Using `<Plug>` Mappings:**

```lua
-- This will automatically override the default <leader>gc
vim.keymap.set('n', '<C-g>', '<Plug>(GeminiChat)')
```

Available `<Plug>` mappings:

- `<Plug>(GeminiChat)`
- `<Plug>(GeminiChatFloat)`
- `<Plug>(GeminiSend)`
- `<Plug>(GeminiStatus)`
- `<Plug>(GeminiRestart)`
- `<Plug>(GeminiStop)`

## Configuration

Full configuration options with their default values:

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
  
  -- Allow :w in diff window to automatically accept and save changes
  -- If true, pressing :w in the diff buffer accepts the suggestions.
  allow_w_to_accept = true,

  -- Automatically setup default keymaps (<leader>gc, <leader>gs)
  setup_keymaps = true,

  -- Focus Gemini terminal when opened via command/keymap (default: true)
  focus_on_open = true,

  -- Focus Gemini terminal when automatically opened by GeminiSend (default: false)
  focus_on_send = false,
})
```

### Configuration Details

#### `allow_w_to_accept`

Controls how you accept diff changes:

-   `true` (default): Pressing `:w` in the diff window automatically applies changes to the original file, saves it to disk, and notifies Gemini CLI.
-   `false`: `:w` in the diff buffer only updates the buffer state without saving to disk or notifying the server. You must accept changes via the Gemini CLI prompt.

Choose based on your workflow:
- Set to `false` if you want explicit control via CLI
- Set to `true` for a streamlined Neovim-centric workflow

#### `focus_on_open`

Controls whether the Gemini terminal window gains focus when it is opened via `:GeminiChat` or the `<leader>gc`/`<leader>gf` keymaps.

- `true` (default): Focus moves to the terminal immediately and enters `Insert` mode.
- `false`: The terminal opens but your cursor stay in the current buffer.

#### `focus_on_send`

Controls whether the Gemini terminal window gains focus when it is **automatically** opened by a context send command (`:GeminiSend` or `<leader>ga`).

- `true`: Focus moves to the terminal.
- `false` (default): Focus stays in your code, allows you to send multiple references conveniently.

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
