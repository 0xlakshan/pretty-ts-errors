local M = {}

local config = {
  indent = "  ",
  max_line_length = 80,
  show_icons = true,
  auto_open_float = false,
  use_diff_highlighting = true,
  highlight_groups = {
    title = "DiagnosticError",
    actual = "DiagnosticInfo",
    expected = "DiagnosticHint",
    separator = "Comment",
    diff_add = "DiffAdd",
    diff_delete = "DiffDelete",
    diff_text = "DiffText",
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

local function tokenize_type(type_str)
  local tokens = {}
  local current = ""
  
  for i = 1, #type_str do
    local char = type_str:sub(i, i)
    if char:match("[{}|;:,<>%[%]()%s]") then
      if #current > 0 then
        table.insert(tokens, current)
        current = ""
      end
      if not char:match("%s") then
        table.insert(tokens, char)
      end
    else
      current = current .. char
    end
  end
  
  if #current > 0 then
    table.insert(tokens, current)
  end
  
  return tokens
end

local function compute_diff(tokens1, tokens2)
  local m, n = #tokens1, #tokens2
  local dp = {}
  
  for i = 0, m do
    dp[i] = {}
    for j = 0, n do
      if i == 0 then
        dp[i][j] = j
      elseif j == 0 then
        dp[i][j] = i
      else
        local cost = (tokens1[i] == tokens2[j]) and 0 or 1
        dp[i][j] = math.min(
          dp[i-1][j] + 1,
          dp[i][j-1] + 1,
          dp[i-1][j-1] + cost
        )
      end
    end
  end
  
  local diff = {}
  local i, j = m, n
  
  while i > 0 or j > 0 do
    if i > 0 and j > 0 and tokens1[i] == tokens2[j] then
      table.insert(diff, 1, {type = "equal", token = tokens1[i]})
      i, j = i - 1, j - 1
    elseif j > 0 and (i == 0 or dp[i][j-1] <= dp[i-1][j]) then
      table.insert(diff, 1, {type = "add", token = tokens2[j]})
      j = j - 1
    else
      table.insert(diff, 1, {type = "delete", token = tokens1[i]})
      i = i - 1
    end
  end
  
  return diff
end

local function highlight_diff(type1, type2)
  local tokens1 = tokenize_type(type1)
  local tokens2 = tokenize_type(type2)
  local diff = compute_diff(tokens1, tokens2)
  
  local result1 = {}
  local result2 = {}
  
  for _, item in ipairs(diff) do
    if item.type == "equal" then
      table.insert(result1, item.token)
      table.insert(result2, item.token)
    elseif item.type == "delete" then
      table.insert(result1, "[-" .. item.token .. "-]")
    elseif item.type == "add" then
      table.insert(result2, "{+" .. item.token .. "+}")
    end
  end
  
  return table.concat(result1, " "), table.concat(result2, " ")
end

local function format_type_string(type_str)
  if not type_str or type_str:match("^%s*$") then
    return ""
  end

  if #type_str < 20 and not type_str:find("[{;|]") then
    return type_str
  end

  local formatted_parts = {}
  local indent_level = 0
  local in_generic = 0

  type_str = type_str:gsub("%s*([{}|;,])%s*", "%1")
  type_str = type_str:gsub("%s*([<>])%s*", "%1")
  type_str = type_str:gsub("([{|,;])", "%1\n")
  type_str = type_str:gsub("}", "\n}")

  for line in type_str:gmatch("([^\n]+)") do
    line = line:match("^%s*(.-)%s*$")

    for i = 1, #line do
      local char = line:sub(i, i)
      if char == "<" then
        in_generic = in_generic + 1
      elseif char == ">" then
        in_generic = math.max(0, in_generic - 1)
      end
    end

    if line:find("}", 1, true) and in_generic == 0 then
      indent_level = math.max(0, indent_level - 1)
    end

    if not line:match("^%s*$") then
      local indented = string.rep(config.indent, indent_level) .. line

      if #indented > config.max_line_length and line:find("|") then
        indented = indented:gsub("%s*|%s*", "\n" .. string.rep(config.indent, indent_level) .. "| ")
      end
      table.insert(formatted_parts, indented)
    end

    if line:find("{", 1, true) and in_generic == 0 then
      indent_level = indent_level + 1
    end
  end

  local result = table.concat(formatted_parts, "\n")
  return result:gsub("\n%s*\n", "\n")
end

local function simplify_type(type_str)
  if not type_str then return "" end
  
  type_str = type_str:match("^%s*(.-)%s*$")
  
  if #type_str <= 25 then
    return type_str
  end
  
  if type_str:find("^%s*{") then
    local props = {}
    for prop in type_str:gmatch("(%w+)%s*:") do
      table.insert(props, prop)
      if #props >= 3 then break end
    end
    if #props > 0 then
      local result = "{ " .. table.concat(props, ", ")
      local total_props = 0
      for _ in type_str:gmatch("(%w+)%s*:") do
        total_props = total_props + 1
      end
      if total_props > #props then
        result = result .. ", ..."
      end
      return result .. " }"
    end
  end
  
  if type_str:find("|") then
    local parts = {}
    for part in type_str:gmatch("([^|]+)") do
      part = part:match("^%s*(.-)%s*$")
      table.insert(parts, part)
      if #parts >= 3 then break end
    end
    if #parts > 0 then
      local result = table.concat(parts, " | ")
      local total_parts = 0
      for _ in type_str:gmatch("([^|]+)") do
        total_parts = total_parts + 1
      end
      if total_parts > #parts then
        result = result .. " | ..."
      end
      return result
    end
  end
  
  type_str = type_str:gsub("Array<(.-)>", "%1[]")
  
  if #type_str > 40 then
    return type_str:sub(1, 37) .. "..."
  end
  
  return type_str
end

local function truncate_for_virtual_text(msg)
  for name, pattern_config in pairs(config.patterns) do
    local match1, match2 = msg:match(pattern_config.pattern)
    if match1 and match2 then
      local simplified1 = simplify_type(match1)
      local simplified2 = simplify_type(match2)
      return string.format("%s → %s", simplified1, simplified2)
    end
  end
  
  local first_line = msg:match("^([^\n]+)")
  return first_line or msg
end

local function format_pattern_match(pattern_config, match1, match2)
  local formatted_match1 = format_type_string(match1)
  local formatted_match2 = format_type_string(match2)

  if #match1 < 20 and #match2 < 20 and not match1:find("[{;|]") and not match2:find("[{;|]") then
    return nil
  end

  local icon = config.show_icons and "❌ " or ""
  local separator = string.rep("=", 50)
  
  local new_message
  if config.use_diff_highlighting then
    local diff1, diff2 = highlight_diff(match1, match2)
    new_message = {
      icon .. "Type Mismatch (diff view)",
      separator,
      pattern_config.labels[1],
      diff1,
      "",
      pattern_config.labels[2],
      diff2,
      "",
      "Legend: [-removed-] {+added+}",
      separator,
    }
  else
    new_message = {
      icon .. "Type Mismatch",
      separator,
      pattern_config.labels[1],
      formatted_match1,
      "",
      pattern_config.labels[2],
      formatted_match2,
      separator,
    }
  end
  
  return table.concat(new_message, "\n")
end

local function prettify_message(msg)
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

M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

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
          local truncated = truncate_for_virtual_text(diagnostic.message)
          return truncated
        end
        return diagnostic.message
      end,
    },
  })

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

  vim.api.nvim_create_user_command("TsPrettifyFloat", show_diagnostic_float, {})

  local icon = config.show_icons and "✅ " or ""
  vim.notify(
    icon .. "TypeScript Error Prettifier is active!",
    vim.log.levels.INFO,
    { title = "ts-error-prettifier" }
  )
end

M.show_float = show_diagnostic_float

return M
