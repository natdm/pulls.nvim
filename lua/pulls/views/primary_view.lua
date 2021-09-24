local api = vim.api
local ui_signs = require("pulls.ui.signs")
local git = require("pulls.git")

local View = {}
local commenting_ext_id_mark = 500

View.__index = View

function View:new(pr_no, config)
    local this = { --
        win = nil,
        buffers = {}, -- {[uri] = number} for saving buffers and showing in this view
        buf = nil,
        display_win = nil,
        buf_mappings = {},
        msg_win = nil,
        msg_buf = nil,
        pr_no = pr_no,
        qflists = {comments = {}},
        config = config or {}
    }
    setmetatable(this, self)
    return this
end

function View:tag_window(win)
    self.display_win = win
end

function View:remove_tag()
    self:tag_window(nil)
end

function View:save_qflist(key, entries)
    self.qflists[key] = entries
end

function View:show_qflist(key)
    local entries = self.qflists[key]
    vim.fn.setqflist(entries, "r")
    vim.cmd("copen")
end

-- returns 0 on error
function View:get_buffer(type, config)
    local repo = git.get_repo_info()
    local name = config.name or "-"
    local uri = string.format("pulls://%s/%s/%s/%s/%s", repo.owner, repo.project, self.pr_number, type, name)
    local buftype = config.buftype or 'nofile'
    local filetype = config.filetype or 'txt'
    local buf = self.buffers[uri]

    if not buf then buf = vim.api.nvim_create_buf(false, false) end
    vim.api.nvim_set_current_buf(buf)
    if buf > 0 then
        self.buffers[uri] = buf
        if name ~= nil then api.nvim_buf_set_name(buf, uri) end
        api.nvim_buf_set_option(buf, 'buftype', buftype)
        -- api.nvim_buf_set_option(buf, 'swapfile', false)
        api.nvim_buf_set_option(buf, 'filetype', filetype)
        api.nvim_buf_set_option(buf, 'hidden', true)
    end
    return buf
end

function View.create_comment_uri(path, line)
    return string.format("%s:%s", path, line)
end

function View.create_uri(repo_owner, project, pr_no, view_type, id)
    return string.format("pulls://%s/%s/%s/%s/%s", repo_owner, project, pr_no, view_type, id)
end

function View:set_view_signs(uri, signs)
    local buf = self.buffers[uri]
    if not buf then
        print("unable to find buffer for uri: " .. uri)
        return
    end
    ui_signs.add(buf, signs)
end

local function call(fn)
    return ":lua require('pulls').__internal." .. fn .. "<CR>"
end

-- set_view will (re)set (and save) a view, where it can be referenced via uri again.
function View:set_view(type, uri, content, config)
    local buf = self.buffers[uri]
    if not buf or not api.nvim_buf_is_valid(buf) then buf = vim.api.nvim_create_buf(false, true) end

    self.buffers[uri] = buf
    api.nvim_buf_set_option(buf, "modifiable", true)

    vim.api.nvim_buf_set_name(buf, uri)
    if content ~= nil then api.nvim_buf_set_lines(buf, 0, -1, false, content) end

    -- "default" settings, toggle in each if to change
    api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    api.nvim_buf_set_option(buf, 'swapfile', false)
    api.nvim_buf_set_option(buf, 'filetype', 'markdown')
    api.nvim_buf_set_option(buf, "modifiable", config.modifiable or false)

    if type == "diff" then
        api.nvim_buf_set_option(buf, 'filetype', 'diff')
    elseif type == "full_diff" then
        api.nvim_buf_set_name(buf, "Diff")
        api.nvim_buf_set_option(buf, 'filetype', 'diff')
        local m = self.config.mappings.diff
        local opt = {noremap = true}
        api.nvim_buf_set_keymap(buf, "n", m.show_comment, call("diff_show_comment()"), opt)
        api.nvim_buf_set_keymap(buf, "n", m.next_comment, call("diff_next_comment()"), opt)
        api.nvim_buf_set_keymap(buf, "n", m.next_hunk, call("diff_next()"), opt)
        api.nvim_buf_set_keymap(buf, "n", m.goto_file, call("diff_go_to_file(false)"), opt)
        api.nvim_buf_set_keymap(buf, "n", m.preview_file, call("diff_go_to_file(true)"), opt)
        api.nvim_buf_set_keymap(buf, "n", m.add_comment, call("diff_add_comment()"), opt)
    elseif type == "description" then
        api.nvim_buf_set_name(buf, "Description")
    elseif type == "comment" then
        if not config.id then
            print("Need an id in config for comment")
            return
        end
        api.nvim_buf_set_name(buf, string.format("Comment %s", tostring(config.id)))
        api.nvim_buf_set_keymap(buf, "n", "cc", call("reply_to_comment()"), {noremap = true})
    else
        print("not sure what to do with type " .. type)
    end

    return buf
end

function View:tagged_window()
    return self.display_win
end

function View:debug()
    for k, b in pairs(self.buffers) do
        print(k .. tostring(b))
        print("loaded: ", api.nvim_buf_is_loaded(b))
        print("valid: ", api.nvim_buf_is_valid(b))
    end
end

-- this expects the current buffer is the full diff, and will get the line number and check the
-- position/file, and load it.
function View:load_comment_for_full_full_diff()
end

-- Show is good for showing contents that need to exist in temporary files.
function View:show(uri, options)
    options = options or {}
    -- for _, mapping in ipairs(self.buf_mappings) do api.nvim_buf_del_keymap(self.buf, "n", mapping) end
    -- self.buf_mappings = {}
    local buf = self.buffers[uri]
    if not buf then
        print("unable to find buffer for ..", uri)
        return
    end

    local win = 0
    -- use the tagged window if it exists.
    if self.display_win ~= nil and api.nvim_win_is_valid(self.display_win) then --
        win = self.display_win
    end
    api.nvim_win_set_buf(win, buf)
end

function View:highlight_comment_line(line_no)
    -- this should get the diff from above and not rely on current buffer, but it's
    -- probably not a problem since this only gets ran on mappings that are in the diff.
    ui_signs.highlight_line(api.nvim_win_get_buf(0), line_no, {id = commenting_ext_id_mark, group = "comment_line"})
end

function View:remove_highlight_comment_line()
    ui_signs.remove_highlight({group = "comment_line"})
end

function View:health()
    print("window loaded:")
    print(api.nvim_win_is_valid(self.win))
    for n, b in pairs(self.buffers) do
        print("buffer name: " .. n)
        print(api.nvim_buf_is_loaded(b))
        print(api.nvim_buf_is_valid(b))
    end
end

function View:remove()
    api.nvim_buf_delete(self.buf)
end

function View:is_active()
    return api.nvim_get_current_buf() == self.buf
end

function View:current_line()
    if not self:is_active() then return -1 end
    return vim.fn.line(".")
end

function View:add_signs(signs)
    ui_signs.add(self.buf, signs)
end

function View:clear_signs()
    ui_signs.clear()
end

function View:input_loaded()
    return api.nvim_buf_is_loaded(self.msg_buf)
end
function View:show_input(type, content, config)
    config = config or {}
    local res = config.res or nil -- to change the viewport, eg: +10 or -20

    if self.msg_win == nil or not api.nvim_buf_is_loaded(self.msg_buf) then --
        api.nvim_command('rightbelow new')
    else
        print("msg_win is valid")
        print(self.msg_win)
    end

    api.nvim_buf_attach(self.msg_buf, true, { --
        on_detach = function(_, _)
            self:hide_input()
        end
    })
    if res ~= nil then api.nvim_command("res " .. res) end
    if self.msg_win == nil or not api.nvim_win_is_valid(self.msg_win) then --
        self.msg_win = api.nvim_get_current_win()
    end
    if self.msg_buf == nil or not api.nvim_buf_is_valid(self.msg_buf) then --
        self.msg_buf = api.nvim_get_current_buf()
    end

    api.nvim_buf_set_option(self.msg_buf, 'buftype', 'nofile')
    api.nvim_buf_set_option(self.msg_buf, 'bufhidden', 'wipe') -- clear the buffer when it vanishes
    api.nvim_buf_set_option(self.msg_buf, 'filetype', 'markdown')
    api.nvim_win_set_option(self.msg_win, 'wrap', true)
    api.nvim_win_set_option(self.msg_win, 'cursorline', true)

    local m = self.config.mappings.action
    local opt = {noremap = true}

    if type == "new_comment" then
        api.nvim_buf_set_keymap(self.msg_buf, "n", m.submit, ":lua require('pulls').__internal.submit_comment()<CR>", opt)
        api.nvim_buf_set_name(self.msg_buf, "New Comment")
    elseif type == "reply_comment" then
        api.nvim_buf_set_keymap(self.msg_buf, "n", m.submit, ":lua require('pulls').__internal.submit_reply()<CR>", opt)
        api.nvim_buf_set_name(self.msg_buf, "Reply")

    end

    if content ~= nil then api.nvim_buf_set_lines(self.msg_buf, 0, -1, false, content) end
end

function View:get_msg_lines()
    if not self:input_loaded() then
        print("message buffer is not loaded")
        return nil
    end
    return api.nvim_buf_get_lines(self.msg_buf, 0, api.nvim_buf_line_count(self.msg_buf), false)
end

function View:hide_input()
    self:remove_highlight_comment_line()
    if self:input_loaded() then api.nvim_buf_delete(self.msg_buf, {}) end
    self.msg_win = nil
    self.msg_buf = nil
end

return View
