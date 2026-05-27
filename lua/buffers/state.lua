local state = {
	buf = -1,
	win = -1,
	exact_width = -1,
	exact_height = -1,
	ns_hl = vim.api.nvim_create_namespace("buffers-highlight"),
	buf_table = require("buffers.buf-table").new(),
	format = nil, -- Format function
	opts = {},
}

return state
