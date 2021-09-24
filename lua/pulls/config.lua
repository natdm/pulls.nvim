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
            -- Goes to the file of the diff the cursor is under.
            goto_file = "cf"
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
