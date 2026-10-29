-- Runs in the standalone interpreter and replaces client globals with stubs on purpose.
---@diagnostic disable: duplicate-set-field, undefined-global
local t = ...

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

-- Upper-left corner of each raid icon on the 4x4 icon texture, marks 1-8.
local ICON_CORNER = {
  { 0, 0 }, { 0.25, 0 }, { 0.5, 0 }, { 0.75, 0 },
  { 0, 0.25 }, { 0.25, 0.25 }, { 0.5, 0.25 }, { 0.75, 0.25 },
}

local SKULL = 8

local function noop() end

local function newAuraFrame()
  return { hides = 0, SetScript = noop, Hide = function(self) self.hides = self.hides + 1 end }
end

-- Fresh client stubs and a fresh addon namespace per test, because the modules cache globals at load.
local function setup()
  local env = { tokens = {}, plates = {}, collected = {}, refreshed = {} }

  _G.bit = { band = band, rshift = rshift }
  _G.wipe = function(tbl) for k in pairs(tbl) do tbl[k] = nil end return tbl end
  _G.GetTime = function() return 0 end
  _G.CreateFrame = function() return { RegisterEvent = noop, SetScript = noop } end
  _G.IsInInstance = function() return false end
  _G.GetNumPartyMembers = function() return 0 end
  _G.GetNumRaidMembers = function() return 2 end
  _G.GetPlayerInfoByGUID = function() return nil end
  _G.UnitExists = function(unit) return env.tokens[unit] ~= nil end
  _G.UnitGUID = function(unit) return env.tokens[unit] and env.tokens[unit].guid end
  _G.UnitName = function(unit) return env.tokens[unit] and env.tokens[unit].name end
  _G.UnitHealthMax = function(unit) return env.tokens[unit] and env.tokens[unit].health end
  _G.UnitIsPlayer = function(unit) return env.tokens[unit] and env.tokens[unit].player or false end
  _G.UnitClass = function(unit) return "Localized", env.tokens[unit] and env.tokens[unit].class end
  _G.GetRaidTargetIndex = function(unit) return env.tokens[unit] and env.tokens[unit].mark end
  _G.UnitCastingInfo = noop
  _G.UnitChannelInfo = noop
  _G.GetSpellInfo = noop
  _G.RAID_CLASS_COLORS = {}

  local ns = t.newNamespace("Units.lua", "ClassIntel.lua", "MarkIntel.lua")
  ns.GetAllNameplates = function() return env.plates end
  ns.Auras = {
    Refresh = function(_, unit) env.refreshed[#env.refreshed + 1] = unit end,
    Collect = function(_, guid) env.collected[#env.collected + 1] = guid return {} end,
  }
  t.loadAddonFile("Nameplate.lua", ns)

  env.ns = ns
  env.nameplate = ns.Nameplate
  return env
end

-- A fake plate: the custom frame plus the default Blizzard frame it hangs from.
local function addPlate(env, name, health)
  local default = {
    name = name, health = health or 100, alpha = 0.5, shown = true, highlighted = false,
    iconShown = false, iconLeft = 0, iconTop = 0,
  }
  default.unitName = { GetText = function() return default.name end }
  default.healthBar = { GetMinMaxValues = function() return 0, default.health end }
  default.highlight = { IsShown = function() return default.highlighted end }
  default.raidIcon = {
    IsShown = function() return default.iconShown end,
    GetTexCoord = function()
      local l, tp = default.iconLeft, default.iconTop
      return l, tp, l, tp + 0.25, l + 0.25, tp, l + 0.25, tp + 0.25
    end,
  }
  default.GetAlpha = function(self) return self.alpha end
  default.IsShown = function(self) return self.shown end

  local plate = {
    default = default,
    GetParent = function() return default end,
    debuffs = { SetWidth = noop },
    buffs = { SetWidth = noop },
    debuffFrames = { newAuraFrame() },
    buffFrames = { newAuraFrame() },
  }
  env.plates[#env.plates + 1] = plate
  plate.index = #env.plates
  return plate
end

local function setToken(env, unit, guid, name, extra)
  local token = { guid = guid, name = name, health = 100, class = nil, player = false }
  for k, v in pairs(extra or {}) do token[k] = v end
  env.tokens[unit] = token
end

-- Makes `plate` the plate of the target token and dims the others, like the client does.
local function setTarget(env, plate, guid, name)
  for _, other in ipairs(env.plates) do other.default.alpha = 0.5 end
  plate.default.alpha = 1
  setToken(env, "target", guid, name)
end

local function showMark(plate, mark)
  plate.default.iconShown = true
  plate.default.iconLeft, plate.default.iconTop = ICON_CORNER[mark][1], ICON_CORNER[mark][2]
end

local function hideMark(plate)
  plate.default.iconShown = false
end

local function resolve(env, plate)
  return env.nameplate:Resolve(plate)
end

-- Which plate the registry says holds `guid`, as a readable value.
local function holder(env, guid)
  local plate = env.nameplate:Get(guid)
  return plate and ("plate" .. plate.index) or "none"
end

local function redraws(plate)
  return plate.debuffFrames[1].hides
end

-- Units reverse map

t.test("A name and health written by two GUIDs finds neither", function()
  local units = t.newNamespace("Units.lua").Units
  units:SetGUID("g1", "Defias Thug", 100)
  units:SetGUID("g2", "Defias Thug", 100)
  t.eq(units:GetGUID("Defias Thug", 100), nil, "ambiguous key")
end)

t.test("An ambiguous name and health stays ambiguous when a GUID is written again", function()
  local units = t.newNamespace("Units.lua").Units
  units:SetGUID("g1", "Defias Thug", 100)
  units:SetGUID("g2", "Defias Thug", 100)
  units:SetGUID("g1", "Defias Thug", 100)
  t.eq(units:GetGUID("Defias Thug", 100), nil)
end)

t.test("A name and health written again by the same GUID still finds it", function()
  local units = t.newNamespace("Units.lua").Units
  units:SetGUID("g1", "Defias Thug", 100)
  units:SetGUID("g1", "Defias Thug", 100, "WARRIOR")
  t.eq(units:GetGUID("Defias Thug", 100), "g1")
end)

t.test("The same name with different health stays unambiguous", function()
  local units = t.newNamespace("Units.lua").Units
  units:SetGUID("g1", "Defias Thug", 100)
  units:SetGUID("g2", "Defias Thug", 200)
  t.eq(units:GetGUID("Defias Thug", 100), "g1")
  t.eq(units:GetGUID("Defias Thug", 200), "g2")
end)

t.test("Per-GUID data survives an ambiguous reverse key", function()
  local units = t.newNamespace("Units.lua").Units
  units:SetGUID("g1", "Defias Thug", 100, "ROGUE")
  units:SetGUID("g2", "Defias Thug", 100)
  t.eq(units:Get("g1").class, "ROGUE")
  t.eq(units:Get("g2").name, "Defias Thug")
end)

-- Proof from the target and mouseover tokens

t.test("The target plate binds to the target's GUID", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  setTarget(env, plate, "g1", "Defias Thug")
  t.eq(resolve(env, plate), "target")
  t.eq(plate.unitGUID, "g1")
  t.eq(holder(env, "g1"), "plate1")
end)

t.test("The mouseover plate binds to the mouseover's GUID even when its name is shared", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  addPlate(env, "Defias Thug")
  plate.default.highlighted = true
  setToken(env, "mouseover", "g1", "Defias Thug")
  t.eq(resolve(env, plate), "mouseover")
  t.eq(plate.unitGUID, "g1")
end)

t.test("A target with another name than the plate is not a proof", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  setTarget(env, plate, "g9", "Defias Rogue")
  t.eq(resolve(env, plate), nil)
  t.eq(plate.unitGUID, nil)
end)

t.test("Binding by token teaches Units the name, health and class", function()
  local env = setup()
  local plate = addPlate(env, "Bob", 500)
  setTarget(env, plate, "g1", "Bob")
  env.tokens.target.health, env.tokens.target.class = 500, "MAGE"
  resolve(env, plate)
  t.eq(env.ns.Units:GetGUID("Bob", 500), "g1")
  t.eq(env.ns.Units:Get("g1").class, "MAGE")
end)

-- Proof from raid marks

t.test("A marked plate binds to the marked GUID without any token", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  showMark(plate, SKULL)
  env.ns.MarkIntel:Set("g1", SKULL)
  t.eq(resolve(env, plate), nil, "no token to return")
  t.eq(plate.unitGUID, "g1")
  t.eq(holder(env, "g1"), "plate1")
end)

t.test("A marked plate returns the token that shows its GUID", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  showMark(plate, SKULL)
  setToken(env, "raid1target", "g1", "Defias Thug")
  env.ns.MarkIntel:Set("g1", SKULL)
  t.eq(resolve(env, plate), "raid1target")
end)

t.test("A mark nobody knows binds nothing", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  showMark(plate, SKULL)
  t.eq(resolve(env, plate), nil)
  t.eq(plate.unitGUID, nil)
end)

t.test("A hidden raid icon binds nothing even if its coordinates map to a mark", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  showMark(plate, SKULL)
  hideMark(plate)
  env.ns.MarkIntel:Set("g1", SKULL)
  resolve(env, plate)
  t.eq(plate.unitGUID, nil)
end)

t.test("Each mark finds its own GUID through the plate icon", function()
  local env = setup()
  for mark = 1, 8 do
    local plate = addPlate(env, "Defias Thug")
    showMark(plate, mark)
    env.ns.MarkIntel:Set("g" .. mark, mark)
    resolve(env, plate)
    t.eq(plate.unitGUID, "g" .. mark, "mark " .. mark)
  end
end)

t.test("Marks scanned from tokens bind a plate through the candidate list", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  showMark(plate, SKULL)
  setToken(env, "raid1target", "g1", "Defias Thug", { mark = SKULL })
  env.ns.MarkIntel:ScanTokens(env.nameplate:GetUnitCandidates())
  t.eq(resolve(env, plate), "raid1target")
  t.eq(plate.unitGUID, "g1")
end)

t.test("Two same-named mobs, one marked: the unmarked plate does not take the marked GUID", function()
  local env = setup()
  local marked = addPlate(env, "Defias Thug")
  local other = addPlate(env, "Defias Thug")
  showMark(marked, SKULL)
  env.ns.MarkIntel:Set("g1", SKULL)
  env.ns.Units:SetGUID("g1", "Defias Thug", 100)
  resolve(env, marked)
  resolve(env, other)
  t.eq(marked.unitGUID, "g1")
  t.eq(other.unitGUID, nil)
  t.eq(holder(env, "g1"), "plate1")
end)

t.test("Two same-named mobs, one marked: the mark takes its GUID back from an earlier guess", function()
  local env = setup()
  local marked = addPlate(env, "Defias Thug")
  local other = addPlate(env, "Defias Thug")
  showMark(marked, SKULL)
  env.ns.MarkIntel:Set("g1", SKULL)
  env.ns.Units:SetGUID("g1", "Defias Thug", 100)
  resolve(env, other)
  t.eq(other.unitGUID, "g1", "guessed first")
  resolve(env, marked)
  t.eq(marked.unitGUID, "g1")
  t.eq(other.unitGUID, nil, "guess displaced")
  resolve(env, other)
  t.eq(other.unitGUID, nil, "guess does not come back")
  t.eq(holder(env, "g1"), "plate1")
end)

t.test("A mark that moves rebinds the marked plate and releases the old GUID", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  showMark(plate, SKULL)
  env.ns.MarkIntel:Set("gA", SKULL)
  resolve(env, plate)
  env.ns.MarkIntel:Set("gB", SKULL)
  resolve(env, plate)
  t.eq(plate.unitGUID, "gB")
  t.eq(holder(env, "gA"), "none")
  t.eq(holder(env, "gB"), "plate1")
end)

t.test("A mark that moves to another mob leaves the first mob's plate bound", function()
  local env = setup()
  local plateA = addPlate(env, "Defias Thug")
  local plateB = addPlate(env, "Defias Thug")
  showMark(plateA, SKULL)
  env.ns.MarkIntel:Set("gA", SKULL)
  resolve(env, plateA)
  hideMark(plateA)
  showMark(plateB, SKULL)
  env.ns.MarkIntel:Set("gB", SKULL)
  resolve(env, plateA)
  resolve(env, plateB)
  t.eq(plateA.unitGUID, "gA")
  t.eq(plateB.unitGUID, "gB")
end)

-- Sticky binding

t.test("A proven plate keeps its GUID when a token for a same-named mob appears", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  showMark(plate, SKULL)
  env.ns.MarkIntel:Set("g1", SKULL)
  resolve(env, plate)
  hideMark(plate)
  setToken(env, "raid2target", "g2", "Defias Thug")
  resolve(env, plate)
  t.eq(plate.unitGUID, "g1")
  t.eq(holder(env, "g1"), "plate1")
  t.eq(holder(env, "g2"), "none")
end)

t.test("A proven plate keeps its GUID after it stops being the target", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  setTarget(env, plate, "g1", "Defias Thug")
  resolve(env, plate)
  plate.default.alpha = 0.5
  setToken(env, "target", "g2", "Defias Rogue")
  t.eq(resolve(env, plate), nil, "g1 has no token any more")
  t.eq(plate.unitGUID, "g1")
end)

t.test("A proven plate keeps its GUID when a second plate with the same name appears", function()
  local env = setup()
  local first = addPlate(env, "Defias Thug")
  setToken(env, "focus", "g1", "Defias Thug")
  resolve(env, first)
  t.eq(first.unitGUID, "g1", "unique name binds")
  addPlate(env, "Defias Thug")
  resolve(env, first)
  t.eq(first.unitGUID, "g1")
end)

t.test("A plate that becomes the target with another GUID rebinds and releases the old one", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  setTarget(env, plate, "g1", "Defias Thug")
  resolve(env, plate)
  setTarget(env, plate, "g2", "Defias Thug")
  t.eq(resolve(env, plate), "target")
  t.eq(plate.unitGUID, "g2")
  t.eq(holder(env, "g1"), "none", "old GUID released")
  t.eq(holder(env, "g2"), "plate1")
end)

t.test("The same GUID proven on a second plate unbinds the first and redraws both", function()
  local env = setup()
  local first = addPlate(env, "Defias Thug")
  local second = addPlate(env, "Defias Thug")
  setTarget(env, first, "g1", "Defias Thug")
  resolve(env, first)
  env.tokens.target = nil
  first.default.alpha = 0.5
  showMark(second, SKULL)
  env.ns.MarkIntel:Set("g1", SKULL)

  local firstDrawn, secondDrawn = redraws(first), redraws(second)
  resolve(env, second)

  t.eq(second.unitGUID, "g1")
  t.eq(first.unitGUID, nil)
  t.eq(holder(env, "g1"), "plate2")
  t.eq(redraws(first), firstDrawn + 1, "old holder redrawn")
  t.eq(redraws(second), secondDrawn + 1, "new holder redrawn")
end)

t.test("Rebinding a plate collects the auras of its new GUID", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  setTarget(env, plate, "g1", "Defias Thug")
  resolve(env, plate)
  env.collected = {}
  setTarget(env, plate, "g2", "Defias Thug")
  resolve(env, plate)
  t.eq(env.collected, { "g2", "g2" }, "debuff row and buff row")
end)

t.test("Resolving an unchanged binding redraws nothing", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  setTarget(env, plate, "g1", "Defias Thug")
  resolve(env, plate)
  local drawn = redraws(plate)
  resolve(env, plate)
  resolve(env, plate)
  t.eq(redraws(plate), drawn)
end)

t.test("A plate whose name changes drops its binding", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  showMark(plate, SKULL)
  env.ns.MarkIntel:Set("g1", SKULL)
  resolve(env, plate)
  hideMark(plate)
  plate.default.name = "Defias Rogue"
  resolve(env, plate)
  t.eq(plate.unitGUID, nil)
  t.eq(holder(env, "g1"), "none")
end)

t.test("Unbind releases the GUID", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  setTarget(env, plate, "g1", "Defias Thug")
  resolve(env, plate)
  env.nameplate:Unbind(plate)
  t.eq(plate.unitGUID, nil)
  t.eq(holder(env, "g1"), "none")
end)

t.test("Unbind forgets the proof, so the plate can bind by name again", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  showMark(plate, SKULL)
  env.ns.MarkIntel:Set("g1", SKULL)
  resolve(env, plate)
  env.nameplate:Unbind(plate)
  hideMark(plate)
  setToken(env, "focus", "g3", "Defias Thug")
  resolve(env, plate)
  t.eq(plate.unitGUID, "g3")
end)

t.test("A guess is replaced by a name proof for another GUID", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  env.ns.Units:SetGUID("g2", "Defias Thug", 100)
  resolve(env, plate)
  t.eq(plate.unitGUID, "g2", "guessed")
  setToken(env, "focus", "g3", "Defias Thug")
  resolve(env, plate)
  t.eq(plate.unitGUID, "g3")
  t.eq(holder(env, "g2"), "none")
end)

-- Guesses

t.test("A guess from name and health fills an empty plate", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug", 100)
  env.ns.Units:SetGUID("g1", "Defias Thug", 100)
  resolve(env, plate)
  t.eq(plate.unitGUID, "g1")
end)

t.test("A guess from a unique player name fills an empty plate", function()
  local env = setup()
  local plate = addPlate(env, "Bob")
  env.ns.ClassIntel:Note("0xB", "Bob", "MAGE")
  resolve(env, plate)
  t.eq(plate.unitGUID, "0xB")
end)

t.test("An ambiguous name and health guesses nothing", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug", 100)
  env.ns.Units:SetGUID("g1", "Defias Thug", 100)
  env.ns.Units:SetGUID("g2", "Defias Thug", 100)
  resolve(env, plate)
  t.eq(plate.unitGUID, nil)
end)

t.test("A guess does not take a GUID another plate holds", function()
  local env = setup()
  local proven = addPlate(env, "Defias Thug")
  local other = addPlate(env, "Defias Thug")
  setTarget(env, proven, "g1", "Defias Thug")
  resolve(env, proven)
  env.ns.Units:SetGUID("g1", "Defias Thug", 100)
  resolve(env, other)
  t.eq(other.unitGUID, nil)
  t.eq(holder(env, "g1"), "plate1")
end)

t.test("A guess never overrides a proof", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug", 100)
  showMark(plate, SKULL)
  env.ns.MarkIntel:Set("g1", SKULL)
  resolve(env, plate)
  env.ns.Units:SetGUID("g2", "Defias Thug", 100)
  resolve(env, plate)
  t.eq(plate.unitGUID, "g1")
end)

t.test("A guess is not replaced by another guess", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug", 100)
  env.ns.Units:SetGUID("g1", "Defias Thug", 100)
  resolve(env, plate)
  env.ns.Units:SetGUID("g2", "Defias Thug", 200)
  plate.default.health = 200
  resolve(env, plate)
  t.eq(plate.unitGUID, "g1")
end)

t.test("A proof for another GUID replaces a guess", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug", 100)
  env.ns.Units:SetGUID("g1", "Defias Thug", 100)
  resolve(env, plate)
  setTarget(env, plate, "g2", "Defias Thug")
  resolve(env, plate)
  t.eq(plate.unitGUID, "g2")
  t.eq(holder(env, "g1"), "none")
end)

t.test("A proof for the guessed GUID upgrades it, and a name match elsewhere then leaves it alone", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug", 100)
  env.ns.Units:SetGUID("g1", "Defias Thug", 100)
  resolve(env, plate)
  setTarget(env, plate, "g1", "Defias Thug")
  resolve(env, plate)
  plate.default.alpha = 0.5
  env.tokens.target = nil
  setToken(env, "focus", "g2", "Defias Thug")
  resolve(env, plate)
  t.eq(plate.unitGUID, "g1", "proven now")
end)

-- Binding by name alone

t.test("A name shown by one plate and one token binds that plate", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  setToken(env, "focus", "g1", "Defias Thug")
  t.eq(resolve(env, plate), "focus")
  t.eq(plate.unitGUID, "g1")
end)

t.test("A name shown by two visible plates binds neither", function()
  local env = setup()
  local first = addPlate(env, "Defias Thug")
  local second = addPlate(env, "Defias Thug")
  setToken(env, "focus", "g1", "Defias Thug")
  resolve(env, first)
  resolve(env, second)
  t.eq(first.unitGUID, nil)
  t.eq(second.unitGUID, nil)
end)

t.test("A hidden plate with the same name does not count", function()
  local env = setup()
  local visible = addPlate(env, "Defias Thug")
  local hidden = addPlate(env, "Defias Thug")
  hidden.default.shown = false
  setToken(env, "focus", "g1", "Defias Thug")
  resolve(env, visible)
  t.eq(visible.unitGUID, "g1")
end)

t.test("A plate that is not in the plate list yet still counts the plates already there", function()
  local env = setup()
  addPlate(env, "Defias Thug")
  local newcomer = addPlate(env, "Defias Thug")
  env.plates[2] = nil
  setToken(env, "focus", "g1", "Defias Thug")
  resolve(env, newcomer)
  t.eq(newcomer.unitGUID, nil)
end)

t.test("A different name on the plate than on the token binds nothing", function()
  local env = setup()
  local plate = addPlate(env, "Defias Rogue")
  setToken(env, "focus", "g1", "Defias Thug")
  resolve(env, plate)
  t.eq(plate.unitGUID, nil)
end)

t.test("Two tokens with different GUIDs and the same name bind nothing", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  setToken(env, "focus", "g1", "Defias Thug")
  setToken(env, "raid1target", "g2", "Defias Thug")
  resolve(env, plate)
  t.eq(plate.unitGUID, nil)
end)

t.test("Two tokens with the same GUID and name bind that GUID", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  setToken(env, "focus", "g1", "Defias Thug")
  setToken(env, "raid1target", "g1", "Defias Thug")
  resolve(env, plate)
  t.eq(plate.unitGUID, "g1")
end)

t.test("Binding by name teaches Units the name, health and class", function()
  local env = setup()
  local plate = addPlate(env, "Bob", 500)
  setToken(env, "focus", "g1", "Bob", { health = 500, class = "ROGUE", player = true })
  resolve(env, plate)
  t.eq(env.ns.Units:GetGUID("Bob", 500), "g1")
  t.eq(env.ns.ClassIntel:ClassForGUID("g1"), "ROGUE")
end)

-- Entering the world

t.test("After entering the world a marked plate has no mark to bind through", function()
  local env = setup()
  local plate = addPlate(env, "Defias Thug")
  showMark(plate, SKULL)
  env.ns.MarkIntel:Set("g1", SKULL)
  env.ns.MarkIntel:OnEnteringWorld()
  resolve(env, plate)
  t.eq(plate.unitGUID, nil)
end)
