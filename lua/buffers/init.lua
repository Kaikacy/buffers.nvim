---@alias buffers.size number|[number, number]
---@alias buffers.pos 'center_right'|'bottom_right'|'top_right'

---@class buffers.Config
---@field width? buffers.size Window width or min, max bounds
---@field height? buffers.size Window height or min, max bounds
---@field pos? buffers.pos Window position
---@field border? 'none'|'single'|'double'|'rounded'|'solid'|'shadow'|string[] Window border
---@field win_opts? table Additional window local options
---@field chars? string Characters to use for mappings
---@field filter? fun(buf: integer): boolean Checks if buf should be included in buffers table
---@field close_keys? string[] Which keys will hide buffers window, without warning, when pressed
---@field separator? string Separator between char and buffer name
---@field formatter? 'relative_path'|'filename_first'|buffers.formatter How to format buffer name
---@field icons? boolean Whether to show icons or not

local M = {}

local formatters = require("buffers.formatters")

local state = {
	buf = -1,
	win = -1,
	cur_buf_line = nil,
	ns = vim.api.nvim_create_namespace("buffers-highlight"),
	buf_table = require("buffers.buf-table").new(),
}

---@param opts buffers.Config
---@return buffers.Config
local function with_defaults(opts)
	return {
		width = opts.width or { 0, 0.5 },
		height = opts.height or { 0, 0.5 },
		pos = opts.pos or "center_right",
		border = opts.border or "single",
		win_opts = opts.win_opts or {},
		chars = opts.chars or "qwertyuiopasdfghjklzxcvbnm1234567890",
		filter = opts.filter or function(buf)
			return vim.fn.buflisted(buf) == 1
		end,
		close_keys = opts.close_keys or { "<ESC>" },
		separator = opts.separator or " | ",
		formatter = opts.formatter or "relative_path",
		icons = opts.icons or false,
	}
end

---@param msg string
---@param level integer|nil
local function notify(msg, level)
	vim.notify(msg, level, { title = "buffers.nvim" })
end

local function get_char_dumb(buffer_table, chars)
	for i = 1, #chars do
		if not buffer_table:get(chars:sub(i, i)) then
			return chars:sub(i, i)
		end
	end
	return nil
end

local function get_buffer_char(name, buffer_table, chars)
	local char = name:sub(1, 1)
	local i = 2
	while buffer_table:get(char) or chars:find(char, 1, true) == nil do
		if i > #name then
			return nil
		end
		char = name:sub(i, i)
		i = i + 1
	end
	return char
end

local function update_buf_table(bufs, chars)
	for i, buf in ipairs(bufs) do
		if not state.buf_table:get(buf) then
			-- New buffer (not yet in the buf_table and key not yet assigned)

			local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
			-- TODO: get available key, assign it and save entry in buf_table
		end
	end
end

local function register_buffers(buffer_table, base_buf, separator, formatter)
	local format = type(formatter) == "string" and formatters[formatter] or formatter
	if not format then
		notify(("Formatter '%s' is not available"):format(formatter))
		return
	end

	vim.bo[base_buf].modifiable = true
	vim.bo[base_buf].readonly = false

	local lines = {}
	local ranges = {}

	for char, bufnr in buffer_table:ordered_pairs() do
		local formatted, range = format(vim.api.nvim_buf_get_name(bufnr))
		local line = char .. separator .. formatted

		table.insert(lines, line)
		table.insert(ranges, range or { 0, 0 })
	end

	vim.api.nvim_buf_clear_namespace(base_buf, state.ns, 0, -1)
	vim.api.nvim_buf_set_lines(base_buf, 0, -1, false, {})
	vim.api.nvim_buf_set_lines(base_buf, 0, #lines, false, lines)

	for i, range in ipairs(ranges) do
		vim.api.nvim_buf_set_extmark(
			base_buf,
			state.ns,
			i - 1,
			range[1] + 1 + #separator,
			{ end_col = range[2] + 1 + #separator, hl_group = "Comment" }
		)
	end
end

local function get_win_config(opts, buffer_count)
	local height = math.max(opts.min_height, buffer_count)

	local col = vim.o.columns
	local row = vim.o.lines

	if opts.position == "top_right" then
		row = 0
	elseif opts.position == "center" then
		col = (vim.o.columns - opts.width) * 0.5
		row = (vim.o.lines - height) * 0.5
	elseif opts.position ~= "bottom_right" then
		notify("Position must be `top_right`, `center` or `bottom_right`", vim.log.levels.ERROR)
		return nil
	end

	return {
		relative = "editor",
		width = opts.width,
		height = height,
		col = col,
		row = row,
		border = opts.border,
		style = "minimal",
	}
end

---Toggle buffers window
function M.toggle()
	vim.g.buffers_config = vim.g.buffers_config or {}
	local opts = with_defaults(vim.g.buffers_config)
	local bufs = vim.tbl_filter(opts.filter, vim.api.nvim_list_bufs())
	update_buf_table(bufs, opts.chars)

	local win_config = get_win_config(opts, #bufs)
	if win_config == nil then
		return
	end

	local base_buf = state.buf
	if not vim.api.nvim_buf_is_valid(base_buf) then
		base_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(base_buf, "buffers")
		vim.bo[base_buf].buftype = "nofile"
		vim.bo[base_buf].filetype = "buffers"
		state.buf = base_buf
	end

	local win = state.win
	if not vim.api.nvim_win_is_valid(win) then
		win = vim.api.nvim_open_win(base_buf, true, win_config)
		for key, val in pairs(opts.win_opts) do
			vim.api.nvim_set_option_value(key, val, { scope = "local", win = win })
		end
		state.win = win
	else
		vim.api.nvim_win_hide(win)
		return
	end

	register_buffers(buffer_table, base_buf, opts.separator, opts.formatter)

	vim.bo[base_buf].modifiable = false
	vim.bo[base_buf].readonly = true
	vim.api.nvim_win_set_cursor(win, { state.cur_buf_line or 1, 0 })

	vim.schedule(function()
		local ok, char = pcall(vim.fn.getcharstr)
		if not ok then
			vim.api.nvim_win_hide(win)
			return
		end

		for _, key in ipairs(opts.close_keys) do
			if char == vim.keycode(key) then
				vim.api.nvim_win_hide(win)
				return
			end
		end

		for c, buf in buffer_table:ordered_pairs() do
			if char == c then
				vim.api.nvim_win_hide(win)
				vim.api.nvim_set_current_buf(buf)
				return
			end
		end

		vim.api.nvim_win_hide(win)
		notify(("No buffer bound to '%s'"):format(char), vim.log.levels.WARN)
	end)
end

return M
