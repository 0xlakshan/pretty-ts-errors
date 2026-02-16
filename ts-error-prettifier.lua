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
  codes = {
    ["2322"] = "assignability",
    ["2345"] = "parameter",
    ["2339"] = "property",
    ["2741"] = "missing_props",
    ["2416"] = "return_mismatch",
    ["2769"] = "overload",
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
    missing_props = {
      pattern = "Type '(.+)' is missing the following properties from type '(.+)'",
      labels = { "Actual type:", "Required type:" },
    },
    return_mismatch = {
      pattern = "Type '(.+)' is not assignable to type '(.+)'",
      labels = { "Returned:", "Expected return:" },
    },
    overload = {
      pattern = "No overload matches this call.*type '(.+)' is not assignable to type '(.+)'",
      labels = { "Argument:", "Overload expects:" },
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
  return true
end

local function get_ts_error_diagnostics(bufnr, lnum)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  return safe_call(function()
    local all = vim.diagnostic.get(bufnr, lnum and { lnum = lnum } or nil)
    local ts = {}
    for _, d in ipairs(all or {}) do
      if d.source == "tsserver" and d.severity == vim.diagnostic.severity.ERROR then
        table.insert(ts, d)
      end
    end
    return ts
  end, {})
end

local function tokenize_type(type_str)
  if not type_str then
    return {}
  end
  local tokens = {}
  local current = ""
  for i = 1, #type_str do
    local c = type_str:sub(i, i)
    if c:match("[{}|;:,<>%[%]()%s]") then
      if #current > 0 then
        table.insert(tokens, current)
        current = ""
      end
      if not c:match("%s") then
        table.insert(tokens, c)
      end
    else
      current = current .. c
    end
  end
  if #current > 0 then
    table.insert(tokens, current)
  end
  return tokens
end

local function compute_diff(a, b)
  local m, n = #a, #b
  local dp = {}
  for i = 0, m do
    dp[i] = {}
    for j = 0, n do
      if i == 0 then
        dp[i][j] = j
      elseif j == 0 then
        dp[i][j] = i
      else
        local cost = (a[i] == b[j]) and 0 or 1
        dp[i][j] = math.min(dp[i-1][j] + 1, dp[i][j-1] + 1, dp[i-1][j-1] + cost)
      end
    end
  end

  local diff = {}
  local i, j = m, n
  while i > 0 or j > 0 do
    if i > 0 and j > 0 and a[i] == b[j] then
      table.insert(diff, 1, { "equal", a[i] })
      i, j = i - 1, j - 1
    elseif j > 0 and (i == 0 or dp[i][j-1] <= dp[i-1][j]) then
      table.insert(diff, 1, { "add", b[j] })
      j = j - 1
    else
      table.insert(diff, 1, { "delete", a[i] })
      i = i - 1
    end
  end
  return diff
end

local function highlight_diff(a, b)
  local t1 = tokenize_type(a)
  local t2 = tokenize_type(b)
  local diff = compute_diff(t1, t2)
  local r1, r2 = {}, {}

  for _, item in ipairs(diff) do
    if item[1] == "equal" then
      table.insert(r1, item[2])
      table.insert(r2, item[2])
    elseif item[1] == "delete" then
      table.insert(r1, "[-" .. item[2] .. "-]")
    elseif item[1] == "add" then
      table.insert(r2, "{+" .. item[2] .. "+}")
    end
  end

  return table.concat(r1, " "), table.concat(r2, " ")
end

local function simplify_type(t)
  if not t then
    return ""
  end
  if #t < 30 then
    return t
  end
  return t:sub(1, 27) .. "..."
end

local function extract_from_pattern(msg, pattern_config)
  local a, b = msg:match(pattern_config.pattern)
  if a and b then
    return a, b
  end
end

local function extract_type_mismatch(diag)
  if not diag or not diag.message then
    return nil
  end

  local code = tostring(diag.code or "")
  local name = config.codes[code]

  if name and config.patterns[name] then
    local a, b = extract_from_pattern(diag.message, config.patterns[name])
    if a and b then
      return { actual = a, expected = b, pattern_config = config.patterns[name] }
    end
  end

  for _, p in pairs(config.patterns) do
    local a, b = extract_from_pattern(diag.message, p)
    if a and b then
      return { actual = a, expected = b, pattern_config = p }
    end
  end
end

local function prettify_message(diag)
  local mismatch = extract_type_mismatch(diag)
  if not mismatch then
    return diag.message
  end

  local a, b = mismatch.actual, mismatch.expected
  local pa, pb = highlight_diff(a, b)

  return table.concat({
    "Type Mismatch",
    string.rep("=", 50),
    mismatch.pattern_config.labels[1],
    pa,
    "",
    mismatch.pattern_config.labels[2],
    pb,
  }, "\n")
end

local function truncate_for_virtual_text(diag)
  local mismatch = extract_type_mismatch(diag)
  if mismatch then
    return simplify_type(mismatch.actual) .. " → " .. simplify_type(mismatch.expected)
  end
  return diag.message:match("^([^\n]+)")
end

local function show_inline_preview()
  vim.api.nvim_buf_clear_namespace(0, preview_ns, 0, -1)
  local diags = get_ts_error_diagnostics(0, vim.fn.line(".") - 1)
  for _, d in ipairs(diags) do
    local mismatch = extract_type_mismatch(d)
    if mismatch then
      local text = "  ⮕ Expected: " .. simplify_type(mismatch.expected)
      vim.api.nvim_buf_set_extmark(0, preview_ns, d.lnum, 0, {
        virt_text = { { text, "DiagnosticHint" } },
        virt_text_pos = "eol",
      })
      break
    end
  end
end

local function show_diagnostic_float()
  if float_open then
    return
  end
  float_open = true

  vim.diagnostic.open_float(nil, {
    border = "rounded",
    source = "always",
    format = function(d)
      return prettify_message(d)
    end,
  })

  vim.defer_fn(function()
    float_open = false
  end, 100)
end

M.setup = function(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  vim.diagnostic.config({
    virtual_text = {
      prefix = config.show_icons and "●" or "■",
      format = function(d)
        if d.source == "tsserver" then
          return truncate_for_virtual_text(d)
        end
        return d.message
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
    autocmd_id = vim.api.nvim_create_autocmd("CursorHold", {
      pattern = { "*.ts", "*.tsx", "*.js", "*.jsx" },
      callback = show_diagnostic_float,
    })
  end

  vim.api.nvim_create_user_command("TsPrettifyFloat", show_diagnostic_float, {})
end

M.show_float = show_diagnostic_float

return M
