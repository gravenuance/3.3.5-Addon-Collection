local _, Private = ...

local pairs = pairs
local Select = select
local GetMapZones = GetMapZones

local C_Map = C_Map or {}

local function LoadZones(Obj, ...)
	for i=1, Select('#', ...) do
		Obj[i] = Select(i, ...)
	end
end

function C_Map.IsWorldMap(UIMap) 
	if ( not C_Map.WorldMap ) then
		C_Map.WorldMap = {}
		for ContinentIndex = 1, 4 do
			LoadZones(C_Map.WorldMap, GetMapZones(ContinentIndex))
		end
	end

	for _, Zone in pairs(C_Map.WorldMap) do
		if ( Zone == UIMap ) then
			return true
		end
	end
end

function C_Map.GetBestMapForUnit(UnitToken)
	-- 3.3.5 has no way to query an arbitrary unit's zone/map; only the
	-- player's own position is available client-side.
	if ( UnitToken ~= "player" ) then
		return nil
	end

	-- SetMapToCurrentZone moves the shared map, so restore it when the player is browsing the world map.
	local Browsing = _G.WorldMapFrame and _G.WorldMapFrame:IsShown()
	local ViewedMap, ViewedLevel
	if ( Browsing ) then
		ViewedMap, ViewedLevel = GetCurrentMapAreaID(), GetCurrentMapDungeonLevel()
	end

	SetMapToCurrentZone()
	local CurrentMap = GetCurrentMapAreaID()

	if ( Browsing ) then
		SetMapByID(ViewedMap)
		if ( ViewedLevel and ViewedLevel > 0 ) then
			SetDungeonMapLevel(ViewedLevel)
		end
	end

	return CurrentMap
end

-- Global
_G.C_Map = C_Map