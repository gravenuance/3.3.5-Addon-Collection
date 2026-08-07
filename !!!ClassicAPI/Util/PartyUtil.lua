local huge = math.huge
local min = math.min
local UnitExists = UnitExists

local PartyUtil = {};

local unitTags = { "player", "party1", "party2", "party3", "party4" };

function PartyUtil.GetMinLevel()
	local minLevel = huge;
	for index, unit in ipairs(unitTags) do
		if UnitExists(unit) then
			minLevel = min(minLevel, UnitLevel(unit));
		end
	end
	return minLevel;
end

-- NOTE: Chromie Time, sharding, and group-role-count tracking are all
-- post-3.3.5 systems (Chromie Time/sharding are Legion+; role-aware
-- GetGroupMemberCounts is Cata+ talent-spec era) with no equivalent on this
-- client. There is nothing meaningful to backport here, so these just
-- return nil/empty rather than erroring on the undefined Enum/API surface
-- the retail versions depend on.

function PartyUtil.GetPhasedReasonString(phaseReason, unitToken)
	return nil;
end

function GetGroupMemberCountsForDisplay()
	return {};
end

-- Global
_G.PartyUtil = PartyUtil