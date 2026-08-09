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

**`quest.lua` — the `[Translate]` button never worked, for two independent reasons.**

1. Its `OnClick` passes the global `self` to `UIDropDownMenu_Initialize` and
   `ToggleDropDownMenu`. A 1.12 script handler has no `self` — the frame is `this` — so both
   received nil and the menu never opened. Silently, with `scriptErrors` off. This one dates
   back to the original and is present in every pfQuest lineage.
2. Even repaired, it would have shown nothing. The locale-freeing loop in `database.lua`
   ("Free unused locale data to reduce memory") nils out every non-active locale table at
   load, so the `pfDB["quests"][lang]` the button reads is always nil for whatever language
   is picked. The optimisation and the feature are mutually exclusive, and the optimisation
   shipped without anyone noticing it had killed the button.

Both are fixed here rather than removed — see below.

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

- **`[Translate]` works.** `this` instead of `self`, and the locale-freeing loop now spares
  the `quests` locale tables — the only ones the button reads. Measured across the eight
  non-active locales, that keeps 19.8 MB and still frees 10.7 MB (`items` 5.6, `units` 2.9,
  `objects` 2.3), all of which really are unreachable once `loc` is assigned. A new
  **Quest Text Translations** option (default on) frees the rest and hides the button.

  The freeing decision moved to `VARIABLES_LOADED`, because `pfQuestConfig:LoadConfig()`
  runs on `ADDON_LOADED` and the option is not readable at file scope. And the button now
  hides itself whenever the data is absent, and lists only languages whose table actually
  survived — a button that is visible and does nothing is the bug, not the feature.

- **`corrections.lua` — objective data missing from the shipped database.** Seven quests
  that draw no objective pins because the upstream data has no `["obj"]` for them, most
  visibly Un'Goro's three crystal pylons (4285/4287/4288), whose entire objective is *find
  this thing* and which pointed at nothing at all. Also *Lonebrow's Journal* (1100),
  *The Torch of Retribution* (3454), *Catalogue of the Wayward* (5164) and
  *A Bijou for Zanza* (8240).

  Corrections apply only where the field is absent, so a future database that ships real
  data silently takes precedence.

  These were found by scanning for quests with no `obj` whose objective text names a known
  game object, then **checking every hit by hand** — which is the point worth recording: of
  the 20 candidates the scan produced, **13 were wrong**. *Master Ryson's All Seeing Eye*
  (6847/6848) resolves to an object standing in Alterac Valley for a quest that happens in
  the Hinterlands, and several others matched the object that *starts* the quest rather than
  the one you are sent to find. A looser earlier pass returned 315 hits and was matching
  quest-giver names and zone signposts. Bulk-applying any of that would have put confidently
  wrong pins on the map, which is worse than none.

- **`/db` no longer prints `@project-version@`.** The toc keeps the packager placeholder
  deliberately: `updatenotify.lua` bails on exactly that string, and that is what stops an
  unpackaged fork broadcasting a version into the shared `pfQuest-CAPI` addon channel and
  telling everyone else in the raid they are out of date. Giving the toc a real version
  number to tidy the display would quietly re-enable that, so the *display* is fixed
  instead — it now reads "ClassicAPI build + local patches".

- **`/db checkdb`** reports any quest in your log with no objective data. A quest with no
  `["obj"]` draws no pins and says nothing about it, which is how *Shizzle's Flyer* went
  unnoticed. Whole-entry database merging used to cause this in bulk (fixed in
  `pfQuest-octo`), but a bad pack update or a real data gap still can, so it is now
  something you can check rather than something you discover by staring at the map.
  A pure delivery quest legitimately has no objectives; anything asking you to kill or
  collect should never be listed.

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
