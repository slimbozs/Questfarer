# Changelog

## 0.9.5-beta

- Quests that start from a rare's drop (Assassin's Contract, The Moss-twined Heart, The Demon Scarred Cloak,
  The Harvester, The Runed Scroll) now get a step to hunt the rare. Click Next to skip it if the rare isn't up:
  the rest of the quest is left out, and if the item drops later you can still hand it in.
- Steps now warn about named elites well above your level close by, like Mor'Ladim in Duskwood.
- Brewer's Trade now sends you to Dun Garok for the Sack of Homebrew Hops before you hand it in.
- Arch Absolution (Hyjal) and Oasis (Tanaris) now have the step that was missing between taking and handing in
  the quest.
- The Missing Diplomat: the arrow now points at Thomas in Stormwind.
- A few more values the game can hide (the flight check, the arrow's facing) no longer risk a Lua error.

## 0.9.4-beta

- Fixed a Lua error from the time tracker (Timer.lua:19) when the game hides whether you are AFK,
  mostly in combat. That time now counts.

## 0.9.3-beta

- Numbered circles on the world map for the current step and the next five, joined by a line. Steps at the same
  spot share a circle; point at one to see its steps. Turn them off on the Navigation page or with `/qf mapsteps`.
- Blizzard's map pin is now off by default for new installs (Navigation page, or `/qf waypoint`).
- The orange dots where a step's mobs and items are now show on the world map too. They were drawn under it.
- The export now holds the paths the arrow learned, so shared data can add checkpoints to the guides. Learned
  paths are capped (three per step, a thousand in all) so the saved data stays small.
- A few kill spots in Duskwood, Redridge and Wetlands moved to where the mobs are.

## 0.9.2-beta

- New look for the guide window: a rounded header with a gem, pill buttons, drawn close, collapse and settings
  icons, a progress bar under the guide name, a medallion and a coloured label on the step card, and coloured shapes
  for the upcoming steps.
- The guide arrow is now a compass. The needle is gold, turns green when you are close and blue at checkpoints, and
  the distance sits in a tag below it.
- The settings menu and the target button have their own icons.
- Drag the target button to an action bar and it becomes a "Questfarer" macro that follows the guide.
- Wetlands: the arrow goes round by the path to Ormer Ironbraid and the dig site camp. Uncovering the Past moved
  to part 2, where it goes with Ormer's Revenge and the dig site mobs are your level.
- The arrow no longer skips a guide checkpoint just because the step is close as the crow flies.
- A hardcore route is being prepared. It is not in this version yet.

## 0.9.1-beta

- The target button puts a star over the NPC or mob it targets when you play alone.
- Gear upgrades show how much better your gear gets as a whole, so a cloak with a little stamina no longer reads
  as +2000%.

## 0.9.0-beta

- Elite quests are optional. Their steps say so, and if you click Next past one, the rest of that quest and the
  quests that follow it are skipped without warnings. Find my step no longer sends you back to a skipped elite.
- Escort quests that are too hard solo are left out (Missing In Action and eight others).
- Quests deep inside caves are left out where nothing needs them. Cave quests that the route needs for XP or a
  chain got a tip about pulling one at a time.
- Tanaris: one turn-in moved earlier so the level stays on track.

## 0.8.0-beta

- First beta as Questfarer (it was called ForeverGuide before).
