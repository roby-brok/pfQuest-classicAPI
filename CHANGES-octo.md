# Changes on top of brues-code/pfQuest

Everything on the `octo` branch that is not in
[brues-code/pfQuest](https://github.com/brues-code/pfQuest).

Small, because the upstream tree needed very little: the shipped databases are
**byte-identical** to the build this fork came from (verified by hashing `quests`, `units`,
`objects` and `items`), and the config surface matches exactly.

## Bugs found in the upstream tree

Every claim below was re-checked against `brues-code/pfQuest@main` on 2026-08-10 before
being offered upstream, the same audit the pfUI changelog got. Two of them did not survive
it and are struck through rather than deleted, because a withdrawn claim is worth as much
as a confirmed one.

**`database.lua` — `FormatQuestText` has no nil guard.** A quest whose locale entry has no
`O` or `D` field arrives as nil and `gsub` throws.

Six of the nine callers test the field first (`if objectives and objectives ~= ""`,
`if objtext then`, …). ~~Four~~ **three** do not — `quest.lua:721-723`, which index
`pfDB["quests"][lang][id]["T"/"O"/"D"]` straight out of the locale table to feed the
`[Translate]` button.

~~A pack replaces a whole locale entry because `patchtable` assigns rather than merges.~~
**Stale — corrected 2026-08-10.** `pfQuest-octo` stopped doing that: it merges locale
entries per-field (`patchlocale`) precisely to avoid it. The mechanism that still bites is
narrower and survives a per-field merge: **a pack quest the base database has never heard
of has no base entry to merge into**, so the pack's record is assigned whole, absent fields
included. Measured — of the 2,456 quests `pfQuest-octo` adds that are not in pfQuest's base
`enUS` table, **13 carry no `D` and 12 carry no `O`** (41908 *Raw Draenethyst Formation*,
41923-41926 the *Stone of Dreams* set, …). So the guard is load-bearing, for a reason the
original entry got wrong.

**`quest.lua` / `database.lua` — the `[Translate]` button does nothing.**

1. ~~Its `OnClick` passes the global `self`, and a 1.12 script handler has no `self`, so
   `UIDropDownMenu_Initialize` and `ToggleDropDownMenu` both received nil and the menu never
   opened.~~ **Wrong — withdrawn 2026-08-10.** `self` is not nil and not a global here. The
   handler is a closure inside `function pfQuest:AddQuestLogIntegration()` (`quest.lua:632`),
   which is called with a colon at `quest.lua:263`, so `self` is that method's implicit
   receiver captured as an upvalue: `pfQuest`, a real frame from `CreateFrame("Frame")` at
   `quest.lua:14`.

   Checked against the client's own `UIDropDownMenu.lua` (patch-9.MPQ): `pfQuest` is merely
   *unnamed*, and nothing on this path needs a name. `UIDropDownMenu_AddButton` addresses
   `DropDownList1` directly, the `UIDROPDOWNMENU_OPEN_MENU` lookups at lines 289/298 are all
   behind `if ( frame )`, and `anchorName == "cursor"` skips the one `..\"Left\"` concat that
   would have thrown on a nil name. **The menu opened.** What it lost was the checkmark on
   the selected language, since that is the part that resolves a frame by name.

   Passing `this` — the button, which *is* named `pfQuestLanguage` — is still right, and is
   kept. It is a correctness fix, not a crash fix, and it is not why the feature was dead.

2. **Confirmed, and this is the whole bug.** The locale-freeing loop in `database.lua`
   ("Free unused locale data to reduce memory") nils every non-active locale table at load,
   `quests` included. The dropdown offers exactly `pfDB.locales` — the nine languages whose
   tables it just freed — so `pfDB["quests"][lang]` is nil for every one the user can pick,
   the guard on `quest.lua:714` fails, and nothing happens. The only table that survives is
   the active locale's, which is the one already on screen.

   Introduced by `3b9b1da perf: free unused locale data after initialization (~79MB
   savings)` — upstream's own commit. The optimisation and the feature are mutually
   exclusive and the optimisation shipped without anyone noticing it had killed the button.

Fixed here rather than removed — see below.

**Five hardening fixes from the 2026-08-12 deep audit** (all present in Shagu's lineage
too, so they apply to the upstream tree as-is):

- **`tracker.lua` errored on empty objective rows** — custom servers can return nil from
  `GetQuestLogLeaderBoard` for a live objective slot, and three sites (`gsub`/concat in
  the tracker tooltip, the progress pass, the cached draw) took the text unguarded. The
  map and database sites were already safe behind their `type == "monster"` checks.
- **`browser.lua` crashed drawing a favourited quest the database no longer names** —
  `loc[id]["T"]` straight off a nil entry. Favourites are SavedVariables; a pack update
  or locale switch is enough. Rows now degrade to `#id`. Same fallback for unit/object
  rows, and for the vendor tooltip, which concatenated a nil unit name.
- **`compat/client.lua` could abort at login** — the minimap-arrow probe calls
  `strlower(v:GetModel())` on every unnamed Model child of the Minimap; a model-less
  frame from any other addon returns nil there and the whole file dies. Now type-checked.
- **`quest.lua` url-copy assumed `pfUI.chat.urlcopy` exists** — a pfUI build with the
  chat module disabled passes the `pfUI.chat` guard and crashes on the member; such
  setups now fall through to the StaticPopup path like non-pfUI users.
- None of these changes behaviour on good data; they only remove ways to error on
  imperfect data.

## Local changes

- **Tracker defaults to Current Zone** rather than All Quests, which otherwise puts every
  active quest in the tracker at once. Upstream already implements mode 5 fully — ~~four call
  sites in `tracker.lua`~~ **ten across three files** (`quest.lua` ×6, `tracker.lua` ×3,
  `route.lua` ×1), a fifth entry in the map-button menu and a `Current Zone` locale string.
  Only `config.lua:48`, the comment listing the modes, still stopped at 4, and is corrected.
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
  Reworked 2026-08-14 after its first field reports: the original message called every
  objective-less quest "draws no pins", which is wrong for delivery/talk-to quests —
  pfQuest always pins a log quest's `["end"]`, colored from accept when there are no
  leaderboards. The report now splits the list: **delivery/talk-to quests are named with
  their turn-in pin** ("turn-in pin at Baine Bloodhoof"), and only a quest with neither
  `["obj"]` nor `["end"]` — one that truly draws nothing — is red-flagged as worth
  reporting. Verified against the 2026-08-13 report round: all four flagged quests were
  talk-to/delivery with working enders, and the old wording sent players to report data
  that was never broken.

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
