# Sleeping Bag Reminder

A tiny WoW Forever addon that reminds you to use your **Cozy Sleeping Bag** whenever it's off cooldown.

The bag's rested bonus lasts 2 hours but its cooldown is only 1 hour, so it's worth unfurling again as soon as it's ready. When the cooldown ends you get a sound, an on-screen warning and a chat line. It also reminds you at login if the bag is ready, and every 5 minutes until you use it. It never interrupts a fight: reminders wait until combat ends.

## Commands

- `/sbr`: turn reminders on or off
- `/sbr test`: play the alert
- `/sbr status`: whether it's on, and how long the bag's cooldown has left

## Releasing

Pushing a version tag runs `.github/workflows/release.yml`, which builds the zip with the [BigWigs packager](https://github.com/BigWigsMods/packager) and makes a GitHub release. It also uploads to CurseForge once `## X-Curse-Project-ID` is in the .toc and the repo has a `CF_API_KEY` secret. Each release: bump `## Version` in the .toc, add notes to the top of `CHANGELOG.md`, commit, then `git tag vX.Y.Z` and `git push origin vX.Y.Z`.
