local ADDON = ...

local ITEM_NAME = "Cozy Sleeping Bag"
local REMIND_EVERY = 300   -- seconds between repeat reminders while it's ready
local CHECK_EVERY = 5      -- seconds between cooldown checks
local LOGIN_DELAY = 8      -- let bags and cooldowns load before the first check
local HEADER = "|cff66ccffSleeping Bag Reminder|r"

local itemID          -- learned from the bags at runtime
local nextRemind = 0
local started = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(HEADER .. ": " .. msg)
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- Finds the bag by name (from the item link, which works even when the item cache is cold).
local function FindBag()
    if not C_Container then return nil end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
            if ok and info and info.itemID and not IsSecret(info.itemID) then
                local name = info.itemName
                if (not name or IsSecret(name)) and info.hyperlink and not IsSecret(info.hyperlink) then
                    name = info.hyperlink:match("%[(.-)%]")
                end
                if not name then name = GetItemInfo(info.itemID) end
                if name == ITEM_NAME then return info.itemID, bag, slot end
            end
        end
    end
end

local bagIndex, slotIndex  -- where the bag was last seen
local lastRaw = "none yet" -- raw cooldown values, for /sbr status

-- Seconds left on one cooldown source, or nil if that source gave nothing usable.
local function Remaining(fn, ...)
    if not fn then return nil end
    local ok, start, duration, enable = pcall(fn, ...)
    if not ok or IsSecret(start) or IsSecret(duration) or IsSecret(enable) then return nil end
    if type(start) == "table" then -- some clients return a cooldown info table
        start, duration, enable = start.startTime, start.duration, start.isEnabled
    end
    if type(start) ~= "number" or type(duration) ~= "number" then return nil end
    if enable == 0 or enable == false then return math.huge end -- cooldown hasn't started ticking yet
    if start == 0 or duration == 0 then return 0 end
    return math.max(0, start + duration - GetTime())
end

-- Seconds left (0 when ready), or nil if the bag isn't in your bags or no source answered.
-- Checks the bag slot (what the tooltip shows) plus both item-ID lookups and trusts the longest.
local function CooldownLeft()
    local info = bagIndex and C_Container.GetContainerItemInfo(bagIndex, slotIndex)
    if not info or info.itemID ~= itemID then
        itemID, bagIndex, slotIndex = FindBag()
        if not itemID then return nil end
    end
    local slotLeft = Remaining(C_Container.GetContainerItemCooldown, bagIndex, slotIndex)
    local itemLeft = Remaining(C_Container.GetItemCooldown, itemID)
    local globalLeft = Remaining(GetItemCooldown, itemID)
    local function fmt(v) return v and (v == math.huge and "paused" or string.format("%.0f", v)) or "-" end
    lastRaw = "slot " .. fmt(slotLeft) .. "s, item " .. fmt(itemLeft) .. "s, global " .. fmt(globalLeft) .. "s"
    local left
    for _, v in ipairs({ slotLeft or -1, itemLeft or -1, globalLeft or -1 }) do
        if v >= 0 and (not left or v > left) then left = v end
    end
    return left
end

-- true = ready, false = cooling down, nil = not in bags / unknown.
-- A cooldown of 1.5s or less is just the global cooldown.
local function IsReady()
    local left = CooldownLeft()
    if left == nil then return nil end
    return left <= 1.5
end

-- The bag's buff. At full stacks it's worth keeping, so the reminder waits
-- until it's nearly gone (sleeping again before it ends keeps the stacks).
local BUFF_ID = 429959
local BUFF_NAME = "Well-Rested"
local FULL_STACKS = 3
local WARN_LEFT = 600 -- seconds of buff left when a full-stack reminder is due

local function ReadWellRested()
    local stacks, expires
    local get = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    local aura = get and get(BUFF_ID)
    if aura then
        stacks, expires = aura.applications, aura.expirationTime
    else
        for i = 1, 40 do
            local name, _, count, _, _, expirationTime, _, _, _, spellId = UnitBuff("player", i)
            if name == nil then break end
            if spellId == BUFF_ID or name == BUFF_NAME then
                stacks, expires = count, expirationTime
                break
            end
        end
    end
    if stacks == nil or IsSecret(stacks) or IsSecret(expires) then return nil end
    if stacks == 0 then stacks = 1 end -- a single application reports 0
    local left = (expires and expires > 0) and math.max(0, expires - GetTime()) or math.huge
    return stacks, left
end

-- Stacks and seconds left on Well-Rested, or nil if you don't have it (or it can't be read).
local function WellRested()
    local ok, stacks, left = pcall(ReadWellRested)
    if ok then return stacks, left end
end

local DEFAULT_MSG = "Your " .. ITEM_NAME .. " is ready. Unfurl it!"

-- Whether a reminder is due now, and what it should say.
-- Below full stacks (or no buff): as soon as the bag is off cooldown.
-- At full stacks: once the bag is ready and the buff has 10 minutes or less left.
local function Due(ready)
    if not ready then return false end
    local stacks, left = WellRested()
    if stacks and stacks >= FULL_STACKS then
        if left > WARN_LEFT then return false end
        return true, string.format("Well-Rested ends in %d min. Unfurl your %s to keep %d stacks!",
            math.ceil(left / 60), ITEM_NAME, FULL_STACKS)
    end
    return true, DEFAULT_MSG
end

-- Other experience buffs (food like Well Fed, and anything else whose tooltip
-- mentions experience): when one wears off, remind you to put it back.
local XP_REMINDERS = 3 -- reminders per worn-off buff, REMIND_EVERY apart, in case you're out of food

local scanTip = CreateFrame("GameTooltip", "SleepingBagReminderScanTip", nil, "GameTooltipTemplate")
local xpLineCache = {} -- spell ID (or name) -> its experience line, or false if it has none

-- The tooltip line that mentions experience, e.g. "Experience gained from kills increased by 5%."
local function ExperienceLine(index)
    scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTip:SetUnitBuff("player", index)
    for n = 2, scanTip:NumLines() do
        local line = _G["SleepingBagReminderScanTipTextLeft" .. n]
        local text = line and line:GetText()
        if text and not IsSecret(text) and text:lower():find("experience") then return text end
    end
    return false
end

-- Your experience buffs right now, other than Well-Rested, by name: { [name] = effect line }.
-- By name, so eating a different food for the same "Well Fed" counts as putting it back.
local function ReadXPBuffs()
    local found = {}
    for i = 1, 40 do
        local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
        if name == nil then break end
        if not IsSecret(name) and name ~= BUFF_NAME and spellId ~= BUFF_ID then
            local key = (spellId and not IsSecret(spellId)) and spellId or name
            if xpLineCache[key] == nil then xpLineCache[key] = ExperienceLine(i) end
            if xpLineCache[key] then found[name] = xpLineCache[key] end
        end
    end
    return found
end

local function XPBuffs()
    local ok, found = pcall(ReadXPBuffs)
    return ok and found or nil
end

local activeXP = {} -- XP buffs you had at the last check
local wornOff = {}  -- name -> { effect, nextRemind, count }

local function WornOffMessage(name, entry)
    local pct = entry.effect:match("(%d+)%%")
    return name .. (pct and (" (+" .. pct .. "% XP)") or "") .. " has worn off. Put it back up!"
end

local function UpdateXPBuffs()
    local now = XPBuffs()
    if not now then return end
    for name, effect in pairs(activeXP) do
        if not now[name] then wornOff[name] = { effect = effect, nextRemind = 0, count = 0 } end
    end
    for name in pairs(now) do wornOff[name] = nil end
    activeXP = now
end

local function InCombat()
    return InCombatLockdown() or UnitAffectingCombat("player")
end

local function Alert(messages, isTest)
    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    for _, msg in ipairs(messages) do
        if RaidNotice_AddMessage and RaidWarningFrame then
            RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
        end
        Print(msg .. (isTest and " |cff9d9d9d(test)|r" or ""))
    end
end

local readySince -- first time this ready stretch was seen
local wasDue     -- bag reminder already shown for this stretch (nil before the first check)

local function Check()
    if not SleepingBagReminderDB.enabled then return end
    -- Never interrupt a fight or a corpse run: everything due waits, and the
    -- check after combat ends or you're alive again picks it up.
    local blocked = InCombat() or UnitIsDeadOrGhost("player")
    local messages = {}
    local t = GetTime()

    UpdateXPBuffs()
    if not blocked then
        for name, entry in pairs(wornOff) do
            if entry.count < XP_REMINDERS and t >= entry.nextRemind then
                entry.count, entry.nextRemind = entry.count + 1, t + REMIND_EVERY
                table.insert(messages, WornOffMessage(name, entry))
            end
        end
    end

    local ready = IsReady()
    if ready ~= nil then
        local settled = true
        if ready then
            -- Only believe "ready" once it has held for a few seconds, in case the
            -- game reports no cooldown before its cooldown data has loaded.
            readySince = readySince or t
            settled = t - readySince >= 4
        else
            readySince = nil
        end
        if settled then
            local due, msg = Due(ready)
            if not due then
                wasDue = false
            elseif (not wasDue or t >= nextRemind) and not blocked then
                wasDue, nextRemind = true, t + REMIND_EVERY
                table.insert(messages, msg)
            end
        end
    end

    if #messages > 0 then Alert(messages) end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            SleepingBagReminderDB = SleepingBagReminderDB or {}
            if SleepingBagReminderDB.enabled == nil then SleepingBagReminderDB.enabled = true end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if not started then
            started = true
            C_Timer.After(LOGIN_DELAY, function()
                Check()
                C_Timer.NewTicker(CHECK_EVERY, Check)
            end)
        end
    elseif started then
        -- Bag cooldown changed, combat ended, or you're alive again: check now
        -- (a moment later, so the game has settled) instead of on the next tick.
        C_Timer.After(1, Check)
    end
end)

SLASH_SLEEPINGBAGREMINDER1 = "/sbr"
SLASH_SLEEPINGBAGREMINDER2 = "/sleepingbag"
SlashCmdList.SLEEPINGBAGREMINDER = function(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "test" then
        Alert({ DEFAULT_MSG, "Well Fed (+5% XP) has worn off. Put it back up!" }, true)
    elseif cmd == "status" then
        local ready = IsReady()
        Print((SleepingBagReminderDB.enabled and "on" or "off") .. ", bag "
            .. (ready == nil and "not found in your bags" or ready and "ready" or "on cooldown")
            .. (itemID and (" (item " .. itemID .. ")") or ""))
        if itemID then Print("cooldown left: " .. lastRaw) end
        local stacks, left = WellRested()
        if not stacks then
            Print(BUFF_NAME .. ": none, so you're reminded when the bag is ready")
        else
            Print(string.format("%s: %d stack%s, %s left%s", BUFF_NAME, stacks, stacks == 1 and "" or "s",
                left == math.huge and "no time limit" or (math.ceil(left / 60) .. " min"),
                stacks >= FULL_STACKS and ", so you're reminded at 10 min left"
                    or ", so you're reminded when the bag is ready"))
        end
        local active, gone = {}, {}
        for name, effect in pairs(XPBuffs() or {}) do table.insert(active, name .. " (" .. effect .. ")") end
        for name in pairs(wornOff) do table.insert(gone, name) end
        Print("other XP buffs: " .. (#active > 0 and table.concat(active, ", ") or "none"))
        if #gone > 0 then Print("worn off, reminding: " .. table.concat(gone, ", ")) end
    else
        SleepingBagReminderDB.enabled = not SleepingBagReminderDB.enabled
        wasDue, readySince = nil, nil
        wornOff = {}
        Print(SleepingBagReminderDB.enabled and "on" or "off")
        if SleepingBagReminderDB.enabled then Check() end
    end
end
