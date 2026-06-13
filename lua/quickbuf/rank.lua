local state = require("quickbuf.state")

local M = {}

function M.buffer_flags(bufnr, is_alternate)
    local flags = {}
    if is_alternate then
        flags[#flags + 1] = "#"
    end

    local loaded = vim.fn.bufloaded(bufnr) == 1
    if #vim.fn.win_findbuf(bufnr) > 0 then
        flags[#flags + 1] = "a"
    elseif loaded then
        flags[#flags + 1] = "h"
    end

    if vim.bo[bufnr].modified then
        flags[#flags + 1] = "+"
    end
    if vim.bo[bufnr].readonly then
        flags[#flags + 1] = "="
    end
    if not vim.bo[bufnr].modifiable then
        flags[#flags + 1] = "-"
    end

    return table.concat(flags)
end

local function buftype_ok(bufnr, include_special)
    if include_special then
        return true
    end
    return vim.bo[bufnr].buftype == ""
end

local function display_parts(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then
        return "[No Name]", "", ""
    end

    local filename = vim.fn.fnamemodify(name, ":t")
    local dirname = vim.fn.fnamemodify(name, ":~:.:h")
    if dirname == "." then
        dirname = ""
    end

    return filename, dirname, name
end

function M.candidates(opts)
    state.cleanup()

    opts = opts or {}
    local current = vim.api.nvim_get_current_buf()
    local alternate = vim.fn.bufnr("#")
    local mru_index = state.mru_index_map()

    local out = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if bufnr ~= current and vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buflisted and buftype_ok(bufnr, opts.include_special) then
            local filename, dirname, path = display_parts(bufnr)
            local is_alternate = bufnr == alternate
            out[#out + 1] = {
                bufnr = bufnr,
                filename = filename,
                dirname = dirname,
                path = path,
                pinned = state.is_pinned(bufnr),
                alternate = is_alternate,
                flags = M.buffer_flags(bufnr, is_alternate),
                mru_index = mru_index[bufnr] or math.huge,
            }
        end
    end

    table.sort(out, function(a, b)
        if a.alternate ~= b.alternate then
            return a.alternate
        end
        if a.pinned ~= b.pinned then
            return a.pinned
        end
        if a.mru_index ~= b.mru_index then
            return a.mru_index < b.mru_index
        end
        if a.filename ~= b.filename then
            return a.filename < b.filename
        end
        if a.dirname ~= b.dirname then
            return a.dirname < b.dirname
        end
        return a.bufnr < b.bufnr
    end)

    return out
end

return M
