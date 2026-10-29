-- The spec replaces client globals with stubs on purpose.
---@diagnostic disable: duplicate-set-field
local t = ...

-- Hostile player, hostile NPC and hostile pet flags from a 3.3.5 combat log.
local PLAYER_FLAGS = 0x0548
local NPC_FLAGS    = 0x0A48
local PET_FLAGS    = 0x1148

local function band(a, b)
  local result, bitValue = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then result = result + bitValue end
    a, b, bitValue = math.floor(a / 2), math.floor(b / 2), bitValue * 2
  end
  return result
end

-- Fresh client stubs and a fresh module per test, because the module caches globals at load.
local function setup()
  local env = { now = 0, infoCalls = {}, classes = {}, requests = 0, instanceType = "none", scores = {} }

  _G.bit = { band = band }
  _G.wipe = function(tbl) for k in pairs(tbl) do tbl[k] = nil end return tbl end
  _G.GetTime = function() return env.now end
  _G.GetPlayerInfoByGUID = function(guid)
    env.infoCalls[#env.infoCalls + 1] = guid
    local class = env.classes[guid]
    if class then return "Localized", class, "Human", "Human", 2 end
    return nil
  end
  _G.IsInInstance = function() return env.instanceType ~= "none", env.instanceType end
  _G.RequestBattlefieldScoreData = function() env.requests = env.requests + 1 end
  _G.GetNumBattlefieldScores = function() return #env.scores end
  _G.GetBattlefieldScore = function(i)
    local row = env.scores[i]
    return row[1], 0, 0, 0, 0, 0, 0, "Human", "Localized", row[2], 0, 0
  end
  _G.RAID_CLASS_COLORS = { MAGE = {}, ROGUE = {}, PRIEST = {} }

  env.intel = t.newNamespace("ClassIntel.lua").ClassIntel
  return env
end

local function combat(env, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags)
  env.intel:OnCombatEvent(env.now, "SPELL_DAMAGE", srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags)
end

-- Store

t.test("Note keeps a player's class by GUID and by name", function()
  local env = setup()
  env.intel:Note("0x01", "Bob", "MAGE")
  t.eq(env.intel:ClassForGUID("0x01"), "MAGE")
  t.eq(env.intel:ClassForName("Bob"), "MAGE")
  t.eq(env.intel:GUIDForName("Bob"), "0x01")
end)

t.test("A cross-realm name is found by its short name", function()
  local env = setup()
  env.intel:Note("0x01", "Bob-Frostmourne", "ROGUE")
  t.eq(env.intel:ClassForName("Bob"), "ROGUE")
  t.eq(env.intel:GUIDForName("Bob"), "0x01")
end)

t.test("Same short name with a different class gives no colour and no GUID", function()
  local env = setup()
  env.intel:Note("0x01", "Bob", "MAGE")
  env.intel:Note("0x02", "Bob-Frostmourne", "ROGUE")
  t.eq(env.intel:ClassForName("Bob"), nil)
  t.eq(env.intel:GUIDForName("Bob"), nil)
end)

t.test("An ambiguous name stays ambiguous when the first class is seen again", function()
  local env = setup()
  env.intel:Note("0x01", "Bob", "MAGE")
  env.intel:Note("0x02", "Bob-Frostmourne", "ROGUE")
  env.intel:Note("0x01", "Bob", "MAGE")
  t.eq(env.intel:ClassForName("Bob"), nil)
end)

t.test("Same short name with the same class keeps the colour but drops the GUID", function()
  local env = setup()
  env.intel:Note("0x01", "Bob", "MAGE")
  env.intel:Note("0x02", "Bob-Frostmourne", "MAGE")
  t.eq(env.intel:ClassForName("Bob"), "MAGE")
  t.eq(env.intel:GUIDForName("Bob"), nil)
end)

t.test("A scoreboard name gains its GUID when the combat log sees that player", function()
  local env = setup()
  env.intel:Note(nil, "Bob", "MAGE")
  t.eq(env.intel:GUIDForName("Bob"), nil)
  env.intel:Note("0x01", "Bob", "MAGE")
  t.eq(env.intel:GUIDForName("Bob"), "0x01")
end)

t.test("Two scoreboard players sharing a short name never bind a GUID", function()
  local env = setup()
  env.intel:Note(nil, "Bob-Frostmourne", "MAGE")
  env.intel:Note(nil, "Bob-Icecrown", "MAGE")
  env.intel:Note("0x01", "Bob-Frostmourne", "MAGE")
  t.eq(env.intel:ClassForName("Bob"), "MAGE")
  t.eq(env.intel:GUIDForName("Bob"), nil)
end)

t.test("The same full name on two GUIDs drops the GUID", function()
  local env = setup()
  env.intel:Note("0x01", "Bob", "MAGE")
  env.intel:Note("0x02", "Bob", "MAGE")
  t.eq(env.intel:ClassForName("Bob"), "MAGE")
  t.eq(env.intel:GUIDForName("Bob"), nil)
end)

t.test("Noting the same player again keeps the GUID", function()
  local env = setup()
  env.intel:Note("0x01", "Bob", "MAGE")
  env.intel:Note(nil, "Bob", "MAGE")
  env.intel:Note("0x01", "Bob", "MAGE")
  t.eq(env.intel:GUIDForName("Bob"), "0x01")
end)

t.test("Missing name, GUID or class is a no-op", function()
  local env = setup()
  env.intel:Note(nil, nil, nil)
  env.intel:Note("0x01", nil, "MAGE")
  env.intel:Note("0x02", "Bob", nil)
  t.eq(env.intel:ClassForGUID("0x01"), "MAGE")
  t.eq(env.intel:ClassForGUID("0x02"), nil)
  t.eq(env.intel:ClassForName("Bob"), nil)
  t.eq(env.intel:ClassForName(nil), nil)
  t.eq(env.intel:GUIDForName(nil), nil)
  t.eq(env.intel:ClassForGUID(nil), nil)
end)

t.test("The store wipes once it holds 4000 GUIDs", function()
  local env = setup()
  for i = 1, 4000 do env.intel:Note("g" .. i, "P" .. i, "MAGE") end
  t.eq(env.intel:ClassForGUID("g1"), "MAGE", "first GUID before the cap")
  t.eq(env.intel:ClassForName("P1"), "MAGE", "first name before the cap")

  env.intel:Note("g4001", "P4001", "PRIEST")
  t.eq(env.intel:ClassForGUID("g1"), nil, "first GUID after the cap")
  t.eq(env.intel:ClassForName("P1"), nil, "first name after the cap")
  t.eq(env.intel:ClassForGUID("g4001"), "PRIEST")
  t.eq(env.intel:ClassForName("P4001"), "PRIEST")
end)

t.test("Re-noting a known GUID doesn't count towards the cap", function()
  local env = setup()
  for i = 1, 3999 do env.intel:Note("g" .. i, nil, "MAGE") end
  for _ = 1, 10 do env.intel:Note("g2", nil, "MAGE") end
  env.intel:Note("g4000", nil, "MAGE")
  t.eq(env.intel:ClassForGUID("g1"), "MAGE")
end)

-- Combat log feed

t.test("The combat log learns both source and destination players", function()
  local env = setup()
  env.classes = { ["0x01"] = "MAGE", ["0x02"] = "ROGUE" }
  combat(env, "0x01", "Bob", PLAYER_FLAGS, "0x02", "Ann-Frostmourne", PLAYER_FLAGS)
  t.eq(env.intel:ClassForName("Bob"), "MAGE")
  t.eq(env.intel:ClassForName("Ann"), "ROGUE")
  t.eq(env.intel:GUIDForName("Ann"), "0x02")
end)

t.test("Pets and NPCs never reach GetPlayerInfoByGUID", function()
  local env = setup()
  combat(env, "0xF1", "Wolf", PET_FLAGS, "0xF2", "Defias Pillager", NPC_FLAGS)
  combat(env, nil, nil, nil, nil, nil, nil)
  t.eq(#env.infoCalls, 0)
end)

t.test("A known player isn't looked up again", function()
  local env = setup()
  env.classes = { ["0x01"] = "MAGE" }
  combat(env, "0x01", "Bob", PLAYER_FLAGS, nil, nil, nil)
  combat(env, "0x01", "Bob", PLAYER_FLAGS, nil, nil, nil)
  t.eq(#env.infoCalls, 1)
end)

t.test("An uncached player is retried after 2 seconds, not sooner", function()
  local env = setup()
  combat(env, "0x01", "Bob", PLAYER_FLAGS, nil, nil, nil)
  t.eq(#env.infoCalls, 1, "first sighting")

  env.now = 1.9
  combat(env, "0x01", "Bob", PLAYER_FLAGS, nil, nil, nil)
  t.eq(#env.infoCalls, 1, "at 1.9 s")

  env.now = 2.0
  env.classes["0x01"] = "PRIEST"
  combat(env, "0x01", "Bob", PLAYER_FLAGS, nil, nil, nil)
  t.eq(#env.infoCalls, 2, "at 2.0 s")
  t.eq(env.intel:ClassForName("Bob"), "PRIEST")
end)

-- Scoreboard feed

t.test("Entering a BG requests the scoreboard at once and then every 15 seconds", function()
  local env = setup()
  env.instanceType = "pvp"
  env.intel:OnEnteringWorld()
  t.eq(env.requests, 1, "on entering")

  env.intel:Tick(14.9)
  t.eq(env.requests, 1, "at 14.9 s")
  env.intel:Tick(0.1)
  t.eq(env.requests, 2, "at 15 s")
end)

t.test("Arena also polls the scoreboard", function()
  local env = setup()
  env.instanceType = "arena"
  env.intel:OnEnteringWorld()
  t.eq(env.requests, 1)
end)

t.test("Leaving the BG stops the polling", function()
  local env = setup()
  env.instanceType = "pvp"
  env.intel:OnEnteringWorld()
  env.instanceType = "none"
  env.intel:OnEnteringWorld()
  env.intel:Tick(60)
  t.eq(env.requests, 1)
end)

t.test("Scoreboard rows are noted by name, skipping unknown class tokens", function()
  local env = setup()
  env.scores = { { "Bob-Frostmourne", "MAGE" }, { "Ann", "Human" }, { "Cid", nil } }
  env.intel:OnScoreUpdate()
  t.eq(env.intel:ClassForName("Bob"), "MAGE")
  t.eq(env.intel:GUIDForName("Bob"), nil)
  t.eq(env.intel:ClassForName("Ann"), nil)
  t.eq(env.intel:ClassForName("Cid"), nil)
end)
