local ok, async_task = pcall(require, "blink.lib.task")

if not ok then
	-- fallback for older blink.cmp versions
	local async = require("blink.cmp.lib.async")

	async_task = {
		resolve = function(value)
			return async.task.empty():map(function()
				return value
			end)
		end,
	}
end

local CompletionItemKind = require("blink.cmp.types").CompletionItemKind
local kind_icons = require("blink.cmp.config").appearance.kind_icons

local M = { config = {} }

function M.new(opts)
	local self = setmetatable({}, { __index = M })

	self.config = vim.tbl_deep_extend("keep", opts or {}, {
		insert = true,
		minLength = 3,
		onlyCurrentFiletype = false,
		trigger_characters = {},
		custom_kind = "Yank",
		kind_icon = "󰉿",
	})

	local kind_name = self.config.custom_kind
	local icon = self.config.kind_icon

	if icon and not CompletionItemKind[kind_name] then
		table.insert(CompletionItemKind, kind_name)
		CompletionItemKind[kind_name] = #CompletionItemKind
		kind_icons[kind_name] = icon
		local hl_group = "BlinkCmpKind" .. kind_name

		local ok = pcall(vim.api.nvim_get_hl, 0, { name = hl_group })
		if not ok then
			vim.api.nvim_set_hl(0, hl_group, { link = "PmenuKind" })
		end
	end

	return self
end

function M:get_trigger_characters()
	return self.config.trigger_characters or {}
end

---@param context blink.cmp.Context
function M:get_completions(context, callback)
	local task = async_task.resolve(nil):map(function()
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
		local kind_name = self.config.custom_kind or "Text"

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
					kind = CompletionItemKind[kind_name] or CompletionItemKind.Text,
					kind_name = kind_name,
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
