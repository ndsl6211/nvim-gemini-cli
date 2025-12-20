---Terminal module for Gemini CLI integration
---@module 'gemini-cli.terminal'

local M = {}

local log = require('gemini-cli.log')

-- Terminal state
local bufnr = nil
local winid = nil
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

---Show terminal window
---@param focus boolean Whether to focus the terminal
local function show_terminal(focus)
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

    -- Create new window for existing buffer
    local original_win = vim.api.nvim_get_current_win()
    local width = math.floor(vim.o.columns * 0.3) -- 30% width

    vim.cmd('botright ' .. width .. 'vsplit')
    local new_winid = vim.api.nvim_get_current_win()

    -- Set the existing buffer in the new window
    vim.api.nvim_win_set_buf(new_winid, bufnr)
    winid = new_winid

    if focus then
        vim.cmd('startinsert')
    else
        vim.api.nvim_set_current_win(original_win)
    end

    return true
end

---Hide terminal window (keep process running)
local function hide_terminal()
    if winid and vim.api.nvim_win_is_valid(winid) then
        vim.api.nvim_win_close(winid, false)
        winid = nil
        log.debug('Terminal window hidden, process preserved')
    end
end

---Create new terminal
---@param focus boolean Whether to focus the terminal
local function create_terminal(focus)
    -- Save original window
    local original_win = vim.api.nvim_get_current_win()

    -- Get working directory
    local cwd = vim.fn.getcwd()

    -- Get server port for discovery
    local server = require('gemini-cli.server')
    local port = server.get_port()

    -- If port is not available yet, wait for it
    if not port then
        log.warn('MCP server port not ready, waiting...')
        vim.notify('Waiting for MCP server to start...', vim.log.levels.INFO)

        -- Wait up to 5 seconds for port to be available
        local max_attempts = 10
        local attempt = 0
        while not port and attempt < max_attempts do
            vim.wait(500) -- Wait 500ms
            port = server.get_port()
            attempt = attempt + 1
        end

        if not port then
            vim.notify('MCP server not ready. Try `:GeminiRestart` first.', vim.log.levels.WARN)
            return false
        end
    end

    -- Setup environment variables for gemini to find the MCP server
    local env = {
        GEMINI_CLI_IDE_SERVER_PORT = tostring(port),
        GEMINI_CLI_IDE_AUTH_TOKEN = server.get_auth_token(),
        GEMINI_CLI_IDE_WORKSPACE_PATH = server.get_workspace_path(),
    }

    log.info_silent(string.format('Starting gemini with:\n  Port: %s\n  Token: %s\n  Workspace: %s',
        tostring(port),
        env.GEMINI_CLI_IDE_AUTH_TOKEN and env.GEMINI_CLI_IDE_AUTH_TOKEN:sub(1, 8) .. '...' or 'nil',
        env.GEMINI_CLI_IDE_WORKSPACE_PATH or 'nil'
    ))
    log.debug('Working directory: ' .. cwd)

    -- Calculate width (30% of screen)
    local width = math.floor(vim.o.columns * 0.3)

    -- Go to the rightmost window first
    vim.cmd('wincmd l')
    -- Keep going right until we can't go further
    local last_win = vim.api.nvim_get_current_win()
    while true do
        vim.cmd('wincmd l')
        local current_win = vim.api.nvim_get_current_win()
        if current_win == last_win then
            -- We've reached the rightmost window
            break
        end
        last_win = current_win
    end



    -- Now create a vertical split on the right
    vim.cmd('rightbelow ' .. width .. 'vsplit')
    local new_winid = vim.api.nvim_get_current_win()

    -- Create a new buffer in this window
    local new_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(new_winid, new_buf)

    -- Start terminal with gemini
    jobid = vim.fn.termopen({ 'zsh', '-c', 'gemini; exit $?' }, {
        cwd = cwd,
        env = env,
        on_exit = function(job_id, exit_code, _)
            vim.schedule(function()
                if job_id == jobid then
                    log.debug('Gemini exited with code ' .. exit_code)
                    -- Clean up state
                    local term_bufnr = bufnr
                    local term_winid = winid
                    bufnr = nil
                    winid = nil
                    jobid = nil

                    -- Close window if still valid
                    if term_winid and vim.api.nvim_win_is_valid(term_winid) then
                        vim.api.nvim_win_close(term_winid, true)
                    end
                end
            end)
        end,
    })

    if not jobid or jobid == 0 then
        vim.notify('Failed to start Gemini', vim.log.levels.ERROR)
        vim.api.nvim_win_close(new_winid, true)
        -- Return to original window
        if vim.api.nvim_win_is_valid(original_win) then
            vim.api.nvim_set_current_win(original_win)
        end
        return false
    end

    -- Save state
    winid = new_winid
    bufnr = new_buf
    vim.bo[bufnr].bufhidden = 'hide'

    -- Setup autocmd to automatically enter insert mode when entering terminal buffer
    vim.api.nvim_create_autocmd('BufEnter', {
        buffer = bufnr,
        callback = function()
            -- Only auto-insert if the buffer is still a terminal
            if vim.bo[bufnr].buftype == 'terminal' then
                vim.cmd('startinsert')
            end
        end,
        desc = 'Auto-enter insert mode in Gemini terminal'
    })

    -- Always focus to the new terminal (this is what user wants)
    vim.api.nvim_set_current_win(winid)
    vim.cmd('startinsert')

    -- First-time help is now shown silently in logs
    if not help_shown then
        vim.defer_fn(function()
            log.info_silent('Gemini started. Tip: Run "/ide enable" in Gemini to auto-connect on startup.')
            help_shown = true
        end, 1000)
    end

    return true
end

---Toggle terminal visibility
function M.toggle()
    if is_visible() then
        -- Terminal is visible, hide it
        hide_terminal()
    elseif is_valid() then
        -- Terminal exists but hidden, show it
        show_terminal(true)
    else
        -- No terminal exists, create it
        create_terminal(true)
    end
end

---Open terminal (create or show)
function M.open()
    if not is_valid() then
        create_terminal(true)
    else
        show_terminal(true)
    end
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
