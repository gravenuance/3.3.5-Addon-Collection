--------------------------------------------------------------------------------
-- CombatLogFix (Wrath 3.3.5 style)
--------------------------------------------------------------------------------

local CombatLogFix = {}
CombatLogFix.__index = CombatLogFix

--------------------------------------------------------------------------------
-- Initialization
--------------------------------------------------------------------------------

function CombatLogFix:new(o)
	o = o or {}
	setmetatable(o, self)
	return o
end

function CombatLogFix:Init()
	-- Simple WoW-style addon: no Apollo here, just set up the fix frame
	self:SetupLifestealFix()
	self:SetupCombatLogKeepAlive()
end

--------------------------------------------------------------------------------
-- Lifesteal formatting fix (from original file, adapted to WoW API if needed)
--------------------------------------------------------------------------------

function CombatLogFix:SetupLifestealFix()
	-- NO-OP placeholder in WoW 3.3.5:
	-- You can hook COMBAT_LOG_EVENT_UNFILTERED and format specific events here
	-- if you actually have a buggy lifesteal string in your client.
	--
	-- This block kept as a stub so the file matches the original structure.
end

--------------------------------------------------------------------------------
-- Combat log keep-alive / soft reset
--------------------------------------------------------------------------------

do
	-- Tunables
	local CLEAR_INTERVAL   = 5 -- seconds between clears
	local MIN_EVENTS       = 50 -- only clear if buffer looks active enough
	local IN_INSTANCE_ONLY = true -- set false if you want it globally

	-- Simple rolling counter of CLEU events
	local eventCount       = 0

	local fixFrame         = CreateFrame("Frame", "CombatLogFixFrame", UIParent)
	fixFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
	fixFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
	fixFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")

	fixFrame:SetScript("OnEvent", function(self, event)
		if event == "COMBAT_LOG_EVENT_UNFILTERED" then
			eventCount = eventCount + 1
		else
			-- reset counter on major transitions
			eventCount = 0
		end
	end)

	local acc = 0
	fixFrame:SetScript("OnUpdate", function(self, elapsed)
		acc = acc + elapsed
		if acc < CLEAR_INTERVAL then
			return
		end
		acc = 0

		if IN_INSTANCE_ONLY then
			local inInstance = IsInInstance()
			if not inInstance then
				return
			end
		end

		-- Heuristic: if nothing at all is flowing, do nothing.
		-- If some events are flowing, periodically clear to unstuck.
		if eventCount >= MIN_EVENTS or eventCount == 0 then
			CombatLogClearEntries()
			-- after clearing, reset counter so we can see fresh flow
			eventCount = 0
		end
	end)
end

--------------------------------------------------------------------------------
-- Instance
--------------------------------------------------------------------------------

-- Create and initialize the singleton
local CombatLogFixInst = CombatLogFix:new()
CombatLogFixInst:Init()
