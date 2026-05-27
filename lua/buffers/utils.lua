local M = {}

---@param msg string
---@param level? integer
function M.notify(msg, level) vim.notify(msg, level, { title = "buffers.nvim" }) end

---@param n number
---@param min number
---@param max number
---@return number
function M.clamp(n, min, max) return math.min(math.max(min, n), max) end

---@param width number
---@return integer
function M.resolve_width(width)
	if width > 0 and width <= 1 then
		return vim.fn.round(vim.o.columns * width)
	else
		return width
	end
end

---@param height number
---@return integer
function M.resolve_height(height)
	if height > 0 and height <= 1 then
		return vim.fn.round(vim.o.lines * height)
	else
		return height
	end
end

return M
