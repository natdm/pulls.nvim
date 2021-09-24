local M = {}

local ns_id = vim.api.nvim_create_namespace("pulls_ns")

-- set an extmark with defaults
function M.set(buf, line, opts)
    return vim.api.nvim_buf_set_extmark(buf, ns_id, line, opts.col or 0, { --
        id = opts.id or nil,
        hl_group = opts.hl_group or "Todo",
        priority = opts.priority or 200,
	hl_eol = true
    })
end

return M
