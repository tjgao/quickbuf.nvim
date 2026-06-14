local state = require("quickbuf.state")

local M = {}

local function buffer_display_name(bufnr)
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then
        return string.format("[No Name] (#%d)", bufnr)
    end
    return vim.fn.fnamemodify(name, ":~:.")
end

function M.delete_buffers(bufnrs, force)
    local deleted = 0
    local failed = {}

    for _, bufnr in ipairs(bufnrs) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            if not force and vim.bo[bufnr].modified then
                failed[#failed + 1] = {
                    name = buffer_display_name(bufnr),
                    reason = "modified",
                }
                goto continue
            end

            local ok, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = force == true })
            if ok then
                state.unpin(bufnr)
                deleted = deleted + 1
            else
                failed[#failed + 1] = {
                    name = buffer_display_name(bufnr),
                    reason = tostring(err):gsub("\n.*$", ""),
                }
            end
        end

        ::continue::
    end

    return deleted, failed
end

function M.notify_delete_failures(prefix, deleted, failed)
    if #failed == 0 then
        return
    end

    local max_items = 8
    local lines = {
        string.format("quickbuf: %s %d, failed %d", prefix, deleted, #failed),
    }

    for i = 1, math.min(#failed, max_items) do
        local item = failed[i]
        if item.reason and item.reason ~= "" then
            lines[#lines + 1] = string.format("- %s (%s)", item.name, item.reason)
        else
            lines[#lines + 1] = string.format("- %s", item.name)
        end
    end

    local extra = #failed - math.min(#failed, max_items)
    if extra > 0 then
        lines[#lines + 1] = string.format("- ... and %d more", extra)
    end

    vim.notify(table.concat(lines, "\n"), vim.log.levels.WARN)
end

function M.write_buffers(bufnrs)
    local written = 0
    local failed = 0

    for _, bufnr in ipairs(bufnrs) do
        if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "" and vim.bo[bufnr].modified then
            local ok = pcall(vim.api.nvim_buf_call, bufnr, function()
                vim.cmd("silent write")
            end)
            if ok then
                written = written + 1
            else
                failed = failed + 1
            end
        end
    end

    return written, failed
end

function M.reload_buffers(bufnrs)
    local reloaded = 0
    local failed = 0

    for _, bufnr in ipairs(bufnrs) do
        if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "" and vim.bo[bufnr].modified then
            local ok = pcall(vim.api.nvim_buf_call, bufnr, function()
                vim.cmd("silent edit!")
            end)
            if ok then
                reloaded = reloaded + 1
            else
                failed = failed + 1
            end
        end
    end

    return reloaded, failed
end

return M
