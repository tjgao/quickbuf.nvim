local config = require("quickbuf.config")

local M = {}

local function normalize_dimension(value, total, fallback)
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

local function float_window_set()
    local out = {}
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) then
            local cfg = vim.api.nvim_win_get_config(win)
            if cfg.relative and cfg.relative ~= "" then
                out[win] = true
            end
        end
    end
    return out
end

local function enforce_new_float_size(before_set, width, height)
    local function apply_once()
        local target = nil
        local target_area = -1

        for _, win in ipairs(vim.api.nvim_list_wins()) do
            if not before_set[win] and vim.api.nvim_win_is_valid(win) then
                local cfg = vim.api.nvim_win_get_config(win)
                if
                    cfg.relative
                    and cfg.relative ~= ""
                    and type(cfg.width) == "number"
                    and type(cfg.height) == "number"
                then
                    local area = cfg.width * cfg.height
                    if area > target_area then
                        target = win
                        target_area = area
                    end
                end
            end
        end

        if not target then
            return false
        end

        local cfg = vim.api.nvim_win_get_config(target)
        cfg.width = width
        cfg.height = height
        pcall(vim.api.nvim_win_set_config, target, cfg)
        return true
    end

    if apply_once() then
        return
    end

    vim.defer_fn(apply_once, 20)
    vim.defer_fn(apply_once, 80)
end

local function fuzzy_picker_size(opts)
    opts = opts or {}
    local cfg = config.values.window or {}
    local columns = math.max(1, vim.o.columns)
    local lines = math.max(1, vim.o.lines - 2)

    local min_width = normalize_dimension(cfg.min_width, columns, math.floor(columns * 0.35))
    local max_width = normalize_dimension(cfg.max_width, columns, math.floor(columns * 0.8))
    min_width = math.max(1, math.min(min_width, columns))
    max_width = math.max(1, math.min(max_width, columns))
    if min_width > max_width then
        min_width, max_width = max_width, min_width
    end

    local width_cols = normalize_dimension(cfg.width, columns, max_width)
    if type(opts.width_cols) == "number" and opts.width_cols > 0 then
        width_cols = math.floor(opts.width_cols)
    else
        width_cols = math.max(min_width, math.min(max_width, width_cols))
    end
    width_cols = math.max(1, math.min(columns, width_cols))

    local fallback_height = opts.fallback_height or math.floor(lines * 0.55)
    local height_rows = normalize_dimension(cfg.height, lines, fallback_height)
    if type(opts.height_rows) == "number" and opts.height_rows > 0 then
        height_rows = math.floor(opts.height_rows)
    end
    height_rows = math.max(1, math.min(math.max(1, vim.o.lines - 4), height_rows))

    local width_frac = math.max(0.2, math.min(1.0, width_cols / columns))
    local height_frac = math.max(0.2, math.min(1.0, height_rows / lines))

    return {
        width_cols = width_cols,
        height_rows = height_rows,
        width_frac = width_frac,
        height_frac = height_frac,
    }
end

function M.open(opts)
    local size = fuzzy_picker_size(opts)

    local function open_snacks(size_hint)
        local ok_snacks, snacks = pcall(require, "snacks")
        if not (ok_snacks and snacks and snacks.picker and type(snacks.picker.buffers) == "function") then
            return false
        end

        local before_float_wins = float_window_set()
        local ok = pcall(snacks.picker.buffers, {
            preview = false,
            layout = {
                preset = "select",
                preview = false,
                width = size_hint.width_frac,
                height = size_hint.height_frac,
                min_width = size_hint.width_cols,
                max_width = size_hint.width_cols,
                min_height = size_hint.height_rows,
                max_height = size_hint.height_rows,
                layout = {
                    width = size_hint.width_cols,
                    height = size_hint.height_rows,
                },
            },
        })
        if not ok then
            local ok_fallback = pcall(snacks.picker.buffers, {
                preview = false,
                layout = {
                    preset = "default",
                    preview = false,
                    width = size_hint.width_frac,
                    height = size_hint.height_frac,
                    min_width = size_hint.width_cols,
                    max_width = size_hint.width_cols,
                    min_height = size_hint.height_rows,
                    max_height = size_hint.height_rows,
                    layout = {
                        width = size_hint.width_cols,
                        height = size_hint.height_rows,
                    },
                },
            })
            if not ok_fallback then
                snacks.picker.buffers()
            end
        end
        enforce_new_float_size(before_float_wins, size_hint.width_cols, size_hint.height_rows)
        return true
    end

    local function open_telescope(size_hint)
        local ok_telescope, telescope = pcall(require, "telescope.builtin")
        if not (ok_telescope and telescope and type(telescope.buffers) == "function") then
            return false
        end

        local telescope_opts = { previewer = false }
        local ok_theme, themes = pcall(require, "telescope.themes")
        if ok_theme and themes and type(themes.get_dropdown) == "function" then
            telescope_opts = themes.get_dropdown({
                previewer = false,
                width = size_hint.width_frac,
                height = size_hint.height_frac,
            })
        else
            telescope_opts.width = size_hint.width_frac
            telescope_opts.height = size_hint.height_frac
        end
        telescope.buffers(telescope_opts)
        return true
    end

    local function open_fzf_lua(size_hint)
        local ok_fzf, fzf = pcall(require, "fzf-lua")
        if not (ok_fzf and fzf and type(fzf.buffers) == "function") then
            return false
        end

        fzf.buffers({
            previewer = false,
            winopts = {
                width = size_hint.width_frac,
                height = size_hint.height_frac,
                preview = {
                    hidden = "hidden",
                },
            },
        })
        return true
    end

    local backend = config.values.fuzzy_backend or "auto"
    if backend == "custom" then
        local custom = config.values.fuzzy_open
        if type(custom) ~= "function" then
            vim.notify(
                "quickbuf: fuzzy_backend is 'custom' but fuzzy_open is not a function",
                vim.log.levels.WARN
            )
            return
        end
        local ok, err = pcall(custom, {
            width_cols = size.width_cols,
            height_rows = size.height_rows,
            width_frac = size.width_frac,
            height_frac = size.height_frac,
        })
        if not ok then
            vim.notify("quickbuf: custom fuzzy_open failed: " .. tostring(err), vim.log.levels.WARN)
        end
        return
    end

    if backend == "snacks" then
        if not open_snacks(size) then
            vim.notify("quickbuf: fuzzy backend 'snacks' is unavailable", vim.log.levels.WARN)
        end
        return
    end

    if backend == "telescope" then
        if not open_telescope(size) then
            vim.notify("quickbuf: fuzzy backend 'telescope' is unavailable", vim.log.levels.WARN)
        end
        return
    end

    if backend == "fzf" then
        if not open_fzf_lua(size) then
            vim.notify("quickbuf: fuzzy backend 'fzf' is unavailable", vim.log.levels.WARN)
        end
        return
    end

    if backend ~= "auto" then
        vim.notify("quickbuf: unknown fuzzy_backend '" .. tostring(backend) .. "'", vim.log.levels.WARN)
        return
    end

    if open_snacks(size) then
        return
    end

    if open_telescope(size) then
        return
    end

    if open_fzf_lua(size) then
        return
    end

    vim.notify("quickbuf: no fuzzy buffer picker found", vim.log.levels.WARN)
end

return M
