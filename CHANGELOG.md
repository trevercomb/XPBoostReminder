# XP Boost Reminder changelog

## 1.0.4

- Fixed: dismissing a reminder (right-click) left its warning text fading on screen for a few seconds. The text now clears at once.
- The on-screen warnings no longer share the raid warning frame, so they don't mix with real raid warnings from your group.

## 1.0.3

- Fixed: a Well Fed (or other XP buff) already running when you logged in could wear off without a reminder. Right after login the game may not have loaded the buff's description yet, and the addon took that as "not an XP buff" for the rest of the session. It now waits for the game's data, checks again later, and remembers your XP buffs between sessions.
- The same for food in your bags: a food tooltip read before the game had its details is checked again later.

## 1.0.2

- The eat button learns your food more reliably: an item that names the buff (like "well fed") now wins over another consumable that only mentions experience, and learning waits for the food's tooltip to load instead of giving up.
- Tooltips the game hides for a moment are read again later instead of being remembered as "not an XP item".

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
