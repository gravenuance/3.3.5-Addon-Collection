local _, addon = ...

-- Learns player classes without unit tokens, from the combat log, the BG
-- scoreboard and any token the plate code happens to resolve.
local ClassIntel = {}
addon.ClassIntel = ClassIntel

local MAX_GUIDS             = 4000
local RETRY_DELAY           = 2
local SCORE_REQUEST_PERIOD  = 15
local OBJECT_TYPE_PLAYER    = 0x00000400 -- COMBATLOG_OBJECT_TYPE_PLAYER

local band                  = bit.band
local find                  = string.find
local sub                   = string.sub
local GetTime               = GetTime
local GetPlayerInfoByGUID   = GetPlayerInfoByGUID

-- `false` in the name maps means "seen, but not one unique answer".
local classByGUID = {}
local retryAt     = {}
local guidCount   = 0
local nameClass   = {}
local nameFull    = {}
local nameGUID    = {}

local scoreboardActive  = false
local scoreElapsed      = 0

local function ShortName(name)
    local dash = find(name, "-", 1, true)
    if dash then
        return sub(name, 1, dash - 1)
    end
    return name
end

local function Wipe()
    wipe(classByGUID)
    wipe(retryAt)
    wipe(nameClass)
    wipe(nameFull)
    wipe(nameGUID)
    guidCount = 0
end

local function TrackGUID(guid)
    if classByGUID[guid] or retryAt[guid] then return end
    if guidCount >= MAX_GUIDS then
        Wipe()
    end
    guidCount = guidCount + 1
end

local function NoteName(guid, name, class)
    local short = ShortName(name)
    local known = nameClass[short]

    if known == nil then
        nameClass[short] = class
        nameFull[short]  = name
        nameGUID[short]  = guid
        return
    end

    if known ~= class then
        nameClass[short] = false
        nameGUID[short]  = false
        return
    end

    -- Same class but a different player: the colour is still right, the binding isn't.
    if nameFull[short] ~= name then
        nameFull[short] = false
        nameGUID[short] = false
        return
    end

    local knownGUID = nameGUID[short]
    if knownGUID == nil then
        nameGUID[short] = guid
    elseif guid and knownGUID ~= guid then
        nameGUID[short] = false
    end
end

---Records that `name` (and `guid`, when known) is a player of `class`.
---@param guid string|nil
---@param name string|nil full name, possibly with a `-Realm` suffix
---@param class string|nil English class token, e.g. "MAGE"
function ClassIntel:Note(guid, name, class)
    if not class then return end
    if guid then
        TrackGUID(guid)
        classByGUID[guid] = class
        retryAt[guid] = nil
    end
    if name then
        NoteName(guid, name, class)
    end
end

---@param guid string|nil
---@return string|nil
function ClassIntel:ClassForGUID(guid)
    return guid and classByGUID[guid] or nil
end

---@param name string|nil plate text; any `-Realm` suffix is ignored
---@return string|nil # class, or nil when unknown or ambiguous
function ClassIntel:ClassForName(name)
    if not name then return nil end
    return nameClass[ShortName(name)] or nil
end

---@param name string|nil
---@return string|nil # GUID, or nil unless exactly one player has this name
function ClassIntel:GUIDForName(name)
    if not name then return nil end
    return nameGUID[ShortName(name)] or nil
end

local function LearnFromCombatLog(guid, name, flags)
    if not guid or not flags or band(flags, OBJECT_TYPE_PLAYER) == 0 then return end
    if classByGUID[guid] then return end

    local now = GetTime()
    local nextTry = retryAt[guid]
    if nextTry and now < nextTry then return end

    -- Returns nil until the client has cached this player.
    local _, class = GetPlayerInfoByGUID(guid)
    if class then
        ClassIntel:Note(guid, name, class)
    else
        TrackGUID(guid)
        retryAt[guid] = now + RETRY_DELAY
    end
end

---Feeds one COMBAT_LOG_EVENT_UNFILTERED payload (3.3.5 layout, no hideCaster).
function ClassIntel:OnCombatEvent(_, _, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags)
    LearnFromCombatLog(srcGUID, srcName, srcFlags)
    LearnFromCombatLog(dstGUID, dstName, dstFlags)
end

-------------------------------------------------
-- Battleground scoreboard
-------------------------------------------------

function ClassIntel:OnEnteringWorld()
    local _, instanceType = IsInInstance()
    scoreboardActive = instanceType == "pvp" or instanceType == "arena"
    scoreElapsed = 0
    if scoreboardActive then
        RequestBattlefieldScoreData()
    end
end

---Re-requests the scoreboard on a fixed period while in a BG or arena.
---@param elapsed number
function ClassIntel:Tick(elapsed)
    if not scoreboardActive then return end
    scoreElapsed = scoreElapsed + elapsed
    if scoreElapsed < SCORE_REQUEST_PERIOD then return end
    scoreElapsed = 0
    RequestBattlefieldScoreData()
end

function ClassIntel:OnScoreUpdate()
    for i = 1, GetNumBattlefieldScores() do
        local name, _, _, _, _, _, _, _, _, classToken = GetBattlefieldScore(i)
        -- Guards against the return order differing on this client.
        if name and classToken and RAID_CLASS_COLORS[classToken] then
            self:Note(nil, name, classToken)
        end
    end
end
