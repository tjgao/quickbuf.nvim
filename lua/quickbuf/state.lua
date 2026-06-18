local config = require("quickbuf.config")

local uv = vim.uv or vim.loop

local M = {
    pinned = {},
    pinned_order = {},
    mru = {},
    persistence = {
        project_root = nil,
        project_file = nil,
        paths = {},
        dirty = false,
        save_seq = 0,
        shutting_down = false,
    },
}

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

local function persistence_enabled()
    local p = config.values.persistence
    return p and p.enabled
end

local function normalize_path(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local abs = vim.fn.fnamemodify(path, ":p")
    if abs == "" then
        return nil
    end

    local real = uv and uv.fs_realpath(abs) or nil
    if type(real) == "string" and real ~= "" then
        abs = real
    end

    return abs
end

local function path_exists(path)
    if not uv then
        return vim.fn.filereadable(path) == 1
    end
    return uv.fs_stat(path) ~= nil
end

local function buffer_path(bufnr)
    if not is_valid_buffer(bufnr) then
        return nil
    end
    return normalize_path(vim.api.nvim_buf_get_name(bufnr))
end

local function mark_dirty()
    local p = M.persistence
    p.dirty = true
    p.save_seq = p.save_seq + 1
end

local function add_persist_path(path)
    if not persistence_enabled() then
        return
    end
    if not path then
        return
    end
    local p = M.persistence
    if p.paths[path] then
        return
    end
    p.paths[path] = true
    mark_dirty()
end

local function remove_persist_path(path)
    if not persistence_enabled() then
        return
    end
    if not path then
        return
    end
    local p = M.persistence
    if not p.paths[path] then
        return
    end
    p.paths[path] = nil
    mark_dirty()
end

local function pin_buffer(bufnr, update_persist)
    if not is_valid_buffer(bufnr) then
        return false
    end

    if not vim.bo[bufnr].buflisted then
        vim.bo[bufnr].buflisted = true
    end

    if not M.pinned[bufnr] then
        M.pinned[bufnr] = true
        M.pinned_order[#M.pinned_order + 1] = bufnr
    end

    if update_persist then
        add_persist_path(buffer_path(bufnr))
    end

    return true
end

local function unpin_buffer(bufnr, update_persist)
    if update_persist then
        remove_persist_path(buffer_path(bufnr))
    end
    M.pinned[bufnr] = nil
    remove_from_order(bufnr)
end

local function schedule_persist_save()
    if not persistence_enabled() then
        return
    end

    local p = M.persistence
    if not p.dirty then
        return
    end

    local debounce_ms = ((config.values.persistence or {}).debounce_ms) or 1000
    debounce_ms = math.max(0, math.floor(debounce_ms))
    local seq = p.save_seq

    if debounce_ms == 0 then
        M.save_project_pins(false)
        return
    end

    vim.defer_fn(function()
        if seq ~= p.save_seq then
            return
        end
        M.save_project_pins(false)
    end, debounce_ms)
end

local function resolve_project_root()
    local cwd = normalize_path(vim.fn.getcwd())
    if not cwd then
        return nil
    end

    local git = vim.fs.find(".git", { path = cwd, upward = true })
    if git and git[1] then
        return normalize_path(vim.fs.dirname(git[1])) or cwd
    end

    return cwd
end

local function project_paths(project_root)
    local pins_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "quickbuf", "pins")
    local project_hash = vim.fn.sha256(project_root)
    local project_file = vim.fs.joinpath(pins_dir, project_hash .. ".json")
    return pins_dir, project_file
end

local function clear_pins_state()
    M.pinned = {}
    M.pinned_order = {}
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
            unpin_buffer(bufnr, true)
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

    schedule_persist_save()
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

    pin_buffer(bufnr, true)
    schedule_persist_save()
    return true
end

function M.unpin(bufnr)
    unpin_buffer(bufnr, true)
    schedule_persist_save()
end

function M.on_buf_deleted(bufnr)
    if M.persistence.shutting_down then
        return
    end
    M.unpin(bufnr)
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

function M.save_project_pins(force)
    if not persistence_enabled() then
        return
    end

    local p = M.persistence
    local project_file = p.project_file
    if type(project_file) ~= "string" or project_file == "" then
        return
    end
    if not force and not p.dirty then
        return
    end

    local pins = {}
    for path, _ in pairs(p.paths) do
        pins[#pins + 1] = path
    end
    table.sort(pins)

    if #pins == 0 then
        vim.fn.delete(project_file)
        p.dirty = false
        return
    end

    local payload = {
        version = 1,
        project_root = p.project_root,
        pins = pins,
    }
    local encoded = vim.json.encode(payload)
    local pins_dir = vim.fs.dirname(project_file)
    if type(pins_dir) ~= "string" or pins_dir == "" then
        return
    end
    if vim.fn.isdirectory(pins_dir) == 0 then
        vim.fn.mkdir(pins_dir, "p")
    end

    local pid = uv and uv.os_getpid and uv.os_getpid() or 0
    local hrtime = uv and uv.hrtime and uv.hrtime() or vim.loop.hrtime()
    local tmp_file = string.format("%s.tmp.%d.%d", project_file, pid, hrtime)
    local ok_write, err_write = pcall(vim.fn.writefile, { encoded }, tmp_file)
    if not ok_write then
        vim.fn.delete(tmp_file)
        vim.notify("quickbuf: failed to write pins temp file: " .. tostring(err_write), vim.log.levels.WARN)
        return
    end

    local ok_rename, err_rename = os.rename(tmp_file, project_file)
    if not ok_rename then
        vim.fn.delete(tmp_file)
        vim.notify("quickbuf: failed to persist pins: " .. tostring(err_rename), vim.log.levels.WARN)
        return
    end

    p.dirty = false
end

function M.load_project_pins()
    if not persistence_enabled() then
        return
    end

    local p = M.persistence
    local project_root = resolve_project_root()
    if not project_root then
        return
    end
    if p.project_root == project_root then
        return
    end

    if p.dirty then
        M.save_project_pins(true)
    end

    p.project_root = project_root
    local _, project_file = project_paths(project_root)
    p.project_file = project_file
    p.paths = {}
    p.dirty = false
    p.save_seq = p.save_seq + 1
    p.shutting_down = false

    clear_pins_state()

    if path_exists(project_file) then
        local raw = table.concat(vim.fn.readfile(project_file), "\n")
        if raw ~= "" then
            local ok, decoded = pcall(vim.json.decode, raw)
            if ok and type(decoded) == "table" and type(decoded.pins) == "table" then
                for _, path in ipairs(decoded.pins) do
                    local normalized = normalize_path(path)
                    if normalized and path_exists(normalized) then
                        p.paths[normalized] = true
                    else
                        mark_dirty()
                    end
                end
            else
                vim.notify("quickbuf: failed to parse pins file, ignoring " .. project_file, vim.log.levels.WARN)
            end
        end
    end

    local seen_paths = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if is_valid_buffer(bufnr) then
            local path = buffer_path(bufnr)
            if path and p.paths[path] then
                if pin_buffer(bufnr, false) then
                    seen_paths[path] = true
                end
            end
        end
    end

    for path, _ in pairs(p.paths) do
        if not seen_paths[path] then
            vim.cmd("silent! badd " .. vim.fn.fnameescape(path))
            local bufnr = vim.fn.bufnr(path)
            if bufnr > 0 then
                pin_buffer(bufnr, false)
            end
        end
    end

    if p.dirty then
        schedule_persist_save()
    end
end

function M.on_vim_leave_pre()
    if not persistence_enabled() then
        return
    end

    M.persistence.shutting_down = true
    M.save_project_pins(true)
end

return M
