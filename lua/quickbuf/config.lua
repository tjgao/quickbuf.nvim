local M = {}

M.defaults = {
    include_special = false,
    auto_jump_single = false,
    isolate_keymaps = true,
    fuzzy_key = "/",
    fuzzy_backend = "auto",
    fuzzy_open = nil,
    alternate_key = "<Tab>",
    alternate_key_display = "",
    alternate_without_label = true,
    label_before_name = true,
    picker = {
        move_up_key = "k",
        move_down_key = "j",
        select_key = "<CR>",
        toggle_pin_key = "T",
    },
    show_icons = true,
    persistence = {
        enabled = false,
        debounce_ms = 1000,
    },
    highlights = {
        label = { fg = "#ff8800", bold = true },
        pinned = { link = "DiagnosticOk", bold = true },
        flags = { link = "Comment" },
        alternate = { fg = "#ff8800", bold = true },
        filename = { link = "Normal" },
        path = { link = "Comment" },
        muted = { link = "Comment" },
        cursorline = { link = "Visual" },
        footer_svt = { link = "DiagnosticWarn" },
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
}

M.values = vim.deepcopy(M.defaults)

function M.setup(opts)
    M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
