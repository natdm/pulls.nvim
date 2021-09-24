# Pulls.nvim

[CLICK HERE FOR DEMO](https://youtu.be/dMYJFKe9A_8)

*TL;DR: View, comment, browse a pull request on the currently checked out branch.*

If you're saying, "But [Octo](https://github.com/pwntester/octo.nvim) does that", you're right. I think of Octo as "Github, but in Neovim". `Pulls.nvim` is more of a lightweight vim-centric way of interacting with PR's as you work with a branch for a PR.

## Features

- List comments in a quickfix list
- List changed hunks of code in a quickfix list
- View full diff
  - Navigate to files from diff
  - Preview files in a split (tagged) window
  - Go to next diff chunk
  - Go to next comment on diff
  - Add comment on diff
  - View comment chain on diff and reply
- View/Edit description

## Functions

The functions are listed in the [helpdocs](./doc/pulls.nvim.txt). Please consult that documentation for up to date functionality.

## Mappings and Usage

### Usage

Make sure you have a github token set in your environment, at `GITHUB_API`.

While `pulls.nvim` tries to be self-encompassing, using `plentary.nvim` was a must for some functionality.

Example using [Packer.nvim](https://github.com/wbthomason/packer.nvim)
```lua
use {'pulls.nvim', config = {require("pulls").setup(nil)}, requires = {'nvim-lua/plenary.nvim'}};
```

The `setup(nil)` takes an optional table, the same structure that's found in [the config file](./lua/pulls/config.lua). Overriding this table and callng `setup()` with anything other than nil removes the default setup. If you do it, remember to remap every key.

### Mappings

There are no mappings outside of the pulls-specific buffers, as I believe you should add what you want. To map a [function](#functions), do it as you would any other neovim plugin:

```lua
local map = vim.api.nvim_set_keymap

local function nmapsl(pattern, action)
    local options = {noremap = true, silent = true}
    map('n', '<leader>' .. pattern, action, options)
end

nmapsl("pt", '<cmd>lua require("pulls").tag_window()<CR>')
nmapsl("pu", '<cmd>lua require("pulls").untag_window()<CR>')
nmapsl("ps", '<cmd>lua require("pulls").comments()<CR>')
nmapsl("pd", '<cmd>lua require("pulls").description()<CR>')
nmapsl("pp", '<cmd>lua require("pulls").diff()<CR>')
nmapsl("pn", '<cmd>lua require("pulls").diff_next()<CR>')
nmapsl("pc", '<cmd>lua require("pulls").list_changes()<CR>')
nmapsl("ph", '<cmd>lua require("pulls").highlight_changes()<CR>')
-- ... etc
```

To use a tagged window, have the diff up in a window and split it, then call `tag_window()` from the new split. 
Navigate back to the diff. Any comments opened (`cg`/`cc`) or files opened (`cf`) will open in the tagged window.

For more functions, `:h pulls.nvim`

As far as the built-in mappings, `pulls.nvim` has mappings for any diffs, comments, replies, etc for any buffers it opens and controls. Any mapping in the setup is purely for `pulls.nvim` buffers, so nothing should collide with yours. These can be overridden in the `setup()` call. The fields are explained in [the config file](./lua/pulls/config.lua). There's also more documentation directly in the setup file, as per what fields do what.

Example of overriding for something new:

```lua
require("pulls").setup {
    mappings = {
        diff = {
            show_comment = "sc", -- not default, but the rest are
            add_comment = "cc",
            next_comment = "cn",
            goto_file = "cf"
        },
        comments = {reply = "cc"},
        action = {submit = "<C-y>"}
    }
}
```

## Roadmap

The project is very much beta, so the roadmap is hefty:

- Editing (Comments)
- Reviews (Viewing, adding, editing, adding reviews)
- Emojis
- Detailed statuses (Who has been assigned, who has approved, etc)
- Add gitlab.
