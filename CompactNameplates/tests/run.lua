-- Offline test runner: lua5.1 tests/run.lua (from the addon folder, no dependencies).
-- Runs every tests/*_spec.lua; each spec receives the test API `t` as its first
-- chunk argument. Exits non-zero when any test fails.

-- The editor checks tests/ against the addon sandbox; the standalone interpreter has the full standard library.
---@diagnostic disable: undefined-global, undefined-field

local root = (arg and arg[0] or ""):match("^(.*)[/\\]tests[/\\]run%.lua$") or "."
local isWindows = package.config:sub(1, 1) == "\\"

local function listSpecs()
  local cmd
  if isWindows then
    cmd = 'dir /b "' .. root:gsub("/", "\\") .. '\\tests\\*_spec.lua" 2>nul'
  else
    cmd = 'ls "' .. root .. '"/tests/*_spec.lua 2>/dev/null'
  end
  local pipe = assert(io.popen(cmd))
  local specs = {}
  for line in pipe:lines() do
    line = line:gsub("\r$", "")
    if line ~= "" then
      specs[#specs + 1] = line:match("[^/\\]+$")
    end
  end
  pipe:close()
  table.sort(specs)
  return specs
end

local function describe(value, depth)
  depth = depth or 0
  if type(value) ~= "table" then
    return type(value) == "string" and string.format("%q", value) or tostring(value)
  end
  if depth > 3 then return "{...}" end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = tostring(k) .. "=" .. describe(value[k], depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function deepEqual(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deepEqual(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local t = { root = root }
local passed, failed = 0, 0
local currentSpec = ""

function t.eq(actual, expected, message)
  if not deepEqual(actual, expected) then
    error((message and (message .. ": ") or "") .. "expected " .. describe(expected) ..
      ", got " .. describe(actual), 2)
  end
end

function t.truthy(value, message)
  if not value then error(message or "expected a truthy value", 2) end
end

function t.falsy(value, message)
  if value then error((message or "expected a falsy value") .. ", got " .. describe(value), 2) end
end

-- Runs a spec under test with a fresh addon namespace, like the client does with `...`.
function t.loadAddonFile(file, ns)
  local chunk = assert(loadfile(root .. "/" .. file))
  chunk("CompactNameplates", ns)
  return ns
end

function t.newNamespace(...)
  local ns = {}
  for _, file in ipairs({ ... }) do t.loadAddonFile(file, ns) end
  return ns
end

function t.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL " .. currentSpec .. " > " .. name .. "\n     " .. tostring(err))
  end
end

for _, spec in ipairs(listSpecs()) do
  currentSpec = spec
  local chunk, loadErr = loadfile(root .. "/tests/" .. spec)
  if not chunk then
    failed = failed + 1
    print("FAIL " .. spec .. " (load)\n     " .. tostring(loadErr))
  else
    local ok, err = pcall(chunk, t)
    if not ok then
      failed = failed + 1
      print("FAIL " .. spec .. " (run)\n     " .. tostring(err))
    end
  end
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
