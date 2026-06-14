# quickbuf.nvim

Fast buffer switching inspired by flash-like label picking.

## Status

Early MVP.

## Why QuickBuf

- Keep a task-focused working set: pin the few buffers you touch repeatedly.
- Switch quickly inside that set with `:QuickBufNextPinned` / `:QuickBufPrevPinned`.
- Clean up safely with `c/C`: unpinned buffers are removed, pinned buffers stay.
- Use one-key labels for speed, and `/` fuzzy fallback when your instinct is filename typing.

## Features

- Quick label picker for `buflisted` buffers (excludes current buffer)
- Border title shows total selectable buffers (current buffer excluded)
- Ranking: alternate buffer (`#`) first, then pinned, then MRU
- Render filename first, with label right next to filename and parent path dimmed
- Vim-style flags are shown after pin mark (e.g. `#a+`, `h+`)
- Optional icons via `nvim-web-devicons`
- No scroll by design: top N buffers are shown, with `+X more` overflow hint
- Press `<Tab>` in picker to jump to alternate buffer (`#`)
- Press `/` in picker to open fuzzy buffers (`fuzzy_backend`: auto/Snacks/Telescope/fzf/custom)
- Picker actions: `k/j` move, `gg/G` first/last, `V` linewise visual, `dd`/`d` delete safe, `D` delete force, `c/C` clear unpinned safe/force, `w/W` write current-or-selection/all, `r/R` reload modified current-or-selection/all, `s/v/t + label` open in split/vsplit/tab, `<CR>` open current (`s/v/t` mode applies to `<CR>`/`<Tab>` too)
- `?` opens an in-picker help popup with all actions
- Pin toggle and next/previous pinned buffer cycling

## Demo

<!-- Demo source https://github.com/tjgao/assets/raw/refs/heads/main/videos/QuickBuf-demo.mp4-->
https://github.com/user-attachments/assets/eaa5bd33-a3af-4b49-8945-12d0c3db2dba

## Demo Walkthrough

1. One-key jump: press a label to open its buffer.
2. Batch pin/unpin: `V` linewise visual selection, then `T` to toggle pinned.
3. Priority behavior: alternate buffer and pinned buffers rank first; use `<Tab>` for alternate.
4. Quick pinned switching: `:QuickBufNextPinned` and `:QuickBufPrevPinned`.
5. Batch delete: `V` linewise visual selection, then `d` (safe) or `D` (force).
6. `s/v/t` open modes: `s` split, `v` vsplit, `t` tab, then pick a label.
7. Fuzzy fallback: `/` to open fuzzy picker (`auto`: Snacks/Telescope/fzf-lua, or custom backend).
8. Cleanup unpinned buffers: `c` (safe) or `C` (force).

<img width="1242" height="1476" alt="Image" src="https://github.com/user-attachments/assets/fe5b5095-dd4d-4315-9160-bc0426844cc9" />

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

- `:QuickBuf` open quick picker
- `:QuickBufPinToggle` pin/unpin current buffer
- `:QuickBufNextPinned` go to next pinned buffer
- `:QuickBufPrevPinned` go to previous pinned buffer

## Suggested keymaps

```lua
vim.keymap.set("n", "<Tab>", "<cmd>QuickBuf<CR>", { desc = "QuickBuf" })
vim.keymap.set("n", "<leader>qt", "<cmd>QuickBufPinToggle<CR>", { desc = "Pin toggle" })
vim.keymap.set("n", "<S-h>", "<cmd>QuickBufPrevPinned<CR>", { desc = "Prev pinned buffer" })
vim.keymap.set("n", "<S-l>", "<cmd>QuickBufNextPinned<CR>", { desc = "Next pinned buffer" })
```

## Config

Defaults:

```lua
require("quickbuf").setup({
    include_special = false,
    auto_jump_single = false,
    isolate_keymaps = true,
    fuzzy_key = "/",
    fuzzy_backend = "auto",
    fuzzy_open = nil,
    alternate_key = "<Tab>",
    alternate_key_display = "",
    alternate_without_label = true,
    picker = {
        move_up_key = "k",
        move_down_key = "j",
        select_key = "<CR>",
        toggle_pin_key = "T",
    },
    show_icons = true,
    highlights = {
        label = { link = "DiagnosticWarn", bold = true },
        pinned = { link = "DiagnosticOk" },
        flags = { link = "Comment" },
        alternate = { fg = "#ff8800", bold = true },
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
- `gg/G`, `V`, `dd/d/D`, `c/C`, `w/W`, `r/R`, and `s/v/t` are reserved from labels to avoid conflicts.
- In `s/v/t` mode, `<Esc>` cancels mode first; press `<Esc>` again to close picker.
- With `alternate_without_label = true`, the alternate entry has no label and is opened with `<Tab>`.
- Set `fuzzy_key = false` or `alternate_key = false` to disable those picker shortcuts.
- `fuzzy_backend = "auto"` tries backends in order: Snacks -> Telescope -> fzf-lua.
- Set `fuzzy_backend` to `"snacks"`, `"telescope"`, or `"fzf"` to force one backend.
- Set `fuzzy_backend = "custom"` and provide `fuzzy_open = function(size) ... end` to integrate any picker.
- `picker.*` keys are conflict-safe: they are automatically reserved from label characters.
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
        alternate = { link = "DiagnosticWarn", bold = true },
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

Example custom fuzzy backend:

```lua
require("quickbuf").setup({
    fuzzy_backend = "custom",
    fuzzy_open = function(size)
        require("mini.pick").builtin.buffers({
            window = {
                config = {
                    width = size.width_cols,
                    height = size.height_rows,
                },
            },
        })
    end,
})
```

## License

MIT. See `LICENSE`.
