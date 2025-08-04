local M = {}

---range is end-exclusive path name without the tail
---@param full_path string
---@return string, integer[]
function M.relative_path(full_path)
	local rel_path = vim.fn.fnamemodify(full_path, ":~:.")
	local dir_name = vim.fn.fnamemodify(rel_path, ":h")
	if dir_name == "." then
		return rel_path, { 0, 0 }
	end
	return rel_path, { 0, #dir_name + 1 }
end

---range is end-exclusive path name without the tail
---@param full_path string
---@return string, integer[]
function M.filename_first(full_path)
	local file_name = vim.fn.fnamemodify(full_path, ":t")
	local dir_name = vim.fn.fnamemodify(full_path, ":~:.:h")
	if dir_name == "." then
		return file_name, { 0, 0 }
	end
	local formatted = file_name .. " " .. dir_name
	return formatted, { #formatted - #dir_name, #formatted }
end

return M
