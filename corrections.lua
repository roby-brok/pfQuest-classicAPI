-- Objective data missing from the shipped database.
--
-- A quest with no ["obj"] block draws no objective pins and says nothing about
-- it. That is how "Shizzle's Flyer" (4503) went unnoticed -- there, the cause
-- was a database pack replacing whole records instead of merging fields, which
-- is fixed. These are the other kind: gaps that are genuinely absent upstream.
--
-- Only corrections verified against the object's own spawn coordinates and zone
-- belong here. A plausible-looking name match is not enough: of 20 candidates a
-- name-matching scan turned up, 13 were wrong. "Master Ryson's All Seeing Eye"
-- (6847/6848) resolves to an object sitting in Alterac Valley for a quest that
-- happens in the Hinterlands, and several others matched the object that
-- *starts* the quest rather than the one you are sent to find. Each entry below
-- was checked by hand: the object name matches the objective text, the object
-- has exactly one spawned record, and its zone matches where the quest happens.
--
-- Applied only when the field is absent, so a future database that ships real
-- data for these silently takes precedence over the correction.
--
-- Use "/db checkdb" in game to list quests in your log that still have none.

local corrections = {
  -- Un'Goro Crater (490) -- the three crystal pylons. Exploration quests: the
  -- objective is to reach the pylon, and nothing pointed at where they are.
  [4285] = { obj = { O = { 164955 } } }, -- The Northern Pylon -> Northern Crystal Pylon (56.5, 12.5)
  [4287] = { obj = { O = { 164957 } } }, -- The Eastern Pylon  -> Eastern Crystal Pylon  (77.2, 50.0)
  [4288] = { obj = { O = { 164956 } } }, -- The Western Pylon  -> Western Crystal Pylon  (23.9, 59.2)

  -- "Read Henrig Lonebrow's Journal" -- the journal is a world object.
  [1100] = { obj = { O = { 19861 } } },

  -- "Take the Torch of Retribution" -- Searing Gorge (51), 39.0 39.2
  [3454] = { obj = { O = { 149047 } } },

  -- "Read from the Catalogue of the Wayward" -- Western Plaguelands (28)
  [5164] = { obj = { O = { 176192 } } },

  -- "Destroy any one of the Hakkari Bijous ... at the Altar of Zanza on
  -- Yojamba Isle" -- Stranglethorn Vale (33), 13.4 15.1
  [8240] = { obj = { O = { 180367 } } },
}

local quests = pfDB and pfDB["quests"] and pfDB["quests"]["data"]
if quests then
  for id, fix in pairs(corrections) do
    local entry = quests[id]
    if entry then
      for field, value in pairs(fix) do
        if not entry[field] then
          entry[field] = value
        end
      end
    end
  end
end
