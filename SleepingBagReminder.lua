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
                if name == ITEM_NAME then return info.itemID end
            end
        end
    end
end

-- true = ready, false = cooling down, nil = not in bags / unknown.
local function IsReady()
    if not itemID or (GetItemCount and GetItemCount(itemID) == 0) then
        itemID = FindBag()
        if not itemID then return nil end
    end
    local ok, start, duration, enable = pcall(C_Container.GetItemCooldown, itemID)
    if not ok or IsSecret(start) or IsSecret(duration) or IsSecret(enable) then return nil end
    if enable == 0 or enable == false then return false end
    -- A duration of 1.5s or less is just the global cooldown.
    return (start or 0) == 0 or (duration or 0) <= 1.5
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

local function Check()
    if not SleepingBagReminderDB.enabled then return end
    local ready = IsReady()
    if ready == nil then return end
    if ready then
        if not wasReady or GetTime() >= nextRemind then TryAlert() end
    else
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
    else
        SleepingBagReminderDB.enabled = not SleepingBagReminderDB.enabled
        wasReady, pending = nil, false
        Print(SleepingBagReminderDB.enabled and "on" or "off")
        if SleepingBagReminderDB.enabled then Check() end
    end
end
