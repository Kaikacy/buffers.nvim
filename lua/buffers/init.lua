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
local devicons_loaded, devicons = pcall(require, "nvim-web-devicons")

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
	state.opts.icons = (opts.icons and devicons_loaded) or false
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
		local key = new_table:create_buf_key(name, state.opts.chars)
		if not key then
			notify(("No key available for %d buffer: '%s'"):format(buf, name), vim.log.levels.ERROR)
			notify("Try expanding `chars` list", vim.log.levels.INFO)
			return true
		end
		new_table:set(key, buf)
	end
	state.buf_table = new_table
end

local function register_buffers()
	local format = type(state.opts.formatter) == "string" and require("buffers.formatters")[state.opts.formatter]
		or state.opts.formatter
	if not format then
		notify(("Formatter '%s' is not available"):format(state.opts.formatter), vim.log.levels.ERROR)
		return true
	end

	local lines = {}
	local ranges_table = {}

	for i, key, buf in state.buf_table:ordered_iter() do
		local text, ranges = format(buf)
		local line = key .. state.opts.separator .. text
		state.exact_width = math.max(state.exact_width, #line)

		table.insert(lines, line)
		ranges_table[i] = ranges -- Might be nil and nothing will be assigned
	end
	state.exact_height = #lines

	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)

	-- NOTE: Key is assumed to be single character
	local text_start = 1 + #state.opts.separator -- key + separator
	for i, ranges in pairs(ranges_table) do
		for _, range in ipairs(ranges) do
			vim.api.nvim_buf_set_extmark(
				state.buf,
				state.ns,
				i - 1,
				text_start + range[2],
				{ end_col = text_start + range[3], hl_group = range[1] }
			)
		end
	end
end

local function clamp(n, min, max)
	return math.min(math.max(min, n), max)
end

local function resolve_width(width)
	if width > 0 and width <= 1 then
		return vim.fn.round(vim.o.columns * width)
	else
		return width
	end
end

local function resolve_height(height)
	if height > 0 and height <= 1 then
		return vim.fn.round(vim.o.lines * height)
	else
		return height
	end
end

local function get_win_config()
	local width = state.opts.width
	if type(width) == "table" then
		width = clamp(state.exact_width, resolve_width(width[1]), resolve_width(width[2]))
	end
	local height = state.opts.height
	if type(height) == "table" then
		height = clamp(state.exact_height, resolve_height(height[1]), resolve_height(height[2]))
	end

	local row, col = 0, vim.o.columns
	local yanchor = "N"
	-- Nothing to do for 'top_right'
	if state.opts.pos == "center_right" then
		row = bit.rshift(vim.o.lines - height, 1)
	elseif state.opts.position == "bottom_right" then
		yanchor = "S"
		row = vim.o.lines
	else
		notify("Invalid value for `pos` option", vim.log.levels.ERROR)
		return
	end

	return {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		anchor = yanchor .. "E", -- X anchor is always east (right)
		border = state.opts.border,
		style = "minimal",
	}
end

---@param action fun(buf: integer): any
---@return any
---Toggle buffers window with custom action
function M.toggle(action)
	set_defaults(vim.g.buffers_config or {})
	local bufs = vim.tbl_filter(state.opts.filter, vim.api.nvim_list_bufs())
	if update_buf_table(bufs) then -- Error
		return
	end

	if not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(state.buf, "buffers")
		vim.bo[state.buf].buftype = "nofile"
		vim.bo[state.buf].filetype = "buffers"
	end

	if register_buffers() then -- Error
		return
	end

	local win_config = get_win_config()
	if win_config == nil then
		return
	end

	if not vim.api.nvim_win_is_valid(state.win) then
		state.win = vim.api.nvim_open_win(state.buf, false, win_config)
		for key, val in pairs(state.opts.win_opts) do
			vim.wo[state.win][key] = val
		end
	else
		vim.api.nvim_win_hide(state.win)
		return
	end

	vim.schedule(function()
		local ok, char = pcall(vim.fn.getcharstr)
		if not ok then
			vim.api.nvim_win_hide(state.win)
			return
		end

		for _, key in ipairs(state.opts.close_keys) do
			if char == vim.keycode(key) then
				vim.api.nvim_win_hide(state.win)
				return
			end
		end

		for _, key, buf in state.buf_table:ordered_iter() do
			if char == key then -- Key should be single character
				vim.api.nvim_win_hide(state.win)
				return action(buf)
			end
		end

		vim.api.nvim_win_hide(state.win)
		notify(("No buffer bound to '%s'"):format(char), vim.log.levels.WARN)
	end)
end

---Switch to selected buffer
function M.switch()
	M.toggle(vim.api.nvim_set_current_buf)
end

---Delete selected buffer with :bdelete
---@param force boolean
function M.delete(force)
	M.toggle(function(buf)
		vim.cmd.bdelete(buf .. "bdelete" .. force and "!" or "")
	end)
end

return M
