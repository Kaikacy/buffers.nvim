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

local buf_table = require("buffers.buf-table")
local formatters = require("buffers.formatters")

local state = require("buffers.state")

---@param opts buffers.Config
local function set_defaults(opts)
	state.opts.width = opts.width or { 0, 0.5 }
	state.opts.height = opts.height or { 0, 0.5 }
	state.opts.pos = opts.pos or "center_right"
	state.opts.border = opts.border or "single"
	state.opts.win_opts = opts.win_opts or {}
	state.opts.chars = opts.chars or "qwertyuiopasdfghjklzxcvbnm1234567890"
	state.opts.filter = opts.filter or function(buf)
		return vim.fn.buflisted(buf) == 1
	end
	state.opts.close_keys = opts.close_keys or { "<ESC>" }
	state.opts.separator = opts.separator or " | "
	state.opts.formatter = opts.formatter or "relative_path"
	state.opts.icons = opts.icons or false
end

---@param msg string
---@param level integer|nil
local function notify(msg, level)
	vim.notify(msg, level, { title = "buffers.nvim" })
end

local function update_buf_table(bufs)
	local new_table = buf_table.new()
	local new_bufs = {}
	for _, buf in ipairs(bufs) do
		local key = state.buf_table.buf2key[buf]
		if key then
			new_table:set(key, buf)
		else -- New buffer (not yet in the buf_table and key not yet assigned)
			table.insert(new_bufs, buf)
		end
	end
	for _, buf in ipairs(new_bufs) do
		local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
		local key = new_table:create_buf_key(name)
		if not key then
			notify(("No key available for %d buffer: '%s'"):format(buf, name), vim.log.levels.ERROR)
			return
		end
		new_table:set(key, buf)
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
	set_defaults(vim.g.buffers_config or {})
	local bufs = vim.tbl_filter(state.opts.filter, vim.api.nvim_list_bufs())
	update_buf_table(bufs)

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
