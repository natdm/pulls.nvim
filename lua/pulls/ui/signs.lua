local config = require("pulls.config")
-- a lot of this lifted from gitsigns.nvim, thank you!
local M = {}

-- TODO: Make our own hl groups, these are stdlib ones.
M.sign_map = {add = "DiffAdd", change = "DiffChange", delete = "DiffDelete", txt = "DiffText"}

local ns = vim.api.nvim_create_namespace("gitpush_ns")

function _G.RemoveSign(lnum)
    local bufnr = vim.fn.bufnr("%")
    vim.fn.sign_unplace(ns, {buffer = bufnr, id = lnum})
end

function M.highlight_line(bufnr, line, opts)
    opts = opts or {}
    vim.fn.sign_define("pulls_hl", {linehl = "Todo"})

    return vim.fn.sign_place(opts.id or 0, opts.group or "pulls", "pulls_hl", bufnr, {lnum = line, priority = 500})
end

function M.remove_highlight(opts)
    opts = opts or {}
    vim.fn.sign_unplace(opts.group or "pulls")
end

function M.clear()
    return vim.fn.sign_unplace("pulls")
end

function M.add(bufnr, signs)
    vim.fn.sign_define("pulls_add", {numhl = "Character"})
    vim.fn.sign_define("pulls_rem", {numhl = "ErrorMsg"})
    vim.fn.sign_define("pulls_alt", {numhl = "WarningMsg"})
    vim.fn.sign_define("pulls_unk", {numhl = "Todo"}) -- unknown, in case we don't do a/c/d

    local entries = {}

    for _, sign in ipairs(signs) do --
        if sign.action ~= "" then
            local name = "pulls_unk"
            if sign.action == "a" then name = "pulls_add" end
            if sign.action == "d" then name = "pulls_rem" end
            if sign.action == "c" then name = "pulls_alt" end
            -- add comments to the left of the number row
            if sign.action == 'comment' then
                name = "pulls_comments_" .. tostring(sign.line)
                vim.fn.sign_define(name, {texthl = "WarningMsg", text = tostring(sign.count)})
            end
            if sign.action == 'comment_outdated' then
                name = "pulls_comments_" .. tostring(sign.line)
                vim.fn.sign_define(name, {texthl = "TermCursorNC", text = tostring(sign.count)})
            end
            table.insert(entries, { --
                buffer = bufnr,
                id = sign.line,
                lnum = sign.line,
                priority = 90,
                group = "pulls",
                name = name
            })
        end
    end

    return vim.fn.sign_placelist(entries)
end

function _G.AddSigns(signs)
    local bufnr = vim.fn.bufnr("%")
    M.add(bufnr, signs)
end

function M.remove(lnum)
    local bufnr = vim.fn.bufnr("%")
    vim.fn.sign_unplace("pulls", {buffer = bufnr, id = lnum})
end

return M

