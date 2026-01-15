local ADDON_NAME, addon = ...

local Settings = {}
addon.Settings = Settings

local CVAR_DEFAULTS = {
    nameplateZ = 1.0,
    nameplateIntersectOpacity = 0.1,
    nameplateIntersectUseCamera = 1,
    -- nameplateFadeIn = 0,  -- removed / not available, so don't set
}

local function SafeSetCVar(cvar, value)
    if GetCVar(cvar) ~= nil then
        SetCVar(cvar, value)
    end
end

function Settings:ApplyDefaults()
    for cvar, value in pairs(CVAR_DEFAULTS) do
        SafeSetCVar(cvar, value)
    end
end
