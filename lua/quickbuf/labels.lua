local M = {}

M.default_string = "fjdkhgl;asrueiwotynmq,c.vxbzpFJDKHGLASRUEIWOTYNMQCVXBZP"

function M.charset_from_string(s)
    local out = {}
    local seen = {}
    for i = 1, #s do
        local ch = s:sub(i, i)
        if not seen[ch] then
            table.insert(out, ch)
            seen[ch] = true
        end
    end
    return out
end

function M.generate(n, charset)
    if n <= 0 then
        return {}
    end
    if #charset == 0 then
        error("quickbuf: labels charset is empty")
    end

    if n > #charset then
        error("quickbuf: too many buffers for one-key labels")
    end

    local out = {}
    for i = 1, n do
        out[#out + 1] = charset[i]
    end
    return out
end

function M.default_charset()
    return M.charset_from_string(M.default_string)
end

return M
