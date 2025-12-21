-- Neovim plugin entry point
-- This file is automatically loaded by Neovim

-- Only load once
if vim.g.loaded_gemini_cli then
  return
end
vim.g.loaded_gemini_cli = 1

-- Ensure Neovim version >= 0.9.0
if vim.fn.has('nvim-0.9.0') ~= 1 then
  vim.api.nvim_err_writeln('nvim-gemini-cli requires Neovim >= 0.9.0')
  return
end

-- Auto-setup only if user hasn't called setup() manually
vim.defer_fn(function()
  if not vim.g.gemini_cli_setup_called then
    require('gemini-cli').setup()
  end
end, 0)
