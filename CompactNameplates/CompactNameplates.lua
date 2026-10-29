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
        return a.sortId < b.sortId
    end
    return da > db
end

-- Hijack default nameplates
local function HijackNameplates()
    local children = { WorldFrame:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        if not child._compactNameplatesHooked and IsNameplate(child) then
            -- Set before Create so a failure can't make every frame retry this plate
            child._compactNameplatesHooked = true

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
            local nameplate = addon.Nameplate:Create(child)
            nameplates[#nameplates + 1] = nameplate
            nameplate.sortId = #nameplates
        end
    end
end

local SORT_INTERVAL = 0.1

local numChildren = 0
local sortElapsed = 0

local function OnUpdate(self, elapsed)
    -- New plates only appear as new WorldFrame children
    local currentNumChildren = WorldFrame:GetNumChildren()
    if currentNumChildren ~= numChildren then
        HijackNameplates()
        numChildren = currentNumChildren
        sortElapsed = SORT_INTERVAL -- lay out new plates right away
    end

    addon.ClassIntel:Tick(elapsed)
    addon.Auras:Tick()

    sortElapsed = sortElapsed + elapsed
    if sortElapsed < SORT_INTERVAL then return end
    sortElapsed = 0

    -- Sort nameplates by depth
    table.sort(nameplates, NameplateDepthSort)

    local base = 10
    local targetBonus = 100 -- small, fixed
    local scale = UIParent:GetScale()

    for i, nameplate in ipairs(nameplates) do
        local level = base + i * FRAME_LEVEL_SPACING
        if addon.Nameplate:IsTarget(nameplate) then
            level = level + targetBonus
        end
        if nameplate:GetFrameLevel() ~= level then
            nameplate:SetFrameLevel(level)
        end
        if nameplate:GetScale() ~= scale then
            nameplate:SetScale(scale)
        end
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
    CompactNameplatesDB = addon.Auras:LoadDB(CompactNameplatesDB)
end

RegisterEvent("ADDON_LOADED", function(self, name)
    if name == ADDON_NAME then
        OnLoad()
        UnregisterEvent("ADDON_LOADED")
    end
end)

RegisterEvent("PLAYER_ENTERING_WORLD", function()
    addon.ClassIntel:OnEnteringWorld()
    addon.MarkIntel:OnEnteringWorld()
    addon.Auras:OnEnteringWorld()
end)

RegisterEvent("RAID_TARGET_UPDATE", function()
    addon.MarkIntel:ScanTokens(addon.Nameplate:GetUnitCandidates())
end)

RegisterEvent("UPDATE_BATTLEFIELD_SCORE", function()
    addon.ClassIntel:OnScoreUpdate()
end)

RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", function(self, ...)
    addon.ClassIntel:OnCombatEvent(...)
    addon.MarkIntel:OnCombatEvent(...)
    local subevent = select(2, ...)
    if subevent == "SPELL_AURA_APPLIED" then
        addon.Auras:OnApply(...)
    elseif subevent == "SPELL_AURA_REFRESH" then
        addon.Auras:OnApply(...)
    elseif subevent == "SPELL_AURA_REMOVED" then
        addon.Auras:OnRemove(...)
    elseif subevent == "SPELL_AURA_BROKEN" then
        addon.Auras:OnRemove(...)
    elseif subevent == "SPELL_AURA_BROKEN_SPELL" then
        addon.Auras:OnBrokenSpell(...)
    elseif subevent == "SPELL_AURA_STOLEN" then
        addon.Auras:OnStolen(...)
    elseif subevent == "UNIT_DIED" then
        addon.Auras:OnDied(...)
    end
end)
