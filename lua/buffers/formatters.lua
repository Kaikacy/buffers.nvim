local M = {}

---@alias buffers.hl_range [string, integer, integer] hl-group, start and end column (0-based, end-exclusive)
---@alias buffers.formatter fun(full_name: string, buf: integer): string, buffers.hl_range[]?

---@type buffers.formatter
function M.relative_path(full_name)
	local rel_path = vim.fn.fnamemodify(full_name, ":~:.")
	local dir_name = vim.fn.fnamemodify(rel_path, ":h")

	if dir_name == "." then
		return rel_path
	end

	return rel_path, { { "Comment", 0, #dir_name + 1 } }
end

-- TODO
---@type buffers.formatter
function M.filename_first(full_path)
	local file_name = vim.fn.fnamemodify(full_path, ":t")
	local dir_name = vim.fn.fnamemodify(full_path, ":~:.:h")

	if devicons_loaded and vim.g.buffers_config.icons then
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
