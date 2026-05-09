local state = {
	buf = -1,
	win = -1,
	cur_buf_line = -1,
	exact_width = -1,
	exact_height = -1,
	ns = vim.api.nvim_create_namespace("buffers-highlight"),
	buf_table = require("buffers.buf-table").new(),
	opts = nil,
}

return state
