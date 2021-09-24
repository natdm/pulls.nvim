local util = require('pulls.util')
local M = {}

local function get_remote_http_url()
    local remote_origin = vim.fn.system("git config --get remote.origin.url")
    local url = string.gsub(remote_origin, "%s+", "")
    -- "git@github.com:natdm/pulls.git"
    -- force to be https if not already, since we're calling the api and not always the cli
    if string.find(url, "git@") then
        url = string.gsub(url, ":", "/")
        url = string.gsub(url, "%.git", "")
        url = string.gsub(url, "git@", "https://")
    end
    return url
end

function M.current_branch()
    local status = vim.fn.system("git status")
    local branch, _ = string.gsub(util.split(status, "\n")[1], "On branch ", "")
    return branch
end

function M.sha()
    local sha = util.split(vim.fn.system("git rev-parse HEAD"), "\n")[1]
    return sha
end

function M.get_repo_info()
    local url = get_remote_http_url()
    local owner, project = url:match(".*/(.*)/(.*)")
    return {owner = owner, project = project, url = url}

end

function _G.GitInfo()
    print(vim.inspect(M.get_repo_info()))
end

return M
