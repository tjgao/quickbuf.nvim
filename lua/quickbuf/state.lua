local M = {
    pinned = {},
    pinned_order = {},
    mru = {},
    picker_mode = "all",
}

local function normalize_picker_mode(mode)
    if mode == "pinned" then
        return "pinned"
    end
    return "all"
end

local function remove_from_mru(bufnr)
    for i, id in ipairs(M.mru) do
        if id == bufnr then
            table.remove(M.mru, i)
            return
        end
    end
end

local function remove_from_order(bufnr)
    for i, id in ipairs(M.pinned_order) do
        if id == bufnr then
            table.remove(M.pinned_order, i)
            return
        end
    end
end

local function is_valid_buffer(bufnr)
    return vim.api.nvim_buf_is_valid(bufnr)
end

local function is_listed_buffer(bufnr)
    return is_valid_buffer(bufnr) and vim.bo[bufnr].buflisted
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
        if not is_listed_buffer(bufnr) then
            M.pinned[bufnr] = nil
        end
    end

    local next_order = {}
    local seen = {}
    for _, bufnr in ipairs(M.pinned_order) do
        if M.pinned[bufnr] and is_listed_buffer(bufnr) and not seen[bufnr] then
            next_order[#next_order + 1] = bufnr
            seen[bufnr] = true
        end
    end
    for bufnr, _ in pairs(M.pinned) do
        if is_listed_buffer(bufnr) and not seen[bufnr] then
            next_order[#next_order + 1] = bufnr
        end
    end
    M.pinned_order = next_order
end

function M.is_pinned(bufnr)
    return M.pinned[bufnr] == true
end

function M.toggle_pin(bufnr)
    if not is_valid_buffer(bufnr) then
        return false
    end

    if M.pinned[bufnr] then
        M.unpin(bufnr)
        return false
    end

    M.pinned[bufnr] = true
    M.pinned_order[#M.pinned_order + 1] = bufnr
    return true
end

function M.unpin(bufnr)
    M.pinned[bufnr] = nil
    remove_from_order(bufnr)
end

function M.pinned_in_order()
    M.cleanup()
    return vim.deepcopy(M.pinned_order)
end

function M.mru_index_map()
    local map = {}
    for i, bufnr in ipairs(M.mru) do
        map[bufnr] = i
    end
    return map
end

function M.get_picker_mode()
    M.picker_mode = normalize_picker_mode(M.picker_mode)
    return M.picker_mode
end

function M.set_picker_mode(mode)
    M.picker_mode = normalize_picker_mode(mode)
    return M.picker_mode
end

function M.toggle_picker_mode()
    if M.get_picker_mode() == "pinned" then
        return M.set_picker_mode("all")
    end
    return M.set_picker_mode("pinned")
end

return M
