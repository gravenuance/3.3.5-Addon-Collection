-- Runs in the standalone interpreter and replaces client globals with stubs on purpose.
---@diagnostic disable: duplicate-set-field, undefined-global
local t = ...

-- Hostile NPC flags from a 3.3.5 combat log, without and with a raid mark.
local NPC_FLAGS   = 0x0A48
local STAR_FLAGS  = 0x0A48 + 0x00100000 -- COMBATLOG_OBJECT_RAIDTARGET1
local MOON_FLAGS  = 0x0A48 + 0x01000000 -- RAIDTARGET5
local SKULL_FLAGS = 0x0A48 + 0x08000000 -- RAIDTARGET8

local function band(a, b)
  local result, bitValue = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then result = result + bitValue end
    a, b, bitValue = math.floor(a / 2), math.floor(b / 2), bitValue * 2
  end
  return result
end

local function rshift(a, n)
  return math.floor(a / 2 ^ n)
end

-- Fresh client stubs and a fresh module per test, because the module caches globals at load.
local function setup()
  local env = { tokens = {} }

  _G.bit = { band = band, rshift = rshift }
  _G.wipe = function(tbl) for k in pairs(tbl) do tbl[k] = nil end return tbl end
  _G.UnitExists = function(unit) return env.tokens[unit] ~= nil end
  _G.UnitGUID = function(unit) return env.tokens[unit] and env.tokens[unit].guid end
  _G.GetRaidTargetIndex = function(unit) return env.tokens[unit] and env.tokens[unit].mark end

  env.marks = t.newNamespace("MarkIntel.lua").MarkIntel
  return env
end

local function combat(env, srcGUID, srcFlags, dstGUID, dstFlags)
  env.marks:OnCombatEvent(0, "SPELL_DAMAGE", srcGUID, "Src", srcFlags, dstGUID, "Dst", dstFlags)
end

-- Flag bits

t.test("MarkFromFlags reads each of the eight raid target flags", function()
  local env = setup()
  t.eq(env.marks.MarkFromFlags(0x00100000), 1)
  t.eq(env.marks.MarkFromFlags(0x00200000), 2)
  t.eq(env.marks.MarkFromFlags(0x00400000), 3)
  t.eq(env.marks.MarkFromFlags(0x00800000), 4)
  t.eq(env.marks.MarkFromFlags(0x01000000), 5)
  t.eq(env.marks.MarkFromFlags(0x02000000), 6)
  t.eq(env.marks.MarkFromFlags(0x04000000), 7)
  t.eq(env.marks.MarkFromFlags(0x08000000), 8)
end)

t.test("MarkFromFlags ignores the other flag bits", function()
  local env = setup()
  t.eq(env.marks.MarkFromFlags(SKULL_FLAGS), 8)
  t.eq(env.marks.MarkFromFlags(NPC_FLAGS), nil)
  t.eq(env.marks.MarkFromFlags(0x00000000), nil)
  t.eq(env.marks.MarkFromFlags(nil), nil)
  -- the focus, target and main tank flags sit just below the mark bits
  t.eq(env.marks.MarkFromFlags(0x000F0000), nil)
end)

t.test("MarkFromFlags gives no mark for two mark bits at once", function()
  local env = setup()
  t.eq(env.marks.MarkFromFlags(0x00300000), nil)
end)

-- Plate icon coordinates

t.test("RaidMarkFromTexCoord maps each cell of the icon grid to its mark", function()
  local env = setup()
  local map = env.marks.RaidMarkFromTexCoord
  t.eq(map(0, 0), 1)
  t.eq(map(0.25, 0), 2)
  t.eq(map(0.5, 0), 3)
  t.eq(map(0.75, 0), 4)
  t.eq(map(0, 0.25), 5)
  t.eq(map(0.25, 0.25), 6)
  t.eq(map(0.5, 0.25), 7)
  t.eq(map(0.75, 0.25), 8)
end)

t.test("RaidMarkFromTexCoord gives nil for a hidden icon and for cells without a mark", function()
  local env = setup()
  local map = env.marks.RaidMarkFromTexCoord
  t.eq(map(nil, nil), nil)
  t.eq(map(0.25, nil), nil)
  t.eq(map(0, 0.5), nil)
  t.eq(map(0.75, 0.75), nil)
  t.eq(map(1, 0), nil)
  t.eq(map(-0.25, 0), nil)
end)

t.test("RaidMarkFromTexCoord gives nil for coordinates between cells", function()
  local env = setup()
  t.eq(env.marks.RaidMarkFromTexCoord(0.3, 0), nil)
  t.eq(env.marks.RaidMarkFromTexCoord(0.25, 0.1), nil)
end)

-- Store

t.test("Set stores a mark both ways", function()
  local env = setup()
  env.marks:Set("0xA", 3)
  t.eq(env.marks:GUIDForMark(3), "0xA")
  t.eq(env.marks:MarkForGUID("0xA"), 3)
  t.eq(env.marks:GUIDForMark(4), nil)
end)

t.test("A mark seen on a second GUID moves off the first", function()
  local env = setup()
  env.marks:Set("0xA", 8)
  env.marks:Set("0xB", 8)
  t.eq(env.marks:GUIDForMark(8), "0xB")
  t.eq(env.marks:MarkForGUID("0xA"), nil)
  t.eq(env.marks:MarkForGUID("0xB"), 8)
end)

t.test("A GUID that gets another mark frees its old one", function()
  local env = setup()
  env.marks:Set("0xA", 3)
  env.marks:Set("0xA", 5)
  t.eq(env.marks:GUIDForMark(3), nil)
  t.eq(env.marks:GUIDForMark(5), "0xA")
  t.eq(env.marks:MarkForGUID("0xA"), 5)
end)

t.test("Set with no mark clears the GUID's mark", function()
  local env = setup()
  env.marks:Set("0xA", 2)
  env.marks:Set("0xA", nil)
  t.eq(env.marks:GUIDForMark(2), nil)
  t.eq(env.marks:MarkForGUID("0xA"), nil)
end)

t.test("Lookups with nil give nil", function()
  local env = setup()
  t.eq(env.marks:GUIDForMark(nil), nil)
  t.eq(env.marks:MarkForGUID(nil), nil)
end)

-- Combat-log feed

t.test("A mark flag on the destination is learned", function()
  local env = setup()
  combat(env, "0xP", 0x0511, "0xA", STAR_FLAGS)
  t.eq(env.marks:GUIDForMark(1), "0xA")
end)

t.test("A mark flag on the source is learned", function()
  local env = setup()
  combat(env, "0xA", MOON_FLAGS, "0xP", 0x0511)
  t.eq(env.marks:GUIDForMark(5), "0xA")
end)

t.test("A mark moves from one GUID to another through the log", function()
  local env = setup()
  combat(env, "0xP", 0x0511, "0xA", SKULL_FLAGS)
  combat(env, "0xP", 0x0511, "0xB", SKULL_FLAGS)
  t.eq(env.marks:GUIDForMark(8), "0xB")
  t.eq(env.marks:MarkForGUID("0xA"), nil)
end)

t.test("A GUID seen with no mark bit loses its mark", function()
  local env = setup()
  combat(env, "0xP", 0x0511, "0xA", SKULL_FLAGS)
  combat(env, "0xP", 0x0511, "0xA", NPC_FLAGS)
  t.eq(env.marks:GUIDForMark(8), nil)
  t.eq(env.marks:MarkForGUID("0xA"), nil)
end)

t.test("Another GUID without a mark bit leaves the mark alone", function()
  local env = setup()
  combat(env, "0xP", 0x0511, "0xA", SKULL_FLAGS)
  combat(env, "0xP", 0x0511, "0xB", NPC_FLAGS)
  t.eq(env.marks:GUIDForMark(8), "0xA")
end)

t.test("Events without a GUID or flags change nothing", function()
  local env = setup()
  combat(env, "0xP", 0x0511, "0xA", SKULL_FLAGS)
  combat(env, nil, nil, "0xA", nil)
  combat(env, nil, SKULL_FLAGS, nil, SKULL_FLAGS)
  t.eq(env.marks:GUIDForMark(8), "0xA")
end)

t.test("The empty source of an environmental event is never marked", function()
  local env = setup()
  combat(env, "0x0000000000000000", SKULL_FLAGS, "0xA", NPC_FLAGS)
  t.eq(env.marks:GUIDForMark(8), nil)
end)

-- Token feed

t.test("ScanTokens reads marks from existing tokens", function()
  local env = setup()
  env.tokens.target = { guid = "0xA", mark = 8 }
  env.tokens.focus = { guid = "0xB", mark = 1 }
  env.marks:ScanTokens({ "target", "focus", "mouseover" })
  t.eq(env.marks:GUIDForMark(8), "0xA")
  t.eq(env.marks:GUIDForMark(1), "0xB")
end)

t.test("ScanTokens clears the mark of a token that no longer has one", function()
  local env = setup()
  env.marks:Set("0xA", 8)
  env.tokens.target = { guid = "0xA", mark = nil }
  env.marks:ScanTokens({ "target" })
  t.eq(env.marks:GUIDForMark(8), nil)
end)

t.test("ScanTokens moves a mark to the token that has it now", function()
  local env = setup()
  env.marks:Set("0xA", 8)
  env.tokens.target = { guid = "0xB", mark = 8 }
  env.marks:ScanTokens({ "target" })
  t.eq(env.marks:GUIDForMark(8), "0xB")
  t.eq(env.marks:MarkForGUID("0xA"), nil)
end)

t.test("ScanTokens keeps marks of GUIDs without a token", function()
  local env = setup()
  env.marks:Set("0xA", 8)
  env.marks:ScanTokens({ "target", "focus" })
  t.eq(env.marks:GUIDForMark(8), "0xA")
end)

t.test("ScanTokens skips a token that exists without a GUID", function()
  local env = setup()
  env.tokens.target = { guid = nil, mark = 3 }
  env.marks:ScanTokens({ "target" })
  t.eq(env.marks:GUIDForMark(3), nil)
end)

-- Entering world

t.test("Entering the world wipes every mark", function()
  local env = setup()
  env.marks:Set("0xA", 8)
  env.marks:Set("0xB", 2)
  env.marks:OnEnteringWorld()
  t.eq(env.marks:GUIDForMark(8), nil)
  t.eq(env.marks:GUIDForMark(2), nil)
  t.eq(env.marks:MarkForGUID("0xA"), nil)
  t.eq(env.marks:MarkForGUID("0xB"), nil)
end)
