> ### This repository was `pfQuest-classicAPI` until 2026-09-01
>
> **If pfQuest started misbehaving after an update, you are on the wrong build for your
> client.** The name `roby-brok/pfQuest` used to hold the pre-ClassicAPI build; the two
> swapped names. GitHub drops a rename redirect once the freed name is reused, so an
> existing `roby-brok/pfQuest` remote now pulls *this* build rather than the old one.
>
> This build is written against **ClassicAPI** and needs it — it reads quest state through
> `C_QuestLog` rather than matching quest text. Without the DLL, use
> **[roby-brok/pfQuest-legacy](https://github.com/roby-brok/pfQuest-legacy)**, which is the
> build that used to live at this address.

> ### Attribution
>
> **This is a downstream fork. Almost none of the work here is mine.**
>
> | | |
> |---|---|
> | **[Shagu](https://github.com/shagu/pfQuest)** | created pfQuest, with **txtsd** maintaining. |
> | **[brues-code / Railgun](https://github.com/brues-code/pfQuest)** | modernised it onto ClassicAPI — reading through the API instead of shipped tables (`C_QuestLog`, `C_Item`, `C_TaxiMap`, DBC-derived race/class bitmasks). **Also the author of [ClassicAPI](https://github.com/brues-code/ClassicAPI)** itself. |
> | **[The Kludge Bureau](https://github.com/The-Kludge-Bureau/pfQuest)** | the build this fork's data lineage came from. |
> | **[VMaNGOS](https://github.com/vmangos)** | the underlying quest database. |
> | **Roby_Brok** | this repo: four local patches for OctoWoW on top of Railgun's tree. |
>
> Upstream is **https://github.com/brues-code/pfQuest** — go there for the real project.
>
> 📋 **[CHANGES-octo.md](CHANGES-octo.md) — full changelog of the changes on top of upstream.**
> Local changes live on the `octo` branch. GPLv3, same as upstream; see `LICENSE`.

# pfQuest

<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/mode.png" float="right" align="right" width="25%">

pfQuest is a quest helper and database browser for World of Warcraft Vanilla (1.12), The Burning Crusade (2.4.3), and Wrath of the Lich King (3.3.5a). Accept a quest and the relevant NPCs, monsters, and objects are automatically pinned on your world map and minimap. Open the database browser to look up any unit, item, or game object in the game — or use the chat commands to build macros for tracking gathering nodes.

The goal is to provide an accurate in-game equivalent of [AoWoW](http://db.vanillagaming.org/) or [Wowhead](http://www.wowhead.com/), not a quest guide or turn-by-turn assistant. The Vanilla database is powered by [VMaNGOS](https://github.com/vmangos). The Burning Crusade version uses data from [CMaNGOS](https://github.com/cmangos) with translations from [MaNGOS Extras](https://github.com/MangosExtras).

pfQuest is the successor of [ShaguQuest](https://shagu.org/ShaguQuest/), written from scratch with no dependency on any specific map or questlog addon. It is designed to work alongside the default UI and any other addon. If you run into a conflict, please open an issue on the bugtracker.

You can check the [Latest Changes](https://github.com/The-Kludge-Bureau/pfQuest/commits/main) page to see what has changed recently.

## What this fork changes, briefly

*(as of 2026-08-10 — details and reasoning in [CHANGES-octo.md](CHANGES-octo.md))*

- **The `[Translate]` button works** — it was inert on every install; a new *Quest Text
  Translations* option (default on) keeps the quest locale data it reads, and turning it
  off frees the memory and hides the button. Offered upstream as
  [PR #2](https://github.com/brues-code/pfQuest/pull/2).
- **Tracker defaults to Current Zone** instead of every active quest at once
- **Configurable quest-database website** (defaults to OctoWoW's DB) and
  **world map / minimap node scale** options
- **Seven quests with missing objective data restored** (`corrections.lua`, each verified
  by hand); **`/db checkdb`** lists quests in your log that draw no pins
- `/db` shows a build identity instead of the raw packager placeholder
- The changelog's claims are **audited against upstream** — the ones that turned out wrong
  stay visible, struck through, rather than quietly deleted.

## Before You Install

pfQuest ships a complete database of all spawns, objects, items, and quests. The full package is approximately 80 MB and is loaded into memory once at login — memory usage is stable after that and does not grow during play.

On Vanilla clients, WoW will show a warning if an addon exceeds the default memory limit. **Before installing, set Script Memory to `0` (no limit)** in the AddOns panel of the character selection screen. This is a one-time step. A [screenshot showing where to find the setting](https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/addons-memory.png) is available if you are unsure where to look.

## Downloads

> ### ⚠️ The folder **must** be named `pfQuest`
>
> Not `pfQuest-classicAPI`, not `pfQuest-classicAPI-octo`. Two things break otherwise:
>
> 1. **WoW skips the addon.** It only loads a folder whose name matches the `.toc` inside
>    it — a folder called `pfQuest-classicAPI` containing `pfQuest.toc` never runs, with no
>    error and no entry in the addon list.
> 2. **Renaming the `.toc` will not save you.** pfQuest resolves its own path by probing a
>    fixed list of folder names:
>    ```lua
>    local tocs = { "", "-master", "-tbc", "-wotlk", "-turtle" }
>    ```
>    Anything else leaves the path unset and the icons break.
>
> Launchers with an "add custom git addon" feature name the folder after the repository, so
> they **cannot** install this correctly. Install it by hand.

**Download**

1. Grab the [latest code](https://github.com/roby-brok/pfQuest/archive/refs/heads/octo.zip) (branch `octo`)
2. Unpack it — you get a folder called `pfQuest-classicAPI-octo`
3. **Rename it to `pfQuest`**
4. Move it into `Wow-Directory\Interface\AddOns`
5. Restart WoW

**Or with git**, so updates are a `git pull`:

```sh
cd Wow-Directory/Interface/AddOns
git clone -b octo https://github.com/roby-brok/pfQuest.git pfQuest
```

The trailing `pfQuest` is what names the folder correctly.

**Requires [ClassicAPI](https://github.com/brues-code/ClassicAPI).** For a build that does
not, use [The Kludge Bureau's releases](https://github.com/The-Kludge-Bureau/pfQuest/releases/latest)
or [my legacy fork](https://github.com/roby-brok/pfQuest-legacy) instead.

### Database packs

This ships the vanilla database. For OctoWoW you also want
**[pfQuest-octo](https://github.com/roby-brok/pfQuest-octo)**, which folds the TurtleWoW
data and the Octo corrections into one pack — its folder name already matches its `.toc`,
so it installs without renaming.

## Controls

Nodes on the world map can be **clicked** to cycle through display colors, making it easy to mark progress visually.

When multiple spawn points are close together they are grouped into a single **cluster** icon to reduce clutter. Holding **\<ctrl\>** on the world map temporarily breaks clusters apart so you can see individual locations. Hovering the minimap and holding **\<ctrl\>** hides minimap nodes entirely.

| Action                                             | Result                                  |
| -------------------------------------------------- | --------------------------------------- |
| **Click** a node on the world map                  | Cycle node color                        |
| **\<Shift\>-click** a quest giver on the world map | Remove completed quest from the map     |
| Hold **\<Ctrl\>** on the world map                 | Temporarily expand clusters / hide them |
| Hover minimap + hold **\<Ctrl\>**                  | Temporarily hide all minimap nodes      |
| **\<Shift\>-drag** the minimap button              | Move the minimap button                 |
| **\<Shift\>-drag** the arrow frame                 | Move the quest arrow                    |

## Map & Minimap Nodes

<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/arrow.png" width="35.8%" align="left">
<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/minimap-nodes.png" width="59.25%">
<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/map-quests.png" width="55.35%" align="left">
<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/map-spawnpoints.png" width="39.65%">

Quest objectives, spawn points, and points of interest are plotted directly on the world map and minimap. The directional arrow (top left) points toward your nearest active objective and updates as you move. Nodes are color-coded by type and quest state — available quests, objectives in progress, and turn-in locations each use distinct icons.

## Auto-Tracking

<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/map-autotrack.png" float="right" align="right" width="30%">

pfQuest supports four tracking modes that control how quest objectives are shown on the map. The active mode is selected from the dropdown menu in the top-right corner of the world map.

#### All Quests

Every quest in your log is automatically shown and updated on the map. This is the default mode.

#### Tracked Quests

Only quests you have manually tracked via Shift-Click in the questlog are shown and updated.

#### Manual Selection

Only quests you have explicitly shown using the **Show** button in the questlog are displayed. Completed objectives are still automatically removed from the map.

#### Hide Quests

Same as Manual Selection, but quest givers are also hidden and completed objectives remain on the map. This mode makes no changes to existing map nodes.

## Database Browser

<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/browser-spawn.png" align="left" width="30%">
<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/browser-quests.png" align="left" width="30%">
<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/browser-items.png" align="center" width="33%">

The database browser lets you search and bookmark units, game objects, items, and quests from the full pfQuest database. Open it by clicking the pfQuest minimap icon or with `/db show`. Each tab shows up to 100 results — use the scroll wheel or the up/down arrows to navigate. If an entry is marked with `[?]`, that object or unit is not currently available on your realm.

## Questlog Integration

### Questlinks

<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/questlink.png" float="right" align="right" width="30%">

On servers that support questlinks, Shift-clicking a selected quest in the questlog inserts a clickable questlink into chat. These links are compatible with those produced by [ShaguQuest](https://shagu.org/ShaguQuest/), [Questie](https://github.com/AeroScripts/QuestieDev), and [QuestLink](http://addons.us.to/addon/questlink-0). Links sent between pfQuest users are locale-independent and use the Quest ID directly.

Some servers (e.g. Kronos) block questlinks entirely. In that case, disable the questlink feature in the pfQuest settings and the quest name will be inserted as plain text instead.

Hovering a questlink displays a tooltip showing your current progress, the objective text, the full quest description, the suggested level, and the minimum required level.

### Questlog Buttons

<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/questlog-integration.png" align="left" width="300">

Each quest in the questlog has four additional buttons for manual map control. These buttons only affect nodes placed by pfQuest's quest tracking — they do not touch anything you have placed manually through the database browser.

**Show** — Adds the quest objectives for the selected quest to the map.

**Hide** — Removes the selected quest from the map.

**Clean** — Removes all nodes placed by pfQuest from the map.

**Reset** — Restores the default node visibility to match the current auto-tracking mode (e.g. re-shows all quests if the mode is set to "All Quests").

## Chat / Macro CLI

<img src="https://raw.githubusercontent.com/The-Kludge-Bureau/pfQuest/main/_img/chat-cli.png">

All pfQuest features are accessible from chat or macros using `/db`. For example, `/db object Iron Deposit` plots all Iron Deposit locations on the map, and `/db track mines 150 225` shows only mines that require a Mining skill between 150 and 225. The commands `/shagu`, `/pfquest`, and `/pfdb` are all aliases for `/db`.

### General

```
/db lock                Lock/unlock the map tracker position
/db tracker             Show the map tracker
/db journal             Show the quest journal
/db arrow               Toggle the quest arrow
/db show                Open the database browser
/db config              Open the settings panel
/db locale              Display the active addon locales
/db scan                Scan the server for custom items
/db debug               Toggle debug output
```

### Questing

```
/db reset               Reload all quest nodes on the map
/db query               Query the server for completed quests
/db clean               Remove all database search results from the map
```

### Database Search

```
/db unit <name>         Find spawn locations for a unit (e.g. Thrall)
/db object <name>       Find locations for a game object (e.g. Iron Deposit)
/db item <name>         Find units and objects that drop an item (e.g. Runecloth)
/db vendor <name>       Find vendors that sell a specific item (e.g. Jagged Arrow)
/db quest <name>        Search for a quest by name
```

### Tracking Lists

Tracking lists let you pin all instances of a category on the map at once.

```
/db track               Show all available tracking lists
/db track clean         Remove all tracked list nodes from the map
/db track <list>        Show all objects in <list> on the map
/db track <list> clean  Remove all objects in <list> from the map
```

The `mines` and `herbs` lists support an optional skill range and an `auto` shortcut that uses your current skill level:

```
/db track mines         Show all mines
/db track mines auto    Show mines within your current skill range
/db track mines 50 150  Show mines requiring skill 50–150
/db track mines clean   Remove all mine nodes from the map
```

Available tracking lists: `auctioneer`, `banker`, `battlemaster`, `chests`, `fish`, `flight`, `herbs`, `innkeeper`, `mailbox`, `meetingstone`, `mines`, `rares`, `repair`, `spirithealer`, `stablemaster`, `vendor`

## Reporting bugs

**Check whether it happens on [upstream](https://github.com/brues-code/pfQuest) first.**
This fork is a thin layer on top, so almost every bug belongs in
[brues-code's tracker](https://github.com/brues-code/pfQuest/issues) — reporting it there
fixes it for everyone rather than just for OctoWoW.

Open an issue [here](https://github.com/roby-brok/pfQuest/issues) only if it
concerns something listed in [CHANGES-octo.md](CHANGES-octo.md), or if it is about the
OctoWoW database itself — in which case
[pfQuest-octo](https://github.com/roby-brok/pfQuest-octo/issues) is the right place.

Useful things to include: the quest or NPC ID, whether a clean config still shows it, what
other addons are loaded, and your client language.

`/db checkdb` lists any quest in your log that has no objective data — worth running before
reporting a missing pin, since it distinguishes "the database is wrong" from "this quest
legitimately has no objectives".

## Supporting the authors

[Shagu](https://github.com/sponsors/shagu) wrote pfQuest, [The Kludge
Bureau](https://github.com/The-Kludge-Bureau/pfQuest) continued it, and
[brues-code](https://buymeacoffee.com/brues) wrote the ClassicAPI Edition and the
ClassicAPI DLL this build depends on. They come first.

If the OctoWoW-specific work here has been useful, mine is
[here](https://buymeacoffee.com/robybrok).
