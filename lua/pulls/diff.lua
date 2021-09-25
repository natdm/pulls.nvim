local util = require("pulls.util")

local M = {}

function M.parse_diff_header(diff)
    local _, _, rm_start_s, rm_ct_s, add_start_s, add_ct_s = string.find( --
    diff, "@@ %-(%d+),(%d+) %+(%d+),(%d+) @@")

    local rm_start = tonumber(rm_start_s)
    local rm_ct = tonumber(rm_ct_s)
    local add_start = tonumber(add_start_s)
    local add_ct = tonumber(add_ct_s)

    local diff_preview = "-" .. rm_start_s .. "," .. rm_ct_s .. --
    " +" .. add_start_s .. "," .. add_ct_s

    return { --
        remove_start = rm_start,
        remove_ct = rm_ct,
        add_start = add_start,
        add_ct = add_ct,
        preview = diff_preview
    }
end

function M.diff(files)
    -- prepare the signs
    local entries = {}
    for _, file in ipairs(files) do --
        -- create a key for each file name to hold all changes
        local lines = util.split(file.patch, '\n')
        if entries[file.filename] == nil then
            entries[file.filename] = { --
                diff_lines = lines,
                chunks = {}
            }
        end

        -- diff chunk header info
        local rm_start = 0
        local rm_ct = 0
        local add_start = 0
        local add_ct = 0

        local diff_preview = nil -- the add/del line count
        local full_diff_desc = nil -- the chunk header, @@ ... @@
        local short_sha = string.sub(file.sha, 1, 7)

        -- diff_line_counter increments each loop after the header of
        -- a diff, and can be used to add diff_line_counter + add_start
        -- to see where to mark the line. Do not add for any deletes
        -- (for now). Set to -1 at the start, to account for the header.
        local diff_line_counter = -1

        -- delete_ctr can be used to track if there's a change or a delete.
        --   if current line starts with + and delete_ctr is > 0, this is
        --     a changed line, and not an addition. Mark it as a change and
        --     decrement delete_ctr
        --   if current line starts with -, increment delete_ctr
        --   if current line starts with neither + or - and delete_ctr is > 0
        --     mark as a delete and reset delete_ctr to 0 since the change is done.
        --     eg: lines [_, _, _, -, -, -, +, +, +, +, +, _, _, _]
        --     has 3 changes and 2 additions.
        --
        -- This logic is possible since deletions always preceed additions in diffs
        local delete_ctr = 0

        -- hold {{line = n, acton = a|c|d}} for each chunk
        local changes_by_line = {}

        for i, line in ipairs(lines) do
            if vim.startswith(line, "@@") then
                -- the start of a chunk of diff. It's possible that we're already
                -- in a diff chunk -- this is guaranteed if i != 1. If that's the
                -- case, save what we have so far in the entries for the previous
                -- chunk, and reset the state.
                if i ~= 1 then
                    table.insert(entries[file.filename].chunks, { --
                        rm_start = rm_start,
                        rm_ct = rm_ct,
                        add_start = add_start,
                        add_ct = add_ct,
                        diff_preview = diff_preview,
                        diff_desc = full_diff_desc,
                        short_sha = short_sha,
                        changes_by_line = changes_by_line,
                        diff_end = diff_line_counter
                    })
                end

                -- reset the row for the new record

                local _, _, rm_start_s, rm_ct_s, add_start_s, add_ct_s = string.find(line, "@@ %-(%d+),(%d+) %+(%d+),(%d+) @@")

                rm_start = tonumber(rm_start_s)
                rm_ct = tonumber(rm_ct_s)
                add_start = tonumber(add_start_s)
                add_ct = tonumber(add_ct_s)
                diff_preview = "-" .. rm_start_s .. "," .. rm_ct_s .. --
                " +" .. add_start_s .. "," .. add_ct_s
                full_diff_desc = line
                diff_line_counter = -1
                delete_ctr = 0
                changes_by_line = {}

            elseif vim.startswith(line, "+") then
                diff_line_counter = diff_line_counter + 1
                local l = diff_line_counter + add_start

                if delete_ctr > 0 then
                    delete_ctr = delete_ctr - 1
                    table.insert(changes_by_line, {line = l, action = "c"})
                else
                    table.insert(changes_by_line, {line = l, action = "a"})
                end

            elseif vim.startswith(line, "-") then
                -- do not increment the diff_line_counter since we don't show
                -- deletes in code
                delete_ctr = delete_ctr + 1
            elseif i == #lines then
                -- the end of the road, add the row.
                table.insert(entries[file.filename].chunks, { --
                    rm_start = rm_start,
                    rm_ct = rm_ct,
                    add_start = add_start,
                    add_ct = add_ct,
                    diff_preview = diff_preview,
                    diff_desc = full_diff_desc,
                    short_sha = short_sha,
                    changes_by_line = changes_by_line,
                    diff_end = diff_line_counter
                })

            else -- not a + or a -, could be at the start, end, or no change
                diff_line_counter = diff_line_counter + 1
                local l = diff_line_counter + add_start

                if delete_ctr > 0 then
                    -- If the delete counter is > 0 and the last entry in changes_by_line was a
                    -- change, code is being consolidated (eg: deleted 10 lines, adding 1, then
                    -- this is the blank line after). Just reset the delete_ctr.
                    -- Don't worry about checking if the change was on the previous line since
                    -- we are tracking chunks within a diff.
                    if #changes_by_line > 0 and changes_by_line[#changes_by_line].action ~= "c" then --
                        table.insert(changes_by_line, {line = l, action = "d"})
                    else
                        -- just deleting some code from a file. Since we can't show deletes,
                        -- mark a single line as a delete for all counted delete lines
                        table.insert(changes_by_line, {line = l, action = "d"})
                    end
                    delete_ctr = 0
                end
            end
        end
    end
    return entries
end

return M
