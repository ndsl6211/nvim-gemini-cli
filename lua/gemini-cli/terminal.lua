---Terminal module for Gemini CLI integration
---@module 'gemini-cli.terminal'

local M = {}

local log = require('gemini-cli.log')

-- Terminal state
---@type number|nil
local bufnr = nil
---@type number|nil
local winid = nil
---@type number|nil
local jobid = nil
local help_shown = false

---Check if terminal is valid
---@return boolean
local function is_valid()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    bufnr = nil
    winid = nil
    jobid = nil
    return false
  end
  return true
end

---Check if terminal window is visible
---@return boolean
local function is_visible()
  if not is_valid() then
    return false
  end

  -- Check all windows to see if our buffer is displayed
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      winid = win
      return true
    end
  end

  winid = nil
  return false
end

---Create a floating window for the terminal
---@param bufnr number
---@return number winid
local function create_floating_window(bufnr)
  local screen_w = vim.o.columns
  local screen_h = vim.o.lines - vim.o.cmdheight
  local width = math.floor(screen_w * 0.5)
  local height = math.floor(screen_h * 0.7)
  local col = math.floor((screen_w - width) / 2)
  local row = math.floor((screen_h - height) / 2)

  local opts = {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
    title = ' Gemini CLI ',
    title_pos = 'center',
  }

  local win = vim.api.nvim_open_win(bufnr, true, opts)
  return win
end

---Show terminal window
---@param focus boolean Whether to focus the terminal
---@param style string|nil 'split' or 'float'
local function show_terminal(focus, style)
  if not is_valid() then
    return false
  end

  -- If already visible, just focus if needed
  if is_visible() then
    if focus and winid then
      vim.api.nvim_set_current_win(winid)
      vim.cmd('startinsert')
    end
    return true
  end

  -- Split logic
  if style == 'float' then
    if bufnr then
      winid = create_floating_window(bufnr)
    end
  else
    -- Side split (default)
    local width = math.floor(vim.o.columns * 0.3)
    vim.cmd('botright ' .. width .. 'vsplit')
    winid = vim.api.nvim_get_current_win()
    if bufnr then
      vim.api.nvim_win_set_buf(winid, bufnr)
    end
  end

  if focus then
    vim.cmd('startinsert')
  end

  return true
end

---Hide terminal window (keep process running)
local function hide_terminal()
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, false)
    winid = nil
  end
end

---Create new terminal
---@param focus boolean Whether to focus the terminal
---@param style string|nil 'split' or 'float'
local function create_terminal(focus, style)
  -- Save original window
  local original_win = vim.api.nvim_get_current_win()

  -- Get server port for discovery
  local server = require('gemini-cli.server')
  local port = server.get_port()

  -- AUTO-START: If server not running, start it
  if not port then
    local log = require('gemini-cli.log')
    log.info('Starting Gemini MCP server...')
    server.start()

    -- Wait for port
    local max_attempts = 10
    local attempt = 0
    while not port and attempt < max_attempts do
      vim.wait(500)
      port = server.get_port()
      attempt = attempt + 1
    end

    if not port then
      vim.notify('Failed to start/connect to Gemini MCP server.', vim.log.levels.ERROR)
      return false
    end
  end

  -- Setup environment
  local env = {
    GEMINI_CLI_IDE_SERVER_PORT = tostring(port),
    GEMINI_CLI_IDE_AUTH_TOKEN = server.get_auth_token(),
    GEMINI_CLI_IDE_WORKSPACE_PATH = server.get_workspace_path(),
  }

  -- Create target window
  local target_buf = vim.api.nvim_create_buf(false, true)
  local target_win
  if style == 'float' then
    target_win = create_floating_window(target_buf)
  else
    local width = math.floor(vim.o.columns * 0.3)
    vim.cmd('botright ' .. width .. 'vsplit')
    target_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(target_win, target_buf)
  end

  -- Start terminal
  jobid = vim.fn.termopen({ 'zsh', '-c', 'gemini; exit $?' }, {
    cwd = vim.fn.getcwd(),
    env = env,
    on_exit = function(job_id, exit_code, _)
      vim.schedule(function()
        if job_id == jobid then
          bufnr = nil
          winid = nil
          jobid = nil
          if target_win and vim.api.nvim_win_is_valid(target_win) then
            vim.api.nvim_win_close(target_win, true)
          end
        end
      end)
    end,
  })

  if not jobid or jobid == 0 then
    vim.notify('Failed to start Gemini terminal', vim.log.levels.ERROR)
    vim.api.nvim_win_close(target_win, true)
    return false
  end

  bufnr = target_buf
  winid = target_win
  vim.bo[bufnr].bufhidden = 'hide'

  -- Auto-insert on enter
  vim.api.nvim_create_autocmd('BufEnter', {
    buffer = bufnr,
    callback = function()
      if vim.bo[bufnr].buftype == 'terminal' then
        vim.cmd('startinsert')
      end
    end,
  })

  vim.cmd('startinsert')
  return true
end

---Toggle terminal visibility
---@param style string|nil 'split' or 'float'
function M.toggle(style)
  if is_visible() then
    hide_terminal()
  elseif is_valid() then
    show_terminal(true, style)
  else
    create_terminal(true, style)
  end
end

---Open terminal (create or show)
---@param style string|nil 'split' or 'float'
function M.open(style)
  if not is_valid() then
    create_terminal(true, style)
  else
    show_terminal(true, style)
  end
end

---Restart the terminal process (called after server restart)
function M.restart()
  local was_visible = is_visible()
  local current_style = 'split'
  -- Detect current style from window config
  if winid and vim.api.nvim_win_is_valid(winid) then
    local config = vim.api.nvim_win_get_config(winid)
    if config.relative ~= '' then
      current_style = 'float'
    end
  end

  if jobid then
    vim.fn.jobstop(jobid)
  end

  -- Small delay to let job clean up
  vim.defer_fn(function()
    if was_visible then
      create_terminal(true, current_style)
    else
      -- If it wasn't visible, just clear state so next open starts fresh
      bufnr = nil
      winid = nil
      jobid = nil
    end
  end, 200)
end

---Close terminal completely
function M.close()
  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_close(winid, true)
  end
  bufnr = nil
  winid = nil
  jobid = nil
end

---Check if terminal is currently open
---@return boolean
function M.is_open()
  return is_visible()
end

---Get terminal buffer number
---@return number|nil
function M.get_bufnr()
  if is_valid() then
    return bufnr
  end
  return nil
end

---Send text directly to the terminal's stdin
---@param text string The text to send
---@return boolean success Whether the text was sent
function M.send_to_terminal(text)
  if not jobid or jobid <= 0 then
    -- Try to open if not valid
    if not is_valid() then
      if not M.open() then
        return false
      end
    end
  end

  -- Ensure we have a jobid after potential open
  if jobid and jobid > 0 then
    vim.api.nvim_chan_send(jobid, text)
    return true
  end

  return false
end

return M
