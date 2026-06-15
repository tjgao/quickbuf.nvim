local config = require("quickbuf.config")

local ns = vim.api.nvim_create_namespace("QuickBufPicker")

local ok_devicons, devicons = pcall(require, "nvim-web-devicons")

local M = {
    win = nil,
    buf = nil,
    help_win = nil,
    help_buf = nil,
}

local function picker_winhighlight(footer_group)
    return "Normal:QuickBufFilename,NormalNC:QuickBufFilename,NormalFloat:QuickBufFilename,FloatBorder:QuickBufFilename,FloatTitle:QuickBufFilename,FloatFooter:"
        .. footer_group
        .. ",CursorLine:QuickBufCursorLine"
end

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

local function buffer_line_number(bufnr)
    local info = vim.fn.getbufinfo(bufnr)
    if type(info) == "table" and info[1] and type(info[1].lnum) == "number" and info[1].lnum > 0 then
        return info[1].lnum
    end
    return nil
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

    local pin_mark = item.pinned and " P " or "   "
    add(pin_mark, item.pinned and "QuickBufPinned" or "QuickBufMuted")

    local flags = item.flags or ""
    if flags ~= "" then
        add(pad_right(flags, 3), "QuickBufFlags")
    else
        add("   ", "QuickBufMuted")
    end

    add(" ")

    local label_text = label ~= "" and label or " "
    local label_hl = label ~= "" and "QuickBufLabel" or "QuickBufMuted"
    if item.alternate then
        local alt_display = config.values.alternate_key_display
        if type(alt_display) == "string" and alt_display ~= "" then
            label_text = alt_display
        else
            label_text = "#"
        end
        label_hl = "QuickBufAlternate"
    end
    local label_cell = pad_right(label_text, 2)
    local icon, icon_hl = icon_for_item(item)

    if config.values.label_before_name then
        add(label_cell, label_hl)
        add(" ")
        if icon ~= "" then
            add(icon, icon_hl)
            add(" ")
        end
        add(item.filename, "QuickBufFilename")
    else
        if icon ~= "" then
            add(icon, icon_hl)
            add(" ")
        end
        add(item.filename, "QuickBufFilename")
        add(" ")
        add(label_cell, label_hl)
    end

    if item.dirname ~= "" then
        add(" ")
        add(item.dirname, "QuickBufPath")
    end

    local lnum = buffer_line_number(item.bufnr)
    if lnum then
        if item.dirname == "" then
            add(" ")
        end
        add(":" .. tostring(lnum), "QuickBufFilename")
    end

    return table.concat(segments), highlights
end

local function apply_highlights(all_highlights)
    vim.api.nvim_buf_clear_namespace(M.buf, ns, 0, -1)
    for line_idx, line_highlights in ipairs(all_highlights) do
        for _, part in ipairs(line_highlights) do
            vim.api.nvim_buf_set_extmark(M.buf, ns, line_idx - 1, part.start_col, {
                end_row = line_idx - 1,
                end_col = part.end_col,
                hl_group = part.hl,
            })
        end
    end
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

function M.get_win()
    return M.win
end

function M.get_buf()
    return M.buf
end

function M.is_win_valid()
    return M.win and vim.api.nvim_win_is_valid(M.win)
end

function M.set_cursor(row, col)
    if not M.is_win_valid() then
        return
    end
    vim.api.nvim_win_set_cursor(M.win, { row, col or 0 })
end

function M.render(lines, all_highlights)
    if not M.buf or not vim.api.nvim_buf_is_valid(M.buf) then
        return
    end
    vim.bo[M.buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.buf, 0, -1, false, lines)
    apply_highlights(all_highlights)
    vim.bo[M.buf].modifiable = false
end

function M.set_footer(text)
    if not M.is_win_valid() then
        return
    end

    local cfg = vim.api.nvim_win_get_config(M.win)
    cfg.footer = text
    cfg.footer_pos = "center"
    pcall(vim.api.nvim_win_set_config, M.win, cfg)
end

function M.set_footer_highlight(group)
    if not M.is_win_valid() then
        return
    end

    local footer_group = group
    if type(footer_group) ~= "string" or footer_group == "" then
        footer_group = "QuickBufFilename"
    end
    vim.wo[M.win].winhighlight = picker_winhighlight(footer_group)
end

function M.build_lines(items, labels_for_items, hidden_count)
    local vertical_padding =
        math.max(0, math.floor((config.values.window and config.values.window.vertical_padding) or 0))
    local lines = {}
    local all_highlights = {}

    for _ = 1, vertical_padding do
        lines[#lines + 1] = ""
        all_highlights[#all_highlights + 1] = {}
    end

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

    for _ = 1, vertical_padding do
        lines[#lines + 1] = ""
        all_highlights[#all_highlights + 1] = {}
    end

    return lines, all_highlights, vertical_padding
end

function M.close()
    if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
        vim.api.nvim_win_close(M.help_win, true)
    end
    M.help_win = nil
    M.help_buf = nil

    if M.win and vim.api.nvim_win_is_valid(M.win) then
        vim.api.nvim_win_close(M.win, true)
    end
    M.win = nil
    M.buf = nil
end

function M.open_help_popup(lines)
    if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
        vim.api.nvim_win_close(M.help_win, true)
    end

    local horizontal_padding = 2
    local vertical_padding = 1

    local max_line_width = 0
    for _, line in ipairs(lines) do
        local width = str_width(line)
        if width > max_line_width then
            max_line_width = width
        end
    end

    local width = math.min(math.max(max_line_width + horizontal_padding * 2, 52), math.max(1, vim.o.columns - 8))
    local height = math.min(#lines + vertical_padding * 2, math.max(1, vim.o.lines - 8))

    local padded_lines = {}
    for _ = 1, vertical_padding do
        padded_lines[#padded_lines + 1] = ""
    end
    for _, line in ipairs(lines) do
        padded_lines[#padded_lines + 1] = string.rep(" ", horizontal_padding) .. line
    end
    for _ = 1, vertical_padding do
        padded_lines[#padded_lines + 1] = ""
    end

    M.help_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[M.help_buf].bufhidden = "wipe"
    vim.bo[M.help_buf].filetype = "quickbufhelp"
    vim.bo[M.help_buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.help_buf, 0, -1, false, padded_lines)
    vim.bo[M.help_buf].modifiable = false

    local row = math.max(0, math.floor((vim.o.lines - height) / 2 - 1))
    local col = math.max(0, math.floor((vim.o.columns - width) / 2))

    M.help_win = vim.api.nvim_open_win(M.help_buf, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        border = "rounded",
        style = "minimal",
        noautocmd = true,
        focusable = true,
        zindex = 250,
        title = " QuickBuf Help ",
        title_pos = "center",
    })

    vim.wo[M.help_win].number = false
    vim.wo[M.help_win].relativenumber = false
    vim.wo[M.help_win].cursorline = false
    vim.wo[M.help_win].signcolumn = "no"
    vim.wo[M.help_win].wrap = false
    vim.wo[M.help_win].winhighlight =
        "Normal:QuickBufFilename,NormalNC:QuickBufFilename,NormalFloat:QuickBufFilename,FloatBorder:QuickBufFilename,FloatTitle:QuickBufFilename"

    vim.keymap.set("n", "q", function()
        if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
            vim.api.nvim_win_close(M.help_win, true)
        end
        M.help_win = nil
        M.help_buf = nil
    end, { buffer = M.help_buf, nowait = true, silent = true })

    vim.keymap.set("n", "<Esc>", function()
        if M.help_win and vim.api.nvim_win_is_valid(M.help_win) then
            vim.api.nvim_win_close(M.help_win, true)
        end
        M.help_win = nil
        M.help_buf = nil
    end, { buffer = M.help_buf, nowait = true, silent = true })
end

function M.open_picker(lines, all_highlights, meta)
    M.close()

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

    local max_line_width = 0
    for _, line in ipairs(lines) do
        local width = str_width(line)
        if width > max_line_width then
            max_line_width = width
        end
    end

    local content_width = math.max(min_width, math.min(max_width, max_line_width + cfg.padding * 2))
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
    M.render(lines, all_highlights)

    local footer = meta and meta.footer or " ? [help]  q [quit] "

    M.win = vim.api.nvim_open_win(M.buf, true, {
        relative = "editor",
        row = math.floor((vim.o.lines - height) / 2 - 1),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        border = cfg.border,
        style = "minimal",
        noautocmd = true,
        title = string.format(" %s (%d) ", meta and meta.title or "QuickBuf", meta and meta.total_count or #lines),
        title_pos = "center",
        footer = footer,
        footer_pos = "center",
    })

    vim.wo[M.win].number = false
    vim.wo[M.win].relativenumber = false
    vim.wo[M.win].cursorline = true
    vim.wo[M.win].winhighlight = picker_winhighlight("QuickBufFilename")
    vim.wo[M.win].signcolumn = "no"
    vim.wo[M.win].wrap = false
    vim.api.nvim_win_set_cursor(M.win, { 1, 0 })
end

return M
