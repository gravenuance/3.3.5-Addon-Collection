local ADDON_NAME, addon  = ...

-- Whitelisted buffs and debuffs per GUID. Units with a token get the real UnitAura data;
-- every other unit gets estimates built from combat-log applies, with durations learned
-- from UnitAura and shortened by diminishing returns.
local Auras              = {}
addon.Auras              = Auras

local Settings           = addon.Settings

local DEBUFF_WHITELIST   = Settings.AURA_DEBUFF_WHITELIST
local BUFF_WHITELIST     = Settings.AURA_BUFF_WHITELIST

local MAX_TRACK_DURATION = 5 * 60
local MAX_GUIDS          = 4000
local UNKNOWN_LIFETIME   = 60 -- how long an aura of unknown duration stays without a removal event
local DB_VERSION         = 1
local CONTROL_PLAYER     = 0x00000100 -- COMBATLOG_OBJECT_CONTROL_PLAYER: players and their pets

local band                 = bit.band
local sort                 = table.sort
local GetTime              = GetTime
local GetSpellInfo         = GetSpellInfo
local UnitAura             = UnitAura
local UnitGUID             = UnitGUID
local UnitPlayerControlled = UnitPlayerControlled

local DR                   = LibStub("LibDRTracker-1.0")

-------------------------------------------------
-- Learned durations (persisted in CompactNameplatesDB)
-------------------------------------------------

-- durations[kind][spellID] = full duration seen undiminished; kind is "player" or "npc".
local durations = { player = {}, npc = {} }

local function IsValidDuration(value)
    return type(value) == "number" and value > 0 and value <= MAX_TRACK_DURATION
end

local function SanitizeKind(byKind)
    if type(byKind) ~= "table" then return {} end
    for spellID, duration in pairs(byKind) do
        if type(spellID) ~= "number" or not IsValidDuration(duration) then
            byKind[spellID] = nil
        end
    end
    return byKind
end

---Validates the saved cache and starts using it. Call once on ADDON_LOADED.
---@param db any the raw CompactNameplatesDB global
---@return table # the table to store back into CompactNameplatesDB
function Auras:LoadDB(db)
    -- A cache only: any other version is discarded. Migrate here once the shape changes.
    if type(db) ~= "table" or db.version ~= DB_VERSION then
        db = { version = DB_VERSION }
    end
    if type(db.durations) ~= "table" then
        db.durations = {}
    end
    db.durations.player = SanitizeKind(db.durations.player)
    db.durations.npc    = SanitizeKind(db.durations.npc)
    durations = db.durations
    return db
end

local function KindForFlags(flags)
    return band(flags or 0, CONTROL_PLAYER) ~= 0 and "player" or "npc"
end

-------------------------------------------------
-- Storage: entries and per-GUID containers are pooled, so events allocate nothing
-------------------------------------------------

-- aurasByGUID[guid] = { BUFF = { entry... }, DEBUFF = { entry... } }
-- entry = { spellID, duration, expirationTime, auraType, dispelType }; duration 0 means no known timer.
local aurasByGUID   = {}
local guidCount     = 0
local entryPool     = {}
local containerPool = {}

local function Pop(pool)
    local n = #pool
    if n == 0 then return nil end
    local item = pool[n]
    pool[n] = nil
    return item
end

local function ClearList(list)
    for i = #list, 1, -1 do
        entryPool[#entryPool + 1] = list[i]
        list[i] = nil
    end
end

local function ReleaseGUID(guid)
    local byGUID = aurasByGUID[guid]
    if not byGUID then return false end
    ClearList(byGUID.BUFF)
    ClearList(byGUID.DEBUFF)
    aurasByGUID[guid] = nil
    guidCount = guidCount - 1
    containerPool[#containerPool + 1] = byGUID
    return true
end

local function WipeAll()
    for guid in pairs(aurasByGUID) do
        ReleaseGUID(guid)
    end
end

local function GetList(guid, auraType)
    local byGUID = aurasByGUID[guid]
    if not byGUID then
        if guidCount >= MAX_GUIDS then
            WipeAll()
        end
        byGUID = Pop(containerPool) or { BUFF = {}, DEBUFF = {} }
        aurasByGUID[guid] = byGUID
        guidCount = guidCount + 1
    end
    return byGUID[auraType]
end

local function AppendEntry(list, spellID, duration, expirationTime, auraType, dispelType)
    local entry = Pop(entryPool) or {}
    entry.spellID        = spellID
    entry.duration       = duration
    entry.expirationTime = expirationTime
    entry.auraType       = auraType
    entry.dispelType     = dispelType
    list[#list + 1]      = entry
    return entry
end

local function FindEntry(list, spellID)
    for i = 1, #list do
        if list[i].spellID == spellID then
            return list[i]
        end
    end
    return nil
end

---Replaces the entry for this spell, or adds one.
local function SetEntry(guid, auraType, spellID, duration, expirationTime)
    local list = GetList(guid, auraType)
    local entry = FindEntry(list, spellID)
    if not entry then
        AppendEntry(list, spellID, duration, expirationTime, auraType, nil)
        return
    end
    entry.duration       = duration
    entry.expirationTime = expirationTime
    entry.dispelType     = nil
end

---@return boolean # whether an entry was removed
local function RemoveEntries(guid, auraType, spellID)
    local byGUID = aurasByGUID[guid]
    if not byGUID then return false end

    local list = byGUID[auraType]
    local removed = false
    for i = #list, 1, -1 do
        if list[i].spellID == spellID then
            entryPool[#entryPool + 1] = table.remove(list, i)
            removed = true
        end
    end

    if #byGUID.BUFF == 0 and #byGUID.DEBUFF == 0 then
        ReleaseGUID(guid)
    end
    return removed
end

-------------------------------------------------
-- Combat-log applies waiting for the next tick
-------------------------------------------------

-- LibDRTracker counts the same event in its own frame, and WoW gives no order between
-- frames, so an apply is resolved on the next tick, when its DR count is final.
-- item = { guid, spellID, auraType, kind, appliedAt }
local pending     = {}
local pendingPool = {}

---@return boolean # whether an item was dropped
local function DropPending(guid, spellID, auraType)
    local dropped = false
    for i = #pending, 1, -1 do
        local item = pending[i]
        if item.guid == guid
            and (not spellID or item.spellID == spellID)
            and (not auraType or item.auraType == auraType) then
            pendingPool[#pendingPool + 1] = table.remove(pending, i)
            dropped = true
        end
    end
    return dropped
end

local function ResolveApply(item)
    local guid, spellID, auraType = item.guid, item.spellID, item.auraType

    local factor = 1
    local category = DR:GetCategory(spellID)
    if category then
        local count = DR:GetState(guid, category, GetTime())
        if count then
            factor = DR:GetFactor(category, count)
        end
    end

    if factor == 0 then
        RemoveEntries(guid, auraType, spellID)
        return
    end

    local learned = durations[item.kind][spellID]
    if learned then
        local duration = learned * factor
        SetEntry(guid, auraType, spellID, duration, item.appliedAt + duration)
    else
        SetEntry(guid, auraType, spellID, 0, item.appliedAt + UNKNOWN_LIFETIME)
    end
end

---Turns the applies queued since the last tick into plate entries. Call every frame.
function Auras:Tick()
    while #pending > 0 do
        local item = table.remove(pending, 1)
        ResolveApply(item)
        local guid = item.guid
        pendingPool[#pendingPool + 1] = item
        addon.Nameplate:UpdateForGUID(guid)
    end
end

-------------------------------------------------
-- Reading
-------------------------------------------------

local function ByDurationDescending(a, b)
    local aTimed, bTimed = a.duration > 0, b.duration > 0
    if aTimed ~= bTimed then
        return aTimed
    end
    if a.duration ~= b.duration then
        return a.duration > b.duration
    end
    return a.spellID < b.spellID
end

---Fills `out` with the live entries of one kind: longest timer first, entries without a timer last.
---@param guid string|nil
---@param auraType "BUFF"|"DEBUFF"
---@param out table[] reused array, cleared first
---@return table[] # `out`; each entry has spellID, duration (0 = no timer), expirationTime, auraType, dispelType
function Auras:Collect(guid, auraType, out)
    wipe(out)
    local byGUID = guid and aurasByGUID[guid]
    local list = byGUID and byGUID[auraType]
    if not list then return out end

    local now = GetTime()
    for i = 1, #list do
        local entry = list[i]
        if entry.expirationTime > now then
            out[#out + 1] = entry
        end
    end
    sort(out, ByDurationDescending)
    return out
end

-------------------------------------------------
-- UnitAura (authoritative for units with a token)
-------------------------------------------------

local function ShouldTrackAura(spellID, duration, auraType)
    local name = GetSpellInfo(spellID)
    if not name then
        return false
    end

    if auraType == "DEBUFF" then
        if not DEBUFF_WHITELIST[name] then
            return false
        end
    elseif auraType == "BUFF" then
        if not BUFF_WHITELIST[name] then
            return false
        end
    end

    if not duration or duration <= 0 then
        return false
    end

    if duration > MAX_TRACK_DURATION then
        return false
    end

    return true
end

-- Diminished sightings would teach a shortened duration.
local function Learn(unitGUID, kind, spellID, duration)
    local category = DR:GetCategory(spellID)
    if category then
        local count = DR:GetState(unitGUID, category, GetTime())
        if count and count ~= 1 then return end
    end
    durations[kind][spellID] = duration
end

local function ScanUnit(unitID, unitGUID, filter, auraType, kind)
    local i = 1
    while true do
        local _, _, _, _, dispelType, duration, expirationTime, _, _, _, spellID =
            UnitAura(unitID, i, filter)
        if not spellID then break end

        if ShouldTrackAura(spellID, duration, auraType) then
            AppendEntry(GetList(unitGUID, auraType), spellID, duration, expirationTime, auraType, dispelType)
            Learn(unitGUID, kind, spellID, duration)
        end
        i = i + 1
    end
end

---Replaces the GUID's auras with what UnitAura reports, and learns their durations.
---@param unitID string
function Auras:Refresh(unitID)
    local unitGUID = UnitGUID(unitID)
    if not unitGUID then return end

    ReleaseGUID(unitGUID)

    local kind = UnitPlayerControlled(unitID) and "player" or "npc"
    ScanUnit(unitID, unitGUID, "HARMFUL", "DEBUFF", kind)
    ScanUnit(unitID, unitGUID, "HELPFUL", "BUFF", kind)
end

-------------------------------------------------
-- Combat-log events (3.3.5 argument layout)
-------------------------------------------------

---Queues SPELL_AURA_APPLIED / SPELL_AURA_REFRESH of a whitelisted spell for the next tick.
function Auras:OnApply(_, _, _, _, _, dstGUID, _, dstFlags, spellID, spellName, _, auraType)
    local whitelist
    if auraType == "DEBUFF" then
        whitelist = DEBUFF_WHITELIST
    elseif auraType == "BUFF" then
        whitelist = BUFF_WHITELIST
    else
        return
    end
    if not spellName or not whitelist[spellName] then return end
    if not dstGUID or not spellID then return end

    local item = Pop(pendingPool) or {}
    item.guid      = dstGUID
    item.spellID   = spellID
    item.auraType  = auraType
    item.kind      = KindForFlags(dstFlags)
    item.appliedAt = GetTime()
    pending[#pending + 1] = item
end

---@return boolean # whether anything changed
local function RemoveAura(guid, spellID, auraType)
    if not guid or not spellID then return false end

    local key = (auraType == "BUFF") and "BUFF" or "DEBUFF"
    local dropped = #pending > 0 and DropPending(guid, spellID, key)
    local removed = RemoveEntries(guid, key, spellID)
    return dropped or removed
end

function Auras:OnRemove(_, _, _, _, _, dstGUID, _, _, spellID, _, _, auraType)
    if RemoveAura(dstGUID, spellID, auraType) then
        addon.Nameplate:UpdateForGUID(dstGUID)
    end
end

---SPELL_AURA_BROKEN_SPELL: the removed aura is `spellID`; the breaking spell takes the next three args.
function Auras:OnBrokenSpell(_, _, _, _, _, dstGUID, _, _, spellID, _, _, _, _, _, auraType)
    if RemoveAura(dstGUID, spellID, auraType) then
        addon.Nameplate:UpdateForGUID(dstGUID)
    end
end

function Auras:OnStolen(_, _, sourceGUID, _, _, destGUID, _, _, _, _, _,
                        extraSpellID, _, _, auraType)
    -- Remove the stolen aura from the original target
    RemoveAura(destGUID, extraSpellID, auraType)
    addon.Nameplate:UpdateForGUID(destGUID)
    if not sourceGUID then return end

    -- Stolen effects are buffs on the stealer
    addon.Nameplate:UpdateForGUID(sourceGUID)
end

function Auras:OnDied(_, _, _, _, _, dstGUID)
    if not dstGUID then return end
    local dropped = #pending > 0 and DropPending(dstGUID, nil, nil)
    local released = ReleaseGUID(dstGUID)
    if dropped or released then
        addon.Nameplate:UpdateForGUID(dstGUID)
    end
end

---Forgets every aura and queued apply; the learned durations stay.
function Auras:OnEnteringWorld()
    WipeAll()
    for i = #pending, 1, -1 do
        pendingPool[#pendingPool + 1] = table.remove(pending, i)
    end
end
