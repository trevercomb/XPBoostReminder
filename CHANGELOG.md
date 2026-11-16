# Sleeping Bag Reminder changelog

## 1.1.0

- At 3 stacks of Well-Rested, the reminder waits until the buff has 10 minutes left, since sleeping in the bag again before it ends keeps the stacks. Below 3 stacks (or with no buff) it still reminds you as soon as the bag is off cooldown.
- `/sbr status` shows your Well-Rested stacks, time left and which reminder applies.

## 1.0.0

- Reminds you when your Cozy Sleeping Bag is off cooldown: a sound, an on-screen warning and a chat line, at login if it's ready and every 5 minutes until you use it.
- Waits until combat ends (or you're alive again) before reminding you.
- `/sbr` turns it on or off, `/sbr test` plays the alert, `/sbr status` shows the bag's cooldown.
