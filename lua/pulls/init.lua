local git = require("pulls.git")
local differ = require("pulls.diff")
local ui_signs = require("pulls.ui.signs")
local api = require("pulls.api")
local util = require("pulls.util")
local views = require("pulls.views.primary_view")

local M = {__internal = {}}

local config = {}

local comments = {}
local comment_id = nil
local pull_req = nil
local pull_req_files = nil -- just the api response, no real parsing

-- pulls_win and pulls_buf should be where *any* of the diffs or comment chains go. As well as
-- any reviews, descriptions, etc -- keep it to one window so it's easy to navigate and control.

-- message_win should actually be called text_win or something, where comments *and* replies can go.
-- NOTE: This opens above the pulls_win right now, but it should open below it.

-- TODO: Remove globals like this
local diff_files = nil

local primary_view = nil

-- full diff line number to comment uri for comment chain
local diff_comment_refs = {}

local comment_buffer_id_to_comment_id = {}

local function save_comment_chains(_comments)
    -- save all comment chains in buffers, and then preload a qflist with the buffers
    local comment_buffer_qf = {}
    local comment_line_ref_qf = {}
    for fpath, c in pairs(_comments) do -- file level
        for line, chain in pairs(c) do -- line level (chain)
            local list = {}
            table.insert(list, #list + 1, "```diff")
            for s in chain[1].diff_hunk:gmatch("[^\r\n]+") do table.insert(list, s) end
            table.insert(list, #list + 1, "```")
            -- TODO: Use nvim_win_get_width here, and repeat '-'
            table.insert(list, #list + 1, "________________________________________________")
            -- line number to comment, ignoring line no since we are loading a qflist that goes
            -- to a comment chain.
            for _, cc in ipairs(chain) do
                table.insert(list, #list + 1, "From: " .. cc.user)
                table.insert(list, #list + 1, "Date: " .. cc.created_at)
                table.insert(list, #list + 1, "----------------------------")
                for s in cc.body:gmatch("[^\r\n]+") do table.insert(list, s) end
                table.insert(list, #list + 1, "")
                table.insert(list, #list + 1, "________________________________________________")
            end
            local uri = views.create_comment_uri(fpath, line)
            local buf = primary_view:set_view("comment", uri, list, {id = chain[1].id})
            if not buf then
                print("unable to save comment view")
                return
            end
            -- set this for easier replies later
            comment_buffer_id_to_comment_id[buf] = chain[1].id
            table.insert(comment_buffer_qf, {bufnr = buf, lnum = 0, text = chain[#chain].preview})
            local cline = chain[1].line
            local flag = ""
            if not cline then
                flag = "[outdated] "
                cline = chain[1].original_line
            end
            table.insert(comment_line_ref_qf, {filename = fpath, lnum = cline, text = flag .. chain[#chain].preview})
        end
    end
    primary_view:save_qflist("comment_chains", comment_buffer_qf)
    primary_view:save_qflist("comments", comment_line_ref_qf)
end

local function save_desc_view(_pull_req)
    local desc = util.split_newlines(_pull_req.body)
    local uri = views.create_uri(pull_req.number, "description", "desc")
    primary_view:set_view("description", uri, desc, {})
end

-- line number of each chunk in the diff, along with their corresponding file path
-- {{line = n, path = p}, {..}, ..}
local diff_chunk_start_lines = {}

local function save_full_diff_view(pr_no, _comments)
    local diff = api.diff(pr_no)
    if diff.error then
        print("unable to load full diff: " .. diff.data)
        return
    end

    local diff_comment_signs = {}

    local diff_lines = util.split_newlines(diff.data)
    for i, line in ipairs(diff_lines) do --
        local add_start = nil
        if vim.startswith(line, "diff") then --
            local _, _, _, _, add_start_s, add_ct_s = string.find(diff_lines[i + 4], "@@ %-(%d+),(%d+) %+(%d+),(%d+) @@")
            add_start = tonumber(add_start_s)
            local path = line:match(".*%sb/(.*)") -- match the diff --git a/.. b/(..)
            local pcomments = _comments[path]
            -- pcomments are per line, but we will need position. Iterate all of them,
            -- ignoring the line, and using the position.
            -- the math should always be the comment position + the line (i) where the
            -- header is plus 4, due to the diff file format
            if pcomments then
                for _, c in pairs(pcomments) do --
                    local pos = c[1].position
                    -- position is nil if comment is old
                    if pos ~= vim.NIL and pos ~= nil then
                        pos = pos + i + 4
                        -- save a reference to the line number in the diff to the uri
                        -- of the comment for keymappings.
                        local comment_uri = views.create_comment_uri(c[1].path, tostring(c[1].original_line))
                        diff_comment_refs[tostring(pos)] = comment_uri
                        table.insert(diff_comment_signs, {action = "comment", line = pos, count = #c})
                    end
                end
            end
            -- BUG: This isn't very exact as to where it goes. Ideally, it'd go to the file, at the place where you have yoour cursor.
            table.insert(diff_chunk_start_lines, { --
                diff_line = i,
                path = path,
                file_line = add_start
            })

        end
    end

    local uri = views.create_uri(pull_req.number, "diff", "full")
    primary_view:set_view("full_diff", uri, diff_lines, {})
    primary_view:set_view_signs(uri, diff_comment_signs)
end

local function save_reviews(pull_req_no)
    local reviews = api.get_all_review_comments(pull_req_no)
    if not reviews.success then
        print("unable to get reviews: " .. reviews.error)
        return
    end
    print(vim.inspect(reviews.data))

    -- NOTE:
    -- Reviews some times have a `body` field, but some times do not. Do they have diffs?
    -- They should always have relating `/comments`, which will have diffs and bodies.
    -- How do we want to show these in an intuitie way?
end

local function load_pull_request(refreshing)
    if not refreshing then print("Loading pull request...") end
    local pulls = api.pulls()
    if #pulls == 0 then
        print("No pull request found")
        return
    end
    pull_req = pulls[1]

    if not primary_view then primary_view = views:new(pull_req.number, config) end
    comments = api.comments_for_pull(pull_req.number)
    pull_req_files = api.files_for_pull(pull_req.number)
    if pull_req_files ~= nil then diff_files = differ.diff(pull_req_files.data) end
    save_desc_view(pull_req)
    save_full_diff_view(pull_req.number, comments.data)
    save_comment_chains(comments.data)
    save_reviews(pull_req.number)
    if not refreshing then print("Done!") end
end

local function has_pr()
    if not pull_req then load_pull_request() end
    return pull_req ~= nil
end

function M.description()
    if not has_pr() then
        print("No PR")
        return
    end
    local uri = views.create_uri(pull_req.number, "description", "desc")
    primary_view:show(uri, {split = true})
end

function M.tag_window()
    -- tag a window and use it for any displays.
    local win = vim.fn.win_getid()
    primary_view:tag_window(win)
end

function M.untag_window()
    primary_view:remove_tag()
end

function M.setup(cfg)
    config = cfg or require("pulls.config")
end
function M.refresh()
    load_pull_request()
end

function M.comments()
    if not has_pr() then
        print("No PR")
        return
    end
    primary_view:show_qflist("comments")
end

function M.get_comment_chains()
    if not has_pr() then
        print("No PR")
        return
    end
    primary_view:show_qflist("comment_chains")
end

function M.diff()
    if not has_pr() then
        print("No PR")
        return
    end
    local uri = views.create_uri(pull_req.number, "diff", "full")
    primary_view:show(uri, {split = true})
end

function M.list_changes()
    if not has_pr() then
        print("No PR")
        return
    end

    -- for each file in diff_files, we want the first changes_by_line.line, and the diff, as well as the short_sha.

    local entries = {}
    for fname, changes in pairs(diff_files) do
        for _, c in ipairs(changes.chunks) do
            local row = {
                filename = fname,
                lnum = c.changes_by_line[1].line,
                col = 0,
                text = c.short_sha .. " | " .. c.diff_desc
                --
            }
            table.insert(entries, row)
        end
    end

    vim.fn.setqflist(entries, "r")
    vim.cmd("copen")
end

function M.highlight_changes()
    if not has_pr() then
        print("No PR")
        return
    end

    -- this diffs all files
    local file = util.file_info()
    local diff = nil
    for f, d in pairs(diff_files) do if string.find(file.file, f) then diff = d end end

    if diff == nil then
        print("diff not found for file")
        return
    end

    for _, f in ipairs(diff.chunks) do ui_signs.add(file.bufnr, f.changes_by_line) end
end

-- ugly state for submitting a comment. Use this as state to keep track of where the
-- comment is being added to.
-- { path, position }
local comment_details = nil

function M.__internal.diff_add_comment()
    if not has_pr() then
        print("No PR")
        return
    end
    -- NOTE: Comment can only be made on diffs (everything after the header), not on any line.
    -- For now, require that the user be in the diff buffer.
    -- Requirements for being allowed to comment:
    --   - be in the diff (current buf == pulls_buf)
    --   - buffer variable 'content' == 'diff'
    --   - cursor be on code, not on header (@@ .. @@)

    local name = vim.api.nvim_buf_get_name(0)
    if not vim.endswith(name, "Diff") then
        print("not on full diff")
        return
    end

    -- from github api:
    -- Note: The position value equals the number of lines down from the first "@@"
    -- hunk header in the file you want to add a comment. The line just below the
    -- "@@" line is position 1, the next line is position 2, and so on. The position
    -- in the diff continues to increase through lines of whitespace and additional
    -- hunks until the beginning of a new file.

    local cursor_pos = vim.fn.line(".")
    -- sub one since the api requires the position to be below the header.
    if cursor_pos == -1 then
        print("unable to put comment on header")
        return
    end

    local header = {diff_line = 0}
    for _, diff in ipairs(diff_chunk_start_lines) do --
        if diff.diff_line < cursor_pos and --
        diff.diff_line > header.diff_line then --
            header = diff
        end
    end

    if header.diff_line == 0 then
        print("Unable to place comment")
        return
    end

    -- sub 4 since what's being tracked in the diff_line is the diff command, which sits
    -- four lines above the start of the diff
    comment_details = {path = header.path, position = cursor_pos - header.diff_line - 4}

    -- Check if this line already has a comment on it -- only have to check
    -- current comments in the diff.
    local existing_comment = diff_comment_refs[tostring(cursor_pos)]
    if existing_comment then
        -- existing comment, go to chain
        -- Use PullsDiffShowComment since it sets up some environmentals
        M.__internal.diff_show_comment()
        -- primary_view:show(existing_comment)
    else
        -- new comment, opening input window.
        primary_view:remove_highlight_comment_line() -- clear any highlights that might be hanging around
        primary_view:highlight_comment_line(cursor_pos)
        primary_view:show_input("new_comment")
    end
end

function M.__internal.submit_comment()
    local lines = primary_view:get_msg_lines()
    if lines == nil then
        primary_view:remove_highlight_comment_line()
        return
    end
    local resp = api.new_comment(pull_req.number, comment_details.path, comment_details.position, git.sha(), lines)
    primary_view:hide_input()
    primary_view:remove_highlight_comment_line()
    if not resp.success then print("unable to post comment: " .. (resp.error or "<nil>")) end
    load_pull_request(true)
end

function M.__internal.diff_next()
    if not has_pr() then
        print("No PR")
        return
    end

    local file = util.file_info()

    local diff = nil
    for f, d in pairs(diff_files) do if string.find(file.file, f) then diff = d end end

    if diff == nil then
        print("diff not found for file")
        return
    end

    local found = false
    -- Get the next diff after the current line. If there is none, go to the first.
    for _, f in ipairs(diff.chunks) do --
        if f.add_start > file.line then
            -- go to this line, the start of the diff is after the cursor.
            vim.api.nvim_win_set_cursor(0, {f.changes_by_line[1].line, 0})
            found = true
            break
        end
    end

    -- go to first one
    if not found then
        vim.api.nvim_win_set_cursor(0, { --
            diff.chunks[1].changes_by_line[1].line, 0
        })
    end
end

function _G.PullsInfo()
    if not has_pr() then
        print("No PR")
        return
    end
    print(vim.inspect(git.get_repo_info()))
    primary_view:debug()
end

function M.__internal.diff_show_comment()
    if not has_pr() then
        print("No PR")
        return
    end
    local name = vim.api.nvim_buf_get_name(0)
    if not vim.endswith(name, "Diff") then
        print("not on full diff")
        return
    end

    local line = vim.fn.line(".")
    local uri = diff_comment_refs[tostring(line)]
    if not uri then
        print("no comment for diff at line " .. tostring(line))
        return
    end

    -- set the global comment_id so other comment functions can use it
    primary_view:show(uri)
    comment_id = comment_buffer_id_to_comment_id[vim.fn.bufnr("%")]
end

local function create_resp_body(rows)
    local resp = {}
    for _, l in ipairs(rows) do table.insert(resp, l) end
    return resp
end

-- ReplyToComment will open the message box for a chain
function M.__internal.reply_to_comment()
    if not has_pr() then
        print("No PR")
        return
    end
    primary_view:show_input("reply_comment")
end

function M.__internal.submit_reply()
    if not has_pr() then
        print("No PR")
        return
    end

    if not comment_id then
        print("no comment id set")
        return
    end
    -- optimiztions: this will submit empty and useless comments. Either here or at the
    -- api layer, filter out responses that are empty or only have line-breaks.
    local content = primary_view:get_msg_lines()
    if content == nil then return end

    local comment = create_resp_body(content)

    comment = table.concat(comment, '\r\n')
    -- comment = vim.fn.escape(comment, [["\]]) -- does this even do anything
    local response = api.reply(pull_req.number, comment_id, comment)
    if response.success ~= true then
        print(response.error)
    else
        print("Responded")
    end
    primary_view:hide_input()
    load_pull_request(true)
end

-- go to the next line that has a comment in the full diff Use the stringified lines in diff_comment_refs to get the next largest one.
function M.__internal.diff_next_comment()
    if not has_pr() then
        print("No PR")
        return
    end
    local name = vim.api.nvim_buf_get_name(0)
    if not vim.endswith(name, "Diff") then
        print("not on full diff")
        return
    end

    -- BUG: Make this loop, currently when it's out of comments, it goes to the last line in the file.
    local line = vim.fn.line(".")
    local next_comment_line = vim.fn.line("$") -- start at end of doc and go back

    for l in pairs(diff_comment_refs) do --
        local ll = tonumber(l)
        if ll > line and ll < next_comment_line then next_comment_line = ll end
    end
    vim.api.nvim_win_set_cursor(0, {next_comment_line, 0})
end

-- if do_preview is true, the cursor will hop back to the original window after opening.
function M.__internal.diff_go_to_file(do_preview)
    if not has_pr() then
        print("No PR")
        return
    end
    local name = vim.api.nvim_buf_get_name(0)
    if not vim.endswith(name, "Diff") then
        print("not on full diff")
        return
    end
    local line = vim.fn.line(".")
    local found = nil
    for _, f in ipairs(diff_chunk_start_lines) do
        if f.diff_line <= line then --
            if not found then
                found = f
            elseif found.diff_line < f.diff_line then
                found = f
            end
        end
    end
    if not found then
        print("unable to find file")
        return
    end

    local current_win = vim.api.nvim_get_current_win()
    if do_preview then
        local w = primary_view:tagged_window()
        if w then vim.api.nvim_set_current_win(w) end
    end

    vim.api.nvim_command(":e " .. found.path)
    vim.api.nvim_win_set_cursor(0, {found.file_line, 0})

    if do_preview then vim.api.nvim_set_current_win(current_win) end
end

function M.__internal.description_edit()
    -- for editing, change the view window to an edit window, then pop back one done (and refresh)
    if not has_pr() then
        print("No PR")
        return
    end

    local name = vim.api.nvim_buf_get_name(0)
    if not vim.endswith(name, "Description") then
        print("not on description")
        return
    end
    if not primary_view:edit_main_content("edit_desc") then print("unable to edit main content") end
end

function M.__internal.submit_description_edit()
    -- TODO: This is identical to suvmitting comments, DRY.
    if not has_pr() then
        print("No PR")
        return
    end

    -- optimiztions: this will submit empty and useless comments. Either here or at the
    -- api layer, filter out responses that are empty or only have line-breaks.
    local content = primary_view:get_msg_lines()
    if content == nil then return end

    local body = create_resp_body(content)
    body = table.concat(body, '\r\n')

    local response = api.description_edit(pull_req.number, body)
    if response.success ~= true then
        print(response.error)
    else
        print("Updated")
    end
    primary_view:hide_input()
    load_pull_request(true)
end

return M
