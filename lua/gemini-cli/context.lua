---@brief [[
--- Context Management Module
--- Tracks and provides the current editor context (open files, cursor position, selection) to the MCP server.
---@brief ]]

---@module 'gemini-cli.context'
local M = {}

local open_files = {}
local debounce_timer = nil

---Get current context
---@return table context The current workspace context
function M.get_context()
  local files = {}

  -- Get all listed buffers
  local buffers = vim.api.nvim_list_bufs()
  local count = 0

  for _, bufnr in ipairs(buffers) do
    if vim.api.nvim_buf_is_loaded(bufnr) and count < require('gemini-cli').get_config().max_open_files then
      local bufname = vim.api.nvim_buf_get_name(bufnr)

      -- Only include files that exist on disk (not virtual buffers)
      if bufname ~= '' and vim.fn.filereadable(bufname) == 1 then
        local is_active = bufnr == vim.api.nvim_get_current_buf()
        local file = {
          path = bufname,
          timestamp = os.time(),
          isActive = is_active,
        }

        -- Add cursor and selection info for active file
        if is_active then
          local cursor = vim.api.nvim_win_get_cursor(0)
          file.cursor = {
            line = cursor[1],
            character = cursor[2] + 1, -- Convert to 1-based
          }

          -- Get selected text if in visual mode
          local mode = vim.api.nvim_get_mode().mode
          if mode:match('^[vV\22]') then -- Visual, V-Line, V-Block
            local start_pos = vim.fn.getpos('v')
            local end_pos = vim.fn.getpos('.')

            local lines = vim.fn.getline(start_pos[2], end_pos[2])
            if #lines > 0 then
              file.selectedText = table.concat(lines, '\n')
              -- Truncate to 16KB
              if #file.selectedText > 16384 then
                file.selectedText = file.selectedText:sub(1, 16384)
              end
            end
          end
        end

        table.insert(files, file)
        count = count + 1
      end
    end
  end

  -- Sort by timestamp (most recent first)
  table.sort(files, function(a, b)
    return a.timestamp > b.timestamp
  end)

  return {
    workspaceState = {
      openFiles = files,
      isTrusted = true,
    },
  }
end

-- Send context update to MCP server
local function send_context_update()
  local context = M.get_context()

  -- TODO: Send to Golang server via RPC
  -- For now, just call the registered handler
  vim.schedule(function()
    local ok, err = pcall(function()
      vim.fn.rpcnotify(0, 'gemini_context_update', context)
    end)
    if not ok then
      -- Silently ignore errors if server is not connected yet
    end
  end)
end

-- Debounced context update
local function debounced_update()
  if debounce_timer then
    vim.fn.timer_stop(debounce_timer)
  end

  local debounce_ms = require('gemini-cli').get_config().context_debounce_ms
  debounce_timer = vim.fn.timer_start(debounce_ms, function()
    send_context_update()
    debounce_timer = nil
  end)
end

---Setup autocmds to track context changes
function M.setup_tracking()
  local group = vim.api.nvim_create_augroup('GeminiCliContext', { clear = true })

  -- Track file open/close/focus
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufLeave', 'BufWinEnter' }, {
    group = group,
    callback = debounced_update,
  })

  -- Track cursor movement
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = group,
    callback = debounced_update,
  })

  -- Track text changes
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = group,
    callback = debounced_update,
  })

  -- Send initial context
  vim.defer_fn(send_context_update, 100)
end

return M
