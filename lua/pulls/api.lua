local config = require("pulls.config")
local git = require("pulls.git")
local curl = require('plenary.curl')
local util = require('pulls.util')

local M = {}

local default_headers = {
    --
    Accept = "application/vnd.github.v3+json",
    Authorization = "token " .. vim.env.GITHUB_API
}

local base_url = ""

local function base()
    if base_url ~= "" then return base_url end

    local repo_info = git.get_repo_info()

    return string.format("https://api.github.com/repos/%s/%s", --
    repo_info.owner, repo_info.project)
end

function M.pulls()
    local repo_info = git.get_repo_info()
    local branch = git.current_branch()
    local head = repo_info.owner .. ":" .. branch
    local pull_reqs = curl.get({url = base() .. "/pulls", query = {state = "open", head = head}, headers = default_headers})
    return vim.fn.json_decode(pull_reqs.body)
end

local default_comments_for_pull_opts = {sorted = true, hide_no_line_counts = true}

function M.new_comment(pull_req_no, path, position, commit_id, body)
    -- https://docs.github.com/en/rest/reference/pulls#create-a-review-comment-for-a-pull-request
    -- Note: The position value equals the number of lines down from the first "@@" hunk
    -- header in the file you want to add a comment. The line just below the "@@" line is
    -- position 1, the next line is position 2, and so on. The position in the diff
    -- continues to increase through lines of whitespace and additional hunks until the
    -- beginning of a new file.
    local url = base() .. "/pulls/" .. pull_req_no .. "/comments"
    local stringified_body = vim.fn.json_encode({ --
        path = path,
        position = position,
        commit_id = commit_id,
        body = table.concat(body, "\r\n")
    })

    local req = { --
        url = url,
        headers = default_headers,
        body = stringified_body,
        dry_run = config.debug
    }

    local resp = curl.post(req)

    if config.debug then
        print(vim.inspect(resp))
        return {success = true}
    else
        if resp.status ~= 201 then return {success = false, error = resp.body} end
        return {success = true}
    end
end

-- full diff for PR
function M.diff(pull_req_no)
    -- needs header Accept: application/vnd.github.v3.diff
    local url = base() .. "/pulls/" .. pull_req_no
    local custom_headers = {}
    for k, v in pairs(default_headers) do custom_headers[k] = v end
    custom_headers["Accept"] = "application/vnd.github.v3.diff"
    local req = {url = url, headers = custom_headers}
    local resp = curl.get(req)
    if resp.status ~= 200 then return {success = false, error = resp.body} end
    return {success = true, data = resp.body}
end

function M.reply(pull_req_no, comment_id, body)
    local url = base() .. "/pulls/" .. pull_req_no .. "/comments/" .. comment_id .. "/replies"

    local stringified_body = vim.fn.json_encode({body = body})

    local req = {url = url, headers = default_headers, body = stringified_body, dry_run = config.debug}
    local resp = curl.post(req)

    if config.debug then
        print(vim.inspect(resp))
        return {success = true}
    else
        if resp.status ~= 201 then return {success = false, error = resp.body} end
        -- not json, do not parse
        return {success = true, data = resp.body}
    end

    -- this returns the body, but just ignore it. Favor a plugin refresh.

    -- exit    = "The shell process exit code." (number)
    -- status  = "The https response status." (number)
    -- headers = "The https response headers." (array)
    -- body    = "The http response body." (string)
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
function M.comments_for_pull(url, opts)
    opts = opts or {}
    opts = util.merge_tables(default_comments_for_pull_opts, opts)

    local resp = curl.get({url = url, headers = default_headers})
    if resp.status ~= 200 then return {success = false, error = resp.body} end

    local comments = vim.fn.json_decode(resp.body)

    local entries = {}
    for _, comment in ipairs(comments) do
        if entries[comment.path] == nil then entries[comment.path] = {} end
        local ol = tostring(comment.original_line)
        if entries[comment.path][ol] == nil then entries[comment.path][ol] = {} end

	print(vim.inspect(comment))
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
    -- https://docs.github.com/en/rest/reference/pulls#list-pull-requests-files
    -- This is paginated, default to 30 files per page. We will have to loop until we get a response with less than 30 files.
    local url = base() .. "/pulls/" .. pull_req_no .. "/files"

    local resp = curl.get({url = url, headers = default_headers})
    if resp.status ~= 200 then return {success = false, error = resp.body} end
    local files = vim.fn.json_decode(resp.body)
    return {success = true, data = files}
end

return M
