if vim.g.loaded_buffers == 1 then
	return
end
vim.g.loaded_buffers = 1

local buffers = require("buffers")

vim.api.nvim_create_user_command("BuffersToggle", function(_)
	buffers.toggle()
end, {})
