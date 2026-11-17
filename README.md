# Quest Rep Reward

A tiny addon for **World of Warcraft: Forever** that shows a quest's reputation reward in the
Rewards section, next to XP, gold and items, styled like the built-in reward buttons.

Works in the quest log / world map quest details and in the NPC quest dialog.

## Install
Copy the `QuestRepReward` folder into `World of Warcraft/_forever_/Interface/AddOns/`
(the folder for your Forever client) and enable it on the character select screen.

## Where the numbers come from
1. The client's quest reputation API, when it has one for that quest.
2. Otherwise, what the addon has seen you earn when turning that quest in on any character
   (saved account-wide). Hover a reputation reward to see if it is a learned value.
