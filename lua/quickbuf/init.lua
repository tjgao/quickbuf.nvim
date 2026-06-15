local config = require("quickbuf.config")
local picker = require("quickbuf.picker")
local state = require("quickbuf.state")

local M = {}

local augroup = vim.api.nvim_create_augroup("QuickBufState", { clear = true })
local did_setup = false

local function has_style_overrides(hl)
    for k, _ in pairs(hl) do
        if k ~= "link" and k ~= "default" then
            return true
        end
    end
    return false
end

local function setup_highlights()
    local groups = {
        label = "QuickBufLabel",
        pinned = "QuickBufPinned",
        flags = "QuickBufFlags",
        alternate = "QuickBufAlternate",
        filename = "QuickBufFilename",
        path = "QuickBufPath",
        muted = "QuickBufMuted",
        cursorline = "QuickBufCursorLine",
        footer_svt = "QuickBufFooterSvt",
    }

    for key, group_name in pairs(groups) do
        local spec = config.values.highlights and config.values.highlights[key]
        if spec ~= false then
            local hl = vim.deepcopy(spec or {})
            if hl.link and has_style_overrides(hl) then
                local ok, base = pcall(vim.api.nvim_get_hl, 0, { name = hl.link, link = false })
                if ok and type(base) == "table" then
                    hl.link = nil
                    hl = vim.tbl_extend("force", base, hl)
                end
            end
            if hl.default == nil then
                hl.default = true
            end
            vim.api.nvim_set_hl(0, group_name, hl)
        end
    end
end

local function notify_pin(bufnr, pinned)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then
        name = "[No Name]"
    else
        name = vim.fn.fnamemodify(name, ":~:.")
    end
    if pinned then
        vim.notify("quickbuf: pinned " .. name, vim.log.levels.INFO)
    else
        vim.notify("quickbuf: unpinned " .. name, vim.log.levels.INFO)
    end
end

function M.open()
    picker.open()
end

function M.pin_toggle(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local pinned = state.toggle_pin(bufnr)
    notify_pin(bufnr, pinned)
end

local function cycle_pinned(step)
    local pinned = state.pinned_in_order()
    if #pinned == 0 then
        vim.notify("quickbuf: no pinned buffers", vim.log.levels.INFO)
        return
    end

    local current = vim.api.nvim_get_current_buf()
    local idx = 0
    for i, bufnr in ipairs(pinned) do
        if bufnr == current then
            idx = i
            break
        end
    end

    local next_idx
    if idx == 0 then
        next_idx = 1
    else
        next_idx = ((idx - 1 + step) % #pinned) + 1
    end

    vim.api.nvim_set_current_buf(pinned[next_idx])
end

function M.next_pinned()
    cycle_pinned(1)
end

function M.prev_pinned()
    cycle_pinned(-1)
end

local function create_commands()
    vim.api.nvim_create_user_command("QuickBuf", function()
        M.open()
    end, { desc = "Quick buffer jump" })

    vim.api.nvim_create_user_command("QuickBufPinToggle", function()
        M.pin_toggle()
    end, { desc = "Toggle pin on current buffer" })

    vim.api.nvim_create_user_command("QuickBufNextPinned", function()
        M.next_pinned()
    end, { desc = "Go to next pinned buffer" })

    vim.api.nvim_create_user_command("QuickBufPrevPinned", function()
        M.prev_pinned()
    end, { desc = "Go to previous pinned buffer" })
end

function M.setup(opts, force_load)
    if force_load == nil then
        force_load = true
    end
    if not force_load and did_setup then
        return
    end

    config.setup(opts)
    setup_highlights()

    if did_setup then
        return
    end

    create_commands()
    vim.api.nvim_create_autocmd("ColorScheme", {
        group = augroup,
        callback = setup_highlights,
    })
    vim.api.nvim_create_autocmd("BufEnter", {
        group = augroup,
        callback = function(args)
            state.track_buf_enter(args.buf)
        end,
    })
    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
        group = augroup,
        callback = function(args)
            state.unpin(args.buf)
        end,
    })
    did_setup = true
end

return M
