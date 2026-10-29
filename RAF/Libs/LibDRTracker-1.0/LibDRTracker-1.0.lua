-- Tracks diminishing returns per unit GUID and DR category from the 3.3.5 combat log.
-- The canonical copy lives in CompactNameplates/Libs; every embedded copy must match it byte for byte.
local MAJOR, MINOR = "LibDRTracker-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end

local RESET_TIME      = 20 -- Wrath resets 15-20 s after the last CC ends; DRList uses the maximum
local STALE_TIME      = 60 -- ends a CC whose removal never reached the combat log (out of range)
local MAX_GUIDS       = 4000
local CONTROL_PLAYER  = 0x00000100 -- COMBATLOG_OBJECT_CONTROL_PLAYER: players and their pets

-- Duration multiplier for the 1st, 2nd, ... application inside one DR window; past the end is immune.
local DEFAULT_FACTORS = { 1, 0.5, 0.25 }
local CATEGORY_FACTORS = { taunt = { 1, 0.65, 0.42, 0.27 } }

-- Only these categories diminish on NPCs; everything else is PvP-only.
local PVE_CATEGORIES  = { taunt = true, stun = true, random_stun = true, opener_stun = true }

local band            = bit.band
local GetTime         = GetTime

lib.RESET_TIME        = RESET_TIME
lib.states            = lib.states or {}    -- states[guid][category] = { count, resetAt, active }
lib.callbacks         = lib.callbacks or {} -- callbacks[owner] = function(guid, category)
lib.guidCount         = lib.guidCount or 0

local states          = lib.states
local callbacks       = lib.callbacks

local function Fire(guid, category)
    for _, callback in pairs(callbacks) do
        securecall(callback, guid, category)
    end
end

local function Prune(guid, byCategory, category)
    byCategory[category] = nil
    if next(byCategory) == nil then
        states[guid] = nil
        lib.guidCount = lib.guidCount - 1
    end
end

-- Returns the live state, or nil once its window has passed (and forgets it).
local function Find(guid, category, now)
    local byCategory = states[guid]
    local state = byCategory and byCategory[category]
    if not state then return nil end
    if now >= state.resetAt then
        Prune(guid, byCategory, category)
        return nil
    end
    return state
end

local function FindOrCreate(guid, category, now)
    local state = Find(guid, category, now)
    if state then return state end

    local byCategory = states[guid]
    if not byCategory then
        if lib.guidCount >= MAX_GUIDS then
            wipe(states)
            lib.guidCount = 0
        end
        byCategory = {}
        states[guid] = byCategory
        lib.guidCount = lib.guidCount + 1
    end
    state = { count = 0, resetAt = 0, active = false }
    byCategory[category] = state
    return state
end

---@param spellID number|nil debuff spell ID
---@return string|nil # DR category, or nil when the spell has no DR
function lib:GetCategory(spellID)
    return spellID and self.spells[spellID] or nil
end

---@param category string
---@param count number how many times the category has been applied in this window, this one included
---@return number # duration multiplier: 1, 0.5, 0.25 or 0 (immune)
function lib:GetFactor(category, count)
    return (CATEGORY_FACTORS[category] or DEFAULT_FACTORS)[count] or 0
end

---@param guid string|nil
---@param category string|nil
---@param now number GetTime()
---@return number|nil count applications in the current window, nil when there is none
---@return number|nil resetAt when the window closes; while the CC is up this is only the stale limit
---@return boolean|nil active whether the CC is still up
function lib:GetState(guid, category, now)
    if not guid or not category then return nil end
    local state = Find(guid, category, now)
    if not state then return nil end
    return state.count, state.resetAt, state.active
end

---Counts one application and keeps the window open while it lasts.
---@return number|nil # this application's duration multiplier, nil for a spell without DR
function lib:OnApplied(guid, spellID, now)
    local category = self:GetCategory(spellID)
    if not guid or not category then return nil end
    local state = FindOrCreate(guid, category, now)
    state.count = state.count + 1
    state.active = true
    state.resetAt = now + STALE_TIME + RESET_TIME
    Fire(guid, category)
    return self:GetFactor(category, state.count)
end

---Starts the reset timer from the moment the CC ended.
function lib:OnRemoved(guid, spellID, now)
    local category = self:GetCategory(spellID)
    if not guid or not category then return end
    local state = FindOrCreate(guid, category, now)
    -- A removal without a seen application (e.g. after a /reload) still proves one happened.
    if state.count == 0 then state.count = 1 end
    state.active = false
    state.resetAt = now + RESET_TIME
    Fire(guid, category)
end

---Feeds one COMBAT_LOG_EVENT_UNFILTERED payload (3.3.5 layout, no hideCaster).
function lib:OnCombatEvent(_, event, _, _, _, dstGUID, _, dstFlags, spellID, _, _, auraType)
    local applied = event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REFRESH"
    if not applied and event ~= "SPELL_AURA_REMOVED" then return end
    if auraType ~= "DEBUFF" or not dstGUID then return end

    local category = self.spells[spellID]
    if not category then return end
    if band(dstFlags or 0, CONTROL_PLAYER) == 0 and not PVE_CATEGORIES[category] then return end

    if applied then
        self:OnApplied(dstGUID, spellID, GetTime())
    else
        self:OnRemoved(dstGUID, spellID, GetTime())
    end
end

---Calls `callback(guid, category)` after any DR state changes. One callback per owner.
---@param owner any
---@param callback fun(guid: string, category: string)
function lib:RegisterCallback(owner, callback)
    callbacks[owner] = callback
end

function lib:UnregisterCallback(owner)
    callbacks[owner] = nil
end

function lib:Reset()
    wipe(states)
    lib.guidCount = 0
end

-- One frame for every embedding addon, so each event is counted once.
lib.frame = lib.frame or CreateFrame("Frame")
lib.frame:UnregisterAllEvents()
lib.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
lib.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
lib.frame:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        lib:OnCombatEvent(...)
    else
        lib:Reset()
    end
end)
