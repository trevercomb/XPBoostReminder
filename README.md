# XP Boost Reminder

A tiny WoW Forever addon that reminds you to keep your experience buffs up. You get a sound, an on-screen warning and a chat line, and it never interrupts a fight: reminders wait until combat ends (or until you're alive again).

## Cozy Sleeping Bag

Sleeping in the bag gives the Well-Rested buff (up to 3 stacks, 2 hours); the bag's cooldown is 1 hour.

- **Below 3 stacks, or no buff:** you're reminded as soon as the bag is off cooldown, so you can build the stacks up.
- **At 3 stacks:** you're reminded when the buff has 10 minutes left, so you sleep again and keep the stacks before they run out.

It checks at login too, and repeats every 5 minutes until you use the bag.

## Other XP buffs

Any other buff whose tooltip mentions experience, such as Well Fed from food that boosts XP. When one wears off (or you lose it by dying), you're reminded to put it back up, up to 3 times, 5 minutes apart.

## Click to use

When a reminder is due, a button appears below the middle of the screen: the sleeping bag (click to sleep) or your XP food (click to eat). Left-click uses it, right-click dismisses it. For food, it remembers what you last ate before the buff appeared, and otherwise looks in your bags for food whose tooltip mentions Well Fed and experience. Buttons hide during combat, since the game doesn't allow changing them then.

## Commands

- `/xpb`: turn reminders on or off
- `/xpb test`: play the alerts
- `/xpb status`: whether it's on, the bag's cooldown, your Well-Rested stacks and time left, your other XP buffs, and which food the eat button would use

`/xpboost` works too.

## Releasing

Pushing a version tag runs `.github/workflows/release.yml`, which builds the zip with the [BigWigs packager](https://github.com/BigWigsMods/packager) and makes a GitHub release. It also uploads to CurseForge once `## X-Curse-Project-ID` is in the .toc and the repo has a `CF_API_KEY` secret. Each release: bump `## Version` in the .toc, add notes to the top of `CHANGELOG.md`, commit, then `git tag vX.Y.Z` and `git push origin vX.Y.Z`.
