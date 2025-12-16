---@brief [[
--- Logging Module
--- Provides logging functionality with different severity levels (debug, info, warn, error).
--- Respects the configured log level.
---@brief ]]

---@module 'gemini-cli.log'
local M = {}

local levels = {
    debug = 1,
    info = 2,
    warn = 3,
    error = 4,
}

local function get_level()
    local config = require('gemini-cli').get_config()
    return levels[config.log_level] or levels.info
end

---Log a debug message
---@param msg string The message to log
function M.debug(msg)
    if get_level() <= levels.debug then
        vim.notify("Gemini [DEBUG]: " .. msg, vim.log.levels.DEBUG)
    end
end

---Log an info message
---@param msg string The message to log
function M.info(msg)
    if get_level() <= levels.info then
        vim.notify("Gemini [INFO]: " .. msg, vim.log.levels.INFO)
    end
end

---Log a warning message
---@param msg string The message to log
function M.warn(msg)
    if get_level() <= levels.warn then
        vim.notify("Gemini [WARN]: " .. msg, vim.log.levels.WARN)
    end
end

---Log an error message
---@param msg string The message to log
function M.error(msg)
    if get_level() <= levels.error then
        vim.notify("Gemini [ERROR]: " .. msg, vim.log.levels.ERROR)
    end
end

---Log a silent info message (non-blocking, goes to :messages)
---@param msg string The message to log
function M.info_silent(msg)
    if get_level() <= levels.info then
        -- Use execute with echomsg and silent: truly non-blocking, writes to :messages
        vim.fn.execute('echomsg "Gemini [INFO]: ' .. msg:gsub('"', '\\"') .. '"', 'silent')
    end
end

---Log a silent debug message (non-blocking, goes to :messages)
---@param msg string The message to log
function M.debug_silent(msg)
    if get_level() <= levels.debug then
        -- Use execute with echomsg and silent: truly non-blocking, writes to :messages
        vim.fn.execute('echomsg "Gemini [DEBUG]: ' .. msg:gsub('"', '\\"') .. '"', 'silent')
    end
end

return M
