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
---@field setup_keymaps boolean Automatically setup default keymaps (default: true)
local config = {
  auto_start = true,
  log_level = 'info',
  context_debounce_ms = 50,
  max_open_files = 10,
  allow_w_to_accept = true, -- Default to true as per user preference
  setup_keymaps = true,
}

M.config = config

---Setup the plugin with user configuration
---@param opts GeminiConfig|nil Optional configuration table to override defaults
function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})

  if config.auto_start then
    require('gemini-cli.server').start()
  end

  -- Setup <Plug> mappings and optionally default keymaps
  M.setup_mappings()

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

---Setup <Plug> mappings and default keymaps
function M.setup_mappings()
  -- Define <Plug> mappings
  -- These act as a stable interface for users to map to
  vim.keymap.set('n', '<Plug>(GeminiChat)', function()
    require('gemini-cli.terminal').toggle()
  end, { desc = 'Toggle Gemini Chat' })

  vim.keymap.set('n', '<Plug>(GeminiStatus)', function()
    require('gemini-cli.server').status()
  end, { desc = 'Gemini Status' })

  vim.keymap.set('n', '<Plug>(GeminiRestart)', function()
    require('gemini-cli.server').restart()
  end, { desc = 'Gemini Restart' })

  vim.keymap.set('n', '<Plug>(GeminiStop)', function()
    require('gemini-cli.server').stop()
  end, { desc = 'Gemini Stop' })

  -- Setup default keymaps if enabled
  if config.setup_keymaps then
    -- <leader>gc for Chat
    if vim.fn.mapcheck('<leader>gc', 'n') == '' then
      vim.keymap.set('n', '<leader>gc', '<Plug>(GeminiChat)', { remap = true, desc = 'Gemini Chat' })
    end

    -- <leader>gs for Status
    if vim.fn.mapcheck('<leader>gs', 'n') == '' then
      vim.keymap.set('n', '<leader>gs', '<Plug>(GeminiStatus)', { remap = true, desc = 'Gemini Status' })
    end
  end
end

---Get the current configuration
---@return GeminiConfig config The current configuration table
function M.get_config()
  return config
end

return M
