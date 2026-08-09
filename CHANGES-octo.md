# Changes on top of brues-code/pfQuest

Everything on the `octo` branch that is not in
[brues-code/pfQuest](https://github.com/brues-code/pfQuest).

Small, because the upstream tree needed very little: the shipped databases are
**byte-identical** to the build this fork came from (verified by hashing `quests`, `units`,
`objects` and `items`), and the config surface matches exactly.

## Bugs found in the upstream tree

**`database.lua` — `FormatQuestText` has no nil guard.** A database pack can replace a
quest's locale entry with one that has no `O` or `D` field — `patchtable` assigns whole
entries rather than merging — leaving the base text gone. Four callers pass the field
straight in with no nil test, so that becomes a `gsub` error.

Relevant to any server running a data pack on top: `pfQuest-octo`'s `patchtable` does
exactly this whole-entry assignment, and the OctoWoW dataset has quests with genuinely
absent descriptions.

## Local changes

- **Tracker defaults to Current Zone** rather than All Quests, which otherwise puts every
  active quest in the tracker at once. Upstream already implements mode 5 — four call sites
  in `tracker.lua` and a `Current Zone` locale string — only the config comment listing the
  modes was stale, and is corrected.
- **Quest database website is settable.** The online-quest button hardcoded wowhead; it now
  goes through `pfQuest:GetDatabaseURL()`, which prefers a configured URL and falls back to
  the hardcoded default when the box is empty. Defaults to OctoWoW's database.
- **World map / minimap node scale.** Node size was hardcoded to 14 (18 for clusters); both
  maps now take a multiplier. Applied in *two* places — `ResizeNode` reassigns `defsize`
  from scratch on every resize, so scaling only in `BuildNode` is discarded the first time
  the map zooms.

- **Build identity in the toc.** Credits brues alongside the original authors and marks the
  loaded build as *[ClassicAPI build + local patches]*, so which tree is running is visible
  from the addon list.

## Not ported, and why

`pfQuest_questcache` from our older fork cached an expensive fuzzy lookup — matching quest
log entries by title + level + objective + text against the database, filtered by race and
class. Upstream replaced the whole thing with

```lua
function pfDatabase:GetQuestIDs(qid)
  local id = C_QuestLog.GetQuestIDForLogIndex(qid)
  if id and id > 0 then return { id } end
end
```

an engine-authoritative ID. The cache is moot because the expensive operation no longer
exists. Probably the clearest single illustration of what ClassicAPI buys.
