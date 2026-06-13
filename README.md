# quickbuf.nvim

Fast buffer switching inspired by flash-like label picking.

## Status

Early MVP.

## Features

- Quick label picker for `buflisted` buffers (excludes current buffer)
- Border title shows total selectable buffers (current buffer excluded)
- Ranking: alternate buffer (`#`) first, then pinned, then MRU
- Render filename first, with label right next to filename and parent path dimmed
- Vim-style flags are shown after pin mark (e.g. `#a+`, `h+`)
- Optional icons via `nvim-web-devicons`
- No scroll by design: top N buffers are shown, with `+X more` overflow hint
- Press `<Tab>` in picker to jump to alternate buffer (`#`)
- Press `/` in picker to fall back to fuzzy buffers (Snacks/Telescope/fzf-lua)
- Picker actions: `k/j` move, `gg/G` first/last, `V` linewise visual, `dd`/`d` delete safe, `D` delete force, `c/C` clear unpinned safe/force, `w/W` write current-or-selection/all, `r/R` reload modified current-or-selection/all, `p` toggle all/pinned view, `<CR>` open current
- `?` opens an in-picker help popup with all actions
- Pin toggle and pinned-view picker (pinned plus alternate)
- Next/previous pinned buffer cycling

## Install

With `lazy.nvim`:

```lua
{
  "tjgao/quickbuf.nvim",
  config = function()
    require("quickbuf").setup()
  end,
}
```

## Commands

- `:QuickBuf` open quick picker (uses current session view mode)
- `:QuickBufAll` open picker with all buffers
- `:QuickBufPinned` open picker with pinned buffers plus alternate (`#`)
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
  isolate_keymaps = true,
  fuzzy_key = "/",
  alternate_key = "<Tab>",
  alternate_key_display = "",
  alternate_without_label = true,
  picker = {
    move_up_key = "k",
    move_down_key = "j",
    select_key = "<CR>",
    toggle_pin_key = "T",
    toggle_view_key = "p",
  },
  show_icons = true,
  highlights = {
    label = { fg = "#ff8800", bold = true },
    pinned = { link = "DiagnosticOk" },
    flags = { link = "Comment" },
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
    vertical_padding = 1,
  },
})
```

## Notes

- Labels are always one-key and use an internal ergonomic charset.
- Visible items are capped to that internal label count, with `+X more` overflow hint.
- `isolate_keymaps = true` blocks unrelated normal-mode mappings inside picker.
- `gg/G`, `V`, `dd/d/D`, `c/C`, `w/W`, and `r/R` are reserved from labels to avoid conflicts.
- With `alternate_without_label = true`, the alternate entry has no label and is opened with `<Tab>`.
- Set `fuzzy_key = false` or `alternate_key = false` to disable those picker shortcuts.
- `picker.*` keys are conflict-safe: they are automatically reserved from label characters.
- Picker view mode (`all`/`pinned`) is session-persistent and can be toggled in-picker with `picker.toggle_view_key`.
- Override colors with `highlights = { ... }` in setup.
- `window.width`, `window.height`, `window.min_width`, and `window.max_width` accept absolute numbers (`80`) or percentages (`0.6`).
- `window.vertical_padding` adds blank rows above and below buffer entries.
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
