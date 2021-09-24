local M = {}

-- open a new vim window in a split, with some sane defaults
function M.open(win, buf, content, config)
    local open_cmd = config.open_cmd or 'botright vnew'
    local name = config.name or nil
    local buftype = config.buftype or 'nofile'
    local filetype = config.filetype or 'txt'
    local res = config.res or nil -- to change the viewport, eg: +10 or -20

    vim.api.nvim_command(open_cmd)
    if res ~= nil then vim.api.nvim_command("res " .. res) end
    win = win or vim.api.nvim_get_current_win()
    buf = buf or vim.api.nvim_get_current_buf()
    if name ~= nil then vim.api.nvim_buf_set_name(buf, name) end
    vim.api.nvim_buf_set_option(buf, 'buftype', buftype)
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
    vim.api.nvim_buf_set_option(buf, 'filetype', filetype)
    vim.api.nvim_win_set_option(win, 'wrap', true)
    vim.api.nvim_win_set_option(win, 'cursorline', true)
    if content ~= nil then vim.api.nvim_buf_set_lines(buf, 0, -1, false, content) end

    return {win = win, buf = buf}

end

return M
