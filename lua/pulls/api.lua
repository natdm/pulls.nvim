local util = require('pulls.util')
local github = require("pulls.github.api")

local M = {}

function M.pulls()
    return github.get_pull_requests()
end
function M.get_reviews(pr_no)
    return github.get_reviews(pr_no)
end
function M.get_review_comments(pr_no, review_id)
    return github.get_review_comments(pr_no, review_id)
end

function M.new_comment(pull_req_no, path, position, commit_id, body)
    return github.post_comment(pull_req_no, commit_id, path, position, body)
end

-- full diff for PR
function M.diff(pull_req_no)
    return github.get_pull_request_diff(pull_req_no)
end

function M.reply(pull_req_no, comment_id, body)
    return github.post_comment_reply(pull_req_no, comment_id, body)
end

--- format the body of a comment in to something that can be previewed
local function comment_preview(body)
    -- local max_preview_len = 50
    -- local formatted = string.sub(body, 0, max_preview_len)
    -- cut off any text within a tick (like ```suggestion...```)
    local formatted = util.split(body, '\r\n')[1]
    -- formatted = util.split(formatted, '`')[1]
    -- TODO: Make these previewable.
    if formatted == nil or formatted == "" then formatted = "No preview available yet.." end
    return formatted
end

-- { [file_path] = { [line] = {{ from = <name>, preview = <...> comment = <..> }}}}
-- load comments as a table of tables, {[orig_line] = {reply, reply, comment}, ...}.
-- All chains are loaded in reverse order, so the latest one is the head.
function M.comments_for_pull(pull_req_no, opts)
    local default_comments_for_pull_opts = {sorted = true, hide_no_line_counts = true}
    opts = opts or {}
    opts = util.merge_tables(default_comments_for_pull_opts, opts)

    local resp = github.get_comments(pull_req_no)
    if not resp.success then return resp end
    local comments = resp.data

    local entries = {}
    for _, comment in ipairs(comments) do
        if entries[comment.path] == nil then entries[comment.path] = {} end
        local ol = tostring(comment.original_line)
        if entries[comment.path][ol] == nil then entries[comment.path][ol] = {} end

        -- NOTE: The pull request number isn't in the payloads here, it needs to be saved
        -- to a variable in init.
        local position = comment.position
        if position == vim.NIL then position = nil end
        local line = comment.line
        if line == vim.NIL then line = nil end

        local formatted_comment = {
            user = comment.user.login,
            line = line,
            original_line = comment.original_line,
            path = comment.path,
            diff_hunk = comment.diff_hunk,
            created_at = comment.created_at,
            body = comment.body,
            preview = comment_preview(comment.body),
            id = comment.id,
            self_link = comment._links.self.href,
            original_position = comment.original_position,
            position = position
        }

        table.insert(entries[comment.path][ol], formatted_comment)
    end

    -- NOTE: this might not work, may be sorting a copy and not a ref.
    for _, p in ipairs(entries) do
        --
        table.sort(p, util.sort_by_field("id"))
    end

    return {success = true, data = entries}
end

function M.files_for_pull(pull_req_no)
    return github.get_pull_request_files(pull_req_no)
end

return M
