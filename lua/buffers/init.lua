---@class buffers.Config
---@field width? integer window width
---@field min_height? integer minimum window height
---@field position? 'center'|'bottom_right'|'top_right' window position
---@field border? 'none'|'single'|'double'|'rounded'|'solid'|'shadow'|string[] window border
---@field chars? string first available character from buffer name, found in this list, will be used as keymap
---@field backup_chars? string if every character from buffer name is unavailable, then this list gets checked
---@field filter? fun(bufnr: integer): boolean checks if bufnr should be included in buffers table
---@field close_keys? string[] which keys will hide buffers window, without warning, when pressed

local M = {}

local state = {
	buf = -1,
	win = -1,
	cur_buf_line = nil,
}

---@param opts buffers.Config
---@return buffers.Config
local function with_defaults(opts)
	return {
		width = opts.width or 70,
		min_height = opts.min_height or 6,
		position = opts.position or "bottom_right",
		border = opts.border or "single",
		chars = opts.chars or "qwertyuiopasdfghjklzxcvbnm1234567890",
		backup_chars = opts.backup_chars or "QWERTYUIOPASDFGHJKLZXCVBNM_-",
		filter = opts.filter or function(bufnr)
			return vim.api.nvim_get_option_value("buflisted", { buf = bufnr })
				and vim.api.nvim_buf_get_name(bufnr) ~= ""
		end,
		close_keys = opts.close_keys or { "<Esc>" },
	}
end

---@param msg string
---@param level integer|nil
local function notify(msg, level)
	vim.notify(msg, level, { title = "Buffers.nvim" })
end

local function filter_buffers(filter_func)
	return vim.tbl_filter(function(bufnr)
		return filter_func(bufnr)
	end, vim.api.nvim_list_bufs())
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
	while buffer_table:get(char) or string.find(chars, char, 1, true) == nil do
		if i > #name then
			return nil
		end
		char = name:sub(i, i)
		i = i + 1
	end
	return char
end

local function get_buffer_table(buffers, chars, backup_chars)
	local out = require("buffers.ordered-table")()
	for i, bufnr in ipairs(buffers) do
		local fullname = vim.api.nvim_buf_get_name(bufnr)
		local name = vim.fn.fnamemodify(fullname, ":t")
		if name == "" then
			name = fullname
		end
		local char = get_buffer_char(name, out, chars)
		if not char then
			char = get_buffer_char(name, out, backup_chars)
			if not char then
				char = get_char_dumb(out, chars .. backup_chars)
				if not char then
					-- super rare to get here
					notify("No available character left from chars and backup_chars", vim.log.levels.ERROR)
				end
			end
		end
		if char then
			out:insert(char, bufnr)
			if vim.api.nvim_get_current_buf() == bufnr then
				state.cur_buf_line = i
			end
		end
	end
	return out
end

local function register_buffers(buffer_table, base_buf)
	vim.bo[base_buf].modifiable = true
	vim.bo[base_buf].readonly = false
	local lines = {}
	for char, bufnr in buffer_table:orderedPairs() do
		local name = vim.api.nvim_buf_get_name(bufnr)
		name = vim.fn.fnamemodify(name, ":~:.")
		table.insert(lines, char .. " | " .. name)
	end
	vim.api.nvim_buf_set_lines(base_buf, 0, -1, false, {})
	vim.api.nvim_buf_set_lines(base_buf, 0, #lines, false, lines)
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

---toggle buffers window with options
---@param opts buffers.Config
function M.toggle(opts)
	---@diagnostic disable-next-line: redefined-local
	local opts = with_defaults(opts or {})
	local buffers = filter_buffers(opts.filter)
	local buffer_table = get_buffer_table(buffers, opts.chars, opts.backup_chars)

	local win_config = get_win_config(opts, #buffers)
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
		state.win = win
	else
		vim.api.nvim_win_hide(win)
		return
	end

	register_buffers(buffer_table, base_buf)

	vim.bo[base_buf].modifiable = false
	vim.bo[base_buf].readonly = true
	vim.api.nvim_win_set_cursor(win, { state.cur_buf_line or 1, 0 })

	vim.schedule(function()
		local ok, char = pcall(vim.fn.getcharstr)
		if not ok then
			vim.api.nvim_win_hide(win)
			return
		end
		char = vim.fn.keytrans(char)
		for _, key in ipairs(opts.close_keys) do
			if char == key then
				vim.api.nvim_win_hide(win)
				return
			end
		end
		for c, buf in buffer_table:orderedPairs() do
			if char == c then
				vim.api.nvim_win_hide(win)
				vim.api.nvim_set_current_buf(buf)
				return
			end
		end
		notify("No buffer bound to '" .. char .. "'", vim.log.levels.WARN)
		vim.api.nvim_win_hide(win)
	end)
end

return M
