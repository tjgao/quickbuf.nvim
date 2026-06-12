if vim.g.loaded_quickbuf then
  return
end
vim.g.loaded_quickbuf = true

require("quickbuf").setup()
