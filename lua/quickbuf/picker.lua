local actions = require("quickbuf.picker_actions")
local config = require("quickbuf.config")
local fuzzy = require("quickbuf.picker_fuzzy")
local labels = require("quickbuf.labels")
local rank = require("quickbuf.rank")
local state = require("quickbuf.state")
local ui = require("quickbuf.picker_ui")

local M = {}

local VISUAL_SELECT_KEY = "V"
local DELETE_KEY = "d"
local FORCE_DELETE_KEY = "D"
local CLEAR_UNPINNED_KEY = "c"
local FORCE_CLEAR_UNPINNED_KEY = "C"
local WRITE_KEY = "w"
local WRITE_ALL_KEY = "W"
local RELOAD_KEY = "r"
local RELOAD_ALL_KEY = "R"
local FIRST_ITEM_KEY = "gg"
local LAST_ITEM_KEY = "G"
local OPEN_SPLIT_PREFIX_KEY = "s"
local OPEN_VSPLIT_PREFIX_KEY = "v"
local OPEN_TAB_PREFIX_KEY = "t"

local function is_single_key(key)
    return type(key) == "string" and #key == 1
end

local function effective_charset()
    local reserved = {
        q = true,
        g = true,
        G = true,
        [VISUAL_SELECT_KEY] = true,
        [DELETE_KEY] = true,
        [FORCE_DELETE_KEY] = true,
        [CLEAR_UNPINNED_KEY] = true,
        [FORCE_CLEAR_UNPINNED_KEY] = true,
        [WRITE_KEY] = true,
        [WRITE_ALL_KEY] = true,
        [RELOAD_KEY] = true,
        [RELOAD_ALL_KEY] = true,
        [OPEN_SPLIT_PREFIX_KEY] = true,
        [OPEN_VSPLIT_PREFIX_KEY] = true,
        [OPEN_TAB_PREFIX_KEY] = true,
    }

    if is_single_key(config.values.fuzzy_key) then
        reserved[config.values.fuzzy_key] = true
    end
    if is_single_key(config.values.alternate_key) then
        reserved[config.values.alternate_key] = true
    end

    local picker_keys = config.values.picker or {}
    if is_single_key(picker_keys.move_up_key) then
        reserved[picker_keys.move_up_key] = true
    end
    if is_single_key(picker_keys.move_down_key) then
        reserved[picker_keys.move_down_key] = true
    end
    if is_single_key(picker_keys.select_key) then
        reserved[picker_keys.select_key] = true
    end
    if is_single_key(picker_keys.toggle_pin_key) then
        reserved[picker_keys.toggle_pin_key] = true
    end
    local out = {}
    for _, ch in ipairs(labels.default_charset()) do
        if not reserved[ch] then
            out[#out + 1] = ch
        end
    end

    return out
end

local function max_visible_items(total_items, label_limit)
    if total_items <= 0 or label_limit <= 0 then
        return 0
    end

    local max_rows = math.max(1, vim.o.lines - 4)
    local vertical_padding =
        math.max(0, math.floor((config.values.window and config.values.window.vertical_padding) or 0))
    local cap = math.min(total_items, label_limit)

    for shown = cap, 1, -1 do
        local hidden_count = total_items - shown
        local line_count = shown + (vertical_padding * 2) + (hidden_count > 0 and 1 or 0)
        if line_count <= max_rows then
            return shown
        end
    end

    return 1
end

local function fuzzy_height_fallback()
    local items = rank.candidates({ include_special = config.values.include_special })
    local charset = effective_charset()
    local shown_count = max_visible_items(#items, #charset)
    local hidden_count = math.max(0, #items - shown_count)
    local vertical_padding =
        math.max(0, math.floor((config.values.window and config.values.window.vertical_padding) or 0))

    local content_height = shown_count + (vertical_padding * 2)
    if hidden_count > 0 then
        content_height = content_height + 1
    end

    return math.max(1, content_height)
end

local function apply_keymaps(items, labels_for_items, ctx)
    local function help_lines()
        local picker_keys = config.values.picker or {}
        local up = picker_keys.move_up_key or "k"
        local down = picker_keys.move_down_key or "j"
        local select = picker_keys.select_key or "<CR>"
        local toggle_pin = picker_keys.toggle_pin_key or "T"
        local fuzzy_key = config.values.fuzzy_key or "/"
        local alternate = config.values.alternate_key or "<Tab>"

        local lines = {
            "[Navigation]",
            string.format("- %s/%s move up/down", up, down),
            string.format("- %s open current", select),
            "- gg/G first/last",
            string.format("- %s alternate buffer", alternate),
            "",
            "[Selection & Actions]",
            "- V enter linewise visual selection",
            "- dd current delete (safe)",
            "- d visual delete (safe)",
            "- D delete current-or-selection (force)",
            "- c/C clear unpinned (safe/force)",
            "- w/W write current-or-selection/all",
            "- r/R reload modified current-or-selection/all",
            "- s/v/t + label open in split/vsplit/tab",
            string.format("- %s toggle pinned/unpinned", toggle_pin),
            "",
            "[Other]",
            string.format("- %s fuzzy fallback", fuzzy_key),
            "- <Esc> cancel svt mode, then close",
            "- q close",
            "- ? this help",
        }

        return lines
    end

    local function refresh_after_action(cursor_row)
        local next_opts = vim.tbl_extend("force", {}, ctx.open_opts or {})
        next_opts.cursor_row = cursor_row
        ui.close()
        M.open(next_opts)
    end

    local function pick(bufnr, open_mode)
        ui.close()
        if vim.api.nvim_buf_is_valid(bufnr) then
            if open_mode == "split" then
                vim.cmd("sbuffer " .. bufnr)
            elseif open_mode == "vsplit" then
                vim.cmd("vert sbuffer " .. bufnr)
            elseif open_mode == "tab" then
                vim.cmd("tab sbuffer " .. bufnr)
            else
                vim.api.nvim_set_current_buf(bufnr)
            end
        end
    end

    local function get_selected_index()
        local win = ui.get_win()
        if not win or not vim.api.nvim_win_is_valid(win) then
            return nil
        end
        local row = vim.api.nvim_win_get_cursor(win)[1] - (ctx.line_offset or 0)
        if row < 1 or row > #items then
            return nil
        end
        return row
    end

    local function refresh_visible_flags()
        local alternate = (ctx and ctx.alternate_bufnr) or vim.fn.bufnr("#")
        local cursor_row = get_selected_index() or 1

        for _, item in ipairs(items) do
            if vim.api.nvim_buf_is_valid(item.bufnr) then
                item.flags = rank.buffer_flags(item.bufnr, item.bufnr == alternate)
            end
        end

        local lines, all_highlights, line_offset = ui.build_lines(items, labels_for_items, ctx.hidden_count or 0)
        ctx.line_offset = line_offset
        ui.render(lines, all_highlights)

        if ui.is_win_valid() and #items > 0 then
            cursor_row = math.max(1, math.min(cursor_row, #items))
            ui.set_cursor(line_offset + cursor_row, 0)
        end
    end

    local function move_cursor(delta)
        if #items == 0 then
            return
        end
        local idx = get_selected_index() or 1
        local next_idx = idx + delta
        if next_idx < 1 then
            next_idx = 1
        elseif next_idx > #items then
            next_idx = #items
        end
        ui.set_cursor((ctx.line_offset or 0) + next_idx, 0)
    end

    local consume_pending_open_mode

    local function pick_current()
        local idx = get_selected_index()
        if not idx then
            return
        end
        pick(items[idx].bufnr, consume_pending_open_mode())
    end

    local function toggle_current_pin()
        local idx = get_selected_index()
        if not idx then
            return
        end
        local item = items[idx]
        item.pinned = state.toggle_pin(item.bufnr)
        refresh_after_action(idx)
    end

    local function visual_targets()
        local mode = vim.fn.mode()
        local start_row
        local end_row

        if mode == "v" or mode == "V" or mode == "\22" then
            start_row = vim.fn.line("v") - (ctx.line_offset or 0)
            end_row = vim.fn.line(".") - (ctx.line_offset or 0)
        else
            start_row = vim.fn.getpos("'<")[2] - (ctx.line_offset or 0)
            end_row = vim.fn.getpos("'>")[2] - (ctx.line_offset or 0)
        end

        if start_row <= 0 or end_row <= 0 then
            return {}
        end
        if start_row > end_row then
            start_row, end_row = end_row, start_row
        end

        start_row = math.max(1, math.min(start_row, #items))
        end_row = math.max(1, math.min(end_row, #items))

        local out = {}
        local seen = {}
        for row = start_row, end_row do
            local bufnr = items[row].bufnr
            if not seen[bufnr] then
                out[#out + 1] = bufnr
                seen[bufnr] = true
            end
        end

        return out
    end

    local function toggle_selected_or_current_pin(prefer_visual)
        local targets = prefer_visual and visual_targets() or {}
        if #targets == 0 then
            local idx = get_selected_index()
            if idx then
                targets[1] = items[idx].bufnr
            end
        end
        if #targets == 0 then
            return
        end

        for _, bufnr in ipairs(targets) do
            state.toggle_pin(bufnr)
        end

        local idx = get_selected_index() or 1
        refresh_after_action(idx)
    end

    local function delete_selected_or_current(prefer_visual, force)
        local preferred_row = get_selected_index() or 1
        local targets = prefer_visual and visual_targets() or {}
        if prefer_visual and #targets > 0 then
            local a = vim.fn.line("v")
            local b = vim.fn.line(".")
            if a > 0 and b > 0 then
                preferred_row = math.min(a, b)
            end
        end

        if #targets == 0 then
            local idx = get_selected_index()
            if idx then
                targets[1] = items[idx].bufnr
                preferred_row = idx
            end
        end
        if #targets == 0 then
            return
        end

        local deleted, failed = actions.delete_buffers(targets, force)
        refresh_after_action(preferred_row)
        actions.notify_delete_failures("deleted", deleted, failed)
    end

    local function clear_unpinned_buffers(force)
        local targets = {}
        for _, item in ipairs(ctx.all_items or {}) do
            if not item.pinned then
                targets[#targets + 1] = item.bufnr
            end
        end

        if #targets == 0 then
            vim.notify("quickbuf: no unpinned buffers to clear", vim.log.levels.INFO)
            return
        end

        local deleted, failed = actions.delete_buffers(targets, force)
        local idx = get_selected_index() or 1
        refresh_after_action(idx)
        actions.notify_delete_failures("cleared", deleted, failed)
    end

    local function write_selected_or_current(prefer_visual)
        local targets = prefer_visual and visual_targets() or {}
        if #targets == 0 then
            local idx = get_selected_index()
            if idx then
                targets[1] = items[idx].bufnr
            end
        end
        if #targets == 0 then
            return
        end

        local written, failed = actions.write_buffers(targets)
        if failed > 0 then
            vim.notify(string.format("quickbuf: written %d, failed %d", written, failed), vim.log.levels.WARN)
        end
        if written > 0 then
            refresh_visible_flags()
        end
    end

    local function write_all_listed_buffers()
        local targets = {}
        local seen = {}
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if
                vim.api.nvim_buf_is_valid(bufnr)
                and vim.bo[bufnr].buflisted
                and vim.bo[bufnr].buftype == ""
                and not seen[bufnr]
            then
                targets[#targets + 1] = bufnr
                seen[bufnr] = true
            end
        end

        local written, failed = actions.write_buffers(targets)
        if failed > 0 then
            vim.notify(string.format("quickbuf: written %d, failed %d", written, failed), vim.log.levels.WARN)
        end
        if written > 0 then
            refresh_visible_flags()
        end
    end

    local function reload_selected_or_current(prefer_visual)
        local targets = prefer_visual and visual_targets() or {}
        if #targets == 0 then
            local idx = get_selected_index()
            if idx then
                targets[1] = items[idx].bufnr
            end
        end
        if #targets == 0 then
            return
        end

        local reloaded, failed = actions.reload_buffers(targets)
        if failed > 0 then
            vim.notify(string.format("quickbuf: reloaded %d, failed %d", reloaded, failed), vim.log.levels.WARN)
        end
        if reloaded > 0 then
            local idx = get_selected_index() or 1
            refresh_after_action(idx)
        end
    end

    local function reload_all_listed_buffers()
        local targets = {}
        local seen = {}
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if
                vim.api.nvim_buf_is_valid(bufnr)
                and vim.bo[bufnr].buflisted
                and vim.bo[bufnr].buftype == ""
                and not seen[bufnr]
            then
                targets[#targets + 1] = bufnr
                seen[bufnr] = true
            end
        end

        local reloaded, failed = actions.reload_buffers(targets)
        if failed > 0 then
            vim.notify(string.format("quickbuf: reloaded %d, failed %d", reloaded, failed), vim.log.levels.WARN)
        end
        if reloaded > 0 then
            local idx = get_selected_index() or 1
            refresh_after_action(idx)
        end
    end

    local function swallow_all_normal_keys()
        if not config.values.isolate_keymaps then
            return
        end

        local map_buf = ui.get_buf()
        local swallow = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789`-=[]\\;',./"
        for i = 1, #swallow do
            vim.keymap.set("n", swallow:sub(i, i), "<Nop>", { buffer = map_buf, nowait = true, silent = true })
        end

        for code = string.byte("a"), string.byte("z") do
            local ch = string.char(code)
            vim.keymap.set("n", "<C-" .. ch .. ">", "<Nop>", { buffer = map_buf, nowait = true, silent = true })
        end

        local special_keys = {
            "<Tab>",
            "<S-Tab>",
            "<CR>",
            "<BS>",
            "<Del>",
            "<Home>",
            "<End>",
            "<PageUp>",
            "<PageDown>",
            "<Up>",
            "<Down>",
            "<Left>",
            "<Right>",
        }
        for _, key in ipairs(special_keys) do
            vim.keymap.set("n", key, "<Nop>", { buffer = map_buf, nowait = true, silent = true })
        end
    end

    swallow_all_normal_keys()

    local picker_keys = config.values.picker or {}
    local map_buf = ui.get_buf()
    local focus_refresh_armed = false
    local pending_open_mode = nil

    local function pending_open_message()
        if pending_open_mode == "split" then
            return " Current Mode: Split (ESC to cancel)"
        end
        if pending_open_mode == "vsplit" then
            return " Current Mode: VSplit (ESC to cancel)"
        end
        if pending_open_mode == "tab" then
            return " Current Mode: Tab (ESC to cancel)"
        end
        return nil
    end

    local function refresh_footer()
        local pending = pending_open_message()
        if pending then
            ui.set_footer_highlight("QuickBufFooterSvt")
            ui.set_footer(pending)
            return
        end
        ui.set_footer_highlight("QuickBufFilename")
        ui.set_footer(ctx.footer or " ? [help]  q [quit] ")
    end

    local function set_pending_open_mode(mode)
        if pending_open_mode == mode then
            pending_open_mode = nil
        else
            pending_open_mode = mode
        end
        refresh_footer()
    end

    consume_pending_open_mode = function()
        local mode = pending_open_mode
        pending_open_mode = nil
        refresh_footer()
        return mode
    end

    local function close_or_cancel_pending_mode()
        if pending_open_mode then
            pending_open_mode = nil
            refresh_footer()
            return
        end
        ui.close()
    end

    vim.keymap.set("n", "<Esc>", close_or_cancel_pending_mode, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", "q", ui.close, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", FIRST_ITEM_KEY, function()
        ui.set_cursor((ctx.line_offset or 0) + 1, 0)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", "?", function()
        ui.open_help_popup(help_lines())
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", LAST_ITEM_KEY, function()
        if #items == 0 then
            ui.set_cursor((ctx.line_offset or 0) + 1, 0)
            return
        end
        ui.set_cursor((ctx.line_offset or 0) + #items, 0)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", VISUAL_SELECT_KEY, "V", { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", DELETE_KEY .. DELETE_KEY, function()
        delete_selected_or_current(false, false)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("x", DELETE_KEY, function()
        delete_selected_or_current(true, false)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", FORCE_DELETE_KEY, function()
        delete_selected_or_current(false, true)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("x", FORCE_DELETE_KEY, function()
        delete_selected_or_current(true, true)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", CLEAR_UNPINNED_KEY, function()
        clear_unpinned_buffers(false)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", FORCE_CLEAR_UNPINNED_KEY, function()
        clear_unpinned_buffers(true)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", WRITE_KEY, function()
        write_selected_or_current(false)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("x", WRITE_KEY, function()
        write_selected_or_current(true)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", WRITE_ALL_KEY, write_all_listed_buffers, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", RELOAD_KEY, function()
        reload_selected_or_current(false)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("x", RELOAD_KEY, function()
        reload_selected_or_current(true)
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", RELOAD_ALL_KEY, reload_all_listed_buffers, { buffer = map_buf, nowait = true, silent = true })

    vim.keymap.set("n", OPEN_SPLIT_PREFIX_KEY, function()
        set_pending_open_mode("split")
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", OPEN_VSPLIT_PREFIX_KEY, function()
        set_pending_open_mode("vsplit")
    end, { buffer = map_buf, nowait = true, silent = true })
    vim.keymap.set("n", OPEN_TAB_PREFIX_KEY, function()
        set_pending_open_mode("tab")
    end, { buffer = map_buf, nowait = true, silent = true })

    if config.values.fuzzy_key and config.values.fuzzy_key ~= "" then
        vim.keymap.set("n", config.values.fuzzy_key, function()
            local size_hint = {}
            local win = ui.get_win()
            if win and vim.api.nvim_win_is_valid(win) then
                local win_cfg = vim.api.nvim_win_get_config(win)
                if type(win_cfg.width) == "number" and win_cfg.width > 0 then
                    size_hint.width_cols = win_cfg.width
                end
                if type(win_cfg.height) == "number" and win_cfg.height > 0 then
                    size_hint.height_rows = win_cfg.height
                end
            end
            size_hint.fallback_height = fuzzy_height_fallback()
            ui.close()
            fuzzy.open(size_hint)
        end, { buffer = map_buf, nowait = true, silent = true })
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
                pick(alternate, consume_pending_open_mode())
            else
                vim.notify("quickbuf: no alternate buffer", vim.log.levels.INFO)
            end
        end, { buffer = map_buf, nowait = true, silent = true })
    end

    if picker_keys.move_up_key and picker_keys.move_up_key ~= "" then
        vim.keymap.set("n", picker_keys.move_up_key, function()
            move_cursor(-1)
        end, { buffer = map_buf, nowait = true, silent = true })
    end
    if picker_keys.move_down_key and picker_keys.move_down_key ~= "" then
        vim.keymap.set("n", picker_keys.move_down_key, function()
            move_cursor(1)
        end, { buffer = map_buf, nowait = true, silent = true })
    end
    if picker_keys.select_key and picker_keys.select_key ~= "" then
        vim.keymap.set("n", picker_keys.select_key, pick_current, { buffer = map_buf, nowait = true, silent = true })
    end
    if picker_keys.toggle_pin_key and picker_keys.toggle_pin_key ~= "" then
        vim.keymap.set(
            "n",
            picker_keys.toggle_pin_key,
            toggle_current_pin,
            { buffer = map_buf, nowait = true, silent = true }
        )
        vim.keymap.set("x", picker_keys.toggle_pin_key, function()
            toggle_selected_or_current_pin(true)
        end, { buffer = map_buf, nowait = true, silent = true })
    end
    vim.api.nvim_create_autocmd("WinLeave", {
        buffer = map_buf,
        callback = function()
            focus_refresh_armed = true
        end,
    })

    vim.api.nvim_create_autocmd("WinEnter", {
        buffer = map_buf,
        callback = function()
            if not focus_refresh_armed then
                return
            end
            local win = ui.get_win()
            if not win or not vim.api.nvim_win_is_valid(win) then
                return
            end
            if vim.api.nvim_get_current_win() ~= win then
                return
            end

            focus_refresh_armed = false
            local idx = get_selected_index() or 1
            refresh_after_action(idx)
        end,
    })

    for i, item in ipairs(items) do
        local label = labels_for_items[i]
        if label and label ~= "" then
            vim.keymap.set("n", label, function()
                pick(item.bufnr, consume_pending_open_mode())
            end, { buffer = map_buf, nowait = true, silent = true })
        end
    end

    refresh_footer()
end

function M.open(opts)
    opts = opts or {}

    local source_bufnr = opts.source_bufnr or vim.api.nvim_get_current_buf()
    local alternate_bufnr = opts.alternate_bufnr
    if alternate_bufnr == nil then
        alternate_bufnr = vim.fn.bufnr("#")
    end
    opts.source_bufnr = source_bufnr
    opts.alternate_bufnr = alternate_bufnr

    local all_items = rank.candidates({
        include_special = config.values.include_special,
        source_bufnr = source_bufnr,
        alternate_bufnr = alternate_bufnr,
    })
    local items = all_items

    if config.values.auto_jump_single and #items == 1 then
        vim.api.nvim_set_current_buf(items[1].bufnr)
        return
    end

    local charset = effective_charset()
    local limit = max_visible_items(#items, #charset)
    local shown = {}
    for i = 1, math.min(#items, limit) do
        shown[#shown + 1] = items[i]
    end

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

    if #shown == 0 then
        vim.notify("quickbuf: no matching buffers", vim.log.levels.INFO)
        return
    end

    local hidden_count = #items - #shown
    local lines, all_highlights, line_offset = ui.build_lines(shown, labels_for_items, hidden_count)

    local footer_parts = {
        "? [help]",
        "q [quit]",
        "s/v/t [mode]",
    }
    if config.values.fuzzy_key and config.values.fuzzy_key ~= "" then
        footer_parts[#footer_parts + 1] = string.format("%s [fuzzy]", config.values.fuzzy_key)
    end

    local footer = " " .. table.concat(footer_parts, "  ") .. " "

    ui.open_picker(lines, all_highlights, {
        title = "QuickBuf",
        total_count = #items,
        footer = footer,
    })

    apply_keymaps(shown, labels_for_items, {
        source_bufnr = source_bufnr,
        alternate_bufnr = alternate_bufnr,
        hidden_count = hidden_count,
        charset = charset,
        all_items = items,
        open_opts = opts,
        line_offset = line_offset,
        footer = footer,
    })

    if ui.is_win_valid() then
        local target_row = opts.cursor_row or 1
        target_row = math.max(1, math.min(target_row, #shown))
        ui.set_cursor(line_offset + target_row, 0)
    end
end

return M
