local M = {}

M.defaults = {
    picker = {
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
        move_up_key = "k",
        move_down_key = "j",
        select_key = "<CR>",
        toggle_pin_key = "T",
        show_icons = true,
        pin_display = "P",
    },
    persistence = {
        enabled = false,
        debounce_ms = 5000,
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

local legacy_picker_keys = {
    "include_special",
    "auto_jump_single",
    "isolate_keymaps",
    "fuzzy_key",
    "fuzzy_backend",
    "fuzzy_open",
    "alternate_key",
    "alternate_key_display",
    "alternate_without_label",
    "label_before_name",
    "show_icons",
    "pin_display",
}

local function normalize_opts(opts)
    if type(opts) ~= "table" then
        return {}
    end

    local out = vim.deepcopy(opts)
    out.picker = out.picker or {}
    for _, key in ipairs(legacy_picker_keys) do
        if out[key] ~= nil then
            if out.picker[key] == nil then
                out.picker[key] = out[key]
            end
            out[key] = nil
        end
    end

    return out
end

function M.setup(opts)
    local normalized = normalize_opts(opts)
    M.values = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), normalized)
end

return M
