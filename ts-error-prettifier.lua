-- ts-error-prettifier.lua
-- An improved Neovim plugin to make TypeScript errors more readable.
-- Location: e.g., ~/.config/nvim/lua/ts-error-prettifier.lua

local M = {}

-- Default configuration options
local config = {
  indent = "  ", -- Two spaces, but user can override
}

--[[
This function takes a string containing a TypeScript type definition and formats it.
It's rewritten to be more robust and handle complex types, unions, and generics.
]]
local function format_type_string(type_str)
  if not type_str or type_str:match("^%s*$") then
    return ""
  end

  local formatted_parts = {}
  local indent_level = 0

  -- 1. Pre-process the string to normalize spacing and add newlines deterministically.
  -- This makes parsing by line much easier.
  type_str = type_str:gsub("%s*([{}|;,])%s*", "%1") -- Collapse whitespace around delimiters
  type_str = type_str:gsub("([{|,;])", "%1\n") -- Add newline AFTER {, |, ,, ;
  type_str = type_str:gsub("}", "\n}")           -- Add newline BEFORE }

  -- 2. Iterate over lines, not characters, to apply indentation.
  for line in type_str:gmatch("([^\n]+)") do
    line = line:match("^%s*(.-)%s*$") -- Trim whitespace from the line

    if line:find("}", 1, true) then
      indent_level = indent_level - 1
    end
    
    -- Ensure indent level never goes below zero
    if indent_level < 0 then indent_level = 0 end

    if not line:match("^%s*$") then -- Don't add empty lines
        table.insert(formatted_parts, string.rep(config.indent, indent_level) .. line)
    end

    if line:find("{", 1, true) then
      indent_level = indent_level + 1
    end
  end

  -- 3. Final cleanup and concatenation
  local result = table.concat(formatted_parts, "\n")
  return result:gsub("\n%s*\n", "\n") -- Remove any leftover blank lines
end


--[[
The main function that reformats a diagnostic message.
It now uses a more flexible regex pattern to catch more error variations.
]]
local function prettify_message(msg)
  -- A more robust pattern:
  -- - Case-insensitive '[Tt]ype'
  -- - Allows for any characters between the two types with '.*'
  -- - Makes the final period optional with '.?'
  local actual, expected = msg:match("[Tt]ype '(.+)' is not assignable to .*type '(.+)'%.?")

  -- Handle another common pattern for function arguments
  if not actual then
    actual, expected = msg:match("[Aa]rgument of type '(.+)' is not assignable to parameter of type '(.+)'%.?")
  end

  if actual and expected then
    local formatted_actual = format_type_string(actual)
    local formatted_expected = format_type_string(expected)

    -- Don't format if the types are simple and short (less than 20 chars and no newlines)
    if #actual < 20 and #expected < 20 and not actual:find("[{;]") and not expected:find("[{;]") then
        return msg
    end

    local new_message = {
      "❌ Type Mismatch",
      "=================",
      "Actual type:",
      formatted_actual,
      "",
      "Expected type:",
      formatted_expected,
      "=================",
    }
    return table.concat(new_message, "\n")
  end

  return msg -- Return original message if no pattern matches
end

--[[
The setup function now accepts user options to allow for configuration.
]]
M.setup = function(opts)
  -- Merge user options with defaults
  if opts then
    config = vim.tbl_deep_extend("force", config, opts)
  end

  vim.diagnostic.config({
    format = function(diagnostic)
      if
        diagnostic.source == "tsserver"
        and diagnostic.severity == vim.diagnostic.severity.ERROR
        and diagnostic.message
      then
        diagnostic.message = prettify_message(diagnostic.message)
      end
      return diagnostic
    end,
  })

  vim.notify("✅ TypeScript Error Prettifier is active!", vim.log.levels.INFO, { title = "ts-error-prettifier" })
end

return M
