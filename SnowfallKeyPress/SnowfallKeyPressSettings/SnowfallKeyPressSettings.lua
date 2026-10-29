-- SnowfallKeyPressSettings.lua

local _G = _G

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

-- The saved variables are not loaded yet while this file runs (they arrive just
-- before ADDON_LOADED), so only publish the defaults; SnowfallKeyPress merges
-- them into the loaded SnowfallKeyPressSV on ADDON_LOADED.
_G.SnowfallKeyPressDefaults = DEFAULT_SETTINGS
