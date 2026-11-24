# Questfarer tools

Offline tools that build the guide files from exact WoW Forever data, and check them against what you
see in-game. They need Python 3. Run them with `python -I` from this folder.

## Pipeline

```
QuestieDB-Forever.zip ──decode_questiedb.py──> db/*.json
zone + level band ──plan_zone.py──> routes/drafts/<zone>.route   (review, then move to routes/ + ORDER)
current state ──compare_zones.py──> which zone gives the most XP/h next
Westfall on ──auto_chain.py──> routes/*.route + ORDER   (compare, plan, travel, repeat)
routes/*.route + db/*.json ──build_guides.py──> ../Questfarer/Guides/*.lua + Guides.xml  (+ reports/unrouted.txt)
in-game recorder (SavedVariables) ──check_recorded.py──> reports/recorded_diff.txt
```

1. **`decode_questiedb.py <zip> db`** decodes QuestieDB's baked Forever release (quests, NPCs, objects, items)
   into JSON. Coordinates are already converted to Forever's maps, and static corrections are already applied.
   Run it again when a new QuestieDB release comes out:
   `python -I decode_questiedb.py questiedb-forever-release/QuestieDB-Forever.zip db`
2. **`build_guides.py`** compiles every route listed in `routes/ORDER`. For each step it looks up the quest title,
   the quest giver or turn-in NPC/object nearest to the previous step, and for `complete` steps the spot where the
   objectives' mobs, items and objects are densest (preferring a spot that covers every objective). It checks:
   - prerequisites (`preQuestSingle` / `preQuestGroup`) are turned in earlier,
   - exclusive quests aren't both taken,
   - every turn-in has an accept, and nothing is accepted twice,
   - required level vs. the route's `level` steps,
   - race/class masks. Class and race filters are added automatically.

   Two corrections are applied when the data loads, so the compiler and the planners all see them:
   `REQUIRED_LEVEL_OVERRIDES` (required levels of Forever's Mount Hyjal quests, which the DB lacks; reported by one
   source, not confirmed) and quest 5244, which either of its two mutually exclusive openers (5249, 5250) unlocks.

   Errors stop the build. `--check` validates without writing. `reports/unrouted.txt` lists quests on the
   guides' maps that fit the race and level range but aren't in any route (`[Forever]` marks Forever-only quests).
   Accept steps also carry `qlevel` and `pre`/`preall` (prerequisites). The addon's `Adapt.lua` uses them to work
   out where a character is when the addon is installed mid-way.
   The build also estimates the level at the end of every guide: quest XP plus kill XP (kill counts from the
   objective text, Classic mob-XP rules, drop rate and extra-kill factors). It is an estimate until recorder data
   exists. `Guides/Guides.xml` (the load list in the TOC) is regenerated too, so new guides load automatically.
3. **`plan_zone.py --map <uiMapID> --levels <lo> <hi> [--name ..] [--file ..] [--out routes/drafts/X.route]`**
   drafts a time-optimised route for one zone. It replays `routes/ORDER` to know what is done, the level and the
   position (or `--fresh --start x,y` for a new character). Then it picks the zone's quests for the race and level
   band and orders them greedily: everything at the current hub first, then the nearest objective area or turn-in,
   with distances in real yards. For objectives with several spawn areas it uses the one nearest to you, and the
   draft writes that spot as `@x,y` so the guide uses the same one. It adds `level` steps when the remaining quests
   need it.

   **XP per hour.** Every step costs time: running (7 yards/s), talking (6 s), the objectives (about 20 s per kill
   of a same-level mob, scaled by `kill_factor`: +1 level x1.16, +2 x1.40, +3 x1.72, -1 x0.9, -2 x0.8, so
   quests on mobs above you cost more and the same quest gets cheaper once you outlevel it; the kill count is estimated from the objective text and drop rates, 25 s per object) and grinding when a
   level is missing. The planner then takes each quest out of the order in turn (quests that need it go too, so a
   chain is judged as a whole) and computes its extra XP per extra minute. Quests below the bar are dropped,
   worst first, and the notes list them with their rates. The bar is grinding (about 80 s per kill of a same-level mob, `GRIND_SEC_PER_KILL`; it was 30 s
   until 2026-11-17, which made grinding look too good and dropped many quests,
   scaled the same way, on the best mobs from 3 below to 1 above you), times `--min-rate`, default 1.0), or, once you are at `--next-level`, the questing rate of the next zone
   (`--next-rate`, XP/h, measured by running the planner on that zone). That is what makes a guide leave a zone
   early instead of finishing it. `--end x,y[,map]` is where you leave the zone, so the run there counts too.
   These timings are estimates, not measurements: compare them with real play and adjust the constants at the top
   of `plan_zone.py`.

   **Rules** (constants at the top of `plan_zone.py`):
   - *Mob levels*: a quest waits until its kill targets (or the easiest mob that drops its items) are at most
     `MOB_GAP` = 1 level above you, counting each mob at its top level (`build_guides.solo_level`). A quest with
     fighting also waits until its own level is at most 1 above you, and an escort until you are its level.
     The build warns when a route breaks this.
   - *Elites*: group content unless they are well below the zone's top level and not above your level, and
     a quest that kills an elite (or needs an item only elites drop) waits until you are 3 levels above it
     (1-2 for the small elites in start areas; `build_guides.elite_level` / `elite_gap`). NPCs friendly to your
     faction and objectives where you only talk to someone don't count as group elites.
   - *Mob camps*: a quest turned in at an object, or needing one, that stands in a mob camp (Sven's mound in
     the Defias orchard in Duskwood) waits as if the camp's mobs were kill targets. A camp is `CAMP_MIN` (4)
     hostile spawns within `CAMP_RADIUS` (2 map %), and its level is their median (`build_guides.camp_level`).
     Only Classic creatures count (id below 200000: the DB also has leaked Season of Discovery spawns), and a
     camp more than 3 levels above the quest is ignored as noise.
   - *Required level*: some Forever quests have none in the DB; quest level - 5 is assumed (the usual gap).
   - *No XP value*: skipped unless another quest needs it. These are mostly other Classic versions' content
     that leaked into the data (Season of Discovery "Duskwood Mission" and so on).
   - *Text-only tasks*: quests whose kill/escort/destroy task exists only as text (no place in the DB) are
     skipped unless `--include`d; escorts cost a flat 5 minutes (`ESCORT_SECONDS`). A quest with no objectives
     in the DB that is `TEXT_LEVEL_GAP` (8) or more levels above you is skipped too, unless it's a delivery
     ("Deliver/Return/Bring ... to ...").
   - *Text-only tasks turned in where they started* ("Fill the gourd at the waterfall", "Find the kittens"): the
     giver is also the turn-in NPC, so the task is somewhere the DB doesn't say; skipped (`self_task`). So are
     reputation goals ("Raise your reputation with ... to Neutral", `REPUTATION_GOAL`). Quests with an
     exploration trigger (`triggerEnd`) have a place and are kept.
   - *Grind steps* (`auto_chain.py`): placed at the nearest cluster of 8+ normal hostile mobs from 3 below to 1 above
     you (NPCs without faction data or with zone-scaled levels don't count), named in the step text.
   - *Grinding*: at most a quarter of a level (`MAX_GRIND`) to unlock quests; more than that ends the zone.
   - *Shared areas* (`joint_spot`): two quests whose objectives can be done in one go (every objective of both has
     spawns within `JOINT_RADIUS`, and each quest spawns for at least `JOINT_COVER` of the kills it needs) are done
     together: the planner puts an objective off while a quest you can take now shares its area, then does both
     there in one `complete` line (wolves and spiders in Duskwood). The plan is made with and without this and the
     faster one is kept (`--no-colocate` turns it off).
   - *On the way* (`build_guides.py`, `Compiler.on_the_way`): when the run to a step passes at least
     `ONWAY_MIN_SPAWNS` spawns of a quest whose objectives come later in the guide (within `ONWAY_YARDS` of the
     straight line), that step gets a tip to do them as you go.
   - *Dungeons* (`inside_dungeon`): a quest is skipped when its objective text names a dungeon (`DUNGEON_TEXT`) or
     a kill target has no open-world spawns. `DUNGEON_TEXT_OK` lists quests that only mention one.
   - *Reputation* (`needs_reputation`): a quest that needs standing with a faction outside `HOME_FACTIONS` is
     skipped, because a leveling character doesn't have it (Argent Dawn, Bloodsail, Silverwing...).
   - *Hearthstone* (`auto_chain.py`, `HEARTH_COOLDOWN`): a trip only uses the hearthstone when at least 65 minutes
     of simulated play have passed since the last use (60 minutes of cooldown, assumed from Classic, plus a margin).
     `simulate.py` reports how many uses still come too early.
   - `NEVER_PLAN`: quests that can't be timed or aren't confirmed on Forever (Green Hills pages, the Pendant of
     Myzrael world drop, Arathi Basin reputation, a few Season of Discovery quests).
   - Map 2548 (Riverglades, new on Forever) has no map bounds in the data; `ESTIMATED_BOUNDS` places it from
     the wiki's neighbours with a guessed size.

   The notes at the top also list what it skipped and why: class quests, quests turned in outside the zone,
   group elites, dungeon objectives, faction-specific QuestieDB corrections and exclusive variants. `--box x1,y1,x2,y2` limits the plan to part of a
   map (Northshire is `43,25,60,50` on Elwynn). Quests left in the log by earlier routes are finished where they
   belong. Add trips to other zones (Stormwind and so on), training, class quests and flight steps by hand, then
   move the file into `routes/` and add it to `routes/ORDER`. Use `--include`/`--exclude` to force quests in or
   out, and `--upto` to plan from an earlier point in the chain.

   `--level L` starts the plan at level L at least (for a hand-written grind step before the zone).

   Northshire and Elwynn were planned by hand with:
   - Northshire: `--map 1429 --levels 1 6 --fresh --start 48.2,42.9 --box 43,25,60,50 --end 45.6,47.7`
   - Elwynn: `--map 1429 --levels 5 12 --upto Human_Northshire.route --end 56.5,52.6,1436 --next-rate 20000 --next-level 10`

   Everything from Westfall on is written by `auto_chain.py` (below).

   **`compare_zones.py [--upto X.route] [--level L] [--zones ..]`** runs the planner on every Alliance zone from
   the end of the chain (or `--upto`) and ranks them by XP/h over the next 90 minutes, trip included. Trips use
   only the flight paths the routes have picked up, the boats (Theramore-Menethil, Forever's Stormwind
   Harbor-Auberdine, Ratchet-Booty Bay, Steamwheedle Port-Powderfuse Port and the one-way ship loop Auberdine >
   Menethil Harbor > Southshore > Auberdine, `ONE_WAY_BOATS`; the direction is reported, not confirmed by Blizzard, and
   `STAY_ABOARD_SECONDS` is an estimate), 20 yards/s effective flight speed (calibrated on Forever flight times)
   and running along `WALK`, a graph of zones you can walk between (plus the Deeprun Tram), so a trip doesn't cut
   through mountains. A zone that runs out of quests within 90 minutes is charged the trip back out as well, and
   the rest of the window counts at the grinding rate, so short or far-away zones don't win just for that.

   **`auto_chain.py [--target 37]`** builds the chain from Westfall on: compare the zones, take the best (or
   grind a level first when nothing beats grinding), plan it against the runner-up's rate, write the route with
   a generated header (no `races` line, so the guide is open to every Alliance race), add the zone's flight path and hearthstone (hearthstone only in zones you stay in for an
   hour or more; both go first when the hub is within 500 yards of where the zone starts, else just before the
   first step near the hub, so there's no detour), and write the trip there into the previous guide
   (hearthstone, flights over known flight paths, boats, or running - whichever is fastest; `train Stormwind`
   when the trip passes Stormwind; nothing between two parts of the same zone). Re-run it after changing
   planner rules: the whole chain shifts with them. Hand-written block it splices in:
   `routes/hand/Alliance_Westfall.stormwind` (the Stormwind trip).

   **Race tracks.** `routes/ORDER` is the main track: the Human start zones, then the shared "Alliance" chain
   (no `races` header, so every Alliance race can use it). Each other start area has its own track file,
   `routes/ORDER.NightElf` (Shadowglen, Teldrassil) and `routes/ORDER.Dwarf` (Coldridge Valley, Dun Morogh, for
   Dwarves and Gnomes): hand-planned start zones, then `auto_chain.py --track NightElf|Dwarf` chains on from
   there for that race until `--target` (default 19) and points the last guide's `next` at the shared guide for
   that level, with the trip there. Every track is replayed and validated as its own character (`build_guides.py`
   compiles each one with a fresh quest log). The planner and the zone comparison take `--order ORDER.<Race>` to
   replay a race track and `--races` for its quests. In `Guides.xml` the Human start guides come first, then the
   race tracks, then the shared chain, so the addon finds a race's own guides before the shared ones.
   **Horde and Skyborne.** Each track has a `faction` (default Alliance) and a `joins` key, the track whose
   shared guides it hands over to. `routes/ORDER.Horde` is the Horde main track: the Orc & Troll start
   (`OrcTroll_ValleyOfTrials`, `OrcTroll_Durotar`, both races start in the Valley of Trials on Forever), then the
   shared "Horde" chain (`Horde_*`, no `races` header). `ORDER.Tauren` (Camp Narache, Mulgore) and
   `ORDER.Undead` (Deathknell, Tirisfal; race token `Scourge`) join it. `ORDER.SkyborneA` and `ORDER.SkyborneH`
   are Forever's Skyborne race (Zephras Isle, map 2521, race bits 2^32 Alliance / 2^33 Horde): one hand-planned
   island guide per faction that hands over to that faction's shared chain from its last start route (the island
   already reaches the join level). For the Horde, `compare_zones.py` / `auto_chain.py` use the Horde zones,
   flight masters (Wind Rider Masters, Bat Handlers), zeppelins (Orgrimmar - Undercity - Grom'gol) and the
   Orgrimmar, Thunder Bluff and Undercity trainers; the Alliance cities and the Deeprun Tram are left out.
   A race track's hand-over (`join_shared`) plays the track on into the shared guides the way the addon would:
   flight paths the shared guides fly from later are learned on the hand-over trip. A node that the trip doesn't
   pass gets a fallback (`fp_fallback`): the shared `fly` step is limited to the other races (`fpfb=<track>`), and
   the track's races fly to the nearest node they know and run on to learn the missing one (`fpfbalt=<track>`).
   Re-joining undoes and redoes this. Quests whose prerequisite
   only the shared chain's skipped zones give get a `{race=...}` filter for the other races, and quests above
   your level get a short catch-up grind at the end of the race track. Re-join the race tracks
   (`--track X --resume`) after the shared chain is re-planned: the filters live in the shared routes.
   Zephras Isle's map bounds are estimated from its two airship docks (`ESTIMATED_BOUNDS`). `plan_zone.py --keep`
   keeps quests the planner would drop for low XP (the island's first quests open the rest).
   The Teldrassil boat (Rut'theran Village - Auberdine) is a `FERRIES` entry in `compare_zones.py`.
   A race trip that passes Stormwind before the race knows its flight path stops there for training and
   `getfp Stormwind` (the shared chain's flights start from it). `--first <uiMapID>` forces the first zone
   (the Night Elf track goes to Darkshore first: Elwynn only tied it over 90 minutes, and Darkshore is the better
   zone as a whole). Trips never run through a zone whose mobs start more than `ZONE_GAP` (5) levels above you
   (`ZONE_MIN` in `compare_zones.py`), so a level 18 doesn't cross the Badlands.
   `--bands routes/ZONE_BANDS.Alliance` limits the zone choice to a level-band plan: at each level only that
   band's zones compete (the free ranking takes over when none of them has quests left, and the log says so);
   the quests, their order and the routes are still planned here. The Alliance band file is a commonly used
   Alliance leveling path (RestedXP's zone order per level, as the user listed it); only the zone choice per
   level is taken from it, never quest order, steps, text or waypoints (its guides are CC BY-NC-SA).
   `--resume` keeps the guides a track already has and carries on after the last one (e.g. to extend the main
   chain with a higher `--target` without re-planning the levels below). When the only thing left before
   `--target` is grinding the last level, the track ends there: the last guide gets the grind step instead of a
   trip to another zone (the main chain grinds 59-60 in the Burning Steppes, the Horde chain in the Eastern Plaguelands).

   **Map bounds of Forever's new zones.** `conversion.json` has none for them. Riverglades' bounds
   (`ESTIMATED_BOUNDS` in `plan_zone.py`) are solved from two flight masters whose map position (QuestieDB) and
   world position (Forever's taxi node table, as exported in the OpenMap addon's `Data/Forever/FlightData.lua`)
   are both known. Mount Hyjal (2482) and Shen'dralas (2652) were MEASURED in game with `/fg bounds 2482 2652`
   (client 1.60.1). Walking links (`compare_zones.WALK`): Hyjal <-> Winterspring (Darkwhisper Gorge),
   Shen'dralas <-> Desolace and Feralas. All creatures in the new zones have NPC ids of 200000 and up, so the
   mob-camp rule's id filter (`CAMP_MAX_ID`) only applies outside `FOREVER_MAPS`.

   **`route_from_draft.py draft dest head [tail]`** turns a draft into a route: hand-written head, the draft's
   steps without comments, optional tail. `routes/hand/splice.py route "after line" block` inserts a block.

4. **`check_recorded.py`** reads `QuestfarerRecorderDB` from your SavedVariables (after `/reload` or logout).
   It lists new quests that aren't in the DB, quest NPCs that differ from the DB, and guide steps or objective
   areas that are far from where things actually happened. Fix them with `@x,y` / `{npc=...}` in the route and
   rebuild.
   **`analyze_play.py`** reads the newest combat log (`Logs\WoWCombatLog-*.txt`; the addon turns it on at login, setting `/fg combatlog`) and the
   recorder's route log, and writes `reports/play_analysis.txt`: seconds per kill by mob and by level difference
   (vs `kill_factor`), the gap between pulls, multi-pulls, close calls, and XP per hour between level-ups. Use it to
   calibrate `SEC_PER_KILL` / `GRIND_SEC_PER_KILL` / `CLASS_SPEED` once there are a few hours of logs.
   **`import_contributions.py`** reads the data players chose to share (the addon's "Make export text", pasted
   into "Data contribution" issues and saved in `contributions/`). It keeps each contributor's newest export and
   writes `reports/contributions.txt`: seconds per fight, downtime, seconds per kill and XP per kill per class and
   level band, fight time by level difference next to `kill_factor`, and real hours per guide and per level. See
   `../publish/README.md` for how to fetch the issues.
   It treats every file as hostile: only `.txt`/`.md` files under 5 MB, no programs or binary data, at most 20 MB
   after unpacking (stops zip bombs), limits on nesting and item counts, every number checked against what the
   game allows, text cleaned of control characters, and medians over contributors (one contributor is one vote,
   copies under new IDs count once, far-off contributors are listed and left out). Run it with `--check` first to
   see what is rejected without writing anything. Never copy text from contributions into a route without reading
   it yourself.
   Files may also hide instructions aimed at an AI assistant ("prompt injection"). The importer never reads the
   post's own text, only the `FGDATA1` lines, and only lets text through that looks like a name from the game:
   class, race and version as one short word, file names in plain characters, NPC names, quest titles and
   objectives at most 8 words and 64 characters, letters, digits and a few punctuation marks only, and no
   instruction or command words (`ignore`, `prompt`, `AI`, `powershell`, links, file endings ...). Removed texts
   are counted in the notes. Give an assistant `reports/contributions.txt`, never the raw files in `contributions/`.
5. **`diff_guides.py`** compares the generated guides with the hand-written originals in `reference/`.
   It was used once to validate the compiler.
6. **Syntax check**: `luau-lsp analyze --platform=standard <file>` (from the Rokit tool storage) is a real Lua
   parser. Look for `SyntaxError` lines and ignore "Unknown global" for WoW API names.
   **`lint_lua.py`, `lint_commas.py`** are quick sanity checks for the addon's Lua files:
   `python -I lint_lua.py ../Questfarer/*.lua ../Questfarer/Guides/*.lua` and `python -I lint_commas.py ../Questfarer`.
7. **`simulate.py [track ...] [--class X]`** replays every track 1-60 (race tracks follow their `next` into the
   shared chain) once per class it has start trainers for. It reports time per band and quest/grind/travel
   share, trainer visits and how many spells/ranks wait in between (`Data/Spells`, `Trainers.lua`), `train`
   steps with no trainer for a class, city stops, the hardest fights (top mob level - your level), long grinds,
   long trips and tiny guides. The class speed factors and the untrained-rank penalty are guesses, so compare
   routes with it rather than reading the hours as real play time.
8. **`crosszone.py [Alliance|Horde] [--dry]`** is a post-pass over the shared chains. `plan_zone.py` plans one
   zone at a time, so it leaves out quests that start in one zone and are done or turned in in another. This pass
   adds such a quest when the finished route goes past every place anyway:
   - it accepts the quest where the route passes the giver;
   - it does the objectives where the route passes them, at a level where they are fine solo;
   - it turns the quest in where the route passes the turn-in NPC later, while the quest still gives full XP.

   It also takes the same-zone quests that such a quest needs first. The pass does not plan any extra trips.

   **Rules**
   - **Distance:** every place must be within `ACCEPT_YARDS`, `OBJECTIVE_YARDS` or `TURNIN_YARDS` of a step the
     route already has.
   - **Value:** the detour plus the objective time must give at least `MIN_SHARE` of the grinding rate.
   - **Quest log:** the log stays within `LOG_LIMIT`.
   - **Compiler check:** an insertion that adds a build error or warning is undone.
   - **Where it applies:** only after every race track has joined the shared chain, so no joiner meets a turn-in
     for a quest it never took.
   - **Events:** seasonal, event and war-effort quests (`EVENT_SORTS`) are never added.

   Inserted lines carry `{via=crosszone}`, and each run first removes the previous run's lines. Run it again after
   re-planning, in this order: `auto_chain.py`, then the race tracks, then `crosszone.py`, then `build_guides.py`.
9. **`class_guides.py`** writes `routes/class/Class_*.route`, one small side guide per class quest chain (Alliance).
   The chains, their levels and the hand-written step texts are the tables at the top of the script. Edit them
   there, then run `class_guides.py` and `build_guides.py`. Side guides are compiled on their own (they aren't in
   any `ORDER` file and `simulate.py` doesn't count them). The addon offers them through `ClassQuests.lua`.
10. **`level_times.py`** reads the times the addon measures (`Timer.lua`, saved after `/reload` or logout) and writes
    `reports/level_times.txt`: minutes per level, and real hours next to `simulate.py`'s model for every band you
    have played in full. Use it to calibrate the planner's constants.

`build_guides.py` also gives each step what the addon's helpers need (`Compiler.add_helpers`): `items` (quest items to
use), `targets` (who the target button goes for) and `area` (a flat x, y list of objective spots for the map dots).

## Route format

See the docstring at the top of `build_guides.py`. Short version:

```
guide Human 1-6 Northshire      # header lines first: guide, file, faction, races, levels, map, next
                                # (class quest side guides also have: side <CLASS>, ability <what it teaches>)
accept 783                      # verb + quest ID(s), comma separated
complete 7, 33 | text           # | replaces the step text
turnin 783 || tip               # || adds a tip line
level 2 @48.5,36.5              # @x,y[,map] overrides coordinates
getfp Sentinel Hill @56.5,52.6,1436 {npc=Thor}   # {k=v;k=v} options: class, race, notclass, npc, radius, title, cp
turnin 266 {cp=60.1,40.2/65.0,42.5}             # cp: arrow checkpoints in order (x,y or x,y,map), / between them
```

The arrow's zone crossings live in `Questfarer/Paths.lua` (`Paths.SEED`). They are estimates:
`python find_crossings.py [mapA mapB]` lists where NPC/object spawns of two walkable zones meet (roads and
passes have spawns, mountains don't); the biggest cluster is usually the crossing, but check it against what
you know of the zone. Crossings the addon learns in-game (`QuestfarerDB.paths`) replace the estimates.

Tips that belong to an NPC (for example "can be dead after an event") go in `NPC_TIPS` in
`build_guides.py` (npc ID -> text); every accept and turn-in at that NPC gets the tip, so it survives
regenerated routes.

## Data and licensing

- `questiedb-forever-release/` holds the QuestieDB Forever release and its docs (https://github.com/Questie/QuestieDB).
  QuestieDB's `LICENSE.md` allows copying under GPLv3 terms (the Questie name and logo are excluded). That is why
  Questfarer is GPLv3 and the generated guides credit QuestieDB. Don't use the Questie name or logo for
  Questfarer.
- `questie-forever/` holds the raw Forever data layers (zone mapping, quest XP) used by `build_guides.py`.
- QuestieDB's runtime "Dynamic Corrections" (faction-specific overrides, mostly shared books, Darkmoon and
  Elders quests) are not applied. Check `questiedb-forever-release/extracted/corrections/` if a quest in
  those groups is routed.
