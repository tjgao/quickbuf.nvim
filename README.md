# quickbuf.nvim

Fast buffer switching inspired by flash-like label picking.

## Status

Early MVP.

## Features

- Quick label picker for `buflisted` buffers (excludes current buffer)
- Ranking: pinned first, then alternate buffer (`#`), then MRU
- Render filename first, with label right next to filename and parent path dimmed
- Clear markers: `P` for pinned, `#` for alternate
- Optional icons via `nvim-web-devicons`
- No scroll by design: top N buffers are shown, with `+X more` overflow hint
- Press `<Tab>` in picker to jump to alternate buffer (`#`)
- Press `/` in picker to fall back to fuzzy buffers (Snacks/Telescope/fzf-lua)
- Picker navigation keys: `K` up, `J` down, `<CR>` select line, `T` toggle pin
- Pin toggle and pinned-only picker
- Next/previous pinned buffer cycling

## Install

With `lazy.nvim`:

```lua
{
  "tiejun/quickbuf.nvim",
  config = function()
    require("quickbuf").setup()
  end,
}
```

## Commands

- `:QuickBuf` open main quick picker
- `:QuickBufPinned` open picker with pinned buffers only
- `:QuickBufPinToggle` pin/unpin current buffer
- `:QuickBufNextPinned` go to next pinned buffer
- `:QuickBufPrevPinned` go to previous pinned buffer

## Suggested keymaps

```lua
vim.keymap.set("n", "<leader>bb", "<cmd>QuickBuf<cr>", { desc = "QuickBuf" })
vim.keymap.set("n", "<leader>bp", "<cmd>QuickBufPinToggle<cr>", { desc = "Pin toggle" })
vim.keymap.set("n", "[b", "<cmd>QuickBufPrevPinned<cr>", { desc = "Prev pinned" })
vim.keymap.set("n", "]b", "<cmd>QuickBufNextPinned<cr>", { desc = "Next pinned" })
```

## Config

Defaults:

```lua
require("quickbuf").setup({
  include_special = false,
  auto_jump_single = true,
  fuzzy_key = "/",
  alternate_key = "<Tab>",
  alternate_without_label = true,
  picker = {
    move_up_key = "K",
    move_down_key = "J",
    select_key = "<CR>",
    toggle_pin_key = "T",
  },
  show_icons = true,
  highlights = {
    label = { fg = "#ff8800", bold = true },
    pinned = { link = "DiagnosticOk" },
    alternate = { link = "DiagnosticWarn" },
    filename = { link = "Normal" },
    path = { link = "Comment" },
    muted = { link = "Comment" },
    cursorline = { link = "Visual" },
  },
  window = {
    border = "rounded",
    width = nil,
    height = nil,
    max_width = 80,
    min_width = 36,
    padding = 2,
  },
})
```

## Notes

- Labels are always one-key and use an internal ergonomic charset.
- Visible items are capped to that internal label count, with `+X more` overflow hint.
- With `alternate_without_label = true`, the alternate entry has no label and is opened with `<Tab>`.
- Set `fuzzy_key = false` or `alternate_key = false` to disable those picker shortcuts.
- Set `picker.* = false` to disable individual picker action keys.
- Override colors with `highlights = { ... }` in setup.
- `window.width`, `window.height`, `window.min_width`, and `window.max_width` accept absolute numbers (`80`) or percentages (`0.6`).
- Pin state is in-memory for now (session only).

Example highlight override:

```lua
require("quickbuf").setup({
  highlights = {
    label = { fg = "#ff5f00", bold = true },
    path = { fg = "#6c7086", italic = true },
  },
})
```

Example percentage sizing:

```lua
require("quickbuf").setup({
  window = {
    width = 0.6,
    height = 0.5,
    min_width = 0.4,
    max_width = 0.8,
  },
})
```
