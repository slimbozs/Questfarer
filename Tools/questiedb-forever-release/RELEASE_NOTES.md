# QuestieDB 1.1.2

**Looking for the Questie quest helper? [Download Questie here](https://github.com/Questie/Questie/releases/latest).**

QuestieDB is the standalone database used by Questie. It does not provide quest tracking or map markers on its own. Install it alongside Questie or another addon that uses its data.

## What's new

### Quest fixes

- [Forever] Update quest XP data ([BreakBB](https://github.com/Questie/QuestieDB/commit/4588c4426bf7a3faaf6a9e0033a67d33887341c9))

### Database fixes

- Add Powderfuse faction ([Cabro](https://github.com/Questie/QuestieDB/commit/a14b129bbd953bbc68523519ccd8b149acdd52c9))
- [Forever] Update quests, NPCs, objects and items data ([BreakBB](https://github.com/Questie/QuestieDB/commit/760c4f96d53d24447fffd99ec962c0b98a5f1f7e))

### Localization fixes

- [Forever] Update all translations ([BreakBB](https://github.com/Questie/QuestieDB/commit/f58a56f5ab10546cd541bafa01c6ca24671c89cf))

[All changes since v1.1.1](https://github.com/Questie/QuestieDB/compare/v1.1.1..e1652ce62113c152da682baf2d6fb85f1396bcfb)

## Download

**Recommended: [QuestieDB-1.1.2-all.zip](https://github.com/Questie/QuestieDB/releases/download/v1.1.2/QuestieDB-1.1.2-all.zip)**

Includes all game flavors. Your client automatically loads the matching database.

For a smaller download, choose just your game flavor:

| Game flavor | Download |
| --- | --- |
| Classic Era / Season of Discovery | [QuestieDB-1.1.2-Vanilla.zip](https://github.com/Questie/QuestieDB/releases/download/v1.1.2/QuestieDB-1.1.2-Vanilla.zip) |
| The Burning Crusade Classic / Anniversary | [QuestieDB-1.1.2-TBC.zip](https://github.com/Questie/QuestieDB/releases/download/v1.1.2/QuestieDB-1.1.2-TBC.zip) |
| Wrath of the Lich King Classic / Titan Reforged | [QuestieDB-1.1.2-Wrath.zip](https://github.com/Questie/QuestieDB/releases/download/v1.1.2/QuestieDB-1.1.2-Wrath.zip) |
| Cataclysm Classic | [QuestieDB-1.1.2-Cata.zip](https://github.com/Questie/QuestieDB/releases/download/v1.1.2/QuestieDB-1.1.2-Cata.zip) |
| Mists of Pandaria Classic | [QuestieDB-1.1.2-Mists.zip](https://github.com/Questie/QuestieDB/releases/download/v1.1.2/QuestieDB-1.1.2-Mists.zip) |
| Classic Forever | [QuestieDB-1.1.2-Forever.zip](https://github.com/Questie/QuestieDB/releases/download/v1.1.2/QuestieDB-1.1.2-Forever.zip) |

Use one addon ZIP. GitHub's **Source code** archives are not the packaged addon.

## Installation

1. Close World of Warcraft.
2. If updating, back up any local edits and remove the old `QuestieDB` addon folder.
3. Extract the ZIP into your game client's `Interface/AddOns/` directory. The result should be `Interface/AddOns/QuestieDB/QuestieDB_<Flavor>.toc`, not a second nested `QuestieDB` folder.
4. Start the game and enable **QuestieDB** in the character-selection AddOns list. Keep Questie or your other consuming addon installed alongside it.

**Addon developers:** see the [integration and API documentation](https://github.com/Questie/QuestieDB/blob/e1652ce62113c152da682baf2d6fb85f1396bcfb/docs/api.md). LuaLS declarations are included in `QuestieDB/Types/`.

<details>
<summary>Build details and checksums</summary>

- Addon version: `1.1.2`
- Producing commit: [`e1652ce`](https://github.com/Questie/QuestieDB/commit/e1652ce62113c152da682baf2d6fb85f1396bcfb)
- Supported API contracts: `1` to `4`

The attached `release.json` records full commit hashes and each ZIP's SHA-256 checksum. Compare your download's hash with its entry before installing:

```sh
sha256sum QuestieDB-*.zip       # Linux
shasum -a 256 QuestieDB-*.zip   # macOS
```

```powershell
Get-FileHash QuestieDB-*.zip -Algorithm SHA256
```

</details>
