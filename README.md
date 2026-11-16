# Sleeping Bag Reminder

A tiny WoW Forever addon that reminds you to use your **Cozy Sleeping Bag** whenever it's off cooldown.

Sleeping in the bag gives the Well-Rested buff (up to 3 stacks, 2 hours); the bag's cooldown is 1 hour. You get a sound, an on-screen warning and a chat line:

- **Below 3 stacks, or no buff:** as soon as the bag is off cooldown, so you can build the stacks up.
- **At 3 stacks:** when the buff has 10 minutes left, so you sleep again and keep the stacks before they run out.

It also watches your other experience buffs, such as Well Fed from food that boosts XP: any buff whose tooltip mentions experience. When one wears off (or you lose it by dying), it reminds you to put it back up, up to 3 times, 5 minutes apart.

It also checks at login, and repeats the bag reminder every 5 minutes until you use the bag. It never interrupts a fight: reminders wait until combat ends.

## Commands

- `/sbr`: turn reminders on or off
- `/sbr test`: play the alert
- `/sbr status`: whether it's on, the bag's cooldown, your Well-Rested stacks and time left, and your other XP buffs

## Releasing

Pushing a version tag runs `.github/workflows/release.yml`, which builds the zip with the [BigWigs packager](https://github.com/BigWigsMods/packager) and makes a GitHub release. It also uploads to CurseForge once `## X-Curse-Project-ID` is in the .toc and the repo has a `CF_API_KEY` secret. Each release: bump `## Version` in the .toc, add notes to the top of `CHANGELOG.md`, commit, then `git tag vX.Y.Z` and `git push origin vX.Y.Z`.
