# Questfarer

A step-by-step leveling guide addon for **WoW Forever** (client 1.60.1, interface 16001).
It shows one step at a time and automatically moves on when the step is done.

**This is a beta (0.9.0-beta).** Both routes have been checked against the quest data and simulated, but not
fully played through yet, and the Horde guides are the newest. Reports of wrong steps help a lot.

## Sharing your data (optional)

Questfarer can count how you really play, so the route and its time estimates can be fixed with real numbers.
It is **off** until you turn on "Collect data to share" (settings window, Data page, or `/qf share`).

- **What is counted**, per level: fights and their length, downtime between fights (up to 3 minutes), kills,
  kill XP, quest XP, quests turned in, deaths, and fight length by the level difference to your target.
- **What the export also holds**: your level and guide times, and the recorder's quest, NPC, trainer and flight
  path data (where things really were). The recorder's route log is left out.
- **What it never holds**: character, realm or player names. Characters are told apart by a random ID.
- **Nothing is sent by itself.** An addon can't send data anywhere. Click "Make export text" (or `/qf export`),
  copy the text and post it in the [Questfarer Discord](https://discord.gg/nqBc8HEcpW) (`#data-contributions`) or the "Data contribution" form on
  GitHub. Both are public. Got the addon from a friend? Then just send the text to them, for example as a Discord
  message (Discord turns long text into a file by itself).
- "Delete collected data" on the Data page forgets the counts.

## Installation

1. Close the game.
2. Unzip the file and copy the `Questfarer` folder to:

   ```
   World of Warcraft\_forever_\Interface\AddOns\Questfarer
   ```

   The folder name must be exactly `Questfarer` (same as the `.toc` file), with the `.toc` file directly inside
   it, not in an extra folder.
3. Start the game and make sure Questfarer is ticked in the AddOns list on the character screen.

When updating, delete the old `Questfarer` folder first and restart the game fully (a `/reload` doesn't pick up
new files). Your settings and progress are kept.

Questfarer was called ForeverGuide up to 0.7.0. If you have a `ForeverGuide` folder in AddOns, delete it. The old
settings don't carry over, but the guide finds your place again from your quests and level, and `/fg` still works.

## Features

- **Settings window**: every setting and every command in one tabbed window (see [The settings window](#the-settings-window)).
  Open it with the gear icon on the guide window, `/qf options`, or Options > AddOns > Questfarer.
- **Guide window**: a dark panel with your level and XP, a card for the current step in the colour of its type (type
  label, step text, location and distance, objectives with check marks), the next steps underneath, and a clear
  **Next** button. The collapse button (-) leaves the title bar and the current step on one line.
- **Step by step**: accept quest → complete → turn in, with NPC, coordinates and distance.
- **Auto-advance**: moves to the next step when the quest is accepted, completed or turned in, when you reach the right level, and so on.
- **Adapts to your character**: install it at any level, or play a while with it turned off. At login it reads
  your finished quests, quest log and level, and jumps to the right guide and step. It skips quests you have
  done, quests that have turned gray, quests whose earlier part you missed, and turn-ins for quests you don't
  have. Gray quests are re-checked on every level-up. `/qf resync` does it on demand.
- **Skipped by mistake?** If you click Next past a quest that a later step needs (for example a
  quest that unlocks the next one in a chain), that step says which earlier step you skipped.
  `/qf fix` goes back to it.
- **Elite quests are optional**: their steps say so. Click Next if you can't solo one or find a group, and the
  rest of that quest and the quests that follow it are skipped too.
- **Class quests** (Alliance): the quests that teach something - a hunter's pet, a warlock's demons, druid forms,
  shaman totems, warrior stances, Redemption, rogue poisons - are short side guides. When you reach the level, a
  bar in the guide window offers the next one. Click it to start, right-click to hide it. When the class quest is
  done, or you click the bar to stop, the guide goes back to the step of the route you left. `/qf class` lists them.
- **Failed quests**: when an escort dies or a timer runs out, the step says so in red. Abandon the quest and the
  guide goes back to the step where you take it again.
- **Hearthstone**: a hearth step shows how many minutes are left on the cooldown.
- **Quest item and target buttons**: two buttons follow the current step. One uses the step's quest item, the other
  targets its NPC or mob and puts a star over it, so it is easy to spot. Drag the strip above them to move them, and set keys under Options > Keybindings > AddOns.
  The game doesn't let addons change these buttons in combat, so they update when the fight is over.
- **Objective areas**: orange dots on the world map and minimap show where the current step's mobs, items and
  objects are.
- **Vendors**: opening a vendor sells your gray items and repairs your gear. It never buys anything for you.
  Hold **Shift** while opening the vendor to skip both. Each part can be turned off in the settings.
- **Full bags and quest log**: a bar in the guide window warns you before you run out of room.
- **Talent suggestions**: a bar shows where your next talent point could go, from one solo leveling plan per class.
  You spend the point yourself. `/qf talents` lists the plan. Talents that don't exist on Forever are skipped.
- **Gear upgrades**: the best quest reward for your class is marked "UP", and a bar offers upgrades from your bags
  (click to equip, right-click to ignore). This is a rough estimate from one stat weighting per class.
- **Leveling times**: the addon measures how long each level takes, not counting time spent away from the keyboard.
  `/qf time` shows it.
- **Travel journal**: the guide window reads like a journal, with your name and a title that grows with your level
  ("Lundgren, Wayfarer") and how many days you have been on the road. New lands, dungeons, titles and seals get a
  line in the journal, and a small note above the guide window that you can click to read the page. The Travels page
  counts miles, flights, quests and more, and shows the 16 seals. `/qf journal` opens it.
- **Guide arrow**: an on-screen arrow points to the current step and shows the distance (drag it to move it,
  right-click it for the settings). Blizzard's map pin is set for every step too.
- **Checkpoints**: when the step is in another zone, the arrow (blue) first points to where you cross into
  the next zone - a road, a pass, a tunnel, a bridge - instead of straight through the mountains. Steps can
  have their own checkpoints too. It learns from your runs: where you really cross between zones, and the
  way you ran when you had to go around something. `/qf cp` skips a checkpoint, `/qf paths` shows what it
  has learned, `/qf checkpoints` turns it off. The built-in zone crossings are estimates; the ones it learns
  replace them.
- **Auto-accept / auto-turn-in**: only for quests that are in the guide. If a quest has several rewards, you choose.
- **Best reward to sell**: when you choose a quest reward, the one that sells to a vendor for the most gets a gold
  coin on its icon and a tooltip line, and chat says what it's worth.
- **Flight paths**: opens the flight master automatically, learns flight paths and flies to the right place on `fly` steps.
- **Trainer**: knows exactly which spells you can train right now (checked against your spellbook), so you can decide if the trip is worth it.
  - The purple bar shows e.g. "3 new spells (1s 20c) - Lyria Du Lac". Hover it for the full list with ranks, costs and what comes at the next level. Click it for a waypoint to the nearest trainer.
  - On level-up, chat lists the new spells. `/qf spells` prints the list any time.
  - The **Train all** button buys every spell while the trainer window is open (`/qf train` does it automatically).
- Hold **Shift** while talking to an NPC to pause the automation for that NPC.
- **Recorder** (on by default): while you play it saves what really happens on Forever - who gives and takes
  each quest and where, where objective counters went up, trainers with their spell lists and costs, and flight
  paths. `Tools/check_recorded.py` compares that with the guide data and lists anything that needs fixing.

## The settings window

Changes take effect at once, and settings changed from chat show up in the window right away. The window remembers
its position and the last page. Actions that can't be undone ask you to click a second time.

| Page | What is on it |
|---|---|
| **Guide** | Current guide, step and progress; previous/next step, Find my step, Fix skipped step, Restart guide; a searchable list of the guides you can use |
| **Automation** | Accept quests, turn in quests, dialogue options, flights, train all, sell gray items, repair |
| **Navigation** | Guide arrow, checkpoints, map pin, objective areas; skip the current checkpoint; learned paths and resetting them |
| **Helpers** | Quest item and target buttons with their key bindings; full bags warning, trainer reminder, best reward, talent suggestions, gear upgrades; clear ignored gear |
| **Appearance** | Show, lock and collapse the window; size, width, opacity, upcoming steps; reset the position of the guide window, the arrow and the item buttons |
| **Character** | Level times, talent plan, trainable spells; your class quests (start, stop, hide, show again) |
| **Journal** | Journal notes on or off; the important days of the road, newest first |
| **Travels** | Days, time, miles, flights, flight paths, hearthstones, quests, lands, dungeons and deaths; the seals |
| **Data** | Recorder, debug messages, recorded stats, combat log at login, sharing your data (collect, export, delete), your position, map bounds; reset all settings to their defaults |
| **About** | Version, what the addon does, all chat commands, credits and licence |

"Reset all settings" keeps what the addon has learned or measured: learned paths, map bounds, level times and your
progress in the guides.

## Commands

Everything here is also in the settings window.

| Command | What it does |
|---|---|
| `/qf` | show/hide the window |
| `/qf options` | open the settings window |
| `/qf help` | list all commands |
| `/qf skip` / `/qf back` | next / previous step |
| `/qf fix` | go back to a step you skipped by mistake that the current step needs |
| `/qf class [nr\|stop]` | list your class quests, start one, or stop and go back to the route |
| `/qf time` | how long your levels have taken |
| `/qf journal` | open the travel journal |
| `/qf talents` | your talent plan |
| `/qf cp` | skip the arrow's current checkpoint |
| `/qf paths [reset]` | learned zone crossings and paths (reset forgets them) |
| `/qf guides`, `/qf load <nr>` | list guides / switch to one and stay in it |
| `/qf reset` | restart the current guide |
| `/qf resync` | jump to the right step from your quests (a guide you loaded stays) |
| `/qf resync all` | pick the guide by level again |
| `/qf spells` | list the spells you can train right now |
| `/qf where` | print your position (map ID + x/y) |
| `/qf bounds [map IDs]` | print the world bounds of the current map or of the given maps (to add Forever's new zones, such as Mount Hyjal, to the route tools) |
| `/qf recstats` | show what the recorder has saved so far |
| `/qf export` | make the text for sharing your data (see [Sharing your data](#sharing-your-data-optional)) |
| `/qf accept`, `turnin`, `flight`, `gossip`, `arrow`, `checkpoints`, `waypoint`, `train`, `reminder`, `reward`, `record`, `combatlog`, `share`, `lock`, `debug` | toggle on/off (`combatlog`: start the game's combat log with advanced logging at login, off by default; `share`: collect data to share, off by default) |
| `/qf scale 1.2` | window size |

## Guides so far

Only the start of the route is race-specific: each start area has its own guides up to about level 12-21, and
from there every race continues on its faction's shared guides ("Alliance ..." or "Horde ..."). At login the
addon picks your faction's and race's guide for your level, so a Dwarf, Gnome or Night Elf never ends up in the
Human start zones, and a Tauren never in Durotar.

**Night Elf** (Night Elf only):
- Night Elf 1-6 Shadowglen and 6-11 Teldrassil (class sigils, Forever's new quests, training in Shadowglen,
  Dolanaar and Darnassus, the Rut'theran Village flight path)
- Night Elf 11-19: Darkshore 11-14 (boat from Rut'theran Village), Loch Modan 14-16 (boat to Menethil Harbor),
  Darkshore 16-19 (three short parts), then the shared guides from Westfall (16-19, part 2).

**Dwarf & Gnome** (both races start in Coldridge Valley on Forever):
- Dwarf & Gnome 1-6 Coldridge Valley and 6-12 Dun Morogh (class letters, including Forever's Gnome priest and
  Dwarf shaman letters, Forever's new quests, training in Anvilmar and Kharanos, the Kharanos hearthstone)
- Dwarf & Gnome 11-19: Darkshore 11-14 (boat from Menethil Harbor), Loch Modan 14-17, Westfall 17-19, then the
  shared guides from Redridge Mountains (19-20; the shared Westfall part is skipped, its quests are done).

**Human and shared:**
- Human 1-6 Northshire (including Forever's new quests and the Human hunter class letter)
- Human 6-11 Elwynn Forest (including Forever's new quests; skips the slow ones and leaves for Westfall at about
  level 11, where questing gives more XP per hour; ends with the Sentinel Hill flight path)
- Alliance 10-14 Westfall (including Forever's new quests from Alba Fairmoon and Ozwin Ironsprocket,
  and a quick trip to Stormwind for its flight path and class training)
- Alliance 11-60 (every Alliance race from here on, 94 guides): the zones hop back and forth where the quests
  fit your level best:
  - 11-30: Dun Morogh, Loch Modan, Westfall, Redridge, Duskwood, Darkshore, Ashenvale, Wetlands, then
    Redridge, Wetlands and Duskwood again.
  - 30-46: Stranglethorn Vale (several parts), Hillsbrad Foothills, Ashenvale, Desolace, Forever's Riverglades
    (several parts), Badlands, Swamp of Sorrows, Dustwallow Marsh, Arathi Highlands, Feralas and Tanaris.
  - 46-60: Searing Gorge, The Hinterlands, Tanaris, Azshara, Felwood, Blasted Lands, Burning Steppes, Western
    and Eastern Plaguelands, Un'Goro Crater, Silithus, Winterspring and Forever's Mount Hyjal (from about 53); the
    route ends in Azshara and Mount Hyjal.
  Each guide ends with the trip to the next one (hearthstone, flight, boat or running directions). Some guides
  start with "kill monsters around here until level N": Classic has too few fitting quests in places, so a
  short grind comes first. Forever's Shen'dralas isn't in the route.

**Skyborne** (Forever's new race, both factions start on Zephras Isle):
- Skyborne (Alliance) 1-12 Zephras Isle (class quests, training in the island's three camps, the Shen'dar Village
  hearthstone), then the zeppelin to Dalaran, the Skyborne portal to Stormwind and the shared Alliance guides from
  Dun Morogh (11-14).
- Skyborne (Horde) 1-13 Zephras Isle, then the airship to Skywatcher Plateau in Mulgore, Thrall in Orgrimmar and
  the shared Horde guides from Tirisfal Glades (11-14).

**Orc & Troll** (both races start in the Valley of Trials on Forever):
- Orc & Troll 1-6 Valley of Trials and 6-12 Durotar (class letters, training in the Valley, Razor Hill and
  Orgrimmar, the Razor Hill hearthstone and the Orgrimmar flight path), then the shared Horde guides.

**Tauren:**
- Tauren 1-6 Camp Narache and 6-12 Mulgore (class letters, training in Camp Narache, Bloodhoof Village and Thunder
  Bluff, the Bloodhoof hearthstone and the Thunder Bluff flight path)
- Tauren 12-22: The Barrens (two parts, with a short grind to 22 at the end so the shared quests fit), then the
  shared Horde guides from Hillsbrad Foothills (21-23).

**Undead** (including Forever's Undead paladins):
- Undead 1-6 Deathknell and 6-13 Tirisfal Glades (class letters, training in Deathknell, Brill and Undercity, the
  Brill hearthstone and the Undercity flight path)
- Undead 13-22: Silverpine Forest 13-14 and The Barrens 15-22 (a short grind to 22 at the end), then the shared
  Horde guides from Hillsbrad Foothills (21-23).

**Horde shared:**
- Horde 11-60 (every Horde race from here on, 78 guides), with the zeppelins between Orgrimmar, Undercity and
  Grom'gol and the boats from Ratchet and Steamwheedle Port:
  - 11-29: Tirisfal Glades, Silverpine Forest, The Barrens, Hillsbrad Foothills, Ashenvale, Stonetalon
    Mountains and Mulgore.
  - 29-46: Thousand Needles, Stranglethorn Vale (several parts), Desolace, Arathi Highlands, Dustwallow Marsh,
    Forever's Riverglades, Badlands, Feralas, Swamp of Sorrows and Tanaris.
  - 46-60: Azshara, Searing Gorge, Blasted Lands, The Hinterlands, Felwood, Un'Goro Crater, Silithus,
    Winterspring, Western and Eastern Plaguelands and Forever's Mount Hyjal (five parts from about 54); the last
    level is ground in Silithus.

Quests only come once their monsters are at most **one level above you** below level 29 and at most **two
levels above you** from level 29 on (a relaxed pace: easier fights, a bit more travel and short grind steps
between zones), and quests with elite monsters wait until you are one to three levels above the elite (more at
higher levels). The routes only pass a class trainer now and then, so watch the addon's training reminder and
visit your trainer when it says new spells are waiting. Within that rule the routes are optimised for XP per hour: a quest is only in the guide if it levels you faster than grinding
or, once you are high enough, faster than moving on to the next zone, and you leave a zone as soon as another
one is better. Where nothing beats grinding, a guide says so ("kill monsters around here until level N"). A few quests are
taken in one zone and turned in in a later one, where the route passes the turn-in NPC anyway.
The timings are estimates and haven't been checked in game yet, the levels 30+ part least of all; the
Riverglades and Zephras Isle guides use estimated map bounds (Forever's new zones aren't in the map data yet), and
the Horde and Skyborne guides are the newest and least tested.

The guide files in `Guides/` are **generated**. Each guide is written as a short route file in
`Tools/routes/` (just the order of quest IDs plus train/level/flight steps), and `Tools/build_guides.py` fills in
quest titles, NPCs, coordinates and objective text from the QuestieDB Forever database and checks the route
(prerequisites, level requirements, race/class filters, accept before turn-in). See `Tools/README.md`.

Coordinates are on Forever's maps (Elwynn Forest is map ID **1429**, Classic IDs, not retail).

**Not included yet**:
- Quests the planner judged too slow (listed in `Tools/routes/drafts/*.route` and `Tools/reports/unrouted.txt`).
- Forever's Shen'dralas (no Horde hub, and the planner never picked it for Alliance).
- Quests with IDs 78000-85999 (Season of Discovery's era; Forever's database carries them, but they aren't
  confirmed on Forever).
- Forever's new dungeons (the guides are for solo questing).

## Writing / fixing guides

Edit the route in `Tools/routes/`, then run `python -I Tools/build_guides.py`. Route lines look like:

```
accept 783
turnin 783 || Marshal McBride is inside the abbey.
complete 7, 33 | Kill Kobold Vermin north of the abbey and wolves for Tough Wolf Meat.
train Northshire
level 2 @48.5,36.5 | kill kobolds/wolves around the abbey
getfp Sentinel Hill @56.5,52.6,1436 {npc=Thor}
```

`| text` replaces the step text, `|| tip` adds a tip line, `@x,y[,map]` overrides the coordinates and
`{class=WARRIOR}` adds a filter (class/race filters for class/race quests are added automatically).

**Tip:** turn on `/qf debug`. It prints the quest ID, title, NPC and position in chat every time you open a quest.
`/qf where` gives your position.

## License

Questfarer is free software, released under the **GNU General Public License v3** (see `LICENSE.md`).
You may share and change it, but copies and changed versions must stay GPLv3 and keep their source open.

## Credits

- **Quest, NPC, object and item data** (names, quest givers, spawn coordinates, objectives, quest XP) comes from
  [QuestieDB](https://github.com/Questie/QuestieDB) (Forever flavor), built by the Questie team and contributors.
  It is used under the GPLv3 terms the Questie team allows in QuestieDB's `LICENSE.md`. Questfarer is not
  made by or affiliated with the Questie team.
- **Class spell lists** in `Data/Spells/` come from [What's Training?](https://www.curseforge.com/wow/addons/whats-training)
  by Sveng, used under the MIT License (see `Data/LICENSE-WhatsTraining.txt`). Forever uses the Classic Era spell
  list. Costs are Classic prices and may differ slightly on Forever.

## Reporting a problem

Type `/console scriptErrors 1` so Lua errors are shown in game. When a step is wrong, note the guide name, the
step text and where you were, and post it in `#bug-reports` on the [Questfarer Discord](https://discord.gg/nqBc8HEcpW)
or open a "Wrong step or bug" issue on the GitHub page (copy the error text too if there was one). Typing `/qf debug` prints the quest ID, title, NPC and position every time you open a quest,
which helps a lot in a report.
