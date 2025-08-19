local M = {}

local devicons_loaded, devicons = pcall(require, "nvim-web-devicons")

---@alias formatter fun(full_path: string): string, integer[]|nil returns formatted string and hl range

---range is end-exclusive path name without the tail
---@type formatter
function M.relative_path(full_path)
	local rel_path = vim.fn.fnamemodify(full_path, ":~:.")
	local dir_name = vim.fn.fnamemodify(rel_path, ":h")
	local dir_offset = 0

	if devicons_loaded and vim.g.buffers_config.icon then
		local icon, _ = devicons.get_icon(
			vim.fn.fnamemodify(full_path, ":t"),
			vim.fn.fnamemodify(full_path, ":e"),
			{ default = true }
		)
		if icon then
			rel_path = icon .. " " .. rel_path
			dir_offset = #icon + 1
		end
	end

	if dir_name == "." then
		return rel_path
	end

	return rel_path, { dir_offset, #dir_name + dir_offset + 1 }
end

---range is end-exclusive path name without the tail
---@type formatter
function M.filename_first(full_path)
	local file_name = vim.fn.fnamemodify(full_path, ":t")
	local dir_name = vim.fn.fnamemodify(full_path, ":~:.:h")

	if devicons_loaded and vim.g.buffers_config.icon then
		local icon, _ = devicons.get_icon(
			vim.fn.fnamemodify(full_path, ":t"),
			vim.fn.fnamemodify(full_path, ":e"),
			{ default = true }
		)
		if icon then
			file_name = icon .. " " .. file_name
		end
	end

	if dir_name == "." then
		return file_name
	end

	local formatted = file_name .. " " .. dir_name
	return formatted, { #formatted - #dir_name, #formatted }
end

return M
