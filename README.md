# Quest Rep Reward

A tiny addon for **World of Warcraft: Forever** that shows a quest's reputation reward in the
Rewards section, next to XP, gold and items, styled like the built-in reward buttons.

Works in the quest log / world map quest details and in the NPC quest dialog.

## Install
Copy the `QuestRepReward` folder into `World of Warcraft/_forever_/Interface/AddOns/`
(the folder for your Forever client) and enable it on the character select screen.

## Where the numbers come from
1. What you actually earned when you turned that quest in before (saved account-wide).
2. The game's quest-log reputation API (quests in your log).
3. [Questie](https://www.curseforge.com/wow/addons/questie)'s quest database, if installed
   (also covers quests offered by an NPC that aren't in your log yet).

Type `/qrr` in chat for diagnostics.
