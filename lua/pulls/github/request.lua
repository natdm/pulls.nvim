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

    -- TODO: This doesn't work with hosted github.
    return string.format("https://api.github.com/repos/%s/%s", --
    repo_info.owner, repo_info.project)
end

local function paginate(per_page, ok_status, req_fn)
    local page = 1
    local resp = req_fn(per_page, page)
    if resp.status ~= ok_status then return resp end
    local body = decode(resp.body)

    local result = {}
    for _, r in ipairs(body) do table.insert(result, r) end

    local body_ct = #body
    while #body_ct == per_page do
        page = page + 1
        resp = req_fn(per_page, page)
        if resp.status ~= ok_status then return {success = false, error = resp.body} end
        body = decode(resp.body)
        for _, r in ipairs(body) do table.insert(result, r) end
    end

    return {success = true, data = result}
end

return { --
    headers = default_headers,
    base_url = base,
    paginate = paginate,
    get = curl.get,
    post = curl.post,
    patch = curl.patch
}
