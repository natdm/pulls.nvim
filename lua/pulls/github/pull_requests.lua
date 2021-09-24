-- local config = require("pulls.config")
local git = require("pulls.git")
-- local util = require('pulls.util')
local request = require('pulls.github.request')
-- local encode = vim.fn.json_encode
local decode = vim.fn.json_decode

local M = {}

function M.get()
    local repo_info = git.get_repo_info()
    local branch = git.current_branch()
    local head = repo_info.owner .. ":" .. branch
    local pull_reqs = request.get({ --
        url = request.base_url() .. "/pulls",
        query = {state = "open", head = head},
        headers = request.headers
    })
    return decode(pull_reqs.body)
end

function M.get_diff(pull_req_no)
    local url = string.format("%s/pulls/%i", request.base_url(), pull_req_no)

    -- needs header Accept: application/vnd.github.v3.diff
    local custom_headers = {}
    for k, v in pairs(request.headers) do custom_headers[k] = v end
    custom_headers["Accept"] = "application/vnd.github.v3.diff"

    local req = {url = url, headers = custom_headers}
    local resp = request.get(req)
    if resp.status ~= 200 then return {success = false, error = resp.body} end
    -- not json, do not decode
    return {success = true, data = resp.body}
end

function M.get_files(pull_req_no)
    local url = string.format("%s/pulls/%i/files", request.base_url(), pull_req_no)
    local resp = request.get({url = url, headers = request.headers})
    if resp.status ~= 200 then return {success = false, error = resp.body} end
    local files = decode(resp.body)
    return {success = true, data = files}
end

return M
