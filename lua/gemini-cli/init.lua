---@brief [[
--- Gemini CLI Neovim Integration
--- This plugin integrates Gemini CLI with Neovim, enabling
--- seamless AI-assisted coding experiences directly in Neovim.
---@brief ]]

---@module 'gemini-cli'
local M = {}

---@class GeminiConfig
---@field auto_start boolean Automatically start the MCP server on setup (default: true)
---@field log_level string Log level: 'debug', 'info', 'warn', 'error' (default: 'info')
---@field context_debounce_ms number Debounce time for context updates in ms (default: 50)
---@field max_open_files number Maximum number of open files to track (default: 10)
---@field allow_w_to_accept boolean Allow :w in diff window to accept changes (default: false)
local config = {
  auto_start = true,
  log_level = 'info',
  context_debounce_ms = 50,
  max_open_files = 10,
  allow_w_to_accept = false,
}

M.config = config

---Setup the plugin with user configuration
---@param opts GeminiConfig|nil Optional configuration table to override defaults
function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})

  if config.auto_start then
    require('gemini-cli.server').start()
  end

  -- Setup commands
  vim.api.nvim_create_user_command('GeminiStatus', function()
    require('gemini-cli.server').status()
  end, {})

  vim.api.nvim_create_user_command('GeminiRestart', function()
    require('gemini-cli.server').restart()
  end, {})

  vim.api.nvim_create_user_command('GeminiStop', function()
    require('gemini-cli.server').stop()
  end, {})

  vim.api.nvim_create_user_command('GeminiChat', function()
    require('gemini-cli.terminal').toggle()
  end, {
    desc = 'Toggle Gemini CLI chat terminal'
  })
end

---Get the current configuration
---@return GeminiConfig config The current configuration table
function M.get_config()
  return config
end

return M
