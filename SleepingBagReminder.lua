local ADDON = ...

local ITEM_NAME = "Cozy Sleeping Bag"
local REMIND_EVERY = 300   -- seconds between repeat reminders while it's ready
local CHECK_EVERY = 5      -- seconds between cooldown checks
local LOGIN_DELAY = 8      -- let bags and cooldowns load before the first check
local HEADER = "|cff66ccffSleeping Bag Reminder|r"

local itemID          -- learned from the bags at runtime
local wasReady        -- nil until the first check, so login/reload counts as "became ready"
local nextRemind = 0
local pending = false -- an alert is waiting for combat to end
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

local function InCombat()
    return InCombatLockdown() or UnitAffectingCombat("player")
end

local function Alert(isTest)
    local msg = "Your " .. ITEM_NAME .. " is ready. Unfurl it!"
    PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, ChatTypeInfo["RAID_WARNING"])
    end
    Print(msg .. (isTest and " |cff9d9d9d(test)|r" or ""))
end

local function TryAlert()
    if InCombat() or UnitIsDeadOrGhost("player") then
        pending = true
        return
    end
    pending = false
    nextRemind = GetTime() + REMIND_EVERY
    Alert()
end

local readySince -- first time this ready stretch was seen

local function Check()
    if not SleepingBagReminderDB.enabled then return end
    local ready = IsReady()
    if ready == nil then return end
    if ready then
        -- Only believe "ready" once it has held for a few seconds, in case the
        -- game reports no cooldown before its cooldown data has loaded.
        readySince = readySince or GetTime()
        if GetTime() - readySince < 4 then return end
        if not wasReady or GetTime() >= nextRemind then TryAlert() end
    else
        readySince = nil
        pending = false
    end
    wasReady = ready
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
    elseif event == "BAG_UPDATE_COOLDOWN" then
        if started and wasReady ~= nil then Check() end
    elseif pending and SleepingBagReminderDB.enabled then
        -- Combat ended or we're alive again: deliver the held alert if it's still ready.
        C_Timer.After(1, function()
            if pending and IsReady() then TryAlert() end
        end)
    end
end)

SLASH_SLEEPINGBAGREMINDER1 = "/sbr"
SLASH_SLEEPINGBAGREMINDER2 = "/sleepingbag"
SlashCmdList.SLEEPINGBAGREMINDER = function(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "test" then
        Alert(true)
    elseif cmd == "status" then
        local ready = IsReady()
        Print((SleepingBagReminderDB.enabled and "on" or "off") .. ", bag "
            .. (ready == nil and "not found in your bags" or ready and "ready" or "on cooldown")
            .. (itemID and (" (item " .. itemID .. ")") or ""))
        if itemID then Print("cooldown left: " .. lastRaw) end
    else
        SleepingBagReminderDB.enabled = not SleepingBagReminderDB.enabled
        wasReady, pending, readySince = nil, false, nil
        Print(SleepingBagReminderDB.enabled and "on" or "off")
        if SleepingBagReminderDB.enabled then Check() end
    end
end
