local request = require('pulls.github.request')
-- local encode = vim.fn.json_encode
local decode = vim.fn.json_decode

local M = {}

function M.get(pull_req_no)
    local url = string.format("%s/pulls/%i/reviews", request.base_url(), pull_req_no)
    local req = {url = url, headers = request.headers}
    local resp = request.get(req)
    if resp.status ~= 200 then return {success = false, error = resp.body} end
    return {success = true, data = decode(resp.body)}
end

function M.get_comments(pull_req_no, review_id)
    return request.paginate(30, 200, function(per_page, page)
        local url = string.format("%s/pulls/%i/reviews/%i/comments", --
        request.base_url(), pull_req_no, review_id, page, per_page)
        return request.get({url = url, headers = request.headers, query = {page = page, per_page = per_page}})
    end)
end

return M
