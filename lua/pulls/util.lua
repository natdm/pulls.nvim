local M = {}

function M.sort_by_field(field)
    return function(a, b)
        return a[field] > b[field]
    end
end

function M.inspect(debug, data)
    if debug then print(vim.inspect(data)) end
    return data
end

function M.merge_tables(left, right)
    for k, v in pairs(right) do left[k] = v end
    return right
end

function M.split(str, pat)
    local t = {} -- NOTE: use {n = 0} in Lua-5.0
    local fpat = "(.-)" .. pat
    local last_end = 1
    local s, e, cap = str:find(fpat, 1)
    while s do
        if s ~= 1 or cap ~= "" then table.insert(t, cap) end
        last_end = e + 1
        s, e, cap = str:find(fpat, last_end)
    end
    if last_end <= #str then
        cap = str:sub(last_end)
        table.insert(t, cap)
    end
    return t
end

function M.split_newlines(str)
    local d = {}
    for s in str:gmatch("[^\r\n]+") do table.insert(d, s) end
    return d
end

function M.file_info()
    local file = vim.fn.expand("%:p")
    local line = vim.fn.line(".")
    local bufnr = vim.fn.bufnr("%")
    return {file = file, line = line, bufnr = bufnr}
end

-- find key for a table, running fn for each value in the table.
function M.find_key(t, fn, default)
    default = default or false
    local f = fn

    if type(f) ~= "function" then
        f = function(x)
            return x == fn
        end
    end

    for k, v in pairs(t) do if f(v) then return k end end
    return false
end

return M
