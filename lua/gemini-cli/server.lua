---@brief [[
--- MCP Server Management Module
--- Handles starting, stopping, restarting, and checking the status of the Gemini MCP server.
---@brief ]]

---@module 'gemini-cli.server'
local M = {}
local log = require('gemini-cli.log')

local job_id = nil
local server_port = nil
local auth_token = nil
local workspace_path = nil
local rpc_socket = nil

-- Get the path to the MCP server binary
local function get_server_path()
    local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ':h:h:h')
    return plugin_dir .. '/bin/gemini-mcp-server'
end

-- Get Neovim's PID
local function get_nvim_pid()
    return vim.fn.getpid()
end

-- Get workspace paths
local function get_workspace_paths()
    local cwd = vim.fn.getcwd()
    -- TODO: Support multiple workspace roots
    return cwd
end

---Start the MCP server
function M.start()
    if job_id then
        log.warn('Gemini MCP server is already running')
        return
    end

    -- Create RPC socket for Neovim communication
    local tmpdir = vim.fn.tempname()
    rpc_socket = tmpdir .. '.sock'

    -- Start Neovim's RPC server
    local rpc_server = vim.fn.serverstart(rpc_socket)
    if rpc_server == '' then
        log.error('Failed to start Neovim RPC server')
        return
    end

    local server_path = get_server_path()
    local pid = get_nvim_pid()
    local workspace = get_workspace_paths()

    -- Check if server binary exists
    if vim.fn.executable(server_path) ~= 1 then
        log.error('Gemini MCP server binary not found at: ' .. server_path)
        log.info('Please run: cd server && go build -o ../bin/gemini-mcp-server')
        return
    end

    -- Start the MCP server process
    local cmd = {
        server_path,
        '-nvim', rpc_socket,
        '-workspace', workspace,
        '-pid', tostring(pid),
    }

    local log = require('gemini-cli.log')

    job_id = vim.fn.jobstart(cmd, {
        on_stdout = function(_, data)
            for _, line in ipairs(data) do
                if line ~= '' then
                    vim.schedule(function()
                        log.debug('Gemini MCP stdout: ' .. line)
                    end)
                end
            end
        end,
        on_stderr = function(_, data)
            for _, line in ipairs(data) do
                if line ~= '' then
                    vim.schedule(function()
                        -- Log stderr messages as debug
                        if line ~= '' then
                            log.debug('Gemini MCP stderr: ' .. line)
                        end
                    end)
                end
            end
        end,
        on_exit = function(_, exit_code)
            vim.schedule(function()
                if exit_code ~= 0 then
                    log.warn('Gemini MCP server exited with code ' .. exit_code)
                end
                job_id = nil
                server_port = nil
                auth_token = nil
                workspace_path = nil
            end)
        end,
    })

    if job_id <= 0 then
        log.error('Failed to start Gemini MCP server')
        job_id = nil
        rpc_socket = nil
    end
end

---Callback when server is ready (called via RPC from Go)
---@param port number
---@param token string
---@param workspace string
function M.on_ready(port, token, workspace)
    server_port = tonumber(port)
    auth_token = token
    workspace_path = workspace

    log.debug(string.format('Gemini MCP server ready (Port: %d, Token: %s, Workspace: %s)',
        port,
        token:sub(1, 8) .. '...',
        workspace
    ))

    -- Trigger terminal restart if it's open to pick up new port/token
    vim.schedule(function()
        local terminal = require('gemini-cli.terminal')
        if terminal.is_open() then
            log.info('Server restarted, refreshing Gemini terminal...')
            terminal.restart()
        end
    end)
end

---Stop the MCP server
function M.stop()
    if not job_id then
        return
    end

    vim.fn.jobstop(job_id)
    job_id = nil
    server_port = nil
    auth_token = nil
    workspace_path = nil

    -- Clean up RPC socket
    if rpc_socket and vim.fn.filereadable(rpc_socket) == 1 then
        vim.fn.delete(rpc_socket)
    end
    rpc_socket = nil

    log.info('Gemini MCP server stopped')
end

---Restart the MCP server
function M.restart()
    M.stop()
    vim.defer_fn(function()
        M.start()
    end, 500)
end

---Show server status
function M.status()
    if job_id then
        local pid = get_nvim_pid()
        local workspace = get_workspace_paths()

        -- Check if server is actually healthy
        local is_healthy = false
        if server_port then
            local health_url = string.format('http://127.0.0.1:%d/health', server_port)
            local result = vim.system({ 'curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', health_url }):wait()

            if result.code == 0 and result.stdout == '200' then
                is_healthy = true
            end
        end

        local status_msg = {}
        if is_healthy then
            table.insert(status_msg, 'Gemini MCP server is running and healthy')
        else
            table.insert(status_msg, 'Gemini MCP server process exists but health check failed')
        end

        table.insert(status_msg, '  PID: ' .. pid)
        if server_port then
            table.insert(status_msg, '  Port: ' .. server_port)
        end
        if auth_token then
            table.insert(status_msg, '  Token: ' .. auth_token:sub(1, 8) .. '...')
        end
        table.insert(status_msg, '  Workspace: ' .. workspace)

        -- Show discovery files
        local tmpdir = os.getenv('TMPDIR') or '/tmp'
        local discovery_dir = tmpdir .. '/gemini/ide'

        if server_port then
            -- Main discovery file
            local main_file = string.format('gemini-ide-server-%d-%d.json', pid, server_port)
            local main_path = discovery_dir .. '/' .. main_file

            table.insert(status_msg, '  Discovery files:')
            if vim.fn.filereadable(main_path) == 1 then
                table.insert(status_msg, '    [main] ' .. main_path)
            end

            -- Get parent PID for correct labeling
            local parent_pid = nil
            local stat_file = '/proc/' .. pid .. '/stat'
            if vim.fn.filereadable(stat_file) == 1 then
                local stat_content = vim.fn.readfile(stat_file)
                if #stat_content > 0 then
                    -- Parse PPID from stat file: PID (comm) state PPID ...
                    local stat_line = stat_content[1]
                    local after_comm = stat_line:match('%)%s+(.+)')
                    if after_comm then
                        local fields = {}
                        for field in after_comm:gmatch('%S+') do
                            table.insert(fields, field)
                        end
                        if #fields >= 2 then
                            parent_pid = tonumber(fields[2])
                        end
                    end
                end
            end

            -- Check for other related discovery files
            local pattern = string.format('gemini-ide-server-*-%d.json', server_port)
            local files = vim.fn.glob(discovery_dir .. '/' .. pattern, false, true)

            for _, file in ipairs(files) do
                -- Extract PID from filename
                local file_pid = file:match('gemini%-ide%-server%-(%d+)%-')
                if file_pid and tonumber(file_pid) ~= pid then
                    local label = '[child]'
                    if parent_pid and tonumber(file_pid) == parent_pid then
                        label = '[parent]'
                    end
                    table.insert(status_msg, '    ' .. label .. ' ' .. file .. ' (PID ' .. file_pid .. ')')
                end
            end
        end

        vim.notify(table.concat(status_msg, '\n'), vim.log.levels.INFO)
    else
        vim.notify('Gemini MCP server is not running', vim.log.levels.WARN)
    end
end

---Get the server port
---@return number|nil port The server port, or nil if not running
function M.get_port()
    return server_port
end

---Get auth token
---@return string|nil
function M.get_auth_token()
    return auth_token
end

---Get workspace path
---@return string|nil
function M.get_workspace_path()
    return workspace_path
end

return M
