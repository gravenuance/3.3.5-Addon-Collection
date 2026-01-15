-- SnowfallKeyPressSettings.lua

local _G = _G

-- SavedVariables root
SnowfallKeyPressSV = SnowfallKeyPressSV or {}

-- Default settings
local DEFAULT_SETTINGS = {
  enable           = true,
  -- modifiers used to build combinations (e.g. "", "ALT-", "CTRL-", etc.)

  enableMacros     = false, -- accelerate MACRO bindings
  enableClicks     = false, -- accelerate CLICK bindings
  enableMousewheel = false, -- accelerate mousewheel keys

  modifiers        = {
    "ALT",
    "CTRL",
    "SHIFT",
  },
  -- keys to accelerate (examples; adjust to your real list)
  keys             = {
    "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
    "-", "=", "Q", "E", "R", "F", "Z", "X", "C", "V",
    "T", "Y", "G", "B", "A", "S", "D", "N", "F9", "F10",
    "F1", "F2", "F3", "F5", "F6", "F7", "F8", "F11", "F12",
  },
}

local function CopyDefaults(dst, src)
  if not dst then return src end
  for k, v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then
        local t = {}
        for kk, vv in pairs(v) do
          t[kk] = vv
        end
        dst[k] = t
      else
        dst[k] = v
      end
    elseif type(v) == "table" and type(dst[k]) == "table" then
      CopyDefaults(dst[k], v)
    end
  end
  return dst
end

-- Merge defaults into saved variables on load
SnowfallKeyPressSV = CopyDefaults(SnowfallKeyPressSV, DEFAULT_SETTINGS)
_G.SnowfallKeyPressSV = SnowfallKeyPressSV
