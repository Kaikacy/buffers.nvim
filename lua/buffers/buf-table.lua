---@class buffers.BufTable
---@field key2buf table<string, integer> Key to buf; Key is keycode
---@field buf2key table<integer, string> Buf to key
---@field buf_ord integer[] Buf order
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
		buf_ord = {},
	}, BufTable)
end

---Set or create an entry
function BufTable:set(key, buf)
	if self.buf2key[buf] == nil then
		table.insert(self.buf_ord, buf)
	end
	self.key2buf[key] = buf
	self.buf2key[buf] = key
end

---Remove an entry with specified key
function BufTable:remove_key(key)
	local buf = self.key2buf[key]
	for i, b in ipairs(self.buf_ord) do
		if b == buf then
			self.key2buf[key] = nil
			self.buf2key[buf] = nil
			table.remove(self.buf_ord, i)
			return
		end
	end
end

---Remove an entry with specified buf
function BufTable:remove_buf(buf)
	for i, b in ipairs(self.buf_ord) do
		if b == buf then
			local key = self.buf2key[buf]
			self.key2buf[key] = nil
			self.buf2key[buf] = nil
			table.remove(self.buf_ord, i)
			return
		end
	end
end

---Create key from name
---@param name string
---@return string?
function BufTable:create_buf_key(name, chars)
	local actual_name = name
	local check_name = actual_name:lower()
	local i = 1
	local key = check_name:sub(i, i)
	while self.key2buf[key] or string.find(chars, key, 1, true) == nil do
		if i > #check_name then
			if check_name == actual_name then
				-- Dumb method
				for j = 1, #chars do
					key = string.sub(chars, j, j)
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

---Ordered index (1-based), key and buf iterator
function BufTable:ordered_iter()
	local i = 0
	return function()
		i = i + 1
		local buf = self.buf_ord[i]
		if buf then
			return i, self.buf2key[buf], buf
		end
	end
end

return BufTable
