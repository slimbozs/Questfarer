"""Write the class quest side guides: routes/class/*.route (Alliance and Horde).

Edit CHAINS / HORDE_CHAINS below (quest IDs in the order you do them, lead-in quests left out).

Usage: python -I class_guides.py   (then python -I build_guides.py)
"""
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
import build_guides as bg  # noqa: E402

OUT = os.path.join(ROOT, "routes", "class")

ALL = ["Human", "Dwarf", "NightElf", "Gnome"]
STORMWIND = "Stormwind: Deeprun Tram from Ironforge, or the boat from Rut'theran Village (Darnassus)."
IRONFORGE = "Ironforge: Deeprun Tram from Stormwind, or the boat to Menethil Harbor and north through Dun Morogh."
DARNASSUS = "Darnassus: the boat from Stormwind Harbor to Rut'theran Village, then the portal up the tree."
BARRENS = "The Barrens: the boat from Menethil Harbor to Theramore, then west to the Barrens."
MOONGLADE = "Your druid trainer teaches Teleport: Moonglade at level 10: use it to reach Dendrite Starblaze."

HORDE = ["Orc", "Scourge", "Tauren", "Troll"]
ORGRIMMAR = "Orgrimmar: the zeppelin from Tirisfal Glades, next to the Undercity, lands in Durotar just outside the city."
RATCHET = ("Strahad is in Ratchet on the Barrens coast. Jorah Annison is in the Undercity: take the zeppelin from "
           "Durotar, just outside Orgrimmar, to Tirisfal Glades.")
WATER = ("The chain also sends you to Tarren Mill and Silverpine Forest: take the zeppelin from Durotar, just "
         "outside Orgrimmar, to Tirisfal Glades.")
FRAY = "Klannoc Macleod is on Fray Island, off the Barrens coast southeast of Ratchet."
ZEPHRAS = "Back to Zephras Isle: the skycutter docks in Mulgore at Skywatcher Plateau, northwest of Thunder Bluff."

# steps the DB describes badly: quest ID -> (where or None, text)
SHRINE = "@45.6,59.9,1436"  # Stendel's Pond, Westfall: Forever's Call of Water ends here
COMPLETE = {
    1689: ("@39.1,84.4,1453", "Go down to the summoning circle in the cellar of the Slaughtered Lamb, use the "
                              "Bloodstone Choker and defeat the voidwalker."),
    1739: ("@39.1,84.4,1453", "Go down to the summoning circle in the cellar of the Slaughtered Lamb, use the "
                              "Heartswood Core and defeat the succubus."),
    1795: (None, "At the summoning circle next to Strahad, use the Tome of the Cabal and defeat the felhunter."),
    5929: (None, "Talk to the Great Bear Spirit in northwestern Moonglade."),
    6001: ("@43.5,46.0,1439", "Use the Cenarion Moondust on the Moonkin Stone in Auberdine, then defeat Lunaclaw."),
    6122: (None, "Use the Empty Cliffspring Falls Sampler at the mouth of the cave by the falls."),
    6124: (None, "Use the Curative Animal Salve on 10 Sickly Deer."),
    29: (None, "Find a Shrine Bauble in Lake Elune'ara, use it at the Shrine of Remulos, then talk to Tajarri."),
    272: ("@48.9,11.3,1439", "Open the Strange Lockbox off the north coast of Darkshore (here) and the one off the "
                             "coast of Westfall (17.9, 33.2), then join the two halves at the Shrine of Remulos."),
    94467: (None, "Defeat the Minor Manifestation of Fire and put the Glowing Ember in the brazier on top of the shrine."),
    94497: ("@65.8,76.5,1437", "Fill the Unfilled Brown Waterskin at the bottom of the waterfalls below Hervdana's cave."),
    94499: ("@75.7,58.5,1433", "Fill the Unfilled Red Waterskin at Stonewatch Falls, near the Nightcrawler murlocs."),
    94500: ("@37.0,49.2,1440", "Fill the Unfilled Blue Waterskin in the waters of Astranaar."),
    94502: (SHRINE, "Drink the Water Sapta and cleanse the corruption at Stendel's Pond."),
    1644: ("@63.8,72.2,1453", "Collect 10 Linen Cloth (humanoids drop it)."),
    1648: ("@23.3,61.9,1455", "Collect 10 Linen Cloth (humanoids drop it)."),
    1786: (None, "Use the Symbol of Life on Henze Faulk to resurrect him."),
    1783: (None, "Use the Symbol of Life on Narm Faulk to resurrect him."),
    1719: (None, "Step on the grate on Fray Island to start the fight, then defeat Big Will."),
    1640: (None, "Beat Bartleby in a fight, then talk to him."),
    2359: (None, "Steal the Defias Tower Key, open the Defias Tower and take what is in the Duskwood Chest."),
    2608: (None, "Type /lay so Doc Mixilpixil can examine you."),
    # Horde
    1504: ("@49.4,50.0,1454", "Go to the summoning circle in the Cleft of Shadow, use the Glyphs of Summoning "
                              "and defeat the voidwalker."),
    1471: ("@86.6,27.1,1458", "At the summoning circle next to Carendin Halgar, use the Runes of Summoning and "
                              "defeat the voidwalker."),
    1513: ("@49.4,50.0,1454", "Go to the summoning circle in the Cleft of Shadow, use Dogran's Pendant and defeat "
                              "the succubus."),
    5930: (None, "Talk to the Great Bear Spirit in northwestern Moonglade."),
    6002: ("@42.0,60.9,1413", "Use the Cenarion Lunardust on the Moonkin Stone in the Barrens, then defeat Lunaclaw."),
    6127: (None, "Use the Empty Dreadmist Peak Sampler at the pool on top of Dreadmist Peak."),
    6129: (None, "Use the Curative Animal Salve on 10 Sickly Gazelles."),
    28: (None, "Find a Shrine Bauble in Lake Elune'ara, use it at the Shrine of Remulos, then talk to Tajarri."),
    30: ("@56.7,8.3,1413", "Open the Strange Lockbox in the northern Barrens (here) and the one in Silverpine "
                           "Forest (29.6, 29.2), then join the two halves at the Shrine of Remulos."),
    1526: (None, "Defeat the Minor Manifestation of Fire and put the Glowing Ember in the brazier on top of the shrine."),
    1535: (None, "Fill the Empty Brown Waterskin at the watering hole below Brine's hut."),
    1536: (None, "Fill the Empty Red Waterskin at the well in Tarren Mill."),
    1534: (None, "Fill the Empty Blue Waterskin at the fountain in the Ruins of Stardust."),
    94434: ("@65.5,37.5,1458", "Collect 10 Linen Cloth (humanoids drop it)."),
    94438: (None, "Use the Symbol of Life on Deathguard Falgan to resurrect him."),
    2460: (None, "Type /salute at Shenthul."),
    2458: (None, "When you see the tower, fire two flares with the Flare Gun, then /salute Taskmaster Fizzule."),
    2478: (None, "Steal Silixiz's Tower Key, kill 2 Drones, 2 Patrollers and 2 Lookouts, then kill Grand Foreman "
                 "Gallywix and pick the lock on his lockbox."),
    2480: (None, "Wait for Serge Hinott to finish the cure."),
}
# quest ID -> where, when it differs from the DB
TURNIN_AT = {94503: SHRINE}
ACCEPT_AT = {94505: SHRINE}
CITIES = (1453, 1455, 1457)  # Alliance capitals, for quests with givers in both factions' cities
HORDE_CITIES = (1454, 1456, 1458)

# file, class, level, races, what you get, quest IDs, tip on the first step
CHAINS = [
    ("Hunter_Pet_HumanGnome", "HUNTER", 10, ["Human", "Gnome"], "Tame Beast and your first pet",
     [94792, 94863, 94864, 94793], None),
    ("Hunter_Pet_Dwarf", "HUNTER", 10, ["Dwarf"], "Tame Beast and your first pet", [6064, 6084, 6085, 6086], None),
    ("Hunter_Pet_NightElf", "HUNTER", 10, ["NightElf"], "Tame Beast and your first pet",
     [6063, 6101, 6102, 6103], None),
    ("Hunter_Pet_Skyborne", "HUNTER", 10, ["Skyborne"], "Tame Beast and your first pet",
     [94978, 94979, 94013, 94050], None),

    ("Warlock_Voidwalker", "WARLOCK", 10, ALL + ["Skyborne"], "Summon Voidwalker", [1688, 1689], STORMWIND),
    ("Warlock_Succubus", "WARLOCK", 20, ALL + ["Skyborne"], "Summon Succubus", [1716, 1738, 1739], BARRENS),
    ("Warlock_Felhunter", "WARLOCK", 30, ALL + ["Skyborne"], "Summon Felhunter",
     [1798, 1758, 1802, 1804, 1795], BARRENS),

    ("Druid_Bear_NightElf", "DRUID", 10, ["NightElf"], "Bear Form", [5921, 5929, 5931, 6001], MOONGLADE),
    ("Druid_Bear_Skyborne", "DRUID", 10, ["Skyborne"], "Bear Form", [94006, 94638], None),
    ("Druid_CurePoison", "DRUID", 14, ["NightElf"], "Cure Poison", [6121, 6122, 6123, 6124, 6125], MOONGLADE),
    ("Druid_Aquatic", "DRUID", 16, ["NightElf"], "Aquatic Form", [26, 29, 272, 5061], MOONGLADE),
    ("Druid_Cat", "DRUID", 20, ["NightElf"], "Cat Form", [98393, 98394, 98396, 98731, 98397], MOONGLADE),

    ("Shaman_Earth", "SHAMAN", 4, ["Dwarf"], "Earth totems", [94373, 94374, 94375], None),
    ("Shaman_Fire", "SHAMAN", 10, ["Dwarf"], "Fire totems", [94465, 94466, 94467, 94468], None),
    ("Shaman_Water", "SHAMAN", 20, ["Dwarf"], "Water totems",
     [94494, 94495, 94497, 94499, 94500, 94501, 94502, 94503, 94505], IRONFORGE),

    ("Warrior_Defensive_Human", "WARRIOR", 10, ["Human"], "Defensive Stance", [1638, 1639, 1640, 1665], STORMWIND),
    ("Warrior_Defensive_DwarfGnome", "WARRIOR", 10, ["Dwarf", "Gnome"], "Defensive Stance", [1679, 1678], None),
    ("Warrior_Defensive_NightElf", "WARRIOR", 10, ["NightElf"], "Defensive Stance", [1684, 1683], None),
    ("Warrior_Defensive_Skyborne", "WARRIOR", 10, ["Skyborne"], "Defensive Stance", [94003], None),
    ("Warrior_Berserker", "WARRIOR", 30, ALL + ["Skyborne"], "Berserker Stance", [1718, 1719], BARRENS),

    ("Paladin_Redemption_Human", "PALADIN", 12, ["Human"], "Redemption",
     [1641, 1642, 1643, 1644, 1780, 1781, 1786, 1787, 1788], STORMWIND),
    ("Paladin_Redemption_Dwarf", "PALADIN", 12, ["Dwarf"], "Redemption",
     [1645, 1646, 1647, 1648, 1778, 1779, 1783, 1784, 1785], IRONFORGE),

    ("Rogue_Poisons", "ROGUE", 20, ALL + ["Skyborne"], "Poisons", [2360, 2359, 2607, 2608, 2609], STORMWIND),
]

# same layout; Skyborne here means the Horde ones
HORDE_CHAINS = [
    ("Hunter_Pet_OrcTroll", "HUNTER", 10, ["Orc", "Troll"], "Tame Beast and your first pet",
     [6062, 6083, 6082, 6081], None),
    ("Hunter_Pet_Tauren", "HUNTER", 10, ["Tauren"], "Tame Beast and your first pet", [6061, 6087, 6088, 6089], None),
    ("Hunter_Pet_Skyborne_Horde", "HUNTER", 10, ["Skyborne"], "Tame Beast and your first pet",
     [94978, 94979, 94013, 94050], None),

    ("Warlock_Voidwalker_Orc", "WARLOCK", 10, ["Orc"], "Summon Voidwalker", [1501, 1504], None),
    ("Warlock_Voidwalker_Undead", "WARLOCK", 10, ["Scourge"], "Summon Voidwalker", [1473, 1471], None),
    # the Orgrimmar version; the Undercity one (1472, 1476, 1474) is the other choice
    ("Warlock_Succubus_Horde", "WARLOCK", 20, HORDE + ["Skyborne"], "Summon Succubus",
     [1507, 1508, 1509, 1510, 1511, 1515, 1512, 1513], ORGRIMMAR),
    ("Warlock_Felhunter_Horde", "WARLOCK", 30, HORDE + ["Skyborne"], "Summon Felhunter",
     [1801, 1803, 1805, 1795], RATCHET),

    ("Druid_Bear_Tauren", "DRUID", 10, ["Tauren"], "Bear Form", [5922, 5930, 5932, 6002], MOONGLADE),
    ("Druid_Bear_Skyborne_Horde", "DRUID", 10, ["Skyborne"], "Bear Form", [94006, 94638], None),
    ("Druid_CurePoison_Tauren", "DRUID", 14, ["Tauren"], "Cure Poison", [6126, 6127, 6128, 6129, 6130], MOONGLADE),
    ("Druid_Aquatic_Tauren", "DRUID", 16, ["Tauren"], "Aquatic Form", [27, 28, 30, 31], MOONGLADE),
    ("Druid_Cat_Tauren", "DRUID", 20, ["Tauren"], "Cat Form", [98340, 98405, 98342, 98739, 98362], MOONGLADE),

    ("Shaman_Earth_OrcTroll", "SHAMAN", 4, ["Orc", "Troll"], "Earth totems", [1516, 1517, 1518], None),
    ("Shaman_Earth_Tauren", "SHAMAN", 4, ["Tauren"], "Earth totems", [1519, 1520, 1521], None),
    ("Shaman_Earth_Skyborne", "SHAMAN", 3, ["Skyborne"], "Earth totems", [92466, 92467, 92468], None),
    ("Shaman_Fire_Horde", "SHAMAN", 10, ["Orc", "Tauren", "Troll"], "Fire totems", [1524, 1525, 1526, 1527], None),
    ("Shaman_Fire_Skyborne", "SHAMAN", 10, ["Skyborne"], "Fire totems", [97243, 97244, 97245, 97257], ZEPHRAS),
    ("Shaman_Water_Horde", "SHAMAN", 20, HORDE + ["Skyborne"], "Water totems",
     [1530, 1535, 1536, 1534, 220, 63, 100, 96], WATER),

    ("Warrior_Defensive_OrcTaurenTroll", "WARRIOR", 10, ["Orc", "Tauren", "Troll"], "Defensive Stance",
     [1505, 1498], None),
    ("Warrior_Defensive_Undead", "WARRIOR", 10, ["Scourge"], "Defensive Stance", [1818, 1819], None),
    ("Warrior_Defensive_Skyborne_Horde", "WARRIOR", 10, ["Skyborne"], "Defensive Stance", [94003], None),
    ("Warrior_Berserker_Horde", "WARRIOR", 30, HORDE + ["Skyborne"], "Berserker Stance", [1718, 1719], FRAY),

    ("Paladin_Redemption_Undead", "PALADIN", 12, ["Scourge"], "Redemption",
     [94427, 94434, 94435, 94436, 94438, 94440, 94441], None),

    ("Rogue_Poisons_Horde", "ROGUE", 20, HORDE + ["Skyborne"], "Poisons", [2460, 2458, 2478, 2479, 2480], ORGRIMMAR),
]
HORDE_NAMES = {"Scourge": "Undead", "Skyborne": "Horde Skyborne"}


def start_map(data, q, cities):
    npcs, objs, _ = data.givers(q.get("startedBy"))
    maps = [p[0] for kind, ids in (("npc", npcs), ("object", objs)) for i in ids for p in data.points(kind, i)]
    return next((m for m in maps if m in cities), maps[0] if maps else None)


def who(faction, races):
    # guides are keyed by name, so race variants need different names
    if faction == "Horde":
        return " (Horde)" if len(races) > 4 else " (%s)" % " & ".join(HORDE_NAMES.get(r, r) for r in races)
    return "" if len(races) > 4 else " (%s)" % " & ".join(r.replace("NightElf", "Night Elf") for r in races)


def complete_line(data, qid, q):
    where, text = COMPLETE.get(qid, (None, None))
    if not text and data.name("item", q.get("sourceItemId")) == "Taming Rod":
        text = str(bg.as_list(q.get("objectivesText"))[0]).split(". ")[0] + "."
    return "complete %d%s%s" % (qid, " " + where if where else "", " | " + text if text else "")


def has_task(q):
    return bool(bg.slots(q.get("objectives"))) or bool(q.get("triggerEnd"))


def main():
    data = bg.Data()
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".route"):
            os.remove(os.path.join(OUT, f))
    names, files = set(), set()
    for faction, chains in (("Alliance", CHAINS), ("Horde", HORDE_CHAINS)):
        cities = CITIES if faction == "Alliance" else HORDE_CITIES
        for fname, cls, level, races, what, quests, tip in chains:
            maps = [m for m in (start_map(data, data.quest(q), cities) for q in quests) if m]
            name = "%s: %s%s" % (cls.capitalize(), what, who(faction, races))
            if name in names or fname in files:
                sys.exit("duplicate guide name or file: %s / %s" % (name, fname))
            names.add(name)
            files.add(fname)
            lines = ["# Class quest side guide, written by class_guides.py - edit the chain there, not this file.",
                     "guide %s" % name,
                     "file Class_%s" % fname,
                     "faction %s" % faction,
                     "races %s" % ", ".join(races),
                     "levels %d 61" % level,
                     "map %d" % maps[0],
                     "side %s" % cls,
                     "ability %s" % what,
                     ""]
            for i, qid in enumerate(quests):
                q = data.quest(qid)
                first = " || %s" % tip if tip and i == 0 else ""
                lines.append("accept %d%s%s" % (qid, " " + ACCEPT_AT[qid] if qid in ACCEPT_AT else "", first))
                hint = ""
                if has_task(q):
                    lines.append(complete_line(data, qid, q))
                elif qid in COMPLETE:  # no objectives in the DB, so the hint goes on the turn-in
                    hint = " | " + COMPLETE[qid][1]
                lines.append("turnin %d%s%s" % (qid, " " + TURNIN_AT[qid] if qid in TURNIN_AT else "", hint))
            with open(os.path.join(OUT, "Class_%s.route" % fname), "w", encoding="utf-8", newline="\n") as fh:
                fh.write("\n".join(lines) + "\n")
    print("wrote %d class quest routes to routes/class" % len(names))


if __name__ == "__main__":
    main()
