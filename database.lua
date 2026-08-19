-- multi api compat
local compat = pfQuestCompat

-- Performance: cache frequently-used globals
local pairs, ipairs, next = pairs, ipairs, next
local strfind, strlower, strlen = strfind, strlower, strlen
local format = string.format
local min, max, abs = math.min, math.max, math.abs
local floor, ceil = floor or math.floor, ceil or math.ceil
local band = bit.band
local getn, insert, concat = table.getn, table.insert, table.concat
local tostring, tonumber, type = tostring, tonumber, type
local unpack = unpack
local GetTime = GetTime
local UnitLevel, UnitRace, UnitClass = UnitLevel, UnitRace, UnitClass
local UnitFactionGroup, UnitName, UnitSex = UnitFactionGroup, UnitName, UnitSex

-- Ensure pfQuestConfig.path exists (fallback if config.lua failed to set it)
if not pfQuestConfig then
  pfQuestConfig = CreateFrame("Frame", "pfQuestConfig", UIParent)
  pfQuestConfig:Hide()
end
if not pfQuestConfig.path then
  pfQuestConfig.path = "Interface\\AddOns\\pfQuest"
end

pfDatabase = { icons = {} }

local loc = GetLocale()
local dbs =
  { "items", "quests", "quests-itemreq", "objects", "units", "zones", "areatrigger", "refloot" }
local noloc = { items = true, quests = true, objects = true, units = true }

pfDB.locales = {
  ["enUS"] = "English",
  ["koKR"] = "Korean",
  ["frFR"] = "French",
  ["deDE"] = "German",
  ["zhCN"] = "Chinese (Simplified)",
  ["zhTW"] = "Chinese (Traditional)",
  ["esES"] = "Spanish",
  ["ruRU"] = "Russian",
  ["ptBR"] = "Portuguese",
}

-- Return the best cluster point for a coordiante table
local best, neighbors = { index = 1, neighbors = 0 }, 0
local cache, cacheindex = {}, nil
local cache_count = 0
local CLUSTER_CACHE_MAX = 200
local ymin, ymax, xmin, xmax
local function getcluster(tbl, name)
  local count = 0
  best.index, best.neighbors = 1, 0
  cacheindex = format("%s:%s", name, getn(tbl))

  -- calculate new cluster if nothing is cached
  if not cache[cacheindex] then
    -- evict cache if too large
    if cache_count >= CLUSTER_CACHE_MAX then
      cache = {}
      cache_count = 0
    end
    for index, data in pairs(tbl) do
      -- precalculate the limits, and compare directly.
      -- This way is much faster than the math.abs function.
      xmin, xmax = data[1] - 5, data[1] + 5
      ymin, ymax = data[2] - 5, data[2] + 5
      neighbors = 0
      count = count + 1

      for _, compare in pairs(tbl) do
        if compare[1] > xmin and compare[1] < xmax and compare[2] > ymin and compare[2] < ymax then
          neighbors = neighbors + 1
        end
      end

      if neighbors > best.neighbors then
        best.neighbors = neighbors
        best.index = index
      end
    end

    cache[cacheindex] = { tbl[best.index][1] + 0.001, tbl[best.index][2] + 0.001, count }
    cache_count = cache_count + 1
  end

  return cache[cacheindex][1], cache[cacheindex][2], cache[cacheindex][3]
end

-- Detects if a non indexed table is empty
local function isempty(tbl)
  return next(tbl) == nil
end

-- detect installed locales
for key, name in pairs(pfDB.locales) do
  if not pfDB["quests"][key] then
    pfDB.locales[key] = nil
  end
end

-- detect localized databases
pfDatabase.dbstring = ""
for id, db in pairs(dbs) do
  -- assign existing locale
  pfDB[db]["loc"] = pfDB[db][loc] or pfDB[db]["enUS"] or {}
  pfDatabase.dbstring = pfDatabase.dbstring
    .. " |cffcccccc[|cffffffff"
    .. db
    .. "|cffcccccc:|cff33ffcc"
    .. (pfDB[db][loc] and loc or "enUS")
    .. "|cffcccccc]"
end

-- Free unused locale data to reduce memory.
--
-- The "loc" reference already points to the correct table, so every other
-- locale table can be dropped and garbage collected.
--
-- EXCEPT "quests". The quest log's [Translate] button reads
-- pfDB["quests"][lang][id] for whatever language the user picks, so freeing
-- those tables silently disables the feature -- the button stays clickable and
-- does nothing, which is exactly what it did before this exception existed.
-- If you free them again, remove the button too (see quest.lua).
--
-- Cost of the exception, measured across the eight non-active locales:
--   quests   19.8 MB  <- kept
--   items     5.6 MB     freed
--   units     2.9 MB     freed
--   objects   2.3 MB     freed
-- so 10.7 MB of the 30.5 MB is still reclaimed here, and the rest can be
-- reclaimed by turning the "Quest text translations" option off.
local function freelocales(only)
  for id, db in pairs(dbs) do
    if not only or db == only then
      for locale in pairs(pfDB.locales) do
        if pfDB[db][locale] and pfDB[db][locale] ~= pfDB[db]["loc"] then
          pfDB[db][locale] = nil
        end
      end
      -- Also free enUS if it's not the active locale (enUS may not be in pfDB.locales)
      if pfDB[db]["enUS"] and pfDB[db]["enUS"] ~= pfDB[db]["loc"] then
        pfDB[db]["enUS"] = nil
      end
    end
  end
end

-- Everything but "quests" is unreachable once "loc" is assigned, so drop it now.
for id, db in pairs(dbs) do
  if db ~= "quests" then
    freelocales(db)
  end
end

-- The quest locales are only reachable through the [Translate] button, so the
-- decision needs pfQuest_config -- which is not populated at file scope.
-- pfQuestConfig:LoadConfig() runs on ADDON_LOADED; VARIABLES_LOADED fires after
-- every addon's ADDON_LOADED, so the option is guaranteed readable by then.
pfDatabase.translations = true
local freequestlocales = CreateFrame("Frame")
freequestlocales:RegisterEvent("VARIABLES_LOADED")
freequestlocales:SetScript("OnEvent", function()
  if pfQuest_config and pfQuest_config["translations"] == "0" then
    pfDatabase.translations = false
    freelocales("quests")
  end
  this:UnregisterEvent("VARIABLES_LOADED")
end)

-- track all previous meta selections on login
pfDatabase.tracking = CreateFrame("Frame", "pfDatabaseMetaTracking", UIParent)
pfDatabase.tracking:RegisterEvent("PLAYER_ENTERING_WORLD")
pfDatabase.tracking:SetScript("OnEvent", function()
  -- break on empty config
  if not pfQuest_track then
    return
  end

  -- build static reject set now that all addon Lua is loaded and
  -- UnitRace/UnitClass/GetBitByRace are all available
  pfDatabase:BuildStaticRejectSet()

  -- enable all tracked
  for name, data in pairs(pfQuest_track) do
    pfDatabase:SearchMetaRelation(data[1], data[2])
  end

  -- remove events
  this:UnregisterAllEvents()
end)

-- track questitems to maintain object requirements
pfDatabase.itemlist = CreateFrame("Frame", "pfDatabaseQuestItemTracker", UIParent)
pfDatabase.itemlist.update = 0
pfDatabase.itemlist.db = {}
pfDatabase.itemlist.db_tmp = {}
pfDatabase.itemlist.registry = {}
pfDatabase.TrackQuestItemDependency = function(self, item, qid)
  self.itemlist.registry[item] = qid
  -- only set the deadline if a scan isn't already pending
  if not self.itemlist.pending then
    self.itemlist.update = GetTime() + 0.5
    self.itemlist.pending = true
    self.itemlist:Show()
  end
end

pfDatabase.itemlist:RegisterEvent("BAG_UPDATE_DELAYED")
pfDatabase.itemlist:SetScript("OnEvent", function()
  -- only set the deadline on the first event in a burst
  if not this.pending then
    this.update = GetTime() + 0.5
    this.pending = true
    this:Show()
  end
end)

pfDatabase.itemlist:SetScript("OnUpdate", function()
  if GetTime() < this.update then
    return
  end

  -- clear pending flag so the next BAG_UPDATE burst can schedule a new scan
  this.pending = false

  -- remove obsolete registry entries
  for item, qid in pairs(this.registry) do
    if not pfQuest.questlog[qid] then
      this.registry[item] = nil
    end
  end

  -- swap db and db_tmp: db_tmp becomes the new db, old db becomes previous
  local previous = this.db
  this.db = this.db_tmp
  this.db_tmp = previous

  -- clear the new db in-place (avoids table allocation)
  for k in pairs(this.db) do
    this.db[k] = nil
  end

  -- fill new item db with bag items
  for bag = 4, 0, -1 do
    for slot = 1, GetContainerNumSlots(bag) do
      local itemName = C_Item.GetItemName(ItemLocation:CreateFromBagAndSlot(bag, slot))
      if itemName then
        this.db[itemName] = true
      end
    end
  end

  -- fill new item db with equipped items
  for i=INVSLOT_FIRST_EQUIPPED,INVSLOT_LAST_EQUIPPED do
    local itemName = C_Item.GetItemName(ItemLocation:CreateFromEquipmentSlot(i))
    if itemName then
      this.db[itemName] = true
    end
  end

  -- find new items
  for item in pairs(this.db) do
    if not previous[item] and this.registry[item] then
      pfQuest.questlog[this.registry[item]] = nil
      pfQuest:UpdateQuestlog()
    end
  end

  -- find removed items
  for item in pairs(previous) do
    if not this.db[item] and this.registry[item] then
      pfQuest.questlog[this.registry[item]] = nil
      pfQuest:UpdateQuestlog()
    end
  end

  this:Hide()
end)

-- sanity check the databases
if isempty(pfDB["quests"]["loc"]) then
  CreateFrame("Frame"):SetScript("OnUpdate", function()
    if GetTime() < 3 then
      return
    end
    DEFAULT_CHAT_FRAME:AddMessage(
      "|cffff5555 !! |cffffaaaaWrong version of |cff33ffccpf|cffffffffQuest|cffffaaaa detected.|cffff5555 !!"
    )
    DEFAULT_CHAT_FRAME:AddMessage("|cffffccccThe language pack does not match the gameclient's language.")
    DEFAULT_CHAT_FRAME:AddMessage(
      "|cffffccccYou'd either need to pick the complete or the " .. GetLocale() .. "-version."
    )
    DEFAULT_CHAT_FRAME:AddMessage("|cffffccccFor more details, see: https://shagu.org/pfQuest")
    this:Hide()
  end)
end

-- add database shortcuts
local items, units, objects, quests, refloot, itemreq
-- zone name/id maps sourced once from the client's AreaTable.dbc (ClassicAPI);
-- zonenames = { [id] = name }, zoneids = { [name] = id } (reverse, for O(1)
-- GetMapIDByName). Cached so C_Map.GetAreas() runs only once.
local zonenames, zoneids
pfDatabase.Reload = function()
  items = pfDB["items"]["data"]
  units = pfDB["units"]["data"]
  objects = pfDB["objects"]["data"]
  quests = pfDB["quests"]["data"]
  refloot = pfDB["refloot"]["data"]
  itemreq = pfDB["quests-itemreq"]["data"]

  -- Zone names come live from the client's AreaTable.dbc via ClassicAPI
  -- (C_Map.GetAreas), replacing the shipped db/<locale>/zones.lua tables.
  -- Built once (cached in the zonenames/zoneids upvalues) with a reverse
  -- name->id map for O(1) GetMapIDByName. Re-pointed here each Reload so it
  -- survives pfQuest-turtle reassigning pfDB.zones.loc (TURTLE_DE_PATCH) before
  -- it calls Reload(). loc/revloc always point at the same cached tables, so
  -- handles captured elsewhere (e.g. browser) stay valid.
  if C_Map and C_Map.GetAreas and not zonenames then
    zonenames = C_Map.GetAreas()
    zoneids = {}
    for id, name in pairs(zonenames) do
      if not zoneids[name] then zoneids[name] = id end
    end
  end
  if zonenames then
    pfDB["zones"]["loc"] = zonenames
    pfDB["zones"]["revloc"] = zoneids
  end
end

pfDatabase.Reload()

-- Inverted name index: maps name → {id, id, ...} for O(1) exact-match lookups.
-- Built once after locale is known. Used by GetIDByName to skip full-table scans
-- for exact matches (the hot path in SearchQuestID). Partial-match calls (browser,
-- slash commands) still use the full scan since they can't use this index.
pfDatabase.nameIndex = {}
pfDatabase.lastQuestGiversSet = {}

-- Pre-computed set of quest IDs that will never pass QuestFilter for this
-- character, regardless of level, questlog, or config changes.
-- Populated by BuildStaticRejectSet, called from PLAYER_ENTERING_WORLD
-- and from the locale-detection OnUpdate (covers locale swaps).
-- Covers: wrong race, wrong class, missing loc name.
pfDatabase.staticRejectSet = {}

function pfDatabase:BuildNameIndex()
  local idx = self.nameIndex
  -- clear existing index in-place
  for db in pairs(idx) do
    for name in pairs(idx[db]) do
      idx[db][name] = nil
    end
    idx[db] = nil
  end

  for _, db in pairs({ "units", "objects", "items" }) do
    idx[db] = {}
    for id, loc in pairs(pfDB[db]["loc"]) do
      if loc then
        if not idx[db][loc] then
          idx[db][loc] = {}
        end
        insert(idx[db][loc], id)
      end
    end
  end

  -- locale tables may have changed; force SearchQuests to re-add all nodes
  for id in pairs(self.lastQuestGiversSet) do
    self.lastQuestGiversSet[id] = nil
  end
end

-- BuildStaticRejectSet
-- Pre-computes the set of quest IDs that can never pass QuestFilter for this
-- character, independent of level, questlog, history, config, or skills.
-- Called from PLAYER_ENTERING_WORLD (guaranteed after all Lua is loaded)
-- and from the locale-detection OnUpdate (covers locale swaps).
-- Checks: wrong race bitmask, wrong class bitmask, missing loc name.
function pfDatabase:BuildStaticRejectSet()
  local reject = self.staticRejectSet
  for id in pairs(reject) do
    reject[id] = nil
  end

  -- UnitRace/UnitClass may return nil before PLAYER_ENTERING_WORLD.
  -- In that case skip race/class checks; BuildNameIndex is called again
  -- from the locale-detection OnUpdate after login, which will populate them.
  local _, race = UnitRace("player")
  local _, class = UnitClass("player")
  local prace = race and pfDatabase:GetBitByRace(race) or nil
  local pclass = class and pfDatabase:GetBitByClass(class) or nil

  for id in pairs(quests) do
    -- missing loc name
    if not pfDB.quests.loc[id] or not pfDB.quests.loc[id].T then
      reject[id] = true

    -- wrong race (only when prace is known)
    elseif prace and quests[id]["race"] and not (bit.band(quests[id]["race"], prace) == prace) then
      reject[id] = true

    -- wrong class (only when pclass is known)
    elseif pclass and quests[id]["class"] and not (bit.band(quests[id]["class"], pclass) == pclass) then
      reject[id] = true
    end
  end
end

pfDatabase:BuildNameIndex()

-- Reusable parse_obj table (cleared and reused each SearchQuestID call)
local parse_obj = { ["U"] = {}, ["O"] = {}, ["I"] = {} }
local function clear_parse_obj()
  for k in pairs(parse_obj["U"]) do
    parse_obj["U"][k] = nil
  end
  for k in pairs(parse_obj["O"]) do
    parse_obj["O"][k] = nil
  end
  for k in pairs(parse_obj["I"]) do
    parse_obj["I"][k] = nil
  end
end

-- Pre-defined vertex color tables (avoid creating new tables each quest)
local VERTEX_BLACK = { 0, 0, 0 }
local VERTEX_RED = { 1, 0.6, 0.6 }
local VERTEX_WHITE = { 1, 1, 1 }
local VERTEX_BLUE = { 0.2, 0.8, 1 }

-- factionMap for GetRaceMaskByID (avoid recreation per call)
local factionMap = { ["A"] = 77, ["H"] = 178, ["AH"] = 255, ["HA"] = 255 }

-- Race/class bitmasks: bit = 2^(dbcID-1) -> token
local bitraces = {}
local bitclasses = {}

for id = 1, 32 do
  local bit = 2 ^ (id - 1)
  local r = C_CreatureInfo.GetRaceInfo(id)
  if r and r.clientFileString and r.clientFileString ~= "" then
    bitraces[bit] = r.clientFileString
  end
  local c = C_CreatureInfo.GetClassInfo(id)
  if c and c.classFile and c.classFile ~= "" then
    bitclasses[bit] = c.classFile
  end
end

-- make them public for extensions
pfDB.bitraces = bitraces
pfDB.bitclasses = bitclasses

function pfDatabase:IsFriendly(id)
  if id and units[id] and units[id].fac then
    local faction = string.lower(UnitFactionGroup("player") or "")
    faction = faction == "horde" and "H" or faction == "alliance" and "A" or "UNKNOWN"

    if string.find(units[id].fac, faction) then
      return true
    end
  end

  return false
end

function pfDatabase:BuildQuestDescription(meta)
  if not meta.title or not meta.quest or not meta.QTYPE then
    return meta.description
  end

  if meta.QTYPE == "NPC_START" then
    return string.format(
      pfQuest_Loc["Speak with |cff33ffcc%s|r to obtain |cffffcc00[!]|cff33ffcc %s|r"],
      (meta.spawn or UNKNOWN),
      (meta.quest or UNKNOWN)
    )
  elseif meta.QTYPE == "OBJECT_START" then
    return string.format(
      pfQuest_Loc["Interact with |cff33ffcc%s|r to obtain |cffffcc00[!]|cff33ffcc %s|r"],
      (meta.spawn or UNKNOWN),
      (meta.quest or UNKNOWN)
    )
  elseif meta.QTYPE == "NPC_END" then
    return string.format(
      pfQuest_Loc["Speak with |cff33ffcc%s|r to complete |cffffcc00[?]|cff33ffcc %s|r"],
      (meta.spawn or UNKNOWN),
      (meta.quest or UNKNOWN)
    )
  elseif meta.QTYPE == "OBJECT_END" then
    return string.format(
      pfQuest_Loc["Interact with |cff33ffcc%s|r to complete |cffffcc00[?]|cff33ffcc %s|r"],
      (meta.spawn or UNKNOWN),
      (meta.quest or UNKNOWN)
    )
  elseif meta.QTYPE == "UNIT_OBJECTIVE" then
    if pfDatabase:IsFriendly(meta.spawnid) then
      return string.format(pfQuest_Loc["Talk to |cff33ffcc%s|r"], (meta.spawn or UNKNOWN))
    else
      return string.format(pfQuest_Loc["Kill |cff33ffcc%s|r"], (meta.spawn or UNKNOWN))
    end
  elseif meta.QTYPE == "UNIT_OBJECTIVE_ITEMREQ" then
    return string.format(
      pfQuest_Loc["Use |cff33ffcc%s|r on |cff33ffcc%s|r"],
      (meta.itemreq or UNKNOWN),
      (meta.spawn or UNKNOWN)
    )
  elseif meta.QTYPE == "OBJECT_OBJECTIVE" then
    return string.format(pfQuest_Loc["Interact with |cff33ffcc%s|r"], (meta.spawn or UNKNOWN))
  elseif meta.QTYPE == "OBJECT_OBJECTIVE_ITEMREQ" then
    return string.format(
      pfQuest_Loc["Use |cff33ffcc%s|r at |cff33ffcc%s|r"],
      (meta.itemreq or UNKNOWN),
      (meta.spawn or UNKNOWN)
    )
  elseif meta.QTYPE == "ITEM_OBJECTIVE_LOOT" then
    return string.format(
      pfQuest_Loc["Loot |cff33ffcc[%s]|r from |cff33ffcc%s|r"],
      (meta.item or UNKNOWN),
      (meta.spawn or UNKNOWN)
    )
  elseif meta.QTYPE == "ITEM_OBJECTIVE_USE" then
    return string.format(
      pfQuest_Loc["Loot and/or Use |cff33ffcc[%s]|r from |cff33ffcc%s|r"],
      (meta.item or UNKNOWN),
      (meta.spawn or UNKNOWN)
    )
  elseif meta.QTYPE == "AREATRIGGER_OBJECTIVE" then
    return string.format(pfQuest_Loc["Explore |cff33ffcc%s|r"], (meta.spawn or UNKNOWN))
  elseif meta.QTYPE == "ZONE_OBJECTIVE" then
    return string.format(pfQuest_Loc["Use Quest Item at |cff33ffcc%s|r"], (meta.spawn or UNKNOWN))
  end
end

-- ShowExtendedTooltip
-- Draws quest informations into a tooltip
function pfDatabase:ShowExtendedTooltip(id, tooltip, parent, anchor, offx, offy)
  local tooltip = tooltip or GameTooltip
  local parent = parent or this
  local anchor = anchor or "ANCHOR_LEFT"

  tooltip:SetOwner(parent, anchor, offx, offy)

  local data = pfDB["quests"]["data"][id]
  local title = pfDatabase:GetQuestText(id, "T")
  local objectives = pfDatabase:GetQuestText(id, "O")
  local description = pfDatabase:GetQuestText(id, "D")

  if title then
    tooltip:SetText(title, .3, 1, .8)
    tooltip:AddLine(" ")
  else
    tooltip:SetText(UNKNOWN, 0.3, 1, 0.8)
  end

  if data then
    -- scan for active quests
    local queststate = pfQuest_history[id] and 2 or 0
    queststate = pfQuest.questlog[id] and 1 or queststate

    if queststate == 0 then
      tooltip:AddLine(pfQuest_Loc["You don't have this quest."] .. "\n\n", 1, 0.5, 0.5)
    elseif queststate == 1 then
      tooltip:AddLine(pfQuest_Loc["You are on this quest."] .. "\n\n", 1, 1, 0.5)
    elseif queststate == 2 then
      tooltip:AddLine(pfQuest_Loc["You already did this quest."] .. "\n\n", 0.5, 1, 0.5)
    end

    -- quest start
    if data["start"] then
      for key, db in pairs({ ["U"] = "units", ["O"] = "objects", ["I"] = "items" }) do
        if data["start"][key] then
          local entries = ""
          for _, id in pairs(data["start"][key]) do
            entries = entries .. (entries == "" and "" or ", ") .. (pfDB[db]["loc"][id] or UNKNOWN)
          end

          tooltip:AddDoubleLine(pfQuest_Loc["Quest Start"] .. ":", entries, 1, 1, 1, 1, 1, 0.8)
        end
      end
    end

    -- quest end
    if data["end"] then
      for key, db in pairs({ ["U"] = "units", ["O"] = "objects" }) do
        if data["end"][key] then
          local entries = ""
          for _, id in ipairs(data["end"][key]) do
            entries = entries .. (entries == "" and "" or ", ") .. (pfDB[db]["loc"][id] or UNKNOWN)
          end

          tooltip:AddDoubleLine(pfQuest_Loc["Quest End"] .. ":", entries, 1, 1, 1, 1, 1, 0.8)
        end
      end
    end
  end

  -- objectives
  if objectives and objectives ~= "" then
    tooltip:AddLine(" ")
    tooltip:AddLine(pfDatabase:FormatQuestText(objectives),1,1,1,true)
  end

  -- details
  if description and description ~= "" then
    tooltip:AddLine(" ")
    tooltip:AddLine(pfDatabase:FormatQuestText(description),.6,.6,.6,true)
  end

  -- add levels
  if data then
    if data["lvl"] or data["min"] then
      tooltip:AddLine(" ")
    end
    if data["lvl"] then
      local questlevel = tonumber(data["lvl"])
      local color = pfQuestCompat.GetDifficultyColor(questlevel)
      tooltip:AddLine("|cffffffff" .. pfQuest_Loc["Quest Level"] .. ": |r" .. questlevel, color.r, color.g, color.b)
    end
    if data["min"] then
      local questlevel = tonumber(data["min"])
      local color = pfQuestCompat.GetDifficultyColor(questlevel)
      tooltip:AddLine("|cffffffff" .. pfQuest_Loc["Required Level"] .. ": |r" .. questlevel, color.r, color.g, color.b)
    end
  end

  tooltip:Show()
end

-- GetPlayerSkill
-- Returns the player's current rank in the given SkillLine.dbc id, or false if
-- they haven't learned it. Read live from the client via ClassicAPI's
-- C_SpellBook.GetSkillLineRank(skillLineID) -> curRank, maxRank, modifier (nil
-- when unlearned), which replaces the old professions name table + skill-window
-- name scan.
function pfDatabase:GetPlayerSkill(skill)
  if not (C_SpellBook and C_SpellBook.GetSkillLineRank) then
    return false
  end
  return (C_SpellBook.GetSkillLineRank(skill)) or false
end

-- GetBitByRace
-- Returns bit of the current race
function pfDatabase:GetBitByRace(model)
  -- scan for regular bitmasks
  for bit, v in pairs(bitraces) do
    if model == v then
      return bit
    end
  end

  -- return alliance/horde racemask as fallback for unknown races
  return UnitFactionGroup("player") == "Alliance" and 77 or 178
end

-- GetBitByClass
-- Returns bit of the current class
function pfDatabase:GetBitByClass(class)
  for bit, v in pairs(bitclasses) do
    if class == v then
      return bit
    end
  end
end

-- GetHexDifficultyColor
-- Returns a string with the difficulty color of the given level
function pfDatabase:GetHexDifficultyColor(level, force)
  if force and UnitLevel("player") < level then
    return "|cffff5555"
  else
    local c = pfQuestCompat.GetDifficultyColor(level)
    return string.format("|cff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
  end
end

-- GetRaceMaskByID
function pfDatabase:GetRaceMaskByID(id, db)
  -- Uses module-level factionMap: A=77, H=178, AH/HA=255
  local raceMask = 0

  if db == "quests" then
    raceMask = quests[id]["race"] or raceMask

    if quests[id]["start"] then
      local questStartRaceMask = 0

      -- get quest starter faction
      if quests[id]["start"]["U"] then
        for _, startUnitId in ipairs(quests[id]["start"]["U"]) do
          if units[startUnitId] and units[startUnitId]["fac"] and factionMap[units[startUnitId]["fac"]] then
            questStartRaceMask = bit.bor(factionMap[units[startUnitId]["fac"]])
          end
        end
      end

      -- get quest object starter faction
      if quests[id]["start"]["O"] then
        for _, startObjectId in ipairs(quests[id]["start"]["O"]) do
          if objects[startObjectId] and objects[startObjectId]["fac"] and factionMap[objects[startObjectId]["fac"]] then
            questStartRaceMask = bit.bor(factionMap[objects[startObjectId]["fac"]])
          end
        end
      end

      -- apply starter faction as racemask
      if raceMask == 0 and questStartRaceMask > 0 and questStartRaceMask ~= raceMask then
        raceMask = questStartRaceMask
      end
    end
  elseif pfDB[db] and pfDB[db]["data"] and pfDB[db]["data"]["fac"] then
    raceMask = factionMap[pfDB[db]["data"]["fac"]]
  end

  return raceMask
end

-- GetIDByName
-- Scans localization tables for matching IDs
-- Returns table with all IDs
function pfDatabase:GetIDByName(name, db, partial, server)
  if not pfDB[db] then
    return nil
  end
  local ret = {}

  -- Fast path: O(1) index lookup for exact case-sensitive matches with no
  -- server filter. This is the hot path called from SearchQuestID for monster
  -- and item objective lookups. Quests are excluded because their loc is a
  -- table ({T=, O=, D=}) and are not indexed.
  if not partial and not server and db ~= "quests" then
    local ids = pfDatabase.nameIndex[db] and pfDatabase.nameIndex[db][name]
    if ids then
      for _, id in pairs(ids) do
        ret[id] = pfDB[db]["loc"][id]
      end
    end
    return ret
  end

  -- Slow path: full scan for partial matches (browser/slash commands) and quests
  for id, loc in pairs(pfDB[db]["loc"]) do
    if db == "quests" then
      loc = loc["T"]
    end

    local custom = server and pfQuest_server[db] and pfQuest_server[db][id] or not server
    if loc and name then
      if partial == true and strfind(strlower(loc), strlower(name), 1, true) and custom then
        ret[id] = loc
      elseif partial == "LOWER" and strlower(loc) == strlower(name) and custom then
        ret[id] = loc
      elseif loc == name and custom then
        ret[id] = loc
      end
    end
  end
  return ret
end

-- GetQuestText
-- Returns localized quest text. Prefers the engine's quest-data cache (the
-- source of truth once the player has loaded the quest) and falls back to
-- the shipped locale table for cache-cold quests (browser search, map
-- pickup pins for quests never accepted, historical journal entries, etc.).
-- field is "T" (title), "O" (objectives), or "D" (description).
function pfDatabase:GetQuestText(id, field)
  local d = C_QuestLog.GetQuestDetails(id)
  if d then
    if field == "T" then return d.title end
    if field == "O" then return d.objectives end
    if field == "D" then return d.description end
  end
  return pfDB.quests.loc[id] and pfDB.quests.loc[id][field]
end

-- GetIDByIDPart
-- Scans localization tables for matching IDs
-- Returns table with all IDs
function pfDatabase:GetIDByIDPart(idPart, db)
  if not pfDB[db] then
    return nil
  end
  local ret = {}

  for id, loc in pairs(pfDB[db]["loc"]) do
    if db == "quests" then
      loc = loc["T"]
    end

    if idPart and loc and strfind(tostring(id), idPart) then
      ret[id] = loc
    end
  end
  return ret
end

-- GetBestMap
-- Scans a map table for all spawns
-- Returns the map with most spawns
function pfDatabase:GetBestMap(maps)
  local bestmap, bestscore = nil, 0

  -- calculate best map results
  for map, count in pairs(maps or {}) do
    if count > bestscore or (count == 0 and bestscore == 0) then
      bestscore = count
      bestmap = map
    end
  end

  return bestmap or nil, bestscore or nil
end

-- SearchAreaTriggerID
-- Reads the trigger's geometry live from the client's AreaTrigger.dbc via
-- ClassicAPI (C_Map.GetAreaTriggerInfo) instead of a shipped coordinate table.
-- Adds a map node for the resolved zone and returns its map table.
function pfDatabase:SearchAreaTriggerID(id, meta, maps, prio)
  if not (C_Map and C_Map.GetAreaTriggerInfo) then
    return maps
  end

  local trigger = C_Map.GetAreaTriggerInfo(id)
  -- areaID/mapX/mapY are absent when the point can't be resolved to a zone rect
  if not trigger or not trigger.areaID or not trigger.mapX or not trigger.mapY then
    return maps
  end

  local maps = maps or {}
  local prio = prio or 1
  local zone = trigger.areaID

  -- add all gathered data
  meta = meta or {}
  meta["spawn"] = pfQuest_Loc["Exploration Mark"]
  meta["spawnid"] = id
  meta["item"] = nil

  meta["title"] = meta["quest"] or meta["item"] or meta["spawn"]
  meta["zone"] = zone
  meta["x"] = trigger.mapX
  meta["y"] = trigger.mapY

  meta["level"] = pfQuest_Loc["N/A"]
  meta["spawntype"] = pfQuest_Loc["Trigger"]
  meta["respawn"] = pfQuest_Loc["N/A"]

  maps[zone] = maps[zone] and maps[zone] + prio or prio
  pfMap:AddNode(meta)

  return maps
end

-- SearchMobID
-- Scans for all mobs with a specified ID
-- Adds map nodes for each and returns its map table
function pfDatabase:SearchMobID(id, meta, maps, prio)
  if not units[id] or not units[id]["coords"] then
    return maps
  end

  local maps = maps or {}
  local prio = prio or 1
  meta = meta or {}

  -- hoist invariant fields outside the coord loop; these are the same for
  -- every spawn point of this mob so there is no need to set them per-coord
  meta["spawn"] = pfDB.units.loc[id]
  meta["spawnid"] = id
  meta["title"] = meta["quest"] or meta["item"] or meta["spawn"]
  meta["level"] = units[id]["lvl"] or UNKNOWN
  meta["spawntype"] = pfQuest_Loc["Unit"]
  -- description only depends on the above invariant fields + QTYPE/quest/item
  -- compute once here; AddNode will skip its own BuildQuestDescription call
  meta["description"] = pfDatabase:BuildQuestDescription(meta)

  for _, data in pairs(units[id]["coords"]) do
    local x, y, zone, respawn = unpack(data)

    if zone > 0 then
      meta["zone"] = zone
      meta["x"] = x
      meta["y"] = y
      meta["respawn"] = respawn > 0 and SecondsToTime(respawn)

      maps[zone] = maps[zone] and maps[zone] + prio or prio
      pfMap:AddNode(meta)
    end
  end

  return maps
end

-- Search MetaRelation
-- Scans for all entries within the specified meta name
-- Adds map nodes for each and returns its map table
-- query = { relation-name, relation-min, relation-max }
local alias = {
  ["flightmaster"] = "flight",
  ["taxi"] = "flight",
  ["flights"] = "flight",
  ["raremobs"] = "rares",
}

local skill = {
  ["herbs"] = true,
  ["mines"] = true,
  ["rares"] = true,
  ["chests"] = true,
}

-- flight-node faction values mirror Enum.FlightPathFaction (Neutral/Horde/Alliance)
local FLIGHT_NEUTRAL, FLIGHT_HORDE, FLIGHT_ALLIANCE = 0, 1, 2

-- The "Nighthaven, Moonglade" flight points are druid-only; hide them from
-- everyone else. TaxiNodes.dbc ids 62 (Alliance) / 63 (Horde). The separate
-- "Moonglade" nodes (49/69) are public, so they're not listed. Keyed by nodeID
-- so it's independent of zone resolution.
local druid_only_nodes = { [62] = true, [63] = true }
local isdruid = PlayerUtil.GetClassFile() == "DRUID"

-- The Eastern Plaguelands contested towers (Plaguewood 84, Northpass 85,
-- Eastwall 86, Crown Guard 87) are only usable while your faction holds the
-- tower and just clutter the map; hide them so only Light's Hope Chapel
-- (67/68) remains in the zone. TaxiNodes.dbc ids.
local hidden_nodes = { [84] = true, [85] = true, [86] = true, [87] = true }

-- SearchFlightNodes
-- Draws flight masters read live from the client's TaxiNodes.dbc via ClassicAPI
-- (C_TaxiMap.GetTaxiNodesForMap() with no arg = every node on all continents),
-- replacing the shipped pfDB.meta.flight table. Each node resolves to a zone
-- (areaID) + map%, so it pins in the correct zone; neutral nodes show for both
-- factions. Returns its map table.
function pfDatabase:SearchFlightNodes(query, meta)
  local maps = {}
  if not (C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap) then
    return maps
  end

  meta = meta or {}
  local want = (query and query.faction and string.lower(query.faction))
    or (UnitFactionGroup("player") and string.lower(UnitFactionGroup("player")))

  meta.tracking = true
  meta.fade_range = meta.icon and 10 or nil

  for _, node in ipairs(C_TaxiMap.GetTaxiNodesForMap()) do
    local f = node.faction
    local show = f == FLIGHT_NEUTRAL
      or not want
      or (want == "horde" and f == FLIGHT_HORDE)
      or (want == "alliance" and f == FLIGHT_ALLIANCE)

    -- Nighthaven/Moonglade flight paths are druid-only
    if druid_only_nodes[node.nodeID] and not isdruid then
      show = false
    end

    -- hidden clutter (Eastern Plaguelands contested towers)
    if hidden_nodes[node.nodeID] then
      show = false
    end

    if show and node.areaID and node.mapX and node.mapY then
      meta.spawn = node.name
      meta.spawnid = node.nodeID
      meta.item = nil
      meta.title = meta.quest or meta.item or meta.spawn
      meta.zone = node.areaID
      meta.x = node.mapX
      meta.y = node.mapY
      meta.level = "N/A"
      meta.spawntype = pfQuest_Loc["Flight Master"]
      meta.respawn = "N/A"

      maps[node.areaID] = (maps[node.areaID] or 0) + 1
      pfMap:AddNode(meta)
    end
  end

  meta.tracking = false
  return maps
end

function pfDatabase:SearchMetaRelation(query, meta, show)
  local maps = {}

  -- abort on invalid queries
  if not query or not query.name then
    return
  end

  -- convert track name aliases
  local track = alias[query.name] or query.name

  -- Flight always comes live from the client (ClassicAPI). pfDB.meta.flight is
  -- kept only as an empty stub so companion addons (pfQuest-turtle) don't error;
  -- pfQuest ignores it here. SearchFlightNodes returns empty without C_TaxiMap.
  if track == "flight" then
    return pfDatabase:SearchFlightNodes(query, meta)
  end

  if pfDB["meta"] and pfDB["meta"][track] then
    -- check which faction should be searched
    local faction = query.faction and string.lower(query.faction)
      or (UnitFactionGroup("player") and string.lower(UnitFactionGroup("player")))
    faction = faction == "horde" and "H" or faction == "alliance" and "A" or ""

    -- iterate over all tracking entries
    for entry, value in pairs(pfDB["meta"][track]) do
      if skill[track] and tonumber(query.min) and tonumber(value) < tonumber(query.min) then
        -- required skill is lower than the queried one
      elseif skill[track] and tonumber(query.max) and tonumber(value) > tonumber(query.max) then
        -- required skill is lower than the queried one
      elseif not skill[track] and not string.find(value, faction) then
        -- faction is different from the queried one
      else
        local prev_icon = meta.icon
        local object = pfDB["objects"]["loc"][math.abs(entry)]
        local unit = pfDB["units"]["loc"][entry]

        -- set node as tracking result
        meta.tracking = true

        -- handle custom tracking icons
        if pfQuest_config.trackingicons == "0" then
          meta.icon = nil
        elseif entry < 0 and object and pfDatabase.icons[object] then
          meta.icon = pfDatabase.icons[object]
        elseif entry > 0 and unit and pfDatabase.icons[unit] then
          meta.icon = pfDatabase.icons[unit]
        end

        -- set custom fade range for skill-trackables
        if meta.icon and skill[track] then
          meta.fade_range = 85
        elseif meta.icon then
          meta.fade_range = 10
        else
          meta.fade_range = nil
        end

        if entry < 0 then
          pfDatabase:SearchObjectID(math.abs(entry), meta, maps)
        else
          pfDatabase:SearchMobID(entry, meta, maps)
        end

        -- reset meta table
        meta.icon = prev_icon
        meta.tracking = false
      end
    end
  end

  return maps
end

-- Search TrackMeta
-- Scans for all entries within the specified list
-- Adds map nodes for each, saves it to the persistent
-- tracking variable per character and returns a map table
function pfDatabase:TrackMeta(list, state)
  local list = alias[list] and alias[list] or list
  local identifier = "TRACK_" .. string.upper(list)

  local meta = {
    ["addon"] = identifier,
    ["icon"] = pfQuestConfig.path .. "\\img\\tracking\\" .. list,
  }

  local query = {
    name = list,
  }

  local maps = nil

  -- hide previous tracks
  pfQuest_track[list] = nil
  pfMap:DeleteNode(identifier)
  pfMap:UpdateNodes()

  -- break here if nothing should be tracked
  if not state then
    return
  end

  -- add extended state values to query
  -- this is used for min/max values
  if type(state) == "table" then
    for k, v in pairs(state) do
      query[k] = v
    end
  end

  -- save and perform the actual meta tracking
  pfQuest_track[list] = { query, meta }
  local maps = pfDatabase:SearchMetaRelation(query, meta)

  -- remove invalid results
  if not maps then
    pfQuest_track[list] = nil
  end

  -- return map results
  return maps
end

-- SearchMob
-- Scans for all mobs with a specified name
-- Adds map nodes for each and returns its map table
function pfDatabase:SearchMob(mob, meta, partial)
  local maps = {}

  for id in pairs(pfDatabase:GetIDByName(mob, "units", partial)) do
    if units[id] and units[id]["coords"] then
      maps = pfDatabase:SearchMobID(id, meta, maps)
    end
  end

  return maps
end

-- Subzone placement is read live from the client's WorldMapOverlay.dbc via
-- ClassicAPI (C_Map.GetMapOverlays), replacing the shipped pfDB["zones"]["data"]
-- table. Each overlay reveals a subzone (areaID) and carries its hit rectangle
-- in world-map canvas pixels (1002x668); the parent zone is the one we queried.
-- Built once, lazily, and cached as: subzone id -> { parentZone, w%, h%, cx%, cy% }
-- (the same shape SearchZoneID consumed before). Any explicit entries in
-- pfDB["zones"]["data"] (e.g. patched in by pfQuest-turtle) are folded in and
-- take precedence over the live read.
local zone_index
local function GetZoneIndex()
  if zone_index then return zone_index end
  zone_index = {}

  if C_Map and C_Map.GetMapOverlays then
    for parent in pairs(pfDB["zones"]["loc"]) do
      local overlays = C_Map.GetMapOverlays(parent)
      if overlays then
        for _, ov in ipairs(overlays) do
          local sub = ov.areaID
          if sub and sub > 0 then
            local cx = (ov.hitRectLeft + ov.hitRectRight) / 2 / 1002 * 100
            local cy = (ov.hitRectTop + ov.hitRectBottom) / 2 / 668 * 100
            local w = (ov.hitRectRight - ov.hitRectLeft) / 1002 * 100
            local h = (ov.hitRectBottom - ov.hitRectTop) / 668 * 100
            zone_index[sub] = { parent, w, h, cx, cy }
          end
        end
      end
    end
  end

  -- fold in explicitly shipped/patched entries (pfQuest-turtle etc.); they win
  for id, data in pairs(pfDB["zones"]["data"]) do
    zone_index[id] = data
  end

  return zone_index
end

-- SearchZoneID
-- Adds a node at the center of the given (sub)zone and returns its map table
function pfDatabase:SearchZoneID(id, meta, maps, prio)
  local index = GetZoneIndex()
  if not index[id] then
    return maps
  end

  local maps = maps or {}
  local prio = prio or 1

  local entry = index[id]
  local zone, x, y = entry[1], entry[4], entry[5]

  if zone > 0 then
    maps[zone] = maps[zone] and maps[zone] + prio or prio

    meta = meta or {}
    meta["spawn"] = pfDB.zones.loc[id] or UNKNOWN
    meta["spawnid"] = id

    meta["title"] = meta["quest"] or meta["item"] or meta["spawn"]
    meta["zone"] = zone
    meta["level"] = "N/A"
    meta["spawntype"] = pfQuest_Loc["Area/Zone"]
    meta["respawn"] = "N/A"
    meta["x"] = x
    meta["y"] = y

    pfMap:AddNode(meta)
    return maps
  end

  return maps
end

-- SearchZone
-- Scans for all zones with a specified name
-- Adds map nodes for each and returns its map table
function pfDatabase:SearchZone(obj, meta, partial)
  local maps = {}
  local index = GetZoneIndex()

  for id in pairs(pfDatabase:GetIDByName(obj, "zones", partial)) do
    if index[id] then
      maps = pfDatabase:SearchZoneID(id, meta, maps)
    end
  end

  return maps
end

function pfDatabase:SearchObjectSkill(id)
  if not id or not tonumber(id) then
    return
  end
  local skill, caption = nil, nil

  if pfDB["meta"]["herbs"][-id] then
    skill = pfDB["meta"]["herbs"][-id]
    caption = pfQuest_Loc["Herbalism"]
  elseif pfDB["meta"]["mines"][-id] then
    skill = pfDB["meta"]["mines"][-id]
    caption = pfQuest_Loc["Mining"]
  end

  return skill, caption
end

-- Scans for all objects with a specified ID
-- Adds map nodes for each and returns its map table
function pfDatabase:SearchObjectID(id, meta, maps, prio)
  if not objects[id] or not objects[id]["coords"] then
    return maps
  end

  local skill, caption = pfDatabase:SearchObjectSkill(id)
  local maps = maps or {}
  local prio = prio or 1
  meta = meta or {}

  -- hoist invariant fields outside the coord loop
  meta["spawn"] = pfDB.objects.loc[id]
  meta["spawnid"] = id
  meta["title"] = meta["quest"] or meta["item"] or meta["spawn"]
  meta["level"] = skill and string.format("%s [%s]", skill, caption) or nil
  meta["spawntype"] = pfQuest_Loc["Object"]
  -- description only depends on invariant fields; compute once
  meta["description"] = pfDatabase:BuildQuestDescription(meta)

  for _, data in pairs(objects[id]["coords"]) do
    local x, y, zone, respawn = unpack(data)

    if zone > 0 then
      meta["zone"] = zone
      meta["x"] = x
      meta["y"] = y
      meta["respawn"] = respawn and SecondsToTime(respawn)

      maps[zone] = maps[zone] and maps[zone] + prio or prio
      pfMap:AddNode(meta)
    end
  end

  return maps
end

-- SearchObject
-- Scans for all objects with a specified name
-- Adds map nodes for each and returns its map table
function pfDatabase:SearchObject(obj, meta, partial)
  local maps = {}

  for id in pairs(pfDatabase:GetIDByName(obj, "objects", partial)) do
    if objects[id] and objects[id]["coords"] then
      maps = pfDatabase:SearchObjectID(id, meta, maps)
    end
  end

  return maps
end

-- SearchItemID
-- Scans for all items with a specified ID
-- Adds map nodes for each drop and vendor
-- Returns its map table
function pfDatabase:SearchItemID(id, meta, maps, allowedTypes)
  if not items[id] then
    return maps
  end

  local maps = maps or {}
  local meta = meta or {}

  meta["itemid"] = id
  meta["item"] = pfDB.items.loc[id]

  local minChance = tonumber(pfQuest_config.mindropchance)
  if not minChance then
    minChance = 0
  end

  -- search unit drops
  if items[id]["U"] and ((not allowedTypes) or allowedTypes["U"]) then
    for unit, chance in pairs(items[id]["U"]) do
      if chance >= minChance then
        meta["texture"] = nil
        meta["droprate"] = chance
        meta["sellcount"] = nil
        maps = pfDatabase:SearchMobID(unit, meta, maps)
      end
    end
  end

  -- search object loot (veins, chests, ..)
  if items[id]["O"] and ((not allowedTypes) or allowedTypes["O"]) then
    for object, chance in pairs(items[id]["O"]) do
      if chance >= minChance and chance > 0 then
        meta["texture"] = nil
        meta["droprate"] = chance
        meta["sellcount"] = nil
        maps = pfDatabase:SearchObjectID(object, meta, maps)
      end
    end
  end

  -- search reference loot (objects, creatures)
  if items[id]["R"] then
    for ref, chance in pairs(items[id]["R"]) do
      if chance >= minChance and refloot[ref] then
        -- ref creatures
        if refloot[ref]["U"] and ((not allowedTypes) or allowedTypes["U"]) then
          for unit in pairs(refloot[ref]["U"]) do
            meta["texture"] = nil
            meta["droprate"] = chance
            meta["sellcount"] = nil
            maps = pfDatabase:SearchMobID(unit, meta, maps)
          end
        end

        -- ref objects
        if refloot[ref]["O"] and ((not allowedTypes) or allowedTypes["O"]) then
          for object in pairs(refloot[ref]["O"]) do
            meta["texture"] = nil
            meta["droprate"] = chance
            meta["sellcount"] = nil
            maps = pfDatabase:SearchObjectID(object, meta, maps)
          end
        end
      end
    end
  end

  -- search vendor goods
  if items[id]["V"] and ((not allowedTypes) or allowedTypes["V"]) then
    for unit, chance in pairs(items[id]["V"]) do
      meta["texture"] = pfQuestConfig.path .. "\\img\\icon_vendor"
      meta["droprate"] = nil
      meta["sellcount"] = chance
      maps = pfDatabase:SearchMobID(unit, meta, maps)
    end
  end

  return maps
end

-- SearchItem
-- Scans for all items with a specified name
-- Adds map nodes for each drop and vendor
-- Returns its map table
function pfDatabase:SearchItem(item, meta, partial)
  local maps = {}
  local bestmap, bestscore = nil, 0

  for id in pairs(pfDatabase:GetIDByName(item, "items", partial)) do
    maps = pfDatabase:SearchItemID(id, meta, maps)
  end

  return maps
end

-- SearchVendor
-- Scans for all items with a specified name
-- Adds map nodes for each vendor
-- Returns its map table
function pfDatabase:SearchVendor(item, meta)
  local maps = {}
  local meta = meta or {}
  local bestmap, bestscore = nil, 0

  for id in pairs(pfDatabase:GetIDByName(item, "items")) do
    meta["itemid"] = id
    meta["item"] = pfDB.items.loc[id]

    -- search vendor goods
    if items[id] and items[id]["V"] then
      for unit, chance in pairs(items[id]["V"]) do
        meta["texture"] = pfQuestConfig.path .. "\\img\\icon_vendor"
        meta["droprate"] = nil
        meta["sellcount"] = chance
        maps = pfDatabase:SearchMobID(unit, meta, maps)
      end
    end
  end

  return maps
end

-- SearchQuestID
-- Scans for all quests with a specified ID
-- Adds map nodes for each objective and involved units
-- Returns its map table
function pfDatabase:SearchQuestID(id, meta, maps)
  if not quests[id] then
    return
  end
  local maps = maps or {}
  local meta = meta or {}

  meta["questid"] = id
  meta["quest"] = pfDatabase:GetQuestText(id, "T")
  meta["qlvl"] = quests[id]["lvl"]
  meta["qmin"] = quests[id]["min"]

  -- clear previous unified quest nodes
  if meta.quest then
    pfMap.unifiedcache[meta.quest] = {}
  end

  if pfQuest_config["currentquestgivers"] == "1" then
    -- search quest-starter
    if quests[id]["start"] and not meta["qlogid"] then
      -- units
      if quests[id]["start"]["U"] then
        for _, unit in pairs(quests[id]["start"]["U"]) do
          meta = meta or {}
          meta["QTYPE"] = "NPC_START"
          meta["layer"] = meta["layer"] or 4
          meta["texture"] = pfQuestConfig.path .. "\\img\\available_c"
          maps = pfDatabase:SearchMobID(unit, meta, maps, 0)
        end
      end

      -- objects
      if quests[id]["start"]["O"] then
        for _, object in pairs(quests[id]["start"]["O"]) do
          meta = meta or {}
          meta["QTYPE"] = "OBJECT_START"
          meta["texture"] = pfQuestConfig.path .. "\\img\\available_c"
          maps = pfDatabase:SearchObjectID(object, meta, maps, 0)
        end
      end
    end

    -- search quest-ender
    if quests[id]["end"] then
      -- compute complete state once, outside both ender loops
      local ender_texture
      if meta["qlogid"] then
        local _, _, _, _, _, complete = compat.GetQuestLogTitle(meta["qlogid"])
        complete = complete or GetNumQuestLeaderBoards(meta["qlogid"]) == 0 and true or nil
        ender_texture = (complete == true or complete == 1) and pfQuestConfig.path .. "\\img\\complete_c"
          or pfQuestConfig.path .. "\\img\\complete"
      else
        ender_texture = pfQuestConfig.path .. "\\img\\complete_c"
      end

      -- units
      if quests[id]["end"]["U"] then
        for _, unit in pairs(quests[id]["end"]["U"]) do
          meta["texture"] = ender_texture
          meta["QTYPE"] = "NPC_END"
          maps = pfDatabase:SearchMobID(unit, meta, maps, 0)
        end
      end

      -- objects
      if quests[id]["end"]["O"] then
        for _, object in pairs(quests[id]["end"]["O"]) do
          meta["texture"] = ender_texture
          meta["QTYPE"] = "OBJECT_END"
          maps = pfDatabase:SearchObjectID(object, meta, maps, 0)
        end
      end
    end
  end

  -- Clear and reuse the module-level parse_obj table
  clear_parse_obj()

  -- If QuestLogID is given, scan and add all finished objectives to blacklist
  if meta["qlogid"] then
    local objectives = GetNumQuestLeaderBoards(meta["qlogid"])
    local _, _, _, _, _, complete = compat.GetQuestLogTitle(meta["qlogid"])
    if complete then
      return maps
    end

    if objectives then
      for i = 1, objectives, 1 do
        local text, type, done = GetQuestLogLeaderBoard(i, meta["qlogid"])
        local objid = GetQuestLogLeaderBoardID(i, meta["qlogid"])

        if type == "monster" then
          local _, _, _, objNum, objNeeded = strfind(text, pfUI.api.SanitizePattern(QUEST_MONSTERS_KILLED))
          -- text doesn't always match the kill template (e.g. "use X on Y"
          -- objectives also come back as type "monster"); skip when it doesn't
          -- to match the original behaviour where GetIDByName(nil) was a no-op
          if objNum and objNeeded then
            local state = ( objNum + 0 >= objNeeded + 0 or done ) and "DONE" or "PROG"

            -- "monster" kind covers both creatures and gameobjects in 1.12
            if units[objid] then
              parse_obj["U"][objid] = state
            elseif objects[objid] then
              parse_obj["O"][objid] = state
            end
          end
        end

        if type == "item" then
          local _, _, _, objNum, objNeeded = strfind(text, pfUI.api.SanitizePattern(QUEST_OBJECTS_FOUND))
          if objNum and objNeeded then
            local state = ( objNum + 0 >= objNeeded + 0 or done ) and "DONE" or "PROG"
            if items[objid] then
              parse_obj["I"][objid] = state
            end
          end
        end
      end
    end
  end

  -- search quest-objectives
  if quests[id]["obj"] then
    local skip_objects
    local skip_creatures

    -- item requirements
    if quests[id]["obj"]["IR"] then
      local requirement

      for _, item in pairs(quests[id]["obj"]["IR"]) do
        if itemreq[item] then
          requirement = pfDB["items"]["loc"][item] or UNKNOWN

          for object, spell in pairs(itemreq[item]) do
            if object < 0 then
              -- gameobject
              meta["texture"] = nil
              meta["layer"] = 2
              meta["QTYPE"] = "OBJECT_OBJECTIVE_ITEMREQ"
              meta.itemreq = requirement

              skip_objects = skip_objects or {}
              skip_objects[math.abs(object)] = true

              pfDatabase:TrackQuestItemDependency(requirement, id)
              if pfDatabase.itemlist.db[requirement] then
                maps = pfDatabase:SearchObjectID(math.abs(object), meta, maps)
              end
            elseif object > 0 then
              -- creature
              meta["texture"] = nil
              meta["layer"] = 2
              meta["QTYPE"] = "UNIT_OBJECTIVE_ITEMREQ"
              meta.itemreq = requirement

              skip_creatures = skip_creatures or {}
              skip_creatures[math.abs(object)] = true

              pfDatabase:TrackQuestItemDependency(requirement, id)
              if pfDatabase.itemlist.db[requirement] then
                maps = pfDatabase:SearchMobID(math.abs(object), meta, maps)
              end
            end
          end
        end
      end
    end

    -- units
    if quests[id]["obj"]["U"] then
      for _, unit in pairs(quests[id]["obj"]["U"]) do
        if not parse_obj["U"][unit] or parse_obj["U"][unit] ~= "DONE" then
          if not skip_creatures or not skip_creatures[unit] then
            meta = meta or {}
            meta["texture"] = nil
            meta["QTYPE"] = "UNIT_OBJECTIVE"
            maps = pfDatabase:SearchMobID(unit, meta, maps)
          end
        end
      end
    end

    -- objects
    if quests[id]["obj"]["O"] then
      for _, object in pairs(quests[id]["obj"]["O"]) do
        if not parse_obj["O"][object] or parse_obj["O"][object] ~= "DONE" then
          if not skip_objects or not skip_objects[object] then
            meta = meta or {}
            meta["texture"] = nil
            meta["layer"] = 2
            meta["QTYPE"] = "OBJECT_OBJECTIVE"
            maps = pfDatabase:SearchObjectID(object, meta, maps)
          end
        end
      end
    end

    -- items
    if quests[id]["obj"]["I"] then
      for _, item in pairs(quests[id]["obj"]["I"]) do
        if not parse_obj["I"][item] or parse_obj["I"][item] ~= "DONE" then
          meta = meta or {}
          meta["texture"] = nil
          meta["layer"] = 2
          if parse_obj["I"][item] then
            meta["QTYPE"] = "ITEM_OBJECTIVE_LOOT"
          else
            meta["QTYPE"] = "ITEM_OBJECTIVE_USE"
          end
          maps = pfDatabase:SearchItemID(item, meta, maps)
        end
      end
    end

    -- areatrigger
    if quests[id]["obj"]["A"] then
      for _, areatrigger in pairs(quests[id]["obj"]["A"]) do
        meta = meta or {}
        meta["texture"] = nil
        meta["layer"] = 2
        meta["QTYPE"] = "AREATRIGGER_OBJECTIVE"
        maps = pfDatabase:SearchAreaTriggerID(areatrigger, meta, maps)
      end
    end

    -- zones
    if quests[id]["obj"]["Z"] then
      for _, zone in pairs(quests[id]["obj"]["Z"]) do
        meta = meta or {}
        meta["texture"] = nil
        meta["layer"] = 2
        meta["QTYPE"] = "ZONE_OBJECTIVE"
        maps = pfDatabase:SearchZoneID(zone, meta, maps)
      end
    end
  end

  -- prepare unified quest location markers
  local addon = meta["addon"] or "PFDB"
  if pfMap.nodes[addon] then
    for map in pairs(pfMap.nodes[addon]) do
      if meta.quest and pfMap.unifiedcache[meta.quest] and pfMap.unifiedcache[meta.quest][map] then
        for hash, data in pairs(pfMap.unifiedcache[meta.quest][map]) do
          meta = data.meta
          meta["title"] = meta["quest"]
          meta["cluster"] = true
          meta["zone"] = map

          local icon = pfQuest_config["clustermono"] == "1" and "_mono" or ""

          if meta.item then
            meta["x"], meta["y"], meta["priority"] = getcluster(data.coords, meta["quest"] .. hash .. map)
            meta["texture"] = pfQuestConfig.path .. "\\img\\cluster_item" .. icon
            pfMap:AddNode(meta, true)
          elseif meta.spawntype and meta.spawntype == pfQuest_Loc["Unit"] and meta.spawn and not meta.itemreq then
            meta["x"], meta["y"], meta["priority"] = getcluster(data.coords, meta["quest"] .. hash .. map)
            meta["texture"] = pfQuestConfig.path .. "\\img\\cluster_mob" .. icon
            pfMap:AddNode(meta, true)
          else
            meta["x"], meta["y"], meta["priority"] = getcluster(data.coords, meta["quest"] .. hash .. map)
            meta["texture"] = pfQuestConfig.path .. "\\img\\cluster_misc" .. icon
            pfMap:AddNode(meta, true)
          end
        end
      end
    end
  end

  return maps
end

-- SearchQuest
-- Scans for all quests with a specified name
-- Adds map nodes for each objective and involved unit
-- Returns its map table
function pfDatabase:SearchQuest(quest, meta, partial)
  local maps = {}

  for id in pairs(pfDatabase:GetIDByName(quest, "quests", partial)) do
    maps = pfDatabase:SearchQuestID(id, meta, maps)
  end

  return maps
end

function pfDatabase:QuestFilter(id, plevel, pclass, prace)
  -- fast reject: race, class, and missing loc name are session-constants,
  -- pre-computed in BuildStaticRejectSet to avoid repeating bit ops per call
  if pfDatabase.staticRejectSet[id] then
    return
  end

  -- hide active quest
  if pfQuest.questlog[id] then
    return
  end

  -- hide completed quests
  if pfQuest_history[id] then
    return
  end

  -- hide missing pre-quests
  if quests[id]["pre"] then
    -- check all pre-quests for one to be completed
    local one_complete = nil
    for _, prequest in pairs(quests[id]["pre"]) do
      if pfQuest_history[prequest] then
        one_complete = true
      end
    end

    -- hide if none of the pre-quests has been completed
    if not one_complete then
      return
    end
  end

  -- hide non-available quests for your race (redundant when staticRejectSet is warm,
  -- retained as fallback for the brief window before locale detection completes)
  if quests[id]["race"] and not (bit.band(quests[id]["race"], prace) == prace) then
    return
  end

  -- hide non-available quests for your class
  if quests[id]["class"] and not (bit.band(quests[id]["class"], pclass) == pclass) then
    return
  end

  -- hide non-available quests for your profession (uses cache when inside SearchQuests)
  if quests[id]["skill"] and not pfDatabase:GetPlayerSkillCached(quests[id]["skill"]) then
    return
  end

  -- hide lowlevel quests
  if quests[id]["lvl"] and quests[id]["lvl"] < plevel - 4 and pfQuest_config["showlowlevel"] == "0" then
    return
  end

  -- hide highlevel quests (or show those that are 3 levels above)
  if quests[id]["min"] and quests[id]["min"] > plevel + (pfQuest_config["showhighlevel"] == "1" and 3 or 0) then
    return
  end

  -- hide event quests
  if quests[id]["event"] and pfQuest_config["showfestival"] == "0" then
    return
  end

  return true
end

-- GetPlayerSkillCached
-- Kept for call-site compatibility (QuestFilter). Skill rank is now a cheap
-- id-keyed client lookup, so the old per-scan name cache (BuildSkillCache) is
-- gone.
function pfDatabase:GetPlayerSkillCached(skill)
  return pfDatabase:GetPlayerSkill(skill)
end

-- SearchQuests incremental node cache.
-- Tracks which quest IDs passed QuestFilter on the last run. On subsequent
-- calls only the delta (quests entering or leaving the passing set) is
-- processed, so SearchMobID/SearchObjectID are skipped for quests whose
-- questgiver nodes already exist. Must be cleared whenever pfMap.nodes
-- ["PFQUEST"] is wiped (e.g. ResetAll).
-- (Initialised at line ~435 alongside nameIndex so BuildNameIndex can clear it.)

-- SearchQuests
-- Scans for available quests and adds/removes questgiver map nodes.
-- On the first call processes all quests; on subsequent calls only the
-- delta between the previous passing set and the current one is touched.
function pfDatabase:SearchQuests(meta, maps)
  local maps = maps or {}
  local meta = meta or {}

  local plevel = UnitLevel("player")
  local pfaction = UnitFactionGroup("player")
  if pfaction == "Horde" then
    pfaction = "H"
  elseif pfaction == "Alliance" then
    pfaction = "A"
  else
    pfaction = "GM"
  end

  local _, race = UnitRace("player")
  local prace = pfDatabase:GetBitByRace(race)
  local _, class = UnitClass("player")
  local pclass = pfDatabase:GetBitByClass(class)

  local t_filter, t_nodes, t_start = 0, 0, GetTime()

  -- Phase 1: build the full set of quests that currently pass the filter.
  -- This loop is unavoidable but is the only O(all_quests) work we do.
  -- Static rejects (wrong race/class, missing name) are skipped before
  -- calling QuestFilter to avoid the function call overhead entirely.
  local currentSet = {}
  local staticReject = self.staticRejectSet
  for id in pairs(quests) do
    if not staticReject[id] then
      local tf0 = GetTime()
      local pass = pfDatabase:QuestFilter(id, plevel, pclass, prace)
      t_filter = t_filter + (GetTime() - tf0)
      if pass then
        currentSet[id] = true
      end
    end
  end

  -- Phase 2: remove nodes for quests that left the passing set.
  -- Skip quests that are now active: their nodes were just refreshed by
  -- SearchQuestID during queue processing and must not be wiped here.
  local t_rm0 = GetTime()
  local removed = 0
  for id in pairs(self.lastQuestGiversSet) do
    if not currentSet[id] and not (pfQuest and pfQuest.questlog and pfQuest.questlog[id]) then
      local title = (pfDB.quests.loc[id] and pfDB.quests.loc[id].T) or UNKNOWN
      pfMap:DeleteNode("PFQUEST", title)
      removed = removed + 1
    end
  end
  local t_rm = GetTime() - t_rm0

  -- Phase 3: add nodes only for quests newly entering the passing set.
  -- Quests already in lastQuestGiversSet are skipped — their nodes exist.
  for id in pairs(currentSet) do
    if not self.lastQuestGiversSet[id] then
      -- set metadata
      meta["quest"] = (pfDB.quests.loc[id] and pfDB.quests.loc[id].T) or UNKNOWN
      meta["questid"] = id
      meta["texture"] = pfQuestConfig.path .. "\\img\\available_c"

      meta["qlvl"] = quests[id]["lvl"]
      meta["qmin"] = quests[id]["min"]

      meta["vertex"] = VERTEX_BLACK
      meta["layer"] = 3

      -- tint high level quests red
      if quests[id]["min"] and quests[id]["min"] > plevel then
        meta["texture"] = pfQuestConfig.path .. "\\img\\available"
        meta["vertex"] = VERTEX_RED
        meta["layer"] = 2
      end

      -- tint low level quests grey
      if quests[id]["lvl"] and quests[id]["lvl"] + 10 < plevel then
        meta["texture"] = pfQuestConfig.path .. "\\img\\available"
        meta["vertex"] = VERTEX_WHITE
        meta["layer"] = 2
      end

      -- tint event quests as blue
      if quests[id]["event"] then
        meta["texture"] = pfQuestConfig.path .. "\\img\\available"
        meta["vertex"] = VERTEX_BLUE
        meta["layer"] = 2
      end

      -- add questgiver nodes
      if quests[id]["start"] then
        -- units
        if quests[id]["start"]["U"] then
          meta["QTYPE"] = "NPC_START"
          for _, unit in pairs(quests[id]["start"]["U"]) do
            if units[unit] and strfind(units[unit]["fac"] or pfaction, pfaction) then
              local tn0 = GetTime()
              maps = pfDatabase:SearchMobID(unit, meta, maps)
              t_nodes = t_nodes + (GetTime() - tn0)
            end
          end
        end

        -- objects
        if quests[id]["start"]["O"] then
          meta["QTYPE"] = "OBJECT_START"
          for _, object in pairs(quests[id]["start"]["O"]) do
            if objects[object] and strfind(objects[object]["fac"] or pfaction, pfaction) then
              local tn0 = GetTime()
              maps = pfDatabase:SearchObjectID(object, meta, maps)
              t_nodes = t_nodes + (GetTime() - tn0)
            end
          end
        end
      end
    end
  end

  -- Update lastQuestGiversSet to reflect the current passing set.
  -- Reuse the table in-place to avoid allocation.
  for id in pairs(self.lastQuestGiversSet) do
    self.lastQuestGiversSet[id] = nil
  end
  for id in pairs(currentSet) do
    self.lastQuestGiversSet[id] = true
  end

  pfQuest:Debug(
    format(
      "|cffff3333TIMER SearchQuests total=%.4fs  filter=%.4fs  remove=%d(%.4fs)  nodes=%.4fs",
      GetTime() - t_start,
      t_filter,
      removed,
      t_rm,
      t_nodes
    )
  )
end

-- AddCustomIcon
-- Helper function to add custom tracking node icons
--   id: negative for objects, positive for units
--   img: path to the image that is appended to root
--   root: optional, default: "Interface\\AddOns\\pfQuest"
function pfDatabase:AddCustomIcon(id, img, root)
  if not id or not img then
    return
  end

  root = root and root .. "\\" or pfQuestConfig.path .. "\\"

  local object = pfDB["objects"]["loc"][math.abs(id)]
  local unit = pfDB["units"]["loc"][math.abs(id)]

  if id < 0 and object then
    pfDatabase.icons[object] = root .. img
  elseif id > 0 and unit then
    pfDatabase.icons[unit] = root .. img
  end
end

function pfDatabase:FormatQuestText(questText)
  -- A quest whose locale entry has no "O" or "D" field arrives here as nil and
  -- gsub throws. Most callers test the field first; the three in quest.lua that
  -- feed the [Translate] button index it straight out of the locale table.
  --
  -- An entry loses a field when a database pack carries a quest the base
  -- database has never heard of: a per-field merge has no base entry to merge
  -- into, so it assigns the pack's record whole, absent fields included.
  -- Measured against pfQuest-octo: of the 2456 quests it adds that are not in
  -- the base enUS table, 13 carry no "D" and 12 carry no "O".
  if not questText then return "" end

  questText = string.gsub(questText, "$[Nn]", UnitName("player"))
  questText = string.gsub(questText, "$[Cc]", strlower(UnitClass("player")))
  questText = string.gsub(questText, "$[Rr]", strlower(UnitRace("player")))
  questText = string.gsub(questText, "$[Bb]", "\n")
  -- UnitSex("player") returns 2 for male and 3 for female
  -- that's why there is an unused capture group around the $[Gg]
  return string.gsub(questText, "($[Gg])([^:]+):([^;]+);", "%" .. UnitSex("player"))
end

-- GetQuestIDs
-- Returns a single-element array containing the engine-authoritative quest
-- ID for the given quest log slot, or nil for headers / empty slots. Callers
-- expect the array shape, so the wrapper stays.
function pfDatabase:GetQuestIDs(qid)
  local id = C_QuestLog.GetQuestIDForLogIndex(qid)
  if id and id > 0 then return { id } end
end

-- browser search related defaults and values
pfDatabase.lastSearchQuery = ""
pfDatabase.lastSearchResults = { ["items"] = {}, ["quests"] = {}, ["objects"] = {}, ["units"] = {} }

-- BrowserSearch
-- Search for a list of IDs of the specified `searchType` based on if `query` is
-- part of the name or ID of the database entry it is compared against.
--
-- `query` must be a string. If the string represents a number, the search is
-- based on IDs, otherwise it compares names.
--
-- `searchType` must be one of these strings: "items", "quests", "objects" or
-- "units"
--
-- Returns a table and an integer, the latter being the element count of the
-- former. The table contains the ID as keys for the name of the search result.
-- E.g.: {{[5] = "Some Name", [231] = "Another Name"}, 2}
-- If the query doesn't satisfy the minimum search length requiered for its
-- type (number/string), the favourites for the `searchType` are returned.
function pfDatabase:BrowserSearch(query, searchType)
  local queryLength = strlen(query) -- needed for some checks
  local queryNumber = tonumber(query) -- if nil, the query is NOT a number
  local results = {} -- save results
  local resultCount = 0 -- count results

  -- Set the DB to be searched
  local minChars = 3
  local minInts = 1
  if (queryLength >= minChars) or (queryNumber and (queryLength >= minInts)) then -- make sure this is no fav display
    if
      ((queryLength > minChars) or (queryNumber and (queryLength > minInts)))
      and (pfDatabase.lastSearchQuery ~= "" and queryLength > strlen(pfDatabase.lastSearchQuery))
    then
      -- there are previous search results to use
      local searchDatabase = pfDatabase.lastSearchResults[searchType]
      -- iterate the last search
      for id, _ in pairs(searchDatabase) do
        local dbLocale = pfDB[searchType]["loc"][id]
        if dbLocale then
          local compare
          local search = query
          if queryNumber then
            -- do number search
            compare = tostring(id)
          else
            -- do name search
            search = strlower(query)
            if searchType == "quests" then
              compare = strlower(dbLocale["T"])
            else
              compare = strlower(dbLocale)
            end
          end
          -- search and save on match
          if strfind(compare, search) then
            results[id] = dbLocale
            resultCount = resultCount + 1
          end
        end
      end
      return results, resultCount
    else
      -- no previous results, search whole DB
      if queryNumber then
        results = pfDatabase:GetIDByIDPart(query, searchType)
      else
        results = pfDatabase:GetIDByName(query, searchType, true)
      end
      local resultCount = 0
      for _, _ in pairs(results) do
        resultCount = resultCount + 1
      end
      return results, resultCount
    end
  else
    -- minimal search length not satisfied, reset search results and return favourites
    return pfBrowser_fav[searchType], -1
  end
end

-- pfQuest_server["items"] is a set of custom item ids (present on the server
-- but not in the shipped DB). Names aren't persisted -- they're resolved live
-- from the client via ClassicAPI (C_Item.GetItemNameByID), so they follow the
-- active locale and never go stale. Ids that aren't cached yet are requested and
-- filled by the ITEM_DATA_LOAD_RESULT handler below.
local function LoadCustomData(always)
  -- table.getn doesn't work here :/
  local icount = 0
  for _ in pairs(pfQuest_server["items"]) do
    icount = icount + 1
  end

  if icount > 0 or always then
    for id in pairs(pfQuest_server["items"]) do
      local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
      if name and name ~= "" then
        pfDB["items"]["loc"][id] = name
      elseif C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(id)
      end
    end
    DEFAULT_CHAT_FRAME:AddMessage(
      "|cff33ffccpf|cffffffffQuest: |cff33ffcc" .. icount .. "|cffffffff " .. pfQuest_Loc["custom items loaded."]
    )
  end
end

local pfServerScan = CreateFrame("Frame", "pfServerItemScan", UIParent)
pfServerScan:SetWidth(200)
pfServerScan:SetHeight(100)
pfServerScan:SetPoint("TOP", 0, 0)
pfServerScan:Hide()

-- The scan drives ClassicAPI's C_Item.RequestLoadItemDataByID for every id
-- from 1..max and reads the authoritative existence answer off the
-- ITEM_DATA_LOAD_RESULT event: success=true means the item exists on the
-- server, success=false means it doesn't (the DLL turns the server's "no
-- such item" reply into a false result -- see ClassicAPI item/Data.cpp).
-- This replaces the old ItemRefTooltip probing + RETRIEVING_ITEM_INFO retry
-- heuristic. We keep at most `window` requests in flight, comfortably under
-- ClassicAPI's kMaxPending (512), so RequestLoadItemDataByID is never
-- refused for lack of room.
pfServerScan.scanID = 1
pfServerScan.max = 100000
pfServerScan.window = 100
pfServerScan.inflight = 0
pfServerScan.scanPending = {}

pfServerScan.header = pfServerScan:CreateFontString("Caption", "LOW", "GameFontWhite")
pfServerScan.header:SetFont(STANDARD_TEXT_FONT, 13, "OUTLINE")
pfServerScan.header:SetJustifyH("CENTER")
pfServerScan.header:SetPoint("CENTER", 0, 0)

-- issue load requests until the in-flight window is full or every id has
-- been requested. ids already in the shipped DB are skipped -- a custom item
-- is by definition not in pfDB, so probing known ids would only add traffic
-- without discovering anything new. Cached items fire ITEM_DATA_LOAD_RESULT
-- synchronously inside RequestLoadItemDataByID, so bookkeeping is set up
-- before the call and the handler tolerates the re-entrant fire.
local function ScanRefill()
  while pfServerScan.scanID <= pfServerScan.max and pfServerScan.inflight < pfServerScan.window do
    local id = pfServerScan.scanID
    if pfDB["items"]["loc"][id] then
      pfServerScan.scanID = id + 1
    else
      pfServerScan.scanPending[id] = true
      pfServerScan.inflight = pfServerScan.inflight + 1
      local accepted = C_Item.RequestLoadItemDataByID(id)
      if not accepted then
        -- ClassicAPI's pending set is momentarily full; undo bookkeeping
        -- (unless a synchronous result already cleared it) and let the next
        -- pump retry this id once outstanding results drain.
        if pfServerScan.scanPending[id] then
          pfServerScan.scanPending[id] = nil
          pfServerScan.inflight = pfServerScan.inflight - 1
        end
        break
      end
      pfServerScan.scanID = id + 1
    end
  end
end

pfServerScan:RegisterEvent("VARIABLES_LOADED")
pfServerScan:RegisterEvent("ITEM_DATA_LOAD_RESULT")
pfServerScan:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    pfQuest_server = pfQuest_server or {}
    pfQuest_server["items"] = pfQuest_server["items"] or {}
    LoadCustomData()
  elseif event == "ITEM_DATA_LOAD_RESULT" then
    local id, success = arg1, arg2
    if id and pfServerScan.scanPending[id] then
      -- discovery result for an id in our scan window
      pfServerScan.scanPending[id] = nil
      pfServerScan.inflight = pfServerScan.inflight - 1
      if success and not pfDB["items"]["loc"][id] then
        -- exists on the server but not in the shipped DB -> custom item.
        -- the data is now cached, so the name resolves immediately.
        pfQuest_server["items"][id] = true
        local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
        if name and name ~= "" then
          pfDB["items"]["loc"][id] = name
        end
      end
    elseif success and id and pfQuest_server and pfQuest_server["items"]
      and pfQuest_server["items"][id] and not pfDB["items"]["loc"][id]
      and C_Item and C_Item.GetItemNameByID then
      -- name-fill for a previously-discovered custom id (LoadCustomData path)
      local name = C_Item.GetItemNameByID(id)
      if name and name ~= "" then
        pfDB["items"]["loc"][id] = name
      end
    end
  end
end)

pfServerScan:SetScript("OnHide", function()
  LoadCustomData(true)
end)

pfServerScan:SetScript("OnShow", function()
  this.scanID = 1
  this.inflight = 0
  this.scanPending = {}
  pfQuest_server["items"] = {}
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest: " .. pfQuest_Loc["Server scan started..."])
end)

pfServerScan:SetScript("OnUpdate", function()
  ScanRefill()
  pfServerScan.header:SetText(
    pfQuest_Loc["Scanning server for items..."] .. " " ..
    string.format("%.1f", 100 * pfServerScan.scanID / pfServerScan.max) .. "%"
  )
  -- done once every id has been requested and every result is back
  if pfServerScan.scanID > pfServerScan.max and pfServerScan.inflight <= 0 then
    pfServerScan:Hide()
  end
end)

function pfDatabase:ScanServer()
  if not (C_Item and C_Item.RequestLoadItemDataByID) then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest: server scan requires ClassicAPI.")
    return
  end
  pfServerScan:Show()
end

-- Pre-create frame and handler for QueryServer (avoid creating per call)
local queryFrame
local function OnQuestQueryComplete(self)
  self:UnregisterEvent("QUEST_QUERY_COMPLETE")

  -- Retrieve completed quests after the QUEST_QUERY_COMPLETE event
  local completedQuests = GetQuestsCompleted()

  if type(completedQuests) == "table" then
    for questID, _ in pairs(completedQuests) do
      pfQuest_history[questID] = { time(), UnitLevel("player") }
    end

    -- Reset all quest markers after processing completed quests
    pfQuest:ResetAll()
  elseif completedQuests == nil then
    print("Error: GetQuestsCompleted() returned nil.")
  else
    print("Error: GetQuestsCompleted() did not return a valid table. Value: ", completedQuests)
  end
end

function pfDatabase:QueryServer()
  -- break here on incompatible versions
  if not QueryQuestsCompleted then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest: Option is not available on your server.")
    return
  end

  -- Reuse frame instead of creating new one each call
  if not queryFrame then
    queryFrame = CreateFrame("Frame")
    queryFrame:SetScript("OnEvent", OnQuestQueryComplete)
  end

  queryFrame:RegisterEvent("QUEST_QUERY_COMPLETE")
  QueryQuestsCompleted()
end

-- check for unlocalized servers and fall back to enUS databases when the server
-- returns item names that differ from the database ones (checked via Hearthstone).
-- Placed at the end of the file so the synchronous cached-item path can safely
-- call BuildNameIndex/BuildStaticRejectSet (and GetBitByRace/GetBitByClass) after
-- every function they depend on is defined. BuildStaticRejectSet self-guards for
-- UnitRace/UnitClass being nil pre-login; PLAYER_ENTERING_WORLD rebuilds it fully.
do
  local function RunNameCheck(name)
    if name and name ~= "" and pfDB["items"][loc] and pfDB["items"][loc][HEARTHSTONE_ITEM_ID] then
      if not strfind(name, pfDB["items"][loc][HEARTHSTONE_ITEM_ID], 1) then
        pfDatabase.dbstring = ""
        for id, db in pairs(dbs) do
          -- assign existing locale and update dbstring
          pfDB[db]["loc"] = noloc[db] and pfDB[db]["enUS"] or pfDB[db][loc] or {}
          pfDatabase.dbstring = pfDatabase.dbstring
            .. " |cffcccccc[|cffffffff"
            .. db
            .. "|cffcccccc:|cff33ffcc"
            .. (noloc[db] and "enUS" or loc)
            .. "|cffcccccc]"
        end
      end
      pfDatabase.localized = true
      -- locale tables may have been swapped above; rebuild the derived indexes
      -- (this replaces the call site the old locale-detection OnUpdate had)
      pfDatabase:BuildNameIndex()
      pfDatabase:BuildStaticRejectSet()
    end
  end
  if C_Item.IsItemDataCachedByID(HEARTHSTONE_ITEM_ID) then
    RunNameCheck(C_Item.GetItemNameByID(HEARTHSTONE_ITEM_ID))
  else
    local item = Item:CreateFromItemID(HEARTHSTONE_ITEM_ID)
    item:ContinueOnItemLoad(function()
      RunNameCheck(item:GetItemName())
    end)
  end
end
