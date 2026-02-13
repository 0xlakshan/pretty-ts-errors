local M = {}

local config = {
  indent = "  ",
  max_line_length = 80,
  show_icons = true,
  auto_open_float = false,
  use_diff_highlighting = true,
  show_type_preview = true,
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

local autocmd_id = nil
local float_open = false
local preview_ns = vim.api.nvim_create_namespace("ts_error_preview")

local function safe_call(fn, fallback)
  local ok, result = pcall(fn)
  if not ok then
    if config.debug then
      vim.notify("ts-error-prettifier: " .. tostring(result), vim.log.levels.WARN)
    end
    return fallback
  end
  return result
end

local function validate_config(user_config)
  if not user_config then
    return true
  end

  if user_config.max_line_length and (type(user_config.max_line_length) ~= "number" or user_config.max_line_length < 20) then
    vim.notify("ts-error-prettifier: max_line_length must be a number >= 20", vim.log.levels.ERROR)
    return false
  end

  if user_config.indent and type(user_config.indent) ~= "string" then
    vim.notify("ts-error-prettifier: indent must be a string", vim.log.levels.ERROR)
    return false
  end

  if user_config.highlight_groups then
    for group, name in pairs(user_config.highlight_groups) do
      if type(name) ~= "string" then
        vim.notify("ts-error-prettifier: highlight group names must be strings", vim.log.levels.ERROR)
        return false
      end
    end
  end

  if user_config.patterns then
    for name, pattern_config in pairs(user_config.patterns) do
      if not pattern_config.pattern or not pattern_config.labels then
        vim.notify("ts-error-prettifier: pattern '" .. name .. "' missing required fields", vim.log.levels.ERROR)
        return false
      end
      if type(pattern_config.labels) ~= "table" or #pattern_config.labels < 2 then
        vim.notify("ts-error-prettifier: pattern '" .. name .. "' labels must be a table with at least 2 items", vim.log.levels.ERROR)
        return false
      end
    end
  end

  return true
end

local function get_nesting_depth(str)
  if not str or type(str) ~= "string" then
    return 0
  end

  return safe_call(function()
    local depth = 0
    for i = 1, #str do
      local char = str:sub(i, i)
      if char == "{" or char == "[" or char == "(" then
        depth = depth + 1
      end
    end
    return depth
  end, 0)
end

local function tokenize_type(type_str)
  if not type_str or type(type_str) ~= "string" then
    return {}
  end

  if #type_str > 10000 then
    return { type_str:sub(1, 1000) .. "..." }
  end

  return safe_call(function()
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
  end, {})
end

local function compute_diff(tokens1, tokens2)
  if not tokens1 or not tokens2 or type(tokens1) ~= "table" or type(tokens2) ~= "table" then
    return {}
  end

  local m, n = #tokens1, #tokens2
  if m > 500 or n > 500 then
    return {}
  end

  return safe_call(function()
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
    local iterations = 0
    local max_iterations = m + n + 100

    while (i > 0 or j > 0) and iterations < max_iterations do
      iterations = iterations + 1
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
  end, {})
end

local function highlight_diff(type1, type2)
  if not type1 or not type2 or type(type1) ~= "string" or type(type2) ~= "string" then
    return type1 or "", type2 or ""
  end

  return safe_call(function()
    local tokens1 = tokenize_type(type1)
    local tokens2 = tokenize_type(type2)
    local diff = compute_diff(tokens1, tokens2)

    if not diff or #diff == 0 then
      return type1, type2
    end

    local result1 = {}
    local result2 = {}

    for _, item in ipairs(diff) do
      if not item or not item.type or not item.token then
        goto continue
      end

      if item.type == "equal" then
        table.insert(result1, item.token)
        table.insert(result2, item.token)
      elseif item.type == "delete" then
        table.insert(result1, "[-" .. item.token .. "-]")
      elseif item.type == "add" then
        table.insert(result2, "{+" .. item.token .. "+}")
      end

      ::continue::
    end

    return table.concat(result1, " "), table.concat(result2, " ")
  end, function()
    return type1, type2
  end)
end

local function format_type_string(type_str)
  if not type_str or type(type_str) ~= "string" or type_str:match("^%s*$") then
    return ""
  end

  if #type_str > 5000 then
    return type_str:sub(1, 4997) .. "..."
  end

  return safe_call(function()
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
      line = line:match("^%s*(.-)%s*$") or line

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
        local indented = string.rep(config.indent or "  ", indent_level) .. line
        if #indented > (config.max_line_length or 80) and line:find("|") then
          indented = indented:gsub("%s*|%s*", "\n" .. string.rep(config.indent or "  ", indent_level) .. "| ")
        end
        table.insert(formatted_parts, indented)
      end

      if line:find("{", 1, true) and in_generic == 0 then
        indent_level = indent_level + 1
      end
    end

    local result = table.concat(formatted_parts, "\n")
    return result:gsub("\n%s*\n", "\n")
  end, type_str)
end

local function simplify_type(type_str)
  if not type_str or type(type_str) ~= "string" then
    return ""
  end

  return safe_call(function()
    type_str = type_str:match("^%s*(.-)%s*$") or type_str

    if #type_str <= 25 then
      return type_str
    end

    if type_str:find("^%s*{") then
      local props = {}
      for prop in type_str:gmatch("(%w+)%s*:") do
        table.insert(props, prop)
        if #props >= 3 then
          break
        end
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
        part = part:match("^%s*(.-)%s*$") or part
        table.insert(parts, part)
        if #parts >= 3 then
          break
        end
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
  end, type_str)
end

local function truncate_for_virtual_text(msg)
  if not msg or type(msg) ~= "string" then
    return ""
  end

  return safe_call(function()
    for name, pattern_config in pairs(config.patterns or {}) do
      if not pattern_config or not pattern_config.pattern then
        goto continue
      end

      local match1, match2 = msg:match(pattern_config.pattern)
      if match1 and match2 then
        local simplified1 = simplify_type(match1)
        local simplified2 = simplify_type(match2)
        return string.format("%s → %s", simplified1, simplified2)
      end

      ::continue::
    end

    local first_line = msg:match("^([^\n]+)")
    return first_line or msg
  end, msg)
end

local function format_pattern_match(pattern_config, match1, match2)
  if not pattern_config or not match1 or not match2 then
    return nil
  end

  return safe_call(function()
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
        pattern_config.labels[1] or "Actual:",
        diff1 or formatted_match1,
        "",
        pattern_config.labels[2] or "Expected:",
        diff2 or formatted_match2,
        "",
        "Legend: [-removed-] {+added+}",
        separator,
      }
    else
      new_message = {
        icon .. "Type Mismatch",
        separator,
        pattern_config.labels[1] or "Actual:",
        formatted_match1,
        "",
        pattern_config.labels[2] or "Expected:",
        formatted_match2,
        separator,
      }
    end

    return table.concat(new_message, "\n")
  end, nil)
end

local function prettify_message(msg)
  if not msg or type(msg) ~= "string" then
    return msg or ""
  end

  return safe_call(function()
    for name, pattern_config in pairs(config.patterns or {}) do
      if not pattern_config or not pattern_config.pattern then
        goto continue
      end

      local match1, match2 = msg:match(pattern_config.pattern)
      if match1 and match2 then
        local formatted = format_pattern_match(pattern_config, match1, match2)
        if formatted then
          return formatted
        end
      end

      ::continue::
    end

    return msg
  end, msg)
end

local function show_inline_preview()
  if not config.show_type_preview then
    return
  end

  return safe_call(function()
    vim.api.nvim_buf_clear_namespace(0, preview_ns, 0, -1)

    local diagnostics = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })
    if not diagnostics or #diagnostics == 0 then
      return
    end

    for _, diag in ipairs(diagnostics) do
      if diag and diag.message and diag.source == "tsserver" and diag.severity == vim.diagnostic.severity.ERROR then
        for name, pattern_config in pairs(config.patterns or {}) do
          if not pattern_config or not pattern_config.pattern then
            goto continue
          end

          local match1, match2 = diag.message:match(pattern_config.pattern)
          if match1 and match2 then
            local simplified_actual = simplify_type(match1)
            local simplified_expected = simplify_type(match2)
            
            local preview_text = string.format("  ⮕ Expected: %s", simplified_expected)
            
            vim.api.nvim_buf_set_extmark(0, preview_ns, diag.lnum, 0, {
              virt_text = {{ preview_text, "DiagnosticHint" }},
              virt_text_pos = "eol",
            })
            
            break
          end

          ::continue::
        end
      end
    end
  end, nil)
end

local function show_diagnostic_float()
  if float_open then
    return
  end

  return safe_call(function()
    local diagnostics = vim.diagnostic.get(0, { lnum = vim.fn.line(".") - 1 })
    if not diagnostics or #diagnostics == 0 then
      return
    end

    float_open = true

    local modified_diagnostics = {}
    for _, diag in ipairs(diagnostics) do
      if diag and diag.message then
        local diag_copy = vim.deepcopy(diag)
        diag_copy.message = prettify_message(diag.message)
        table.insert(modified_diagnostics, diag_copy)
      end
    end

    vim.diagnostic.open_float(nil, {
      border = "rounded",
      source = "always",
    })

    vim.defer_fn(function()
      float_open = false
    end, 100)
  end, nil)
end

M.setup = function(opts)
  if not validate_config(opts) then
    return
  end

  return safe_call(function()
    config = vim.tbl_deep_extend("force", config, opts or {})

    local original_handlers = vim.diagnostic.handlers

    vim.diagnostic.handlers.virtual_text = {
      show = function(namespace, bufnr, diagnostics, opts_vt)
        local modified = {}
        for _, diag in ipairs(diagnostics) do
          local diag_copy = vim.deepcopy(diag)
          if diag.source == "tsserver" and diag.severity == vim.diagnostic.severity.ERROR then
            diag_copy.message = truncate_for_virtual_text(diag.message)
          end
          table.insert(modified, diag_copy)
        end
        return original_handlers.virtual_text.show(namespace, bufnr, modified, opts_vt)
      end,
      hide = original_handlers.virtual_text.hide,
    }

    vim.diagnostic.config({
      virtual_text = {
        prefix = config.show_icons and "●" or "■",
      },
      float = {
        format = function(diagnostic)
          if not diagnostic or not diagnostic.message then
            return ""
          end
          if diagnostic.source == "tsserver" and diagnostic.severity == vim.diagnostic.severity.ERROR then
            return prettify_message(diagnostic.message)
          end
          return diagnostic.message
        end,
      },
    })

    if config.show_type_preview then
      vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        pattern = { "*.ts", "*.tsx", "*.js", "*.jsx" },
        callback = function()
          vim.defer_fn(show_inline_preview, 50)
        end,
      })
    end

    if config.auto_open_float then
      if autocmd_id then
        pcall(vim.api.nvim_del_autocmd, autocmd_id)
      end
      autocmd_id = vim.api.nvim_create_autocmd("CursorHold", {
        pattern = { "*.ts", "*.tsx", "*.js", "*.jsx" },
        callback = function()
          show_diagnostic_float()
        end,
      })
    end

    vim.api.nvim_create_user_command("TsPrettifyFloat", show_diagnostic_float, {})
    vim.api.nvim_create_user_command("TsPrettifyTogglePreview", function()
      config.show_type_preview = not config.show_type_preview
      if not config.show_type_preview then
        vim.api.nvim_buf_clear_namespace(0, preview_ns, 0, -1)
      end
      local status = config.show_type_preview and "enabled" or "disabled"
      vim.notify("Type preview " .. status, vim.log.levels.INFO)
    end, {})

    local icon = config.show_icons and "✅ " or ""
    vim.notify(
      icon .. "TypeScript Error Prettifier is active!",
      vim.log.levels.INFO,
      { title = "ts-error-prettifier" }
    )
  end, function()
    vim.notify("ts-error-prettifier: Failed to setup plugin", vim.log.levels.ERROR)
  end)
end

M.show_float = show_diagnostic_float

M.cleanup = function()
  return safe_call(function()
    if autocmd_id then
      vim.api.nvim_del_autocmd(autocmd_id)
      autocmd_id = nil
    end
    vim.api.nvim_buf_clear_namespace(0, preview_ns, 0, -1)
    float_open = false
  end, nil)
end

return M
