---@class buffers.BufTable
---@field data table
---@field keys string[] Keycodes; Vim representation
local BufTable = {}
BufTable.__index = BufTable

---Ordered Table of buffers and keys
---Used to preserve buf to key mappings for consistency and also saves key to buf
---@return buffers.BufTable
function BufTable.new()
	return setmetatable({
		data = {}, -- key -> buf and buf -> key
		keys = {}, -- Saves key order
	}, BufTable)
end

---Create a new entry
function BufTable:set(key, buf)
	if self.keys[key] == nil then
		table.insert(self.keys, key)
	end
	self.data[key] = buf
	self.data[buf] = key
end

---If key was provided, get buf, otherwise get key
function BufTable:get(key_or_buf)
	return self.data[key_or_buf]
end

---Remove an entry with specified key
function BufTable:remove(key)
	local buf = self.data[key]
	self.data[key] = nil
	self.data[buf] = nil
	for i, k in ipairs(self.keys) do
		if k == key then
			table.remove(self.keys, i)
			return
		end
	end
end

---Key, buf pairs iterator in order
function BufTable:ordered_iter()
	local i = 0
	return function()
		i = i + 1
		local key = self.keys[i]
		if key then
			return key, self.data[key]
		end
	end
end

return BufTable
