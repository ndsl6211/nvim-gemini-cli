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
---@field focus_on_open boolean Focus Gemini terminal when opened via command/keymap (default: true)
---@field focus_on_send boolean Focus Gemini terminal when automatically opened by GeminiSend (default: false)
local config = {
  auto_start = true,
  log_level = 'info',
  context_debounce_ms = 50,
  max_open_files = 10,
  allow_w_to_accept = true, -- Default to true as per user preference
  setup_keymaps = true,
  focus_on_open = true,
  focus_on_send = false,
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

  vim.api.nvim_create_user_command('GeminiChat', function(opts)
    local style = nil
    if opts.args ~= '' then
      style = opts.args:match('^%s*(%S+)')
    end
    require('gemini-cli.terminal').toggle(style)
  end, {
    nargs = '?',
    desc = 'Toggle Gemini CLI chat terminal (optional style: split|float)',
    complete = function()
      return { 'split', 'float' }
    end,
  })

  vim.api.nvim_create_user_command('GeminiSend', function(opts)
    local range = nil
    if opts.range > 0 then
      range = { opts.line1, opts.line2 }
    end
    M.send_context(range)
  end, {
    range = true,
    desc = 'Send selection or current file context to Gemini CLI',
  })
end

---Send selection or current file context to the Gemini terminal
---@param range table|nil Optional {start_line, end_line} (1-based)
function M.send_context(range)
  local bufnr = vim.api.nvim_get_current_buf()
  local filetype = vim.bo[bufnr].filetype
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local target_path = bufname
  local start_line, end_line

  -- Handle NvimTree
  if filetype == 'NvimTree' then
    local ok, api = pcall(require, 'nvim-tree.api')
    if ok then
      local node = api.tree.get_node_under_cursor()
      if node and node.absolute_path then
        target_path = node.absolute_path
      else
        vim.notify('No file selected in NvimTree', vim.log.levels.WARN)
        return
      end
    else
      vim.notify('NvimTree API not found', vim.log.levels.WARN)
      return
    end
  end

  if target_path == '' then
    vim.notify('Buffer has no name', vim.log.levels.WARN)
    return
  end

  -- Get relative path from workspace root
  local workspace = require('gemini-cli.server').get_workspace_path()
  local rel_path = target_path
  if workspace then
    -- Normalize paths for replacement
    local norm_workspace = workspace:gsub('([%(%)%.%%%+%-%*%?%[%^%$])', '%%%1')
    rel_path = target_path:gsub('^' .. norm_workspace .. '/?', '')
  end

  if range then
    start_line = range[1]
    end_line = range[2]
  elseif filetype ~= 'NvimTree' then
    -- Normal mode (not NvimTree): Include current line number
    local cursor = vim.api.nvim_win_get_cursor(0)
    start_line = cursor[1]
    end_line = start_line
  end

  -- Format as @path#Lx-y (Always range-style or single line if start==end)
  local ref = '@' .. rel_path
  if start_line then
    ref = ref .. string.format('#L%d', start_line)
    if start_line ~= end_line then
      ref = ref .. string.format('-%d', end_line)
    end
  end

  -- Send to terminal (with a space at the end)
  local success = require('gemini-cli.terminal').send_to_terminal(ref .. ' ')
  if success then
    vim.notify(string.format('Sent reference %s to Gemini', rel_path), vim.log.levels.INFO)
  else
    vim.notify('Failed to send context. Is Gemini terminal open?', vim.log.levels.ERROR)
  end
end

---Setup <Plug> mappings and default keymaps
function M.setup_mappings()
  -- We use Lua functions directly instead of string commands (e.g. ':GeminiChat<CR>')
  -- to provide a cleaner UI experience (no command-line flickering) and better
  -- performance. For GeminiSend, this also prevents the ':<,'> from appearing.
  -- Define <Plug> mappings as a stable interface for users.
  vim.keymap.set('n', '<Plug>(GeminiChat)', function()
    require('gemini-cli.terminal').toggle()
  end, { desc = 'Toggle Gemini Chat (Split)' })

  vim.keymap.set('n', '<Plug>(GeminiChatFloat)', function()
    require('gemini-cli.terminal').toggle('float')
  end, { desc = 'Toggle Gemini Chat (Float)' })

  vim.keymap.set('n', '<Plug>(GeminiStatus)', function()
    require('gemini-cli.server').status()
  end, { desc = 'Gemini Status' })

  vim.keymap.set('n', '<Plug>(GeminiRestart)', function()
    require('gemini-cli.server').restart()
  end, { desc = 'Gemini Restart' })

  vim.keymap.set('n', '<Plug>(GeminiStop)', function()
    require('gemini-cli.server').stop()
  end, { desc = 'Gemini Stop' })

  vim.keymap.set({ 'n', 'v' }, '<Plug>(GeminiSend)', function()
    local mode = vim.api.nvim_get_mode().mode
    local range = nil
    if mode:match('^[vV\22]') then
      -- Visual mode needs an explicit exit (Escape) to update the '< and '> marks
      vim.cmd('normal! \27')
      local start_line = vim.fn.getpos("'<")[2]
      local end_line = vim.fn.getpos("'>")[2]
      range = { start_line, end_line }
    end
    M.send_context(range)
  end, { desc = 'Send context to Gemini' })

  -- Setup default keymaps if enabled
  if config.setup_keymaps then
    -- <leader>gc for Chat
    if vim.fn.mapcheck('<leader>gc', 'n') == '' then
      vim.keymap.set('n', '<leader>gc', '<Plug>(GeminiChat)', { remap = true, desc = 'Gemini Chat (Split)' })
    end
    -- <leader>gf for Float
    if vim.fn.mapcheck('<leader>gf', 'n') == '' then
      vim.keymap.set('n', '<leader>gf', '<Plug>(GeminiChatFloat)', { remap = true, desc = 'Gemini Chat (Float)' })
    end

    -- <leader>gs for Status
    if vim.fn.mapcheck('<leader>gs', 'n') == '' then
      vim.keymap.set('n', '<leader>gs', '<Plug>(GeminiStatus)', { remap = true, desc = 'Gemini Status' })
    end

    -- <leader>ga for Send/Append
    if vim.fn.mapcheck('<leader>ga', 'n') == '' and vim.fn.mapcheck('<leader>ga', 'v') == '' then
      vim.keymap.set({ 'n', 'v' }, '<leader>ga', '<Plug>(GeminiSend)', { remap = true, desc = 'Gemini Send Context' })
    end
  end
end

---Get the current configuration
---@return GeminiConfig config The current configuration table
function M.get_config()
  return config
end

return M
