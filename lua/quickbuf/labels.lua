local M = {}

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

  local base = #charset

  if n <= base then
    local single = {}
    for i = 1, n do
      single[#single + 1] = charset[i]
    end
    return single
  end

  local labels = {}
  for i = 1, base do
    local first = charset[i]
    for j = 1, base do
      labels[#labels + 1] = first .. charset[j]
      if #labels >= n then
        return labels
      end
    end
  end

  error("quickbuf: too many buffers for current labels charset")
end

return M
