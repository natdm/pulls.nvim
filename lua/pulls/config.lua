return {
    mappings = {
        -- Each key is grouped in a buffer. It's fine to use the same
        -- mapping in different keys. eg: `diff` and `comments` can
        -- share a common mapping.

        diff = { -- Mappings for the diff view.
            -- Show a comment under the current cursor (cc would do the same).
            show_comment = "cg",
            -- Add a new comment under the cursor. This will open the thread
            -- of any existing comments.
            add_comment = "cc",
            -- Skip to the next comment in the diff (goes to EOF if none).
            next_comment = "cn",
            -- Go to next file (hunk) in diff, separated by diff headers (@@ ... @@)
            next_hunk = "ch",
            -- Goes to the file of the diff the cursor is under.
            goto_file = "cf",
            -- If a window is tagged, the preview will show in that window, and
            -- the cursor will remain in the diff. No effect at all if no window
            -- is tagged.
            preview_file = "cp"
        },

        description = { -- Mappings for when the cursor is in the PR description.
            -- Edit the PR description.
            edit = "ce"
        },

        comments = { -- Mappings for when viewing a thread
            -- Draft a reply to a comment. Opens a new diff.
            reply = "cc"
        },

        action = { -- Mappings for when inserting text (comments, editing, etc).
            -- Execute the action (submit a comment, save an update, etc).
            submit = "<C-y>"
        }
    }
}
