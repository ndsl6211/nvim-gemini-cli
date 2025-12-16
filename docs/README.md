# Documentation

This directory contains comprehensive documentation for nvim-gemini-cli.

## Documentation Overview

### For Users

Start here if you're using nvim-gemini-cli:

1. **[../README.md](../README.md)** - Installation, configuration, and basic usage
2. **[how-it-works.md](how-it-works.md)** - Understanding the key mechanisms (discovery, context sharing, diffs)
3. **[troubleshooting.md](troubleshooting.md)** - Common issues and solutions

### For Contributors

Start here if you're contributing to nvim-gemini-cli:

1. **[development.md](development.md)** - Development setup, building, testing, and contributing
2. **[architecture.md](architecture.md)** - Detailed system architecture
3. **[neovim-communication.md](neovim-communication.md)** - RPC protocol details
4. **[gemini-communication.md](gemini-communication.md)** - HTTP/MCP protocol details

## Quick Reference

### Understanding the System

- **How does Gemini CLI find Neovim?** → [how-it-works.md#discovery-mechanism](how-it-works.md#discovery-mechanism)
- **How do diffs work?** → [how-it-works.md#diff-implementation](how-it-works.md#diff-implementation)
- **What protocols are used?** → [how-it-works.md#communication-protocols](how-it-works.md#communication-protocols)

### Troubleshooting

- **Gemini CLI won't connect** → [troubleshooting.md#gemini-cli-doesnt-connect](troubleshooting.md#gemini-cli-doesnt-connect)
- **Diff window issues** → [troubleshooting.md#diff-issues](troubleshooting.md#diff-issues)
- **RPC timeout errors** → [troubleshooting.md#rpc-timeout-errors](troubleshooting.md#rpc-timeout-errors)

### Development

- **Building from source** → [development.md#building-from-source](development.md#building-from-source)
- **Running tests** → [development.md#running-tests](development.md#running-tests)
- **Adding new features** → [development.md#common-development-tasks](development.md#common-development-tasks)

### Architecture Deep Dives

- **Component breakdown** → [architecture.md#component-breakdown](architecture.md#component-breakdown)
- **Data flow examples** → [architecture.md#data-flow-examples](architecture.md#data-flow-examples)
- **MCP tools** → [architecture.md#mcp-tools-deep-dive](architecture.md#mcp-tools-deep-dive)

## Document Descriptions

### [how-it-works.md](how-it-works.md)
Explains the key mechanisms that make nvim-gemini-cli work:
- Discovery mechanism (PID-based and workspace-based)
- Context sharing and updates
- Diff implementation workflow
- Communication protocols overview
- Security model
- Performance considerations

### [troubleshooting.md](troubleshooting.md)
Comprehensive troubleshooting guide covering:
- Connection issues
- Diff problems
- RPC errors
- Performance issues
- Server problems
- Debugging checklist

### [development.md](development.md)
Developer guide including:
- Project structure
- Building and testing
- Key technical details (RPC, avoiding deadlocks)
- Development workflow
- Debugging tips
- Contributing guidelines

### [architecture.md](architecture.md)
Detailed system architecture documentation:
- High-level overview
- Component breakdown (Lua plugin, Go server, Gemini CLI)
- Data flow examples
- MCP tools deep dive
- Discovery mechanism internals
- Security model
- Performance considerations
- Error handling
- Testing strategy

### [neovim-communication.md](neovim-communication.md)
RPC protocol details:
- Connection setup
- Communication patterns (Go → Neovim, Neovim → Go)
- Common operations
- Avoiding deadlocks
- Debugging RPC issues

### [gemini-communication.md](gemini-communication.md)
HTTP/MCP protocol details:
- Connection setup and discovery
- Communication patterns (HTTP, SSE)
- MCP protocol methods
- Available tools (openDiff, closeDiff, acceptDiff, rejectDiff)
- Notification events
- Authentication
- Debugging

## Contributing to Documentation

When updating documentation:

1. **Keep it concise** - Users should find information quickly
2. **Use examples** - Show, don't just tell
3. **Cross-reference** - Link to related sections
4. **Update all affected docs** - Changes may impact multiple files
5. **Test commands** - Verify all code examples and commands work

See [development.md](development.md) for more details on contributing.
