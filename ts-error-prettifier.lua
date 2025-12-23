-- ts-error-prettifier.lua
-- An improved Neovim plugin to make TypeScript errors more readable.
-- Location: e.g., ~/.config/nvim/lua/ts-error-prettifier.lua

local M = {}

-- Default configuration options
local config = {
  indent = "  ",
  max_line_length = 80,
  show_icons = true,
  auto_open_float = false,
  highlight_groups = {
    title = "DiagnosticError",
    actual = "DiagnosticInfo",
    expected = "DiagnosticHint",
    separator = "Comment",
  },
  patterns = {
    assignability = {
      pattern = "[Tt]ype '(.+)' is not assignable to .*type '(.+)'%.?",
      labels = { "Actual type:", "Expected type:" },
    },
    parameter = {
      pattern = "[Aa]rgument of type '(.+)' is not assignable to parameter of type '(.+)'%.?",
      labels = { "Argument type:", "Parameter type:" },
    },
    property = {
      pattern = "Property '(.+)' does not exist on type '(.+)'%.?",
      labels = { "Property:", "Type:" },
    },
  },
}

-- Utility function to count nested depth
local function get_nesting_depth(str)
  local depth = 0
  for i = 1, #str do
    local char = str:sub(i, i)
    if char == "{" or char == "[" or char == "(" then
      depth = depth + 1
    end
  end
  return depth
end

-- Enhanced type formatter with better handling of complex types
local function format_type_string(type_str)
  if not type_str or type_str:match("^%s*$") then
    return ""
  end

  -- Handle simple types quickly
  if #type_str < 20 and not type_str:find("[{;|]") then
    return type_str
  end

  local formatted_parts = {}
  local indent_level = 0
  local in_generic = 0

  -- Normalize spacing around key characters
  type_str = type_str:gsub("%s*([{}|;,])%s*", "%1")
  
  -- Handle angle brackets for generics
  type_str = type_str:gsub("%s*([<>])%s*", "%1")
  
  -- Add strategic newlines
  type_str = type_str:gsub("([{|,;])", "%1\n")
  type_str = type_str:gsub("}", "\n}")
  
  -- Process each line
  for line in type_str:gmatch("([^\n]+)") do
    line = line:match("^%s*(.-)%s*$")
    
    -- Track generic depth
    for i = 1, #line do
      local char = line:sub(i, i)
      if char == "<" then
        in_generic = in_generic + 1
      elseif char == ">" then
        in_generic = math.max(0, in_generic - 1)
      end
    end
    
    -- Adjust indentation for closing braces
    if line:find("}", 1, true) and in_generic == 0 then
      indent_level = math.max(0, indent_level - 1)
    end
    
    -- Add indented line if not empty
    if not line:match("^%s*$") then
      local indented = string.rep(config.indent, indent_level) .. line
      
      -- Break long lines at union operators
      if #indented > config.max_line_length and line:find("|") then
        indented = indented:gsub("%s*|%s*", "\n" .. string.rep(config.indent, indent_level) .. "| ")
      end
      
      table.insert(formatted_parts, indented)
    end
    
    -- Adjust indentation for opening braces
    if line:find("{", 1, true) and in_generic == 0 then
      indent_level = indent_level + 1
    end
  end
  
  local result = table.concat(formatted_parts, "\n")
  return result:gsub("\n%s*\n", "\n")
end

-- Format a specific error pattern
local function format_pattern_match(pattern_config, match1, match2)
  local formatted_match1 = format_type_string(match1)
  local formatted_match2 = format_type_string(match2)
  
  -- Don't format if both are simple
  if #match1 < 20 and #match2 < 20 and not match1:find("[{;|]") and not match2:find("[{;|]") then
    return nil
  end
  
  local icon = config.show_icons and "❌ " or ""
  local separator = string.rep("=", 50)
  
  local new_message = {
    icon .. "Type Mismatch",
    separator,
    pattern_config.labels[1],
    formatted_match1,
    "",
    pattern_config.labels[2],
    formatted_match2,
    separator,
  }
  
  return table.concat(new_message, "\n")
end

-- Main prettification function with multiple pattern support
local function prettify_message(msg)
  -- Try each configured pattern
  for name, pattern_config in pairs(config.patterns) do
    local match1, match2 = msg:match(pattern_config.pattern)
    if match1 and match2 then
      local formatted = format_pattern_match(pattern_config, match1, match2)
      if formatted then
        return formatted
      end
    end
  end
  
  return msg
end

-- Create a floating window with formatted diagnostics
local function show_diagnostic_float()
  local diagnostics = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })
  
  if #diagnostics == 0 then
    return
  end
  
  local lines = {}
  for _, diag in ipairs(diagnostics) do
    local formatted = prettify_message(diag.message)
    for line in formatted:gmatch("[^\n]+") do
      table.insert(lines, line)
    end
    table.insert(lines, "")
  end
  
  vim.diagnostic.open_float(nil, {
    border = "rounded",
    format = function(diagnostic)
      return diagnostic.message
    end,
  })
end

-- Setup function with enhanced configuration
M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  
  -- Configure diagnostics formatting
  vim.diagnostic.config({
    format = function(diagnostic)
      if diagnostic.source == "tsserver" and diagnostic.severity == vim.diagnostic.severity.ERROR then
        diagnostic.message = prettify_message(diagnostic.message)
      end
      return diagnostic
    end,
    virtual_text = {
      prefix = config.show_icons and "●" or "■",
      format = function(diagnostic)
        if diagnostic.source == "tsserver" and diagnostic.severity == vim.diagnostic.severity.ERROR then
          -- Show abbreviated message in virtual text
          local first_line = diagnostic.message:match("^([^\n]+)")
          return first_line or diagnostic.message
        end
        return diagnostic.message
      end,
    },
  })
  
  -- Set up keybindings if auto_open_float is enabled
  if config.auto_open_float then
    vim.api.nvim_create_autocmd("CursorHold", {
      pattern = { "*.ts", "*.tsx", "*.js", "*.jsx" },
      callback = function()
        local diagnostics = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })
        if #diagnostics > 0 then
          show_diagnostic_float()
        end
      end,
    })
  end
  
  -- Create user command for manual float opening
  vim.api.nvim_create_user_command("TsPrettifyFloat", show_diagnostic_float, {})
  
  local icon = config.show_icons and "✅ " or ""
  vim.notify(
    icon .. "TypeScript Error Prettifier is active!",
    vim.log.levels.INFO,
    { title = "ts-error-prettifier" }
  )
end

-- Export show_diagnostic_float for manual use
M.show_float = show_diagnostic_float

return M