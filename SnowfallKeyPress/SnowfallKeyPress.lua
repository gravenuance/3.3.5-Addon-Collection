-- SnowfallKeyPress – refactored core

local _G                      = _G

local CreateFrame             = CreateFrame
local hooksecurefunc          = hooksecurefunc
local SetOverrideBindingClick = SetOverrideBindingClick
local InCombatLockdown        = InCombatLockdown
local ipairs                  = ipairs
local pairs                   = pairs
local string_match            = string.match
local string_gsub             = string.gsub
local strfind                 = string.find

local SnowfallKeyPressSV      = SnowfallKeyPressSV or {}
_G.SnowfallKeyPressSV         = SnowfallKeyPressSV

local overrideFrame           = CreateFrame("Frame", "SnowfallKeyPress_OverrideFrame")
local hook                    = true

-------------------------------------------------
-- Allowed types and templates
-------------------------------------------------

local allowedTypeAttributes   = {
  actionbar  = true,
  action     = true,
  pet        = true,
  multispell = true,
  spell      = true,
  item       = true,
  macro      = true,
  cancelaura = true,
  stop       = true,
  target     = true,
  focus      = true,
  assist     = true,
  maintank   = true,
  mainassist = true,
}

local templates               = {
  {
    command = "^ACTIONBUTTON(%d+)$",
    attributes = {
      { "type",         "macro" },
      { "actionbutton", "%1" },
    },
  },
  {
    command = "^MULTIACTIONBAR1BUTTON(%d+)$",
    attributes = {
      { "type",        "click" },
      { "clickbutton", "MultiBarBottomLeftButton%1" },
    },
  },
  {
    command = "^MULTIACTIONBAR2BUTTON(%d+)$",
    attributes = {
      { "type",        "click" },
      { "clickbutton", "MultiBarBottomRightButton%1" },
    },
  },
  {
    command = "^MULTIACTIONBAR3BUTTON(%d+)$",
    attributes = {
      { "type",        "click" },
      { "clickbutton", "MultiBarLeftButton%1" },
    },
  },
  {
    command = "^MULTIACTIONBAR4BUTTON(%d+)$",
    attributes = {
      { "type",        "click" },
      { "clickbutton", "MultiBarRightButton%1" },
    },
  },
  {
    command = "^CLICK (.+):([^:]+)$",
    attributes = {
      { "type",        "click" },
      { "clickbutton", "%1" },
    },
  },
  {
    command = "^SHAPESHIFTBUTTON(%d+)$",
    attributes = {
      { "type",        "click" },
      { "clickbutton", "ShapeshiftButton%1" },
    },
  },
  {
    command = "^BONUSACTIONBUTTON(%d+)$",
    attributes = {
      { "type",         "macro" },
      { "actionbutton", "%1" },
    },
  },
  {
    command = "^MULTICASTSUMMON(%d+)$",
    attributes = {
      { "type",            "click" },
      { "multicastsummon", "%1" },
    },
  },
  {
    command = "^BUTTON(%d+)$",
    attributes = {
      { "type",         "macro" },
      { "actionbutton", "%1" },
    },
  },
  {
    command = "^SPELL (.+)$",
    attributes = {
      { "type",  "spell" },
      { "spell", "%1" },
    },
  },
  {
    command = "^ITEM (.+)$",
    attributes = {
      { "type", "item" },
      { "item", "%1" },
    },
  },
}

-------------------------------------------------
-- Helper: secure button check
-------------------------------------------------

local function isSecureButton(btn)
  return type(btn) == "table"
      and type(btn.IsObjectType) == "function"
      and issecurevariable(btn, "IsObjectType")
      and btn:IsObjectType("Button")
      and select(2, btn:IsProtected())
end

-------------------------------------------------
-- Core: accelerate a key binding
-------------------------------------------------

local function accelerateKey(key, command)
  -- Respect mousewheel toggle
  if (key == "MOUSEWHEELUP" or key == "MOUSEWHEELDOWN")
      and SnowfallKeyPressSV.enableMousewheel == false then
    return
  end

  -- Skip generic MACRO bindings if macros disabled
  if not SnowfallKeyPressSV.enableMacros and strfind(command, "^MACRO ") then
    return
  end

  -- Skip CLICK macros if clicks disabled
  if not SnowfallKeyPressSV.enableClicks and strfind(command, "^CLICK ") then
    return
  end

  local bindButtonName, bindButton
  local attributeName, attributeValue
  local mouseButton, harmButton, helpButton
  local mouseType, harmType, helpType
  local clickButtonName, clickButton

  for _, template in ipairs(templates) do
    if string_match(command, template.command) then
      if not template.attributes then
        return
      end

      clickButtonName, mouseButton = string_match(command, "^CLICK (.+):([^:]+)$")
      if clickButtonName then
        clickButton = _G[clickButtonName]
        if not isSecureButton(clickButton) or clickButton:GetAttribute("", "downbutton", mouseButton) then
          return
        end

        harmButton = SecureButton_GetModifiedAttribute(clickButton, "harmbutton", mouseButton)
        helpButton = SecureButton_GetModifiedAttribute(clickButton, "helpbutton", mouseButton)

        mouseType  = SecureButton_GetModifiedAttribute(clickButton, "type", mouseButton)
        harmType   = SecureButton_GetModifiedAttribute(clickButton, "type", harmButton)
        helpType   = SecureButton_GetModifiedAttribute(clickButton, "type", helpButton)

        if (mouseType and not allowedTypeAttributes[mouseType])
            or (harmType and not allowedTypeAttributes[harmType])
            or (helpType and not allowedTypeAttributes[helpType]) then
          return
        end
      else
        mouseButton = "LeftButton"
      end

      bindButtonName = "SnowfallKeyPress_Button_" .. key
      bindButton = _G[bindButtonName]

      if not bindButton then
        bindButton = CreateFrame("Button", bindButtonName, nil, "SecureActionButtonTemplate")
        bindButton:RegisterForClicks("AnyDown")

        SecureHandlerSetFrameRef(bindButton, "VehicleMenuBar", VehicleMenuBar)
        SecureHandlerSetFrameRef(bindButton, "BonusActionBarFrame", BonusActionBarFrame)
        SecureHandlerSetFrameRef(bindButton, "MultiCastSummonSpellButton", MultiCastSummonSpellButton)

        SecureHandlerExecute(bindButton, [[
                    VehicleMenuBar            = self:GetFrameRef("VehicleMenuBar");
                    BonusActionBarFrame       = self:GetFrameRef("BonusActionBarFrame");
                    MultiCastSummonSpellButton = self:GetFrameRef("MultiCastSummonSpellButton");
                ]])
      end

      SecureHandlerUnwrapScript(bindButton, "OnClick")

      for _, attribute in ipairs(template.attributes) do
        attributeName  = attribute[1]
        attributeValue = string_gsub(command, template.command, attribute[2], 1)

        if attributeName == "clickbutton" then
          bindButton:SetAttribute(attributeName, _G[attributeValue])
        elseif attributeName == "actionbutton" then
          SecureHandlerWrapScript(
            bindButton, "OnClick", bindButton,
            (string.format([[
                            local clickMacro = "/click ActionButton%s";
                            if VehicleMenuBar:IsProtected() and VehicleMenuBar:IsShown() and %s then
                                clickMacro = "/click VehicleMenuBarActionButton%s";
                            elseif BonusActionBarFrame:IsProtected() and BonusActionBarFrame:IsShown() then
                                clickMacro = "/click BonusActionButton%s";
                            end
                            self:SetAttribute("macrotext", clickMacro);
                        ]], attributeValue,
              tostring(tonumber(attributeValue) <= VEHICLE_MAX_ACTIONBUTTONS),
              attributeValue, attributeValue))
          )
        elseif attributeName == "multicastsummon" then
          SecureHandlerWrapScript(
            bindButton, "OnClick", bindButton,
            string.format([[
                            lastID = MultiCastSummonSpellButton:GetID();
                            MultiCastSummonSpellButton:SetID(%s);
                        ]], attributeValue),
            [[
                            MultiCastSummonSpellButton:SetID(lastID);
                        ]]
          )
          bindButton:SetAttribute("clickbutton", MultiCastSummonSpellButton)
        else
          bindButton:SetAttribute(attributeName, attributeValue)
        end
      end

      hook = false
      SetOverrideBindingClick(overrideFrame, true, key, bindButtonName, mouseButton)
      hook = true
      return
    end
  end
end

-------------------------------------------------
-- Binding rebuild
-------------------------------------------------

-- Base key of a possibly modifier-prefixed binding, e.g. "ALT-F1" -> "F1".
local function baseKey(key)
  return string_gsub(key, "^.*%-(.+)", "%1", 1)
end

-- nil = no filter (accelerate every matching binding); otherwise a set of
-- allowed base keys, built from the "Accelerated keys" edit box.
local keyWhitelist = nil

local function rebuildKeyWhitelist()
  local list = SnowfallKeyPressSV.keys
  if type(list) ~= "table" or #list == 0 then
    keyWhitelist = nil
    return
  end

  keyWhitelist = {}
  for _, key in ipairs(list) do
    keyWhitelist[key:upper()] = true
  end
end

local function isKeyAllowed(key)
  return not keyWhitelist or keyWhitelist[baseKey(key):upper()]
end

local function updateBindings()
  if InCombatLockdown() then
    return
  end

  if not SnowfallKeyPressSV.enable then
    return
  end

  rebuildKeyWhitelist()

  local numBindings = GetNumBindings()
  local seenKeys    = {}

  for i = 1, numBindings do
    local command, key1, key2 = GetBinding(i)
    if command and command ~= "" then
      if key1 and key1 ~= "" and not seenKeys[key1] and isKeyAllowed(key1) then
        seenKeys[key1] = true
        accelerateKey(key1, command)
      end
      if key2 and key2 ~= "" and not seenKeys[key2] and isKeyAllowed(key2) then
        seenKeys[key2] = true
        accelerateKey(key2, command)
      end
    end
  end
end

-------------------------------------------------
-- Config frame (keys list)
-------------------------------------------------

local configFrame = CreateFrame("Frame", "SnowfallKeyPress_ConfigFrame", InterfaceOptionsFramePanelContainer)
configFrame.name = "Snowfall Key Press"

-------------------------------------------------
-- Enable/disable + category toggles
-------------------------------------------------

-- Master enable
configFrame.enableButton = CreateFrame(
  "CheckButton",
  "SnowfallKeyPress_configFrameEnableButton",
  configFrame,
  "UICheckButtonTemplate"
)
configFrame.enableButton:SetPoint("TOPLEFT", 16, -120)
SnowfallKeyPress_configFrameEnableButtonText:SetText(ENABLE)
configFrame.enableButton:SetScript("OnClick", function(self)
  SnowfallKeyPressSV.enable = self:GetChecked() and true or false
  if SnowfallKeyPressSV.enable then
    hook = true
    overrideFrame:RegisterEvent("UPDATE_BINDINGS")
  else
    overrideFrame:UnregisterEvent("UPDATE_BINDINGS")
  end
  updateBindings()
end)

-- Macros toggle
configFrame.macrosButton = CreateFrame(
  "CheckButton",
  "SnowfallKeyPress_configFrameMacrosButton",
  configFrame,
  "UICheckButtonTemplate"
)
configFrame.macrosButton:SetPoint("TOPLEFT", configFrame.enableButton, "BOTTOMLEFT", 0, -4)
SnowfallKeyPress_configFrameMacrosButtonText:SetText("Accelerate macros")
configFrame.macrosButton:SetScript("OnClick", function(self)
  SnowfallKeyPressSV.enableMacros = self:GetChecked() and true or false
  updateBindings()
end)

-- Clicks toggle
configFrame.clicksButton = CreateFrame(
  "CheckButton",
  "SnowfallKeyPress_configFrameClicksButton",
  configFrame,
  "UICheckButtonTemplate"
)
configFrame.clicksButton:SetPoint("TOPLEFT", configFrame.macrosButton, "BOTTOMLEFT", 0, -4)
SnowfallKeyPress_configFrameClicksButtonText:SetText("Accelerate click macros")
configFrame.clicksButton:SetScript("OnClick", function(self)
  SnowfallKeyPressSV.enableClicks = self:GetChecked() and true or false
  updateBindings()
end)

-- Mousewheel toggle
configFrame.wheelButton = CreateFrame(
  "CheckButton",
  "SnowfallKeyPress_configFrameWheelButton",
  configFrame,
  "UICheckButtonTemplate"
)
configFrame.wheelButton:SetPoint("TOPLEFT", configFrame.clicksButton, "BOTTOMLEFT", 0, -4)
SnowfallKeyPress_configFrameWheelButtonText:SetText("Accelerate mousewheel")
configFrame.wheelButton:SetScript("OnClick", function(self)
  SnowfallKeyPressSV.enableMousewheel = self:GetChecked() and true or false
  updateBindings()
end)

-------------------------------------------------
-- Accelerated keys edit box
-------------------------------------------------

configFrame.keysLabel = configFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
configFrame.keysLabel:SetPoint("TOPLEFT", configFrame.wheelButton, "BOTTOMLEFT", 4, -10)
configFrame.keysLabel:SetText("Accelerated keys (comma-separated):")

configFrame.keysEdit = CreateFrame("EditBox", nil, configFrame, "InputBoxTemplate")
configFrame.keysEdit:SetAutoFocus(false)
configFrame.keysEdit:SetSize(316, 24)
configFrame.keysEdit:SetPoint("TOPLEFT", configFrame.keysLabel, "BOTTOMLEFT", 0, -4)

local function serializeKeys()
  if type(SnowfallKeyPressSV.keys) ~= "table" then return "" end
  local t = {}
  for _, key in ipairs(SnowfallKeyPressSV.keys) do
    t[#t + 1] = key
  end
  return table.concat(t, ", ")
end

local function parseKeys(text)
  local keys = {}
  for token in string.gmatch(text or "", "([^,%s]+)") do
    keys[#keys + 1] = token
  end
  return keys
end

configFrame.keysEdit:SetScript("OnEnterPressed", function(self)
  SnowfallKeyPressSV.keys = parseKeys(self:GetText())
  self:ClearFocus()
  updateBindings()
end)

configFrame.keysEdit:SetScript("OnEscapePressed", function(self)
  self:SetText(serializeKeys())
  self:ClearFocus()
end)

-------------------------------------------------
-- Clear Blizzard keybinding mode spam
-------------------------------------------------

hooksecurefunc("ShowUIPanel", function()
  if KeyBindingFrame then
    KeyBindingFrame.mode = nil
  end
end)

-------------------------------------------------
-- Core event hook to rebuild on binding changes
-------------------------------------------------

overrideFrame:SetScript("OnEvent", function(_, event)
  if event == "UPDATE_BINDINGS" and hook then
    updateBindings()
  end
end)

-- Initialize checkbox state and initial binding scan
configFrame.enableButton:SetChecked(SnowfallKeyPressSV.enable ~= false)
configFrame.macrosButton:SetChecked(SnowfallKeyPressSV.enableMacros == true)
configFrame.clicksButton:SetChecked(SnowfallKeyPressSV.enableClicks == true)
configFrame.wheelButton:SetChecked(SnowfallKeyPressSV.enableMousewheel == true)
configFrame.keysEdit:SetText(serializeKeys())

if SnowfallKeyPressSV.enable ~= false then
  overrideFrame:RegisterEvent("UPDATE_BINDINGS")
  updateBindings()
end

InterfaceOptions_AddCategory(configFrame)
