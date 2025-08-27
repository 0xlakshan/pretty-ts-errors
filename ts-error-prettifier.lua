-- ts-error-prettifier.lua
-- A simple Neovim plugin to make TypeScript errors more readable.
-- Location: e.g., ~/.config/nvim/lua/ts-error-prettifier.lua
-- Or for a plugin structure: ~/.config/nvim/plugin/ts-error-prettifier.lua

local M = {}

--[[
This function takes a string containing a TypeScript type definition
(e.g., "{ a: string; b: { c: number; }; }") and formats it with
proper indentation to make it readable.
]]
local function format_type_string(type_str)
	local formatted = ""
	local indent_level = 0
	local indent_char = "  " -- Two spaces for indentation

	-- Add a newline and indent after opening braces and semicolons
	type_str = type_str:gsub("({)", "%1\n")
	type_str = type_str:gsub("(;)", "%1\n")
	-- Add a newline before closing braces
	type_str = type_str:gsub("(})", "\n%1")

	for char in type_str:gmatch(".") do
		if char == "{" then
			formatted = formatted .. "{\n"
			indent_level = indent_level + 1
			formatted = formatted .. string.rep(indent_char, indent_level)
		elseif char == "}" then
			indent_level = indent_level - 1
			if indent_level < 0 then
				indent_level = 0
			end -- Safety check
			-- Remove trailing spaces from previous line before adding the brace
			formatted = formatted:gsub("%s*$", "")
			formatted = formatted .. "\n" .. string.rep(indent_char, indent_level) .. "}"
		elseif char == "\n" then
			-- Trim whitespace and add a newline, followed by new indentation
			formatted = formatted:gsub("%s*$", "") .. "\n" .. string.rep(indent_char, indent_level)
		else
			formatted = formatted .. char
		end
	end

	-- Final cleanup: remove empty lines and trailing/leading whitespace
	formatted = formatted:gsub("\n%s*\n", "\n")
	formatted = formatted:gsub("^%s+", ""):gsub("%s+$", "")
	-- Remove space after a newline which might be added by the loop
	formatted = formatted:gsub("\n ", "\n")

	return formatted
end

--[[
The main function that reformats a diagnostic message.
It looks for the common "Type '...' is not assignable to type '...'" pattern.
]]
local function prettify_message(msg)
	-- Match the two types in the error message
	local match1, match2 = msg:match("Type '(.+)' is not assignable to type '(.+)'%.")

	if match1 and match2 then
		-- We found a type mismatch error, let's format it.
		local formatted_type1 = format_type_string(match1)
		local formatted_type2 = format_type_string(match2)

		local new_message = {
			"❌ Type Mismatch",
			"=================",
			"Got:",
			formatted_type1,
			"", -- Spacer
			"Expected:",
			formatted_type2,
			"=================",
		}

		-- Check for more details in the original message
		local details = msg:match("'%. (.+)")
		if details then
			table.insert(new_message, "")
			table.insert(new_message, "Details: " .. details)
		end

		return table.concat(new_message, "\n")
	end

	-- If the pattern doesn't match, return the original message
	return msg
end

--[[
The setup function that configures Neovim's diagnostics.
This is the function you'll call from your init.lua.
]]
M.setup = function()
	vim.diagnostic.config({
		-- This function is called for each diagnostic message.
		format = function(diagnostic)
			-- Only apply formatting to errors from the TypeScript language server
			if diagnostic.source == "tsserver" and diagnostic.severity == vim.diagnostic.severity.ERROR then
				diagnostic.message = prettify_message(diagnostic.message)
			end
			return diagnostic
		end,
	})
	vim.notify("✅ TypeScript Error Prettifier is active!", vim.log.levels.INFO)
end

-- If you place this file in `plugin/`, Neovim will run it on startup.
-- You can call setup directly here if you don't need lazy loading.
-- For lazy-loading with package managers, you'll call M.setup() yourself.
if vim.g.ts_error_prettifier_auto_setup then
	M.setup()
end

return M
