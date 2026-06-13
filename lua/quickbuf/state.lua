local M = {
    pinned = {},
    mru = {},
}

local function remove_from_mru(bufnr)
    for i, id in ipairs(M.mru) do
        if id == bufnr then
            table.remove(M.mru, i)
            return
        end
    end
end

local function is_valid_buffer(bufnr)
    return vim.api.nvim_buf_is_valid(bufnr)
end

function M.track_buf_enter(bufnr)
    if not is_valid_buffer(bufnr) then
        return
    end
    remove_from_mru(bufnr)
    table.insert(M.mru, 1, bufnr)
end

function M.cleanup()
    local next_mru = {}
    for _, bufnr in ipairs(M.mru) do
        if is_valid_buffer(bufnr) then
            table.insert(next_mru, bufnr)
        else
            M.pinned[bufnr] = nil
        end
    end
    M.mru = next_mru

    for bufnr, _ in pairs(M.pinned) do
        if not is_valid_buffer(bufnr) then
            M.pinned[bufnr] = nil
        end
    end
end

function M.is_pinned(bufnr)
    return M.pinned[bufnr] == true
end

function M.toggle_pin(bufnr)
    if not is_valid_buffer(bufnr) then
        return false
    end

    if M.pinned[bufnr] then
        M.pinned[bufnr] = nil
        return false
    end

    M.pinned[bufnr] = true
    return true
end

function M.pinned_in_mru_order()
    M.cleanup()
    local out = {}
    local seen = {}

    for _, bufnr in ipairs(M.mru) do
        if M.pinned[bufnr] and not seen[bufnr] then
            table.insert(out, bufnr)
            seen[bufnr] = true
        end
    end

    for bufnr, _ in pairs(M.pinned) do
        if not seen[bufnr] and is_valid_buffer(bufnr) then
            table.insert(out, bufnr)
        end
    end

    return out
end

function M.mru_index_map()
    local map = {}
    for i, bufnr in ipairs(M.mru) do
        map[bufnr] = i
    end
    return map
end

return M
