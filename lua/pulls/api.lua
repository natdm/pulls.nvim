local util = require('pulls.util')
local diff = require('pulls.diff')
local github = require("pulls.github.api")

local M = {}

function M.pulls()
    return github.get_pull_requests()
end

function M.new_comment(pull_req_no, path, position, commit_id, body)
    return github.post_comment(pull_req_no, commit_id, path, position, body)
end

function M.description_edit(pull_req_no, body)
    return github.update_pull_requests(pull_req_no, {body = body})
end

function M.description_edit_title(pull_req_no, title)
    return github.update_pull_requests(pull_req_no, {title = title})
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

local function format_comments(comments)
    local entries = {}
    for _, comment in ipairs(comments) do
        if entries[comment.path] == nil then entries[comment.path] = {} end
        -- comment.line and comment.original_line is nil for review comments. Not for issue comments.
        -- 🤷
        local diff_header = diff.parse_diff_header(comment.diff_hunk)

        local line = diff_header.add_start + comment.position

        if entries[comment.path][line] == nil then entries[comment.path][line] = {} end

        local position = comment.position
        if position == vim.NIL then position = nil end

        local formatted_comment = {
            user = comment.user.login,
            line = line,
            -- original_line = comment.original_line,
            path = comment.path,
            diff_hunk = comment.diff_hunk,
            created_at = comment.created_at,
            body = comment.body,
            preview = comment_preview(comment.body),
            id = comment.id,
            review_id = comment.pull_request_review_id,
            self_link = comment._links.self.href,
            original_position = comment.original_position,
            position = position
        }

        table.insert(entries[comment.path][line], formatted_comment)
    end

    -- NOTE: this might not work, may be sorting a copy and not a ref.
    for _, p in ipairs(entries) do
        --
        table.sort(p, util.sort_by_field("id"))
    end

    return entries
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
    return {success = true, data = format_comments(resp.data)}
end

function M.get_reviews(pr_no)
    return github.get_reviews(pr_no)
end

function M.get_review_comments(pr_no, review_id)
    return github.get_review_comments(pr_no, review_id)
end

function M.get_issue_comments(pr_no)
    return github.get_issue_comments(pr_no)
end

function M.comments(pr_no)
    local reviews = github.get_reviews(pr_no)
    if not reviews.success then return reviews end

    local comments = github.get_comments(pr_no)
    if not comments.success then return comments end

    local issues = github.get_issue_comments(pr_no)
    if not issues.success then return issues end

    return {issues = issues.data, comments = comments.data, reviews = reviews.data}
end

-- this will get all reviews, then all comments for reviews, format the coments, and add
-- them as a "comments" key under the original review.
--
-- { { author, commit_id, id, state, submitted_at, user, body = (could be blank if a normal comment), author_association, comments = {
--     [filepath] = { 
--         [line] = { { body, created_at, diff_hunk, id, path, user, original_position, etc... } }
--     } }
-- } }
function M.get_all_review_comments(pr_no)
    local reviews = M.get_reviews(pr_no)
    if not reviews.success then return reviews end
    for i, r in ipairs(reviews.data) do --
        local comments = M.get_review_comments(pr_no, r.id)
        -- todo: util to wrap errors?
        if not comments.success then return comments end
        -- BUG: This requests line and original line, which does not exist in the api return call.
        -- Need to grab the diff then get the position and do some math if we want that.
        reviews.data[i].comments = format_comments(comments.data)
    end
    return {success = true, data = reviews.data}
end

function M.files_for_pull(pull_req_no)
    return github.get_pull_request_files(pull_req_no)
end

return M
