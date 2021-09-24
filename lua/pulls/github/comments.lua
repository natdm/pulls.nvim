local request = require('pulls.github.request')
local encode = vim.fn.json_encode
local decode = vim.fn.json_decode
local config = require('pulls.config')

local M = {}

function M.get(pull_req_no)
    local url = string.format("%s/pulls/%i/comments", request.base_url(), pull_req_no)
    local resp = request.get({url = url, headers = request.headers})
    if resp.status ~= 200 then return {success = false, error = resp.body} end
    return {success = true, data = decode(resp.body)}
end

function M.reply(pull_req_no, comment_id, body)
    local url = string.format("%s/pulls/%i/comments/%i/replies", request.base_url(), pull_req_no, comment_id)
    local encoded = encode({body = body})
    local req = {url = url, headers = request.headers, body = encoded, dry_run = config.debug}
    local resp = request.post(req)

    if config.debug then
        print(vim.inspect(resp))
        return {success = true}
    else
        if resp.status ~= 201 then return {success = false, error = resp.body} end
        -- not json, do not parse
        return {success = true, data = decode(resp.body)}
    end
end

function M.new(pull_req_no, commit_id, file_path, diff_position, body)
    local url = string.format("%s/pulls/%i/comments", request.base_url(), pull_req_no)
    local encoded = encode({ --
        url = url,
        path = file_path,
        position = diff_position,
        commit_id = commit_id,
        body = table.concat(body, "\r\n")
    })

    local resp = request.post(encoded)

    if config.debug then
        print(vim.inspect(resp))
        return {success = true}
    else
        if resp.status ~= 201 then return {success = false, error = resp.body} end
        return {success = true, data = decode(resp.body)}
    end
end

return M
