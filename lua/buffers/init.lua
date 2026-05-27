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

local devicons_loaded, devicons = pcall(require, "nvim-web-devicons")

local utils = require("buffers.utils")
local state = require("buffers.state")

---@param opts buffers.Config
local function set_defaults(opts)
	state.opts.width = opts.width or { 0, 0.5 }
	state.opts.height = opts.height or { 0, 0.5 }
	state.opts.pos = opts.pos or "center_right"
	state.opts.border = opts.border or "single"
	state.opts.win_opts = opts.win_opts or {}
	state.opts.chars = opts.chars or "qwertyuiopasdfghjklzxcvbnm1234567890"
	state.opts.filter = opts.filter or function(buf) return vim.fn.buflisted(buf) == 1 end
	state.opts.close_keys = opts.close_keys or { "<ESC>" }
	state.opts.separator = opts.separator or " | "
	state.opts.formatter = "relative_path"
	state.format = require("buffers.formatters")[state.opts.formatter]
	if opts.formatter then
		state.opts.formatter = opts.formatter
		if type(opts.formatter) == "string" then
			local format = require("buffers.formatters")[opts.formatter]
			if format then
				state.format = format
			else
				utils.notify(("Formatter '%s' is not available"):format(opts.formatter), vim.log.levels.ERROR)
			end
		else -- Function
			state.format = opts.formatter
		end
	end
	if devicons_loaded then
		state.opts.icons = opts.icons
	else
		if opts.icons then
			utils.notify("nvim-web-devicons is not loaded, but `icons` is enabled", vim.log.levels.WARN)
		end
		state.opts.icons = false
	end
end

local function update_buf_table(bufs)
	local old_bufs = state.buf_table.buf_ord
	state.buf_table.buf_ord = bufs -- Invalid state
	-- Delete old entries
	for _, old_buf in ipairs(old_bufs) do
		if not vim.list_contains(bufs, old_buf) then
			local key = state.buf_table.buf2key[old_buf]
			state.buf_table.buf2key[old_buf] = nil
			state.buf_table.key2buf[key] = nil
		end
	end
	-- Add new entries
	for _, buf in ipairs(bufs) do
		if not state.buf_table.buf2key[buf] then
			local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":t")
			local key = state.buf_table:create_buf_key(name, state.opts.chars)
			if not key then
				utils.notify(("No key available for %d buffer: '%s'"):format(buf, name), vim.log.levels.ERROR)
				utils.notify("Try expanding `chars` list", vim.log.levels.INFO)
				return true
			end
			state.buf_table.buf2key[buf] = key
			state.buf_table.key2buf[key] = buf
		end
	end
end

local function register_buffers()
	vim.api.nvim_buf_clear_namespace(state.buf, state.ns_hl, 0, -1)

	local lines = {}

	for i, key, buf in state.buf_table:ordered_iter() do
		local full_name = vim.api.nvim_buf_get_name(buf)
		local segments = state.format(full_name, buf)

		local icon, icon_hl, icon_segment
		local icon_len = 0
		if state.opts.icons then
			icon, icon_hl = devicons.get_icon_color(
				vim.fn.fnamemodify(full_name, ":t"),
				vim.fn.fnamemodify(full_name, ":e"),
				{ default = true }
			)
			icon = icon .. " "
			icon_len = vim.fn.strdisplaywidth(icon)
			icon_segment = { icon, icon_hl }
		end

		local text_len = 0
		for _, segment in ipairs(segments) do
			text_len = text_len + #segment[1]
		end
		state.exact_width = math.max(state.exact_width, #key + #state.opts.separator + icon_len + text_len)

		-- Prepend key, separator and icon
		segments = vim.list_extend({ { key .. state.opts.separator, "NormalFloat" }, icon_segment }, segments)

		if i == 1 then
			-- virt_lines displays below extmark, so first line should be virt_text
			vim.api.nvim_buf_set_extmark(
				state.buf,
				state.ns_hl,
				0,
				0,
				{ virt_text = segments, virt_text_win_col = 0, strict = false }
			)
		else
			table.insert(lines, segments)
		end

		state.exact_height = i
	end

	vim.api.nvim_buf_set_extmark(
		state.buf,
		state.ns_hl,
		0,
		0,
		{ virt_lines = lines, virt_lines_leftcol = true, strict = false }
	)
end

local function get_win_config()
	local width = state.opts.width
	if type(width) == "table" then
		width = utils.clamp(state.exact_width, utils.resolve_width(width[1]), utils.resolve_width(width[2]))
	end
	local height = state.opts.height
	if type(height) == "table" then
		height = utils.clamp(state.exact_height, utils.resolve_height(height[1]), utils.resolve_height(height[2]))
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
		utils.notify("Invalid value for `pos` option", vim.log.levels.ERROR)
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
	if win_config == nil then return end

	if not vim.api.nvim_win_is_valid(state.win) then
		state.win = vim.api.nvim_open_win(state.buf, false, win_config)
		vim.api.nvim_win_set_hl_ns(state.win, state.ns_hl)
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
		utils.notify(("No buffer bound to '%s'"):format(vim.fn.keytrans(char)), vim.log.levels.WARN)
	end)
end

---Switch to selected buffer
function M.switch() M.toggle(vim.api.nvim_set_current_buf) end

---Delete selected buffer with :bdelete
---@param force boolean
function M.delete(force)
	M.toggle(function(buf) vim.cmd.bdelete(buf .. "bdelete" .. force and "!" or "") end)
end

return M
