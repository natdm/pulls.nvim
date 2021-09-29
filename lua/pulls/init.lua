local git = require("pulls.git")
local differ = require("pulls.diff")
local ui_signs = require("pulls.ui.signs")
local api = require("pulls.api")
local util = require("pulls.util")
local views = require("pulls.views.primary_view")

local M = {__internal = {}}

local config = {}

local comment_id = nil
local pull_req = nil

-- pulls_win and pulls_buf should be where *any* of the diffs or comment chains go. As well as
-- any reviews, descriptions, etc -- keep it to one window so it's easy to navigate and control.

-- message_win should actually be called text_win or something, where comments *and* replies can go.
-- NOTE: This opens above the pulls_win right now, but it should open below it.

-- TODO: Remove globals like this
local diff_files = nil

local primary_view = nil

local function save_code_comments(comments)
    local code_comments_qf = {}
    local latest_code_comments = {}

    for _, c in ipairs(comments) do
        local k = c.path .. tostring(c.line)
        local latest = latest_code_comments[k]
        if latest == nil then
            latest_code_comments[k] = c
        elseif latest.id < c.id then
            latest_code_comments[k] = c
        end
    end

    for _, c in pairs(comments) do
        table.insert(code_comments_qf, { --
            lnum = c.line,
            filename = c.path,
            text = string.format("%s: %s", c.user.login, c.body)
        })
    end

    primary_view:save_qflist("code_comments", code_comments_qf)
end

local function save_issue_views(issues)
    local qflist = {}
    for _, issue in ipairs(issues) do
        local body = util.split_newlines(issue.body)
        local uri = views.create_uri(pull_req.number, "issue", tostring(issue.id))
        local buf = primary_view:set_view("issue", uri, body, {id = issue.id})
        table.insert(qflist, {bufnr = buf, lnum = 1, text = string.format("%s: %s", issue.user.login, body[1])})
    end
    primary_view:save_qflist("issues", qflist)
end

local function create_review_view(review)
    local lines = {}

    table.insert(lines, string.format("## %s left a review:", review.user.login))
    if review.body ~= "" then
        table.insert(lines, string.format("*Commented on %s*", review.submitted_at)) -- TODO: Add edited flag (created_at < updated_at)
        for _, b in ipairs(util.split_newlines(review.body)) do table.insert(lines, string.format("> %s<br>", b)) end
    end

    for _, c in pairs(review.comments) do --
        table.insert(lines, "")
        table.insert(lines, string.format("### %s", c.path))
        table.insert(lines, "```diff")
        for _, d in ipairs(util.split_newlines(c.diff_hunk)) do table.insert(lines, d) end
        table.insert(lines, "```")
        table.insert(lines, "")
        table.insert(lines, string.format("> _*%s* at %s_:<br>", c.user.login, c.created_at))
        for _, l in ipairs(util.split_newlines(c.body)) do table.insert(lines, string.format("> %s<br>", l)) end
        if c.replies then
            table.insert(lines, "")
            for _, r in ipairs(c.replies) do
                table.insert(lines, string.format("> %s at %s:<br>", r.user.login, r.created_at))
                for _, b in ipairs(util.split_newlines(r.body)) do table.insert(lines, string.format("> %s<br>", b)) end
                table.insert(lines, "")
            end
        end
        table.insert(lines, "")
    end
    return lines
end

local review_file_pos = {}

local function save_review_views(reviews, comments)
    local review_indexes = {} -- review id to index
    for i, r in ipairs(reviews) do
        review_indexes[tostring(r.id)] = i
        r.comments = {}
    end

    -- reviews could have comments, or not have comments. The comments that they may
    -- have might show an `in_reply_to_id`, indicating the comment chain they are on.
    --
    -- Reviews won't have diffs, but the comments are guaranteed to have diffs.
    --
    -- Build a table with..
    -- {review..., comments: {[id]: {..., replies: {{...}}}}}

    -- first loop to get all the comments that don't have an in_reply_to_id field and store
    -- them in the review.

    -- apparently the pull_request_review_id in replies is not correct? So we need to save the
    -- comment id and point it to the review index so we know which one to grab.
    local comment_id_to_review_index = {}

    for _, c in ipairs(comments) do
        if not c.in_reply_to_id then
            reviews[review_indexes[tostring(c.pull_request_review_id)]].comments[tostring(c.id)] = c
            comment_id_to_review_index[tostring(c.id)] = review_indexes[tostring(c.pull_request_review_id)]
        end
    end

    for _, c in ipairs(comments) do
        if c.in_reply_to_id then
            local idx = comment_id_to_review_index[tostring(c.in_reply_to_id)]
            local thread = reviews[idx].comments[tostring(c.in_reply_to_id)]
            if not thread.replies then
                thread.replies = {c}
            else
                table.insert(thread.replies, c)
            end
        end
    end

    local reviews_qf = {}

    for _, r in ipairs(reviews) do
        local tableempty = true
        for _ in pairs(r.comments) do tableempty = false end
        if r.body == "" and tableempty then goto continue end

        -- set the global review location for go-to-file capability.
        for _, c in pairs(r.comments) do review_file_pos[r.id] = {path = c.path, line = c.line} end

        local lines = create_review_view(r)
        local uri = primary_view.create_uri(pull_req.number, "review", tostring(r.id))
        local buf = primary_view:set_view("review", uri, lines, {})
        local preview = ""
        if r.body ~= "" then
            preview = string.format("%s: [%s] %s", r.user.login, r.state, util.split_newlines(r.body)[1])
        else
            for _, c in pairs(r.comments) do
                -- save the comment to review relation since the API is incorrect.
                preview = string.format("%s: [%s] %s", r.user.login, r.state, util.split_newlines(c.body)[1])
            end
        end
        table.insert(reviews_qf, {bufnr = buf, lnum = 1, text = preview})
        ::continue::
    end

    primary_view:save_qflist("reviews", reviews_qf)
end

local function save_desc_view(_pull_req)
    local desc = util.split_newlines(_pull_req.body)
    local uri = views.create_uri(pull_req.number, "description", "desc")
    primary_view:set_view("description", uri, desc, {})
end

-- line number of each chunk in the diff, along with their corresponding file path
-- {{line = n, path = p}, {..}, ..}
local diff_chunk_start_lines = {}

local comment_id_pos = {}

local review_id_diff_pos = {} -- review id to file diff pos

local function save_diff_view(diff_lines, comments)
    -- TODO: save comment review ID's to actual review ID's and their pos on the diff.
    local uri = views.create_uri(pull_req.number, "diff", "full")
    primary_view:set_view("full_diff", uri, diff_lines, {})

    -- get file positions in diff for the relative positions of the comments
    local file_idx = {}
    local new_file_ct = 0
    for k, v in pairs(diff_lines) do
        if vim.startswith(v, "diff --git") then
            -- left and right side files in diff --git
            local _, b = differ.parse_diff_command(v)
            file_idx[b] = k + 3 + new_file_ct -- 4 is the space between the comand and the diff hunk
        elseif vim.startswith(v, "new file") then
            new_file_ct = new_file_ct + 1
        end
    end

    local comment_counts = {}
    for _, c in ipairs(comments) do
        local record = {}
        if c.position == vim.NIL then
            record = {line = file_idx[c.path] + c.original_position, action = "comment_outdated", count = 1}
        else
            record = {line = file_idx[c.path] + c.position, action = "comment", count = 1}
        end

        if c.in_reply_to_id ~= nil then
            local cc = comment_counts[c.in_reply_to_id]
            if cc == nil then
                comment_counts[c.in_reply_to_id] = record
                comment_id_pos[c.in_reply_to_id] = record.line
            else
                cc.count = cc.count + 1
            end
        else
            local cc = comment_counts[c.id]
            if cc == nil then
                comment_counts[c.id] = record
                comment_id_pos[c.id] = record.line
                review_id_diff_pos[record.line] = c.pull_request_review_id
            else
                cc.count = cc.count + 1
            end
        end
    end

    local signs = {}
    for _, v in pairs(comment_counts) do table.insert(signs, v) end
    primary_view:set_view_signs(uri, signs)
end

local diff_lines = nil

local function load_pull_request(refreshing)
    if not refreshing then print("Loading pull request...") end
    local pulls = api.pulls()
    if #pulls == 0 then
        print("No pull request found")
        return
    end

    pull_req = pulls[1]
    if not primary_view then primary_view = views:new(pull_req.number, config) end

    local diff = api.diff(pull_req.number)
    if diff.error then
        print("unable to load full diff: " .. diff.error)
        return
    end

    diff_lines = util.split_newlines(diff.data)

    local comments = api.comments(pull_req.number)

    local pull_req_files = api.files_for_pull(pull_req.number)
    if pull_req_files ~= nil then diff_files = differ.diff(pull_req_files.data) end
    save_desc_view(pull_req)
    save_review_views(comments.reviews, comments.comments)
    save_diff_view(diff_lines, comments.comments)
    save_code_comments(comments.comments)
    save_issue_views(comments.issues)
    save_review_views(comments.reviews, comments.comments)
    -- save_comment_chains(comments.data)
    -- save_reviews(pull_req.number)
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

function M.issues()
    if not has_pr() then
        print("No PR")
        return
    end
    primary_view:show_qflist("issues")
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

function M.reviews()
    if not has_pr() then
        print("No PR")
        return
    end
    primary_view:show_qflist("reviews")
end

function M.code_comments()
    if not has_pr() then
        print("No PR")
        return
    end
    primary_view:show_qflist("code_comments")
end

function M.diff()
    if not has_pr() then
        print("No PR")
        return
    end
    local uri = views.create_uri(pull_req.number, "diff", "full")
    primary_view:show(uri, {})
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
    local review_id = review_id_diff_pos[line]
    local uri = primary_view.create_uri(pull_req.number, "review", tostring(review_id))
    primary_view:show(uri)
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

    local response = api.reply(pull_req.number, comment_id, comment)
    if response.success ~= true then
        print(response.error)
    else
        print("Responded")
    end
    primary_view:hide_input()
    load_pull_request(true)
end

-- go to the next line that has a comment in the full diff Use the stringified lines in the comment_id_pos to get the next largest one.
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

    for _, l in pairs(comment_id_pos) do --
        local ll = l
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

    -- If the line starts with index, diff, new file @@@, --- /, +++ /, print an error. KISS for now.
    -- Crawl upwards until the header is found (@@) and grab the + position. Then crawl up until a
    -- `diff` is found and grab the b file, and go to b file at line `+` plus the amount tha we crawled up.

    for _, s in ipairs {"--- /", "+++ /", "@@", "new file", "diff", "index"} do
        if vim.startswith(diff_lines[line], s) then
            print("unable to navigate to file on that portion of the diff")
            return
        end
    end

    local ct = 0
    local file_line_ct = 0
    local file = nil
    local file_pos = nil

    while file == nil do
        local l = diff_lines[line - file_line_ct]

        if vim.startswith(l, "@@") and file_pos == nil then
            -- we found the header. Grab the addition line, and save it as the file_pos.
            local addition_line = string.match(l, "@@ %-.+ %+(.+),.+ @@")
            if addition_line == nil then
                print("unable to parse header " .. l)
                return
            end

            file_pos = tonumber(addition_line) + ct
        elseif vim.startswith(l, "diff") then
            file = string.match(l, "diff %-%-git a/.+ b/(.+)")
            if file == nil then
                print("unable to parse file " .. l)
                return
            end

        elseif ct == line then
            -- somehow we crawled all the way up
            print("oh no")
            print(vim.inspect({file = file, file_pos = file_pos, ct = ct}))
            return
        end

        if not vim.startswith(l, "-") then ct = ct + 1 end
        file_line_ct = file_line_ct + 1
    end

    local current_win = vim.api.nvim_get_current_win()

    if do_preview then
        local w = primary_view:tagged_window()
        if w then vim.api.nvim_set_current_win(w) end
    end

    vim.api.nvim_command(":e " .. file)
    vim.api.nvim_win_set_cursor(0, {file_pos - 1, 0})

    if do_preview then vim.api.nvim_set_current_win(current_win) end

    --     -- use the line to grab the review_id_diff_pos then use that review id to grab the review_file_pos
    --     -- All this was to only go to reviews.. that makes no sense, go to all files in the diff.
    --     local review_id = review_id_diff_pos[line]
    --     if review_id == nil then
    --         print("no review id for line " .. line)
    --         return
    --     end

    --     local found = review_file_pos[review_id]
    --     if found == nil then
    --         print("no file id for review " .. review_id)
    --         return
    --     end

    --     local current_win = vim.api.nvim_get_current_win()
    --     if do_preview then
    --         local w = primary_view:tagged_window()
    --         if w then vim.api.nvim_set_current_win(w) end
    --     end

    --     vim.api.nvim_command(":e " .. found.path)
    --     vim.api.nvim_win_set_cursor(0, {found.line, 0})

    --     if do_preview then vim.api.nvim_set_current_win(current_win) end
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
