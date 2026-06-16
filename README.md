# GuildRecipes XL
**Version:** 1.0
**Game Version:** OctoWoW (1.18) or other WoW Client 1.12.1

I didn't like how small things were in the original version. I also have literally no idea how to code, but I made the UI bigger. :high_brightness:

First, uninstall the original if you have it installed already. Then install this version. If you have issues in-game you may need to delete your WDB folder and `/reload` in-game.

If it breaks, uninstall this version and reinstall the original, don't forget to clear WDB and `/reload` in-game.

Original made by Sica42

Original addon link: https://github.com/sica42/GuildRecipes

Forked from Glowrot

GuildRecipes XL lets you view the recipes of other guild members using the addon.
If you have GuildAlts installed it will show the main character for any alts sharing recipes.

> [!NOTE]
> Each character is tracked separately — alts on the same account are not automatically linked. Their recipes are only shared when you log into that character and open their tradeskill window.

---

## ✨ Usage

Use the text field to search for any recipe you're looking for. You can limit the search to any specific tradeskill by using the dropdown. Clicking search without any input will show all recipes.

Click a recipe to see who can craft it. You can also view reagents for recipes by clicking the **Show Reagents** button. Reagent data requires either **AtlasLoot** or **Atlas-CFM** to be installed — AtlasLoot is checked first, with Atlas-CFM as a fallback.

With your chat open, you can shift-click items in the list to say the item. You can also shift-click the item icon to say the recipe with required reagents. The message will be posted to your current chat channel, so ensure you have the right channel set before clicking.

You can assign a hotkey in Key Bindings to toggle the window.

The title bar shows live counts of **Synced Players** (yellow) and **Online** guild members with synced data (green), updated whenever the window is opened or new data comes in.

> [!NOTE]
> Your own recipes are only shared when you open your tradeskill window, so make sure to open all your tradeskills after installing the addon.

> [!NOTE]
> Synced data does not automatically update when guildies log in after you. Use `/gr refresh` to pull the latest data, or wait for a guildie to open their tradeskill window which will broadcast their recipes automatically.

---

## 🧰 Slash Commands

Type `/gr` or `/guildrecipes` in chat to see all options.

- `/gr show` — Open the Guild Recipes window.
- `/gr hide` — Close the Guild Recipes window.
- `/gr toggle` — Toggle the Guild Recipes window.
- `/gr refresh` — Request updated tradeskills from all guild members.
- `/gr players` — List all players with synced tradeskill data, their online status, and which tradeskills are known.
- `/gr remove_player <Player>` — Remove a player from all recipes.
- `/gr version` — Check which version other guild members are running.

---

## 📦 Dependencies

**Required for reagent display (one of):**
- [AtlasLoot](https://github.com/Lag4YT/AtlasLootClassic) — checked first
- [Atlas-CFM](https://github.com/byCFM2/Atlas-CFM) — used as fallback if AtlasLoot is not installed

---

## 📦 Installation

Manual install:
1. Download or clone the addon into your `Interface\AddOns\` folder.
2. Make sure the folder is named `GuildRecipes`.
3. Restart WoW or type `/reload` in-game.

