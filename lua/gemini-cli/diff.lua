---@brief [[
--- Diff module for Gemini CLI
--- Handles diff operations, including opening, closing, accepting, and rejecting diffs.
---@brief ]]

---@module 'gemini-cli.diff'
local M = {}
local log = require('gemini-cli.log')

-- Track active diff buffers
---@type table<string, {original_buf: number, original_win: number, diff_buf: number, diff_win: number}>
local active_diffs = {}

-- Helper: Find a suitable editable window for opening diff
-- Returns: window_id (or nil if no suitable window found)
---@return number|nil window_id The window ID of a suitable editable window, or nil
local function find_editable_window()
    local all_wins = vim.api.nvim_tabpage_list_wins(0)

    -- Filter for editable windows (normal file buffers)
    local editable_wins = {}
    for _, win in ipairs(all_wins) do
        local buf = vim.api.nvim_win_get_buf(win)
        local buftype = vim.api.nvim_buf_get_option(buf, 'buftype')
        local filetype = vim.api.nvim_buf_get_option(buf, 'filetype')
        local modifiable = vim.api.nvim_buf_get_option(buf, 'modifiable')

        -- Check if this is an editable normal file buffer
        local is_editable = buftype == '' and
            modifiable and
            filetype ~= 'NvimTree' and
            filetype ~= 'neo-tree' and
            filetype ~= 'qf' and
            filetype ~= 'help' and
            filetype ~= 'terminal'

        if is_editable then
            table.insert(editable_wins, win)
        end
    end

    -- If we have editable windows, prefer one that's not leftmost/rightmost
    if #editable_wins > 0 then
        -- If we have more than 2 editable windows, pick one in the middle
        if #editable_wins > 2 then
            return editable_wins[2] -- Second window (not leftmost)
        else
            -- Just use the first editable window
            return editable_wins[1]
        end
    end

    -- No editable window found
    return nil
end

---Open a diff view for a file
---@param file_path string|table The path to the file (or a table of args from RPC)
---@param new_content string|nil The new content for the file (if file_path is string)
---@return boolean success Whether the operation was successful
function M.open_diff(file_path, new_content)
    if type(file_path) == 'table' then
        -- Attempt to unpack if it looks like the args list
        if #file_path >= 2 and type(file_path[1]) == 'string' then
            new_content = file_path[2]
            file_path = file_path[1]
        end
    end

    -- Close existing diff for this file if any
    if active_diffs[file_path] then
        M.close_diff(file_path)
    end

    -- Read current file content
    local current_content = ''
    if vim.fn.filereadable(file_path) == 1 then
        current_content = table.concat(vim.fn.readfile(file_path), '\n')
    end

    -- Create a scratch buffer for the new content
    local new_buf = vim.api.nvim_create_buf(false, true)

    -- Clean up any existing buffer with the same name
    local buf_name = file_path .. ' [Gemini Suggestion]'
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == buf_name then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end

    vim.api.nvim_buf_set_name(new_buf, buf_name)

    -- Set new content
    local new_lines = vim.split(new_content, '\n')
    vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, new_lines)
    vim.api.nvim_buf_set_option(new_buf, 'filetype', vim.filetype.match({ filename = file_path }) or '')
    vim.api.nvim_buf_set_option(new_buf, 'modifiable', true)
    vim.api.nvim_buf_set_option(new_buf, 'buftype', 'acwrite') -- Virtual buffer that handles :w manually

    -- Find or create an editable window
    local editable_win = find_editable_window()

    if editable_win then
        -- Use existing editable window
        vim.api.nvim_set_current_win(editable_win)
        vim.cmd('edit ' .. vim.fn.fnameescape(file_path))
    else
        -- No editable window found, create a new split
        -- First, try to find any non-special window to split from
        local all_wins = vim.api.nvim_tabpage_list_wins(0)
        local best_win = nil
        for _, win in ipairs(all_wins) do
            local buf = vim.api.nvim_win_get_buf(win)
            local filetype = vim.api.nvim_buf_get_option(buf, 'filetype')
            -- Avoid splitting from nvimtree/terminal
            if filetype ~= 'NvimTree' and filetype ~= 'neo-tree' and filetype ~= 'terminal' then
                best_win = win
                break
            end
        end

        if best_win then
            vim.api.nvim_set_current_win(best_win)
        end

        -- Create new split for the original file
        vim.cmd('vsplit ' .. vim.fn.fnameescape(file_path))
    end

    local original_win = vim.api.nvim_get_current_win()
    local original_buf = vim.api.nvim_win_get_buf(original_win)

    -- Ensure original buffer has the correct file path
    local current_buf_name = vim.api.nvim_buf_get_name(original_buf)
    if current_buf_name ~= file_path then
        vim.api.nvim_buf_set_name(original_buf, file_path)
    end

    -- Split and show diff
    vim.cmd('vertical split')
    local diff_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(diff_win, new_buf)

    -- Enable diff mode ONLY on these two windows
    vim.api.nvim_win_call(original_win, function()
        vim.cmd('diffthis')
    end)
    vim.api.nvim_win_call(diff_win, function()
        vim.cmd('diffthis')
    end)

    -- Set up :w (write) to accept changes
    vim.api.nvim_create_autocmd('BufWriteCmd', {
        buffer = new_buf,
        callback = function()
            local config = require('gemini-cli').get_config()
            if config.allow_w_to_accept then
                M.accept_diff(file_path)
            else
                log.info('Please accept changes in the Gemini CLI')
            end
            if vim.api.nvim_buf_is_valid(new_buf) then
                vim.api.nvim_buf_set_option(new_buf, 'modified', false)
            end
        end,
        desc = 'Accept Gemini changes on :w',
    })

    -- Store diff info
    active_diffs[file_path] = {
        original_buf = original_buf,
        original_win = original_win,
        diff_buf = new_buf,
        diff_win = diff_win,
    }

    -- Show instructions (non-blocking)
    log.info_silent('Gemini diff opened. Press :w in the diff window to accept changes.')

    return true
end

---Close diff view and return final content
---@param file_path string The path to the file
---@return string|nil content The final content of the file, or nil if no diff was active
function M.close_diff(file_path)
    local diff = active_diffs[file_path]
    if not diff then
        return nil
    end

    -- Get final content from original file
    local content = table.concat(vim.api.nvim_buf_get_lines(diff.original_buf, 0, -1, false), '\n')

    -- Close diff window and buffer
    if vim.api.nvim_win_is_valid(diff.diff_win) then
        vim.api.nvim_win_close(diff.diff_win, true)
    end
    if vim.api.nvim_buf_is_valid(diff.diff_buf) then
        vim.api.nvim_buf_delete(diff.diff_buf, { force = true })
    end

    -- Turn off diff mode in original window
    if vim.api.nvim_win_is_valid(diff.original_win) then
        vim.api.nvim_win_call(diff.original_win, function()
            vim.cmd('diffoff')
        end)
    end

    active_diffs[file_path] = nil
    return content
end

---Accept diff changes
---@param file_path string The path to the file
function M.accept_diff(file_path)
    local diff = active_diffs[file_path]
    if not diff then
        return
    end

    -- Get new content from diff buffer
    local new_lines = vim.api.nvim_buf_get_lines(diff.diff_buf, 0, -1, false)

    -- Apply to original buffer
    vim.api.nvim_buf_set_lines(diff.original_buf, 0, -1, false, new_lines)

    -- Ensure original buffer is modifiable and has correct name
    vim.api.nvim_buf_set_option(diff.original_buf, 'modifiable', true)
    local buf_name = vim.api.nvim_buf_get_name(diff.original_buf)
    if buf_name == '' or vim.fn.isdirectory(buf_name) == 1 then
        return
    end

    -- Save the file explicitly (User Requirement)
    vim.api.nvim_buf_call(diff.original_buf, function()
        vim.cmd('write')
    end)

    -- Notify server immediately (synchronous)
    -- Since we just saved, the file on disk is fresh.
    local content = table.concat(new_lines, '\n')
    local ok, err = pcall(function()
        vim.fn.rpcnotify(0, 'gemini_diff_accepted', file_path, content)
    end)
    if not ok then
        log.error('RPC notification failed: ' .. tostring(err))
    end

    -- Close diff
    M.close_diff(file_path)

    -- Show message (silent, non-blocking)
    log.info_silent('Gemini changes accepted and saved.')
end

---Reject diff changes
---@param file_path string The path to the file
function M.reject_diff(file_path)
    -- Close diff
    M.close_diff(file_path)

    -- Notify server immediately
    pcall(function()
        vim.fn.rpcnotify(0, 'gemini_diff_rejected', file_path)
    end)

    -- Show message (silent, non-blocking)
    log.info_silent('Gemini changes rejected')
end

---Get list of active diffs
---@return string[] diffs List of file paths with active diffs
function M.get_active_diffs()
    local diffs = {}
    for path, _ in pairs(active_diffs) do
        table.insert(diffs, path)
    end
    return diffs
end

return M
