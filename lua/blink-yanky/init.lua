local async = require("blink.cmp.lib.async")

local M = { config = {} }

function M.new(opts)
	local self = setmetatable({}, { __index = M })
	self.config = vim.tbl_deep_extend("keep", opts or {}, {
		insert = true,
		minLength = 3,
		onlyCurrentFiletype = false,
		trigger_characters = {},
	})
	return self
end

function M:get_trigger_characters()
	return self.config.trigger_characters or {}
end

---@param context blink.cmp.Context
function M:get_completions(context, callback)
	local task = async.task.empty():map(function()
		local history = require("yanky.history").all()
		local ft = vim.bo.filetype

		if self.config.onlyCurrentFiletype then
			history = vim.tbl_filter(function(item)
				return item.filetype == ft
			end, history)
		end

		history = vim.tbl_filter(function(item)
			return item.regcontents and #vim.trim(item.regcontents) >= self.config.minLength
		end, history)

		local seen = {}
		local items = {}

		for _, item in ipairs(history) do
			local text = vim.trim(item.regcontents or "")
			if not seen[text] then
				seen[text] = true

				local short_label = #text > 30 and text:sub(1, 30) .. "…" or text

				table.insert(items, {
					label = short_label,
					insertText = text,
					filterText = text,
					documentation = {
						kind = "markdown",
						value = string.format("```%s\n%s\n```", item.filetype or "", text),
					},
					kind = require("blink.cmp.types").CompletionItemKind.Text,
					textEdit = {
						range = {
							start = {
								line = context.cursor[1] - 1,
								character = context.bounds.start_col - 1,
							},
							["end"] = {
								line = context.cursor[1] - 1,
								character = context.cursor[2],
							},
						},
						newText = "",
					},
				})
			end
		end

		callback({
			is_incomplete_forward = true,
			is_incomplete_backward = true,
			items = items,
			context = context,
		})

		return nil
	end)

	return function()
		task:cancel()
	end
end

---@param item table
function M:resolve(item, callback)
	local resolved = vim.deepcopy(item)
	if self.config.insert then
		resolved.textEdit.newText = resolved.insertText
	end
	callback(resolved)
end

---@type blink.cmp.Source
return M
