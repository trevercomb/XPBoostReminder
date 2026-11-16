# XP Boost Reminder changelog

## 1.0.1

- Fixed: eating and drinking together could make the eat button remember your drink instead of your food. It now only remembers an item whose tooltip gives that buff.
- Fixed: switching to a different XP food could set off a false "Well Fed has worn off" alert.
- Fixed: the sleeping bag button could stay up after the bag left your bags.
- Fixed: turning reminders off and back on could remember the wrong item for a buff.
- Fewer checks during combat, and the bag search for food only reruns when your bags change.

## 1.0.0

First release. Reminds you to keep your experience buffs up, with a sound, an on-screen warning and a chat line, and never during a fight.

- **Cozy Sleeping Bag:** below 3 stacks of Well-Rested you're reminded as soon as the bag is off cooldown; at 3 stacks, when the buff has 10 minutes left, so you keep the stacks.
- **XP food and other XP buffs:** when Well Fed (or any buff whose tooltip mentions experience) wears off, you're reminded to put it back up, up to 3 times, 5 minutes apart.
- **Click to use:** a button appears for the reminder that's due. Click to eat (it remembers your food, or finds XP food in your bags) or click to sleep. Right-click means "not now": it hides the button and silences that reminder.
- `/xpb` turns it on or off, `/xpb test` plays the alerts, `/xpb status` shows the bag, your buffs and which food the button would use.
