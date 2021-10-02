local git = require("pulls.git")
local curl = require('plenary.curl')
local decode = vim.fn.json_decode

local default_headers = {
    --
    Accept = "application/vnd.github.v3+json",
    Authorization = "token " .. vim.env.GITHUB_API
}

local base_url = ""

local function base()
    if base_url ~= "" then return base_url end

    local repo_info = git.get_repo_info()

    base_url = string.format("%s/repos/%s/%s", --
    repo_info.url, repo_info.owner, repo_info.project)
    return base_url
end

local function format_error_resp(resp)
    if not resp.exit then
        return string.format("[status: %i]: %s", resp.status, (resp.body or "<nil>"))
    else
        return string.format("[exit: %i]", resp.exit)
    end
end

local function paginate(per_page, ok_status, req_fn)
    local page = 1
    local resp = req_fn(per_page, page)
    if resp.status ~= ok_status then return resp end
    local body = decode(resp.body)

    local result = {}
    for _, r in ipairs(body) do table.insert(result, r) end

    local body_ct = #body
    while body_ct == per_page do
        page = page + 1
        resp = req_fn(per_page, page)
        if resp.status ~= ok_status then return {success = false, error = format_error_resp(resp)} end
        body = decode(resp.body)
        for _, r in ipairs(body) do table.insert(result, r) end
    end

    return {success = true, data = result}
end

return { --
    headers = default_headers,
    base_url = base,
    paginate = paginate,
    format_error_resp = format_error_resp,
    get = curl.get,
    post = curl.post,
    patch = curl.patch
}
