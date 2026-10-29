local _, addon = ...

-- Remembers which GUID carries which raid mark, from the combat log and from
-- any unit token that shows one. At most 8 entries, so there is no cap.
local MarkIntel = {}
addon.MarkIntel = MarkIntel

local MARK_FLAGS_MASK     = 0x0FF00000 -- COMBATLOG_OBJECT_RAIDTARGET1..8
local MARK_FLAGS_SHIFT    = 20
local ICON_GRID           = 4          -- UI-RaidTargetingIcons is a 4x4 grid; marks fill the first two rows
local ICON_ROWS           = 2
local ICON_ALIGN_EPSILON  = 0.01
local NO_SOURCE_GUID      = "0x0000000000000000"

-- A mark flag set alone, shifted down to bit 0, to its mark index.
local MARK_BY_FLAG_BIT = { [1] = 1, [2] = 2, [4] = 3, [8] = 4, [16] = 5, [32] = 6, [64] = 7, [128] = 8 }

local band                = bit.band
local rshift              = bit.rshift
local floor               = math.floor
local abs                 = math.abs
local UnitExists          = UnitExists
local UnitGUID            = UnitGUID
local GetRaidTargetIndex  = GetRaidTargetIndex

local guidByMark = {}
local markByGUID = {}

---@param flags number|nil combat-log unit flags
---@return number|nil # raid mark 1-8, or nil when the flags carry none
function MarkIntel.MarkFromFlags(flags)
    if not flags then return nil end
    return MARK_BY_FLAG_BIT[rshift(band(flags, MARK_FLAGS_MASK), MARK_FLAGS_SHIFT)]
end

---Maps the upper-left corner of a plate's raid icon on the 4x4 icon grid to its mark.
---@param left number|nil
---@param top number|nil
---@return number|nil # 1-8, or nil for a hidden icon or coordinates off the icon cells
function MarkIntel.RaidMarkFromTexCoord(left, top)
    if not left or not top then return nil end
    local column = floor(left * ICON_GRID + 0.5)
    local row    = floor(top * ICON_GRID + 0.5)
    if abs(left * ICON_GRID - column) > ICON_ALIGN_EPSILON
        or abs(top * ICON_GRID - row) > ICON_ALIGN_EPSILON then
        return nil
    end
    if column < 0 or column >= ICON_GRID or row < 0 or row >= ICON_ROWS then return nil end
    return row * ICON_GRID + column + 1
end

---Records that `guid` carries `mark`, or carries none when `mark` is nil.
---A mark is on one GUID at a time, so it leaves its previous holder.
---@param guid string
---@param mark number|nil
function MarkIntel:Set(guid, mark)
    local oldMark = markByGUID[guid]
    if oldMark == mark then return end

    if oldMark then
        guidByMark[oldMark] = nil
        markByGUID[guid] = nil
    end
    if mark then
        local oldGUID = guidByMark[mark]
        if oldGUID then
            markByGUID[oldGUID] = nil
        end
        guidByMark[mark] = guid
        markByGUID[guid] = mark
    end
end

---@param mark number|nil
---@return string|nil
function MarkIntel:GUIDForMark(mark)
    return mark and guidByMark[mark] or nil
end

---@param guid string|nil
---@return number|nil
function MarkIntel:MarkForGUID(guid)
    return guid and markByGUID[guid] or nil
end

local function LearnFromFlags(self, guid, flags)
    if not guid or not flags or guid == NO_SOURCE_GUID then return end
    local mark = MarkIntel.MarkFromFlags(flags)
    if not mark and not markByGUID[guid] then return end
    self:Set(guid, mark)
end

---Feeds one COMBAT_LOG_EVENT_UNFILTERED payload (3.3.5 layout, no hideCaster).
function MarkIntel:OnCombatEvent(_, _, srcGUID, _, srcFlags, dstGUID, _, dstFlags)
    LearnFromFlags(self, srcGUID, srcFlags)
    LearnFromFlags(self, dstGUID, dstFlags)
end

---Reads the mark of every existing unit token; a token without a mark clears its GUID's mark.
---@param tokens string[]
function MarkIntel:ScanTokens(tokens)
    for i = 1, #tokens do
        local unit = tokens[i]
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            if guid then
                self:Set(guid, GetRaidTargetIndex(unit))
            end
        end
    end
end

function MarkIntel:OnEnteringWorld()
    wipe(guidByMark)
    wipe(markByGUID)
end
