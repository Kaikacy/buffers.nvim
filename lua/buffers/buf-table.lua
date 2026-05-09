local state = require("buffers.state")

---@class buffers.BufTable
---@field key2buf table<string, number> Key to buf; Key is keycode
---@field buf2key table<number, string> Buf to key
---@field order string[] Key order
local BufTable = {}
BufTable.__index = BufTable

---Ordered Table of buffers and keys
---Used to preserve buf to key mappings for consistency and also saves key to buf
---@return buffers.BufTable
function BufTable.new()
	---@type buffers.BufTable
	return setmetatable({
		key2buf = {},
		buf2key = {},
		order = {},
	}, BufTable)
end

---Set or create an entry
function BufTable:set(key, buf)
	if self.key2buf[key] == nil then
		table.insert(self.order, key)
	end
	self.key2buf[key] = buf
	self.buf2key[buf] = key
end

---Remove an entry with specified key
function BufTable:remove_key(key)
	for i, k in ipairs(self.order) do
		if k == key then
			local buf = self.key2buf[key]
			self.key2buf[key] = nil
			self.buf2key[buf] = nil
			table.remove(self.order, i)
			return
		end
	end
end

---Remove an entry with specified buf
function BufTable:remove_buf(buf)
	local key = self.buf2key[buf]
	for i, k in ipairs(self.order) do
		if k == key then
			self.key2buf[key] = nil
			self.buf2key[buf] = nil
			table.remove(self.order, i)
			return
		end
	end
end

---Create key from name
---@param name string
---@return string?
function BufTable:create_buf_key(name)
	local actual_name = name
	local check_name = actual_name:lower()
	local i = 1
	local key = check_name:sub(i, i)
	while self.key2buf[key] or string.find(state.opts.chars, key, 1, true) == nil do
		if i > #check_name then
			if check_name == actual_name then
				-- Dumb method
				for j = 1, #state.opts.chars do
					key = string.sub(state.opts.chars, j, j)
					if not self.key2buf[key] then
						return key
					end
				end
				return nil
			end
			i = 1
			-- Lowercase letters are occupied, so try uppercase
			check_name = actual_name:upper()
		end
		key = check_name:sub(i, i)
		i = i + 1
	end

	return key
end

---Ordered key and buf pairs iterator
function BufTable:ordered_iter()
	local i = 0
	return function()
		i = i + 1
		local key = self.order[i]
		if key then
			return key, self.key2buf[key]
		end
	end
end

return BufTable
