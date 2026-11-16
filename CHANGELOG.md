# XP Boost Reminder changelog

## 1.4.2

- Right-clicking a button now also silences that reminder's alerts, not just the button: food until the buff is back and wears off again, the sleeping bag until you next use it.

## 1.4.1

- Fixed: `/xpb status` hit a Lua error on the food line.

## 1.4.0

- Click to eat: when Well Fed (or another XP buff) wears off, a button with your food appears below the middle of the screen. Left-click eats, right-click dismisses it. It remembers the food you last ate before the buff appeared, and otherwise looks in your bags for food whose tooltip mentions Well Fed and experience.
- Click to sleep: the same kind of button for the Cozy Sleeping Bag when its reminder is due.
- Buttons never change during combat: they hide as combat starts and come back after.
- `/xpb status` shows which food the button would use.

## 1.3.1

- Fixed: other XP buffs like Well Fed weren't found, so no reminder came when they wore off. Buffs are now read with the same aura API that finds Well-Rested.
- `/xpb status` says so if the buff scan fails.

## 1.3.0

- Renamed from Sleeping Bag Reminder to XP Boost Reminder, since it now covers XP food too. The commands are now `/xpb` (or `/xpboost`): `/xpb`, `/xpb test` and `/xpb status`.

## 1.2.0

- Other experience buffs: when a buff whose tooltip mentions experience (like Well Fed from food that boosts XP) wears off, or you lose it by dying, you're reminded to put it back up. Up to 3 reminders, 5 minutes apart, in case you're out of food.
- `/sbr status` lists your current XP buffs and any worn-off ones it's still reminding you about.

## 1.1.0

- At 3 stacks of Well-Rested, the reminder waits until the buff has 10 minutes left, since sleeping in the bag again before it ends keeps the stacks. Below 3 stacks (or with no buff) it still reminds you as soon as the bag is off cooldown.
- `/sbr status` shows your Well-Rested stacks, time left and which reminder applies.

## 1.0.0

- Reminds you when your Cozy Sleeping Bag is off cooldown: a sound, an on-screen warning and a chat line, at login if it's ready and every 5 minutes until you use it.
- Waits until combat ends (or you're alive again) before reminding you.
- `/sbr` turns it on or off, `/sbr test` plays the alert, `/sbr status` shows the bag's cooldown.
