---@type table<string, buffers.formatter>
local M = {}

---@alias buffers.highlight [string, string[]|string] text, hl-group
---@alias buffers.formatter fun(full_path: string, buf: integer): buffers.highlight[]

function M.relative_path(full_path)
	local file_name = vim.fn.fnamemodify(full_path, ":t")
	local path_head = vim.fn.fnamemodify(full_path, ":~:.:h")
	if path_head == "." then return { { file_name, "NormalFloat" } } end

	return { { path_head .. "/", "Comment" }, { file_name, "NormalFloat" } }
end

function M.filename_first(full_path)
	local file_name = vim.fn.fnamemodify(full_path, ":t")
	local path_head = vim.fn.fnamemodify(full_path, ":~:.:h")
	if path_head == "." then return { { file_name, "NormalFloat" } } end

	return { { file_name .. " ", "NormalFloat" }, { path_head, "Comment" } }
end

return M
