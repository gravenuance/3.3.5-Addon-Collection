local ADDON_NAME, addon   = ...

local FRAME_LEVEL_SPACING = 3 -- allows children to occupy intermediate frame levels without risk of overlapping incorrectly


-------------------------------------------------
-- Extend Blizzard object methods (SetShown)
-------------------------------------------------

local driverFrame  = CreateFrame("Frame")
local dummyTexture = driverFrame:CreateTexture()

local function SetShown(self, show)
    if show then
        self:Show()
    else
        self:Hide()
    end
end

do
    local frameMeta      = getmetatable(driverFrame).__index
    local textureMeta    = getmetatable(dummyTexture).__index
    frameMeta.SetShown   = SetShown
    textureMeta.SetShown = SetShown
end

-------------------------------------------------
-- Nameplate detection
-------------------------------------------------

local function IsNameplate(frame)
    local r1, r2 = frame:GetRegions()
    if not r1 or not r2 then return false end
    if r2:GetObjectType() ~= "Texture" then return false end
    local tex = r2:GetTexture() or ""
    return tex:find("Nameplate", 1, true) or tex:find("NamePlate", 1, true)
end

-------------------------------------------------
-- Nameplate collection and depth sorting
-------------------------------------------------

local nameplates       = {}

addon.GetAllNameplates = function()
    return nameplates
end

local function NameplateDepthSort(a, b)
    local da, db = a:GetEffectiveDepth(), b:GetEffectiveDepth()
    if da == db then
        return tostring(a) < tostring(b)
    end
    return da > db
end

local function OnUpdate(self, elapsed)
    -- Hijack default nameplates
    local currentNumChildren = WorldFrame:GetNumChildren()
    for i = 1, currentNumChildren do
        local child = select(i, WorldFrame:GetChildren())
        if IsNameplate(child) and not child._compactNameplatesHooked then
            -- Save references for easier access
            child.healthBar, child.castBar = child:GetChildren()
            child.threatGlow, child.healthBarBorder, child.castBarBorder,
            child.castBarShieldBorder, child.spellIcon, child.highlight,
            child.unitName, child.unitLevel, child.skullIcon, child.raidIcon,
            child.eliteIcon = child:GetRegions()

            -- Hide or neutralize textures and text
            child.healthBar:Hide()
            child.castBar:SetStatusBarTexture(nil)
            child.threatGlow:SetTexCoord(0, 0, 0, 0)
            child.healthBarBorder:SetTexture(nil)
            child.castBarBorder:SetTexture(nil)
            child.castBarShieldBorder:SetTexture(nil)
            child.spellIcon:SetWidth(0.1)
            child.highlight:SetTexture(nil)
            child.unitName:SetWidth(0.1)
            child.unitLevel:SetWidth(0.1)
            child.skullIcon:SetTexture(nil)
            child.raidIcon:SetTexture(nil)
            child.eliteIcon:SetTexture(nil)

            -- Attach custom nameplate to Blizzard's default nameplates
            nameplates[#nameplates + 1] = addon.Nameplate:Create(child)
        end
    end

    numChildren = currentNumChildren

    -- Sort nameplates by depth
    table.sort(nameplates, NameplateDepthSort)

    local base = 10
    local targetBonus = 100 -- small, fixed

    for i, nameplate in ipairs(nameplates) do
        local level = base + i * FRAME_LEVEL_SPACING
        if addon.Nameplate:IsTarget(nameplate) then
            level = level + targetBonus
        end
        nameplate:SetFrameLevel(level)
        nameplate:SetScale(UIParent:GetScale())
    end
end

-------------------------------------------------
-- Event dispatch
-------------------------------------------------

local eventHandlers = {}

local function OnEvent(self, event, ...)
    local handler = eventHandlers[event]
    if handler then
        handler(addon, ...)
    end
end

local function RegisterEvent(event, handler)
    eventHandlers[event] = handler
    driverFrame:RegisterEvent(event)
end

local function UnregisterEvent(event)
    eventHandlers[event] = nil
    driverFrame:UnregisterEvent(event)
end

driverFrame:SetScript("OnEvent", OnEvent)
driverFrame:SetScript("OnUpdate", OnUpdate)

-------------------------------------------------
-- Initialization and combat log hooks
-------------------------------------------------

local function OnLoad()
    addon.Settings:ApplyDefaults()
end

RegisterEvent("ADDON_LOADED", function(self, name)
    if name == ADDON_NAME then
        OnLoad()
        UnregisterEvent("ADDON_LOADED")
    end
end)

RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function(self, ...)
    local subevent = select(2, ...)
    if subevent == "SPELL_AURA_APPLIED" then
        addon.Auras:OnApply(...)
    elseif subevent == "SPELL_AURA_REFRESH" then
        addon.Auras:OnApply(...)
    elseif subevent == "SPELL_AURA_REMOVED" then
        addon.Auras:OnRemove(...)
    elseif subevent == "SPELL_AURA_STOLEN" then
        addon.Auras:OnStolen(...)
    end
end)
