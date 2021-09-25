local request = require('pulls.github.request')
local encode = vim.fn.json_encode
local decode = vim.fn.json_decode
local config = require('pulls.config')

local M = {}

function M.get(pull_req_no)
    local url = string.format("%s/pulls/%i/comments", request.base_url(), pull_req_no)
    local resp = request.get({url = url, headers = request.headers})
    if resp.status ~= 200 then return {success = false, error = request.format_error_resp(resp)} end
    return {success = true, data = decode(resp.body)}
end

-- github v3:
-- Note: GitHub's REST API v3 considers every pull request an issue, but not every issue is a pull
-- request. For this reason, "Issues" endpoints may return both issues and pull requests in the response.
-- -
-- So these are the comments that aren't tied to a diff, just standalone.
function M.get_issue_comments(pull_req_no)
    local url = string.format("%s/issues/%i/comments", request.base_url(), pull_req_no)
    local resp = request.get({url = url, headers = request.headers})
    if resp.status ~= 200 then return {success = false, error = request.format_error_resp(resp)} end
    return {success = true, data = decode(resp.body)}
end

-- An issue comment is a comment not tied to a diff.
function M.create_issue_comments(pull_req_no, comment)
    local url = string.format("%s/issues/%i/comments", request.base_url(), pull_req_no)
    local encoded = encode({body = comment})
    local resp = request.post({ --
        url = url,
        headers = request.headers,
        body = encoded,
        dry_run = config.debug
    })
    if resp.status ~= 201 then return {success = false, error = request.format_error_resp(resp)} end
    return {success = true, data = decode(resp.body)}
end

function M.reply(pull_req_no, comment_id, comment)
    local url = string.format("%s/pulls/%i/comments/%i/replies", request.base_url(), pull_req_no, comment_id)
    local encoded = encode({body = comment})
    local req = {url = url, headers = request.headers, body = encoded, dry_run = config.debug}
    local resp = request.post(req)

    if config.debug then
        print(vim.inspect(resp))
        return {success = true}
    else
        if resp.status ~= 201 then return {success = false, error = request.format_error_resp(resp)} end
        -- not json, do not parse
        return {success = true, data = decode(resp.body)}
    end
end

function M.new(pull_req_no, commit_id, file_path, diff_position, body)
    local url = string.format("%s/pulls/%i/comments", request.base_url(), pull_req_no)
    local req = encode({ --
        path = file_path,
        position = diff_position,
        commit_id = commit_id,
        body = table.concat(body, "\r\n")
    })

    local resp = request.post({url = url, headers = request.headers, body = req})

    if config.debug then
        print(vim.inspect(resp))
        return {success = true}
    else
        if resp.status ~= 201 then return {success = false, error = request.format_error_resp(resp)} end
        return {success = true, data = decode(resp.body)}
    end
end

return M
