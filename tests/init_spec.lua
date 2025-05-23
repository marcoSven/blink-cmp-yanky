local yanky = require("blink-yanky")

describe("blink-yanky yank source", function()
	it("should create a new instance", function()
		local src = yanky.new({})
		assert.is_table(src)
		assert.is_function(src.get_completions)
	end)

	it("should return expected completions", function(done)
		local src = yanky.new({ minLength = 0 })

		local context = {
			cursor = { 1, 1 },
			bounds = { start_col = 1 },
		}

		-- This will be called asynchronously by get_completions
		local callback_called = false
		src:get_completions(context, function(completions)
			callback_called = true
			assert.is_table(completions)
			assert.is_true(completions.is_incomplete_forward)
			assert.is_true(completions.is_incomplete_backward)
			assert.is_table(completions.items)
			done()
		end)
	end)

	it("returns empty items if no yank history", function(done)
		local src = yanky.new({ minLength = 0 })
		local context = { cursor = { 1, 1 }, bounds = { start_col = 1 } }

		-- Mock yank history to empty
		package.loaded["yanky.history"] = {
			all = function()
				return {}
			end,
		}

		src:get_completions(context, function(completions)
			assert.is_table(completions.items)
			assert.are_equal(0, #completions.items)
			done()
		end)
	end)

	it("resolve returns modified textEdit when insert = true", function(done)
		local src = yanky.new({ insert = true })
		local item = {
			insertText = "test text",
			textEdit = { newText = "" },
		}

		src:resolve(item, function(resolved)
			assert.are_equal("test text", resolved.textEdit.newText)
			-- Defer done() to next event loop tick so test runner registers it correctly
			vim.defer_fn(function()
				done()
			end, 1)
		end)
	end)
	-- onlyCurrentFiletype filtering
	it("filters history by current filetype when onlyCurrentFiletype = true", function(done)
		local src = yanky.new({ onlyCurrentFiletype = true, minLength = 0 })

		local fake_history = {
			{ regcontents = "foo", filetype = "lua" },
			{ regcontents = "bar", filetype = "python" },
			{ regcontents = "baz", filetype = "lua" },
		}
		package.loaded["yanky.history"] = {
			all = function()
				return fake_history
			end,
		}

		vim = vim or {}
		vim.bo = vim.bo or {}
		vim.bo.filetype = "lua"
		vim.trim = vim.trim or function(s)
			return s
		end

		local context = { cursor = { 1, 1 }, bounds = { start_col = 1 } }

		src:get_completions(context, function(completions)
			assert.is_table(completions.items)
			-- Only items with filetype lua should be present
			for _, item in ipairs(completions.items) do
				assert.is_true(item.insertText == "foo" or item.insertText == "baz")
			end
			done()
		end)
	end)

	-- trigger_characters usage
	it("returns configured trigger_characters", function()
		local triggers = { "a", "b", "c" }
		local src = yanky.new({ trigger_characters = triggers })
		local result = src:get_trigger_characters()
		assert.are.same(triggers, result)
	end)

	-- Cancellation behavior returned by get_completions
	it("returns a cancellation function from get_completions", function()
		local src = yanky.new({})
		local context = { cursor = { 1, 1 }, bounds = { start_col = 1 } }
		local canceled = false

		local cancel_fn = src:get_completions(context, function() end)
		-- cancel_fn should be a function
		assert.is_function(cancel_fn)

		-- Simulate cancellation by calling the function
		-- It won't do anything here, but should not error
		cancel_fn()
	end)

	it("filters out yanks shorter than minLength", function(done)
		local src = yanky.new({ minLength = 5 })

		local fake_history = {
			{ regcontents = "1234", filetype = "lua" }, -- length 4, should be filtered out
			{ regcontents = "12345", filetype = "lua" }, -- length 5, should be included
			{ regcontents = "123456789", filetype = "lua" }, -- length 9, should be included
		}

		package.loaded["yanky.history"] = {
			all = function()
				return fake_history
			end,
		}

		local context = { cursor = { 1, 1 }, bounds = { start_col = 1 } }

		src:get_completions(context, function(completions)
			assert.is_table(completions.items)
			for _, item in ipairs(completions.items) do
				assert.is_true(#item.insertText >= 5)
			end
			done()
		end)
	end)
end)
