local SimpleCombatLogger = LibStub("AceAddon-3.0"):NewAddon("SimpleCombatLogger", "AceConsole-3.0", "AceEvent-3.0",
    "AceTimer-3.0")

local IsLoggingCombat = false
local DelayStopTimer = nil

local function Trim(str)
    if not str then return "" end
    return (str:gsub("^%s*(.-)%s*$", "%1"))
end

local options = {
    name = "SimpleCombatLogger",
    handler = SimpleCombatLogger,
    type = "group",
    args = {
        enable = {
            name = "Enabled",
            desc = "Enables / Disables the addon",
            type = "toggle",
            set = function(info, value) SimpleCombatLogger:SetEnable(value) end,
            get = function(info) return SimpleCombatLogger.db.profile.enable end,
        },

        enabledebug = {
            name = "Debug",
            desc = "Enable Debug output",
            type = "toggle",
            set = function(info, value) SimpleCombatLogger.db.profile.enabledebug = value end,
            get = function(info) return SimpleCombatLogger.db.profile.enabledebug end,
        },

        delaystop = {
            name = "Delayed Log Stop",
            desc = "Delay the stopping of combat logging by 30 seconds.",
            type = "toggle",
            set = function(info, value) SimpleCombatLogger.db.profile.delaystop = value end,
            get = function(info) return SimpleCombatLogger.db.profile.delaystop end,
        },

        party = {
            name = "Party",
            type = "group",
            args = {
                normal = {
                    name = "Normal",
                    desc = "Enables / Disables normal dungeon logging",
                    type = "toggle",
                    set = function(info, value)
                        SimpleCombatLogger.db.profile.party.normal = value
                        SimpleCombatLogger:CheckToggleLogging(nil)
                    end,
                    get = function(info) return SimpleCombatLogger.db.profile.party.normal end,
                },
                heroic = {
                    name = "Heroic",
                    desc = "Enables / Disables heroic dungeon logging",
                    type = "toggle",
                    set = function(info, value)
                        SimpleCombatLogger.db.profile.party.heroic = value
                        SimpleCombatLogger:CheckToggleLogging(nil)
                    end,
                    get = function(info) return SimpleCombatLogger.db.profile.party.heroic end,
                },
            },
        },

        raid = {
            name = "Raid",
            type = "group",
            args = {
                normal = {
                    name = "Normal",
                    desc = "Enables / Disables normal raid logging",
                    type = "toggle",
                    set = function(info, value)
                        SimpleCombatLogger.db.profile.raid.normal = value
                        SimpleCombatLogger:CheckToggleLogging(nil)
                    end,
                    get = function(info) return SimpleCombatLogger.db.profile.raid.normal end,
                },
                heroic = {
                    name = "Heroic",
                    desc = "Enables / Disables heroic raid logging",
                    type = "toggle",
                    set = function(info, value)
                        SimpleCombatLogger.db.profile.raid.heroic = value
                        SimpleCombatLogger:CheckToggleLogging(nil)
                    end,
                    get = function(info) return SimpleCombatLogger.db.profile.raid.heroic end,
                },
            },
        },

        pvp = {
            name = "PvP",
            type = "group",
            args = {
                bg = {
                    name = "Battlegrounds",
                    desc = "Enables / Disables battleground logging",
                    type = "toggle",
                    set = function(info, value)
                        SimpleCombatLogger.db.profile.pvp.bg = value
                        SimpleCombatLogger:CheckToggleLogging(nil)
                    end,
                    get = function(info) return SimpleCombatLogger.db.profile.pvp.bg end,
                },
                arena = {
                    name = "Arena",
                    desc = "Enables / Disables arena logging",
                    type = "toggle",
                    set = function(info, value)
                        SimpleCombatLogger.db.profile.pvp.arena = value
                        SimpleCombatLogger:CheckToggleLogging(nil)
                    end,
                    get = function(info) return SimpleCombatLogger.db.profile.pvp.arena end,
                },
            },
        },
    },
}

local defaults = {
    profile = {
        enable = true,
        enabledebug = false,
        delaystop = true,

        party = {
            normal = true,
            heroic = true,
        },

        raid = {
            normal = true,
            heroic = true,
        },

        pvp = {
            bg = true,
            arena = true,
        },
    },
}
function SimpleCombatLogger:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("SimpleCombatLoggerDB", defaults, true)

    self.db.RegisterCallback(self, "OnProfileChanged", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileCopied", "RefreshConfig")
    self.db.RegisterCallback(self, "OnProfileReset", "RefreshConfig")

    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("SimpleCombatLogger", options)
    _, self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("SimpleCombatLogger", "SimpleCombatLogger")

    LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("SCL/Profiles",
        LibStub("AceDBOptions-3.0"):GetOptionsTable(self.db))
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("SCL/Profiles", "Profiles", "SimpleCombatLogger")

    self:RegisterChatCommand("scl", "ChatCommand")
    self:RegisterChatCommand("SimpleCombatLogger", "ChatCommand")

    hooksecurefunc("LoggingCombat", function(state)
        IsLoggingCombat = state
        if self.db.profile.enabledebug then
            self:Print("LoggingCombat called with: " .. tostring(state))
        end
    end)
end

function SimpleCombatLogger:RefreshConfig()
    self:CheckToggleLogging(nil)
end

function SimpleCombatLogger:OnEnable()
    if not self.db.profile.enable then
        self:OnDisable()
        return
    end

    self:Print("Enabled")

    self:RegisterEvent("UPDATE_INSTANCE_INFO", "CheckEnableLogging")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "CheckDisableLogging")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ArenaEventTimer")

    self:CheckToggleLogging(nil)
end

function SimpleCombatLogger:OnDisable()
    self:Print("Disabled")

    self:UnregisterEvent("UPDATE_INSTANCE_INFO")
    self:UnregisterEvent("ZONE_CHANGED_NEW_AREA")
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")

    self:StopLogging()
end

function SimpleCombatLogger:ChatCommand(input)
    input = Trim(input)

    if input == "" then
        InterfaceOptionsFrame_OpenToCategory("SimpleCombatLogger")
    elseif input == "enable" then
        self:SetEnable(true)
    elseif input == "disable" then
        self:SetEnable(false)
    elseif input == "test" then
        self:Print("Logging Combat: " .. tostring(IsLoggingCombat))
        self:Print("Instance Info: " .. tostring(GetInstanceInfo()))
    else
        LibStub("AceConfigCmd-3.0").HandleCommand(SimpleCombatLogger, "SimpleCombatLogger", "SimpleCombatLogger", input)
    end
end

function SimpleCombatLogger:ArenaEventTimer(event)
    local name, instanceType, difficultyID, difficultyName, maxPlayers = GetInstanceInfo()

    if self.db.profile.enabledebug then
        self:Print("Arena Event Timer")
        self:Print("Currently Logging: " .. tostring(IsLoggingCombat))
        self:Print("Event: " .. tostring(event))
        self:Print(" name: " .. tostring(name))
        self:Print(" instanceType: " .. tostring(instanceType))
        self:Print(" difficultyID: " .. tostring(difficultyID))
        self:Print(" difficultyName: " .. tostring(difficultyName))
        self:Print(" maxPlayers: " .. tostring(maxPlayers))
    end

    if instanceType == "arena" then
        if self.db.profile.enabledebug then
            self:Print("Scheduling arena check for 5 seconds")
        end
        self:ScheduleTimer("CheckToggleLogging", 5)
    else
        -- entering world somewhere else, just re‑evaluate
        self:CheckToggleLogging(nil)
    end
end

function SimpleCombatLogger:CheckToggleLogging(event)
    if IsLoggingCombat then
        self:CheckDisableLogging(event)
    else
        self:CheckEnableLogging(event)
    end
end

function SimpleCombatLogger:CheckEnableLogging(event)
    local name, instanceType, difficultyID, difficultyName, maxPlayers = GetInstanceInfo()

    if self.db.profile.enabledebug then
        self:Print("Check Enable")
        self:Print("Currently Logging: " .. tostring(IsLoggingCombat))
        self:Print("Event: " .. tostring(event))
        self:Print(" name: " .. tostring(name))
        self:Print(" instanceType: " .. tostring(instanceType))
        self:Print(" difficultyID: " .. tostring(difficultyID))
        self:Print(" difficultyName: " .. tostring(difficultyName))
        self:Print(" maxPlayers: " .. tostring(maxPlayers))
    end

    if instanceType == "party" then
        if difficultyID == 1 and self.db.profile.party.normal then
            self:StartLogging()
        elseif difficultyID == 2 and self.db.profile.party.heroic then
            self:StartLogging()
        end
    elseif instanceType == "raid" then
        -- 3.3.5: treat all raids as either normal or heroic, but most servers
        -- encode 10/25 + normal/heroic via difficultyID; for simplicity:
        if self.db.profile.raid.normal or self.db.profile.raid.heroic then
            self:StartLogging()
        end
    elseif instanceType == "pvp" then
        -- Battlegrounds
        if self.db.profile.pvp.bg then
            self:StartLogging()
        end
    elseif instanceType == "arena" then
        if self.db.profile.pvp.arena then
            self:StartLogging()
        end
    end
end

function SimpleCombatLogger:CheckDisableLogging(event)
    local name, instanceType, difficultyID, difficultyName, maxPlayers = GetInstanceInfo()

    if self.db.profile.enabledebug then
        self:Print("Check Disable")
        self:Print("Currently Logging: " .. tostring(IsLoggingCombat))
        self:Print("Event: " .. tostring(event))
        self:Print(" name: " .. tostring(name))
        self:Print(" instanceType: " .. tostring(instanceType))
        self:Print(" difficultyID: " .. tostring(difficultyID))
        self:Print(" difficultyName: " .. tostring(difficultyName))
        self:Print(" maxPlayers: " .. tostring(maxPlayers))
    end

    if instanceType == nil or instanceType == "none" then
        if self.db.profile.enabledebug then
            self:Print("Not in instance, stopping logging")
        end

        self:StopLogging()
        return
    end

    if instanceType == "party" then
        if difficultyID == 1 and not self.db.profile.party.normal then
            if self.db.profile.enabledebug then
                self:Print("Normal dungeons disabled, stopping logging")
            end
            self:StopLogging()
        elseif difficultyID == 2 and not self.db.profile.party.heroic then
            if self.db.profile.enabledebug then
                self:Print("Heroic dungeons disabled, stopping logging")
            end

            self:StopLogging()
        end
    elseif instanceType == "raid" then
        if not (self.db.profile.raid.normal or self.db.profile.raid.heroic) then
            if self.db.profile.enabledebug then
                self:Print("Raid logging disabled, stopping logging")
            end

            self:StopLogging()
        end
    elseif instanceType == "pvp" then
        if not self.db.profile.pvp.bg then
            if self.db.profile.enabledebug then
                self:Print("Battlegrounds disabled, stopping logging")
            end

            self:StopLogging()
        end
    elseif instanceType == "arena" then
        if not self.db.profile.pvp.arena then
            if self.db.profile.enabledebug then
                self:Print("Arena disabled, stopping logging")
            end

            self:StopLogging()
        end
    end
end

function SimpleCombatLogger:SetEnable(value)
    if self.db.profile.enable == value then
        return
    end

    self.db.profile.enable = value

    if value then
        self:OnEnable()
    else
        self:OnDisable()
    end
end

function SimpleCombatLogger:StartLogging()
    if self.db.profile.enabledebug then
        self:Print("Start called")
    end

    if IsLoggingCombat then
        if self.db.profile.enabledebug then
            self:Print("Combat Logging is already enabled")
        end

        if DelayStopTimer ~= nil then
            if self.db.profile.enabledebug then
                self:Print("Cancelling Delayed Stop")
            end
            self:CancelTimer(DelayStopTimer)
            DelayStopTimer = nil
        else
            if self.db.profile.enabledebug then
                self:Print("No active delayed stop")
            end
        end

        return
    end

    self:Print("Starting Combat Logging")

    if LoggingCombat(true) then
        if self.db.profile.enabledebug then
            self:Print("Successfully started Combat Logging")
        end
    else
        self:Print("Failed to start Combat Logging")
    end
end

function SimpleCombatLogger:StopLogging()
    if self.db.profile.enabledebug then
        self:Print("Stop called")
    end

    if IsLoggingCombat then
        if self.db.profile.delaystop then
            if self.db.profile.enabledebug then
                self:Print("Delay enabled, stopping in 30 seconds")
            end

            if DelayStopTimer ~= nil then
                if self.db.profile.enabledebug then
                    self:Print("Another delayed stop is queued, overwriting it")
                end
                self:CancelTimer(DelayStopTimer)
            end

            DelayStopTimer = self:ScheduleTimer("StopLoggingNow", 30)
        else
            self:StopLoggingNow()
        end
    elseif self.db.profile.enabledebug then
        self:Print("Combat logging is already stopped")
    end
end

function SimpleCombatLogger:StopLoggingNow()
    DelayStopTimer = nil

    if IsLoggingCombat then
        self:Print("Stopping Combat Logging")

        if LoggingCombat(false) then
            if self.db.profile.enabledebug then
                self:Print("Successfully stopped Combat Logging")
            end
        elseif self.db.profile.enabledebug then
            self:Print("Failed to stop Combat Logging")
        end
    elseif self.db.profile.enabledebug then
        self:Print("Combat Logging is not running")
    end
end
