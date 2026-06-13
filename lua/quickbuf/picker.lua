local config = require("quickbuf.config")
local labels = require("quickbuf.labels")
local rank = require("quickbuf.rank")
local state = require("quickbuf.state")

local ns = vim.api.nvim_create_namespace("QuickBufPicker")

local ok_devicons, devicons = pcall(require, "nvim-web-devicons")

local M = {
    win = nil,
    buf = nil,
}

local function str_width(s)
    return vim.fn.strdisplaywidth(s)
end

local function pad_right(s, width)
    local missing = width - str_width(s)
    if missing <= 0 then
        return s
    end
    return s .. string.rep(" ", missing)
end

local function icon_for_item(item)
    if not config.values.show_icons then
        return "", nil
    end

    if ok_devicons and item.path ~= "" then
        local ext = vim.fn.fnamemodify(item.path, ":e")
        local icon, hl = devicons.get_icon(item.filename, ext, { default = true })
        return icon or "", hl
    end

    return "", nil
end

local function open_fuzzy_buffers()
    local ok_snacks, snacks = pcall(require, "snacks")
    if ok_snacks and snacks and snacks.picker and type(snacks.picker.buffers) == "function" then
        snacks.picker.buffers()
        return
    end

    local ok_telescope, telescope = pcall(require, "telescope.builtin")
    if ok_telescope and telescope and type(telescope.buffers) == "function" then
        telescope.buffers()
        return
    end

    local ok_fzf, fzf = pcall(require, "fzf-lua")
    if ok_fzf and fzf and type(fzf.buffers) == "function" then
        fzf.buffers()
        return
    end

    vim.notify("quickbuf: no fuzzy buffer picker found", vim.log.levels.WARN)
end

local function close()
    if M.win and vim.api.nvim_win_is_valid(M.win) then
        vim.api.nvim_win_close(M.win, true)
    end
    M.win = nil
    M.buf = nil
end

local function format_line(item, label)
    local segments = {}
    local highlights = {}
    local byte_col = 0

    local function add(text, hl)
        if text == "" then
            return
        end
        segments[#segments + 1] = text
        if hl then
            highlights[#highlights + 1] = {
                hl = hl,
                start_col = byte_col,
                end_col = byte_col + #text,
            }
        end
        byte_col = byte_col + #text
    end

    if item.pinned then
        add(" P", "QuickBufPinned")
    else
        add("  ")
    end

    add(" ")

    local icon, icon_hl = icon_for_item(item)
    if icon ~= "" then
        add(icon, icon_hl)
        add(" ")
    end

    add(item.filename, "QuickBufFilename")

    add(" ")
    local label_cell = pad_right(label ~= "" and label or " ", 2)
    add(label_cell, label ~= "" and "QuickBufLabel" or "QuickBufMuted")

    if item.alternate then
        add("#", "QuickBufAlternate")
    end

    if item.dirname ~= "" then
        add(" ")
        add(item.dirname, "QuickBufPath")
    end

    return table.concat(segments), highlights
end

local function apply_highlights(all_highlights)
    vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)
    for line_idx, line_highlights in ipairs(all_highlights) do
        for _, item in ipairs(line_highlights) do
            vim.api.nvim_buf_set_extmark(M.buf, ns, line_idx - 1, item.start_col, {
                end_row = line_idx - 1,
                end_col = item.end_col,
                hl_group = item.hl,
            })
        end
    end
end

local function render_lines(lines, all_highlights)
    vim.bo[M.buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
    apply_highlights(all_highlights)
    vim.bo[M.buf].modifiable = false
end

local function resolve_size(value, total, fallback)
    if type(value) ~= "number" then
        return fallback
    end
    if value > 0 and value <= 1 then
        return math.max(1, math.floor(total * value))
    end
    if value > 1 then
        return math.floor(value)
    end
    return fallback
end

local function open_window(lines, all_highlights)
    close()

    local cfg = config.values.window
    local max_columns = math.max(1, vim.o.columns - 2)
    local max_rows = math.max(1, vim.o.lines - 4)
    local min_width = resolve_size(cfg.min_width, vim.o.columns, 1)
    local max_width = resolve_size(cfg.max_width, vim.o.columns, max_columns)
    min_width = math.max(1, math.min(min_width, max_columns))
    max_width = math.max(1, math.min(max_width, max_columns))
    if min_width > max_width then
        min_width, max_width = max_width, min_width
    end

    local max_line = 0
    for _, line in ipairs(lines) do
        local width = str_width(line)
        if width > max_line then
            max_line = width
        end
    end

    local content_width = math.max(min_width, math.min(max_width, max_line + cfg.padding * 2))
    local width = resolve_size(cfg.width, vim.o.columns, content_width)
    width = math.max(min_width, math.min(max_width, width))
    width = math.min(width, max_columns)

    local content_height = #lines
    local height = resolve_size(cfg.height, vim.o.lines - 2, content_height)
    height = math.max(content_height, height)
    height = math.min(height, max_rows)

    M.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.buf].bufhidden = "wipe"
    vim.bo[M.buf].filetype = "quickbuf"
    render_lines(lines, all_highlights)

    M.win = vim.api.nvim_open_win(M.buf, true, {
        relative = "editor",
        row = math.floor((vim.o.lines - height) / 2 - 1),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        border = cfg.border,
        style = "minimal",
        noautocmd = true,
    })

    vim.wo[M.win].number = false
    vim.wo[M.win].relativenumber = false
    vim.wo[M.win].cursorline = true
    vim.wo[M.win].winhighlight = "CursorLine:QuickBufCursorLine"
    vim.wo[M.win].signcolumn = "no"
    vim.wo[M.win].wrap = false
    vim.api.nvim_win_set_cursor(M.win, { 1, 0 })
end

local function build_lines(items, labels_for_items, hidden_count)
    local lines = {}
    local all_highlights = {}
    for i, item in ipairs(items) do
        local line, line_highlights = format_line(item, labels_for_items[i])
        lines[#lines + 1] = line
        all_highlights[#all_highlights + 1] = line_highlights
    end
    if hidden_count and hidden_count > 0 then
        lines[#lines + 1] = string.format(" ..  +%d more", hidden_count)
        all_highlights[#all_highlights + 1] = {
            {
                hl = "QuickBufMuted",
                start_col = 0,
                end_col = #lines[#lines],
            },
        }
    end

    return lines, all_highlights
end

local function apply_keymaps(items, labels_for_items, ctx)
    local function pick(bufnr)
        close()
        if vim.api.nvim_buf_is_valid(bufnr) then
            vim.api.nvim_set_current_buf(bufnr)
        end
    end

    local function get_selected_index()
        if not M.win or not vim.api.nvim_win_is_valid(M.win) then
            return nil
        end
        local row = vim.api.nvim_win_get_cursor(M.win)[1]
        if row < 1 or row > #items then
            return nil
        end
        return row
    end

    local function move_cursor(delta)
        local idx = get_selected_index() or 1
        local next_idx = idx + delta
        if next_idx < 1 then
            next_idx = 1
        elseif next_idx > #items then
            next_idx = #items
        end
        vim.api.nvim_win_set_cursor(M.win, { next_idx, 0 })
    end

    local function pick_current()
        local idx = get_selected_index()
        if not idx then
            return
        end
        pick(items[idx].bufnr)
    end

    local function toggle_current_pin()
        local idx = get_selected_index()
        if not idx then
            return
        end
        local item = items[idx]
        item.pinned = state.toggle_pin(item.bufnr)
        local lines, all_highlights = build_lines(items, labels_for_items, ctx.hidden_count)
        render_lines(lines, all_highlights)
        vim.api.nvim_win_set_cursor(M.win, { idx, 0 })
    end

    vim.keymap.set("n", "<Esc>", close, { buffer = M.buf, nowait = true, silent = true })
    vim.keymap.set("n", "q", close, { buffer = M.buf, nowait = true, silent = true })

    if config.values.fuzzy_key and config.values.fuzzy_key ~= "" then
        vim.keymap.set("n", config.values.fuzzy_key, function()
            close()
            open_fuzzy_buffers()
        end, { buffer = M.buf, nowait = true, silent = true })
    end

    if config.values.alternate_key and config.values.alternate_key ~= "" then
        vim.keymap.set("n", config.values.alternate_key, function()
            local alternate = ctx and ctx.alternate_bufnr or -1
            if
                alternate > 0
                and alternate ~= (ctx and ctx.source_bufnr or -1)
                and vim.api.nvim_buf_is_valid(alternate)
                and vim.bo[alternate].buflisted
            then
                pick(alternate)
            else
                vim.notify("quickbuf: no alternate buffer", vim.log.levels.INFO)
            end
        end, { buffer = M.buf, nowait = true, silent = true })
    end

    local picker_keys = config.values.picker or {}
    if picker_keys.move_up_key and picker_keys.move_up_key ~= "" then
        vim.keymap.set("n", picker_keys.move_up_key, function()
            move_cursor(-1)
        end, { buffer = M.buf, nowait = true, silent = true })
    end
    if picker_keys.move_down_key and picker_keys.move_down_key ~= "" then
        vim.keymap.set("n", picker_keys.move_down_key, function()
            move_cursor(1)
        end, { buffer = M.buf, nowait = true, silent = true })
    end
    if picker_keys.select_key and picker_keys.select_key ~= "" then
        vim.keymap.set("n", picker_keys.select_key, pick_current, { buffer = M.buf, nowait = true, silent = true })
    end
    if picker_keys.toggle_pin_key and picker_keys.toggle_pin_key ~= "" then
        vim.keymap.set(
            "n",
            picker_keys.toggle_pin_key,
            toggle_current_pin,
            { buffer = M.buf, nowait = true, silent = true }
        )
    end

    for i, item in ipairs(items) do
        local label = labels_for_items[i]
        if label and label ~= "" then
            vim.keymap.set("n", label, function()
                pick(item.bufnr)
            end, { buffer = M.buf, nowait = true, silent = true })
        end
    end
end

function M.open(opts)
    opts = opts or {}
    local source_bufnr = vim.api.nvim_get_current_buf()
    local alternate_bufnr = vim.fn.bufnr("#")
    local items = rank.candidates({ include_special = config.values.include_special })

    if opts.pinned_only then
        local pinned = {}
        for _, item in ipairs(items) do
            if item.pinned then
                pinned[#pinned + 1] = item
            end
        end
        items = pinned
    end

    if #items == 0 then
        vim.notify("quickbuf: no matching buffers", vim.log.levels.INFO)
        return
    end

    if config.values.auto_jump_single and #items == 1 then
        vim.api.nvim_set_current_buf(items[1].bufnr)
        return
    end

    local limit = math.max(1, config.values.max_items)
    local shown = {}
    for i = 1, math.min(#items, limit) do
        shown[#shown + 1] = items[i]
    end

    local charset = labels.charset_from_string(config.values.labels)
    local labels_needed = 0
    local labels_for_items = {}
    for i, item in ipairs(shown) do
        if
            not (
                config.values.alternate_without_label
                and item.alternate
                and config.values.alternate_key
                and config.values.alternate_key ~= ""
            )
        then
            labels_needed = labels_needed + 1
            labels_for_items[i] = true
        else
            labels_for_items[i] = ""
        end
    end

    local generated_labels = labels.generate(labels_needed, charset)
    local gen_idx = 1
    for i, v in ipairs(labels_for_items) do
        if v == true then
            labels_for_items[i] = generated_labels[gen_idx]
            gen_idx = gen_idx + 1
        end
    end

    local hidden_count = #items - #shown
    local lines, all_highlights = build_lines(shown, labels_for_items, hidden_count)

    open_window(lines, all_highlights)
    apply_keymaps(shown, labels_for_items, {
        source_bufnr = source_bufnr,
        alternate_bufnr = alternate_bufnr,
        hidden_count = hidden_count,
    })
end

return M
