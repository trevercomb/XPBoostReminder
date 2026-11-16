local ADDON = ...

local ITEM_NAME = "Cozy Sleeping Bag"
local REMIND_EVERY = 300   -- seconds between repeat reminders while it's ready
local CHECK_EVERY = 5      -- seconds between cooldown checks
local LOGIN_DELAY = 8      -- let bags and cooldowns load before the first check
local HEADER = "|cff66ccffXP Boost Reminder|r"

local itemID          -- learned from the bags at runtime
local nextRemind = 0
local started = false

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(HEADER .. ": " .. msg)
end

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- Forever has the newer C_Item versions; the old globals may be gone.
local ItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

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
                if not name and ItemInfo then name = ItemInfo(info.itemID) end
                if name == ITEM_NAME then return info.itemID, bag, slot end
            end
        end
    end
end

local bagIndex, slotIndex  -- where the bag was last seen
local lastRaw = "none yet" -- raw cooldown values, for /xpb status

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

local scanTip = CreateFrame("GameTooltip", "XPBoostReminderScanTip", nil, "GameTooltipTemplate")
local xpLineCache = {} -- spell ID (or name) -> its experience line, or false if it has none
local scanError         -- why the last buff scan failed, for /xpb status

local function FindExperience(text)
    if type(text) == "string" and not IsSecret(text) and text:lower():find("experience") then return text end
end

-- The buff's tooltip lines, or nil if the game didn't give us any. Tries the
-- newer tooltip-data API first, then a hidden tooltip.
local function TooltipLines(index, instanceID)
    local lines = {}
    local tip = C_TooltipInfo
    local data = tip and ((instanceID and tip.GetUnitBuffByAuraInstanceID
            and tip.GetUnitBuffByAuraInstanceID("player", instanceID))
        or (tip.GetUnitBuff and tip.GetUnitBuff("player", index)))
    if data and data.lines then
        for _, line in ipairs(data.lines) do table.insert(lines, line.leftText) end
    else
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        if instanceID and scanTip.SetUnitBuffByAuraInstanceID then
            scanTip:SetUnitBuffByAuraInstanceID("player", instanceID)
        else
            scanTip:SetUnitBuff("player", index)
        end
        for n = 1, scanTip:NumLines() do
            local line = _G["XPBoostReminderScanTipTextLeft" .. n]
            table.insert(lines, line and line:GetText())
        end
    end
    if #lines >= 2 then return lines end
end

-- The tooltip line that mentions experience, e.g. "Experience gained from kills
-- increased by 5%.", false if the buff has none, or nil if the tooltip didn't load.
local function ExperienceLine(index, instanceID)
    local lines = TooltipLines(index, instanceID)
    if not lines then return nil end
    for n = 2, #lines do
        local text = FindExperience(lines[n])
        if text then return text end
    end
    return false
end

-- Buff number i: name, spell ID, aura instance ID; nil when there are no more.
local function BuffAt(i)
    local auras = C_UnitAuras
    local getter = auras and (auras.GetBuffDataByIndex or auras.GetAuraDataByIndex)
    if getter then
        local aura = getter == auras.GetBuffDataByIndex and getter("player", i)
            or getter("player", i, "HELPFUL")
        if aura then return aura.name, aura.spellId, aura.auraInstanceID end
        return nil
    end
    local name, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
    return name, spellId
end

-- Your experience buffs right now, other than Well-Rested, by name: { [name] = effect line }.
-- By name, so eating a different food for the same "Well Fed" counts as putting it back.
local function ReadXPBuffs()
    local found = {}
    for i = 1, 40 do
        local name, spellId, instanceID = BuffAt(i)
        if name == nil then break end
        if not IsSecret(name) and name ~= BUFF_NAME and spellId ~= BUFF_ID then
            local key = (spellId and not IsSecret(spellId)) and spellId or name
            -- Only remember a "no experience line" answer once the tooltip actually loaded.
            if xpLineCache[key] == nil then xpLineCache[key] = ExperienceLine(i, instanceID) end
            if xpLineCache[key] then found[name] = xpLineCache[key] end
        end
    end
    return found
end

local function XPBuffs()
    local ok, found = pcall(ReadXPBuffs)
    scanError = not ok and tostring(found) or nil
    return ok and found or nil
end

local activeXP = {} -- XP buffs you had at the last check
local wornOff = {}  -- name -> { effect, nextRemind, count }

local function WornOffMessage(name, entry)
    local pct = entry.effect:match("(%d+)%%")
    return name .. (pct and (" (+" .. pct .. "% XP)") or "") .. " has worn off. Put it back up!"
end

-- Click to eat: which item puts each XP buff back. Learned from the last item
-- you used before the buff appeared (saved per buff name), with a bag search
-- for food whose tooltip mentions Well Fed and experience as a fallback.
local LEARN_WINDOW = 90 -- seconds between using an item and its buff appearing
local lastUsed          -- { id, time } of the last item you used

local function ItemCount(id)
    local fn = (C_Item and C_Item.GetItemCount) or GetItemCount
    return fn and fn(id) or 0
end

local function IsConsumable(id)
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local classID = fn and select(6, fn(id))
    return classID == 0
end

local function NoteUse(id)
    if type(id) == "number" and id ~= itemID then lastUsed = { id = id, time = GetTime() } end
end

local function ItemIDOf(item)
    if type(item) == "number" then return item end
    local fn = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    return item and fn and fn(item)
end

-- Notice items used from bags, action bars and /use, without touching how they work.
local function SafeHook(owner, name, handler)
    if owner and owner[name] then
        hooksecurefunc(owner, name, function(...) pcall(handler, ...) end)
    end
end
SafeHook(C_Container, "UseContainerItem", function(bag, slot) NoteUse(C_Container.GetContainerItemID(bag, slot)) end)
SafeHook(_G, "UseAction", function(slot)
    local kind, id = GetActionInfo(slot)
    if kind == "item" then NoteUse(id) end
end)
SafeHook(_G, "UseItemByName", function(item) NoteUse(ItemIDOf(item)) end)
SafeHook(C_Item, "UseItemByName", function(item) NoteUse(ItemIDOf(item)) end)

local foodCache = {} -- item ID -> true if its tooltip mentions Well Fed and experience

local function IsXPFood(bag, slot, id)
    if foodCache[id] ~= nil then return foodCache[id] end
    if not IsConsumable(id) then foodCache[id] = false return false end
    local lines = {}
    local data = C_TooltipInfo and C_TooltipInfo.GetBagItem and C_TooltipInfo.GetBagItem(bag, slot)
    if data and data.lines then
        for _, line in ipairs(data.lines) do table.insert(lines, line.leftText) end
    else
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        scanTip:SetBagItem(bag, slot)
        for n = 1, scanTip:NumLines() do
            local line = _G["XPBoostReminderScanTipTextLeft" .. n]
            table.insert(lines, line and line:GetText())
        end
    end
    if #lines < 2 then return false end -- tooltip didn't load; try again next time
    local text = ""
    for _, line in ipairs(lines) do
        if type(line) == "string" and not IsSecret(line) then text = text .. " " .. line:lower() end
    end
    foodCache[id] = text:find("well fed") ~= nil and text:find("experience") ~= nil
    return foodCache[id]
end

-- The item to click for a worn-off buff, or nil if you have none.
local function ItemFor(buffName)
    local learned = XPBoostReminderDB.items[buffName]
    if learned and ItemCount(learned) > 0 then return learned end
    if not buffName:lower():find("well fed") then return nil end
    local best, bestCount
    for bag = 0, NUM_BAG_SLOTS or 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local id = C_Container.GetContainerItemID(bag, slot)
            if id and not IsSecret(id) and IsXPFood(bag, slot, id) then
                local count = ItemCount(id)
                if not best or count > bestCount then best, bestCount = id, count end
            end
        end
    end
    return best
end

local function SafeItemFor(buffName)
    local ok, id = pcall(ItemFor, buffName)
    return ok and id or nil
end

local function UpdateXPBuffs()
    local now = XPBuffs()
    if not now then return end
    for name, effect in pairs(activeXP) do
        if not now[name] then wornOff[name] = { effect = effect, nextRemind = 0, count = 0 } end
    end
    for name in pairs(now) do
        wornOff[name] = nil
        -- A buff that just appeared after you used a consumable: that's its item.
        if not activeXP[name] and lastUsed and GetTime() - lastUsed.time <= LEARN_WINDOW
            and IsConsumable(lastUsed.id) then
            XPBoostReminderDB.items[name] = lastUsed.id
        end
    end
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

-- Click-to-use buttons. WoW only lets you use an item through a secure button
-- you click yourself, and secure buttons can't be shown, hidden or changed in
-- combat, so they're only updated outside it (and hidden as combat starts).
local BUTTON_SIZE, BUTTON_Y = 48, -120
local bagDueNow, bagDismissed = false, false

local function MakeButton(key, label)
    local b = CreateFrame("Button", "XPBoostReminder" .. key .. "Button", UIParent, "SecureActionButtonTemplate")
    b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    b:SetFrameStrata("HIGH")
    b:Hide()
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type1", "item") -- left-click uses the item; right-click only dismisses
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("TOP", b, "BOTTOM", 0, -3)
    b.label:SetText(label)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemID then GameTooltip:SetItemByID(self.itemID) end
        GameTooltip:AddLine("Left-click to use, right-click to dismiss", 0.6, 0.8, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local bagButton = MakeButton("Bag", "Click to sleep")
local foodButton = MakeButton("Food", "Click to eat")

-- Set a button's item and show it; returns it, or nil when there's no item.
local function Arm(button, id, count)
    if not id then return nil end
    if button.itemID ~= id then
        button.itemID = id
        button:SetAttribute("item", "item:" .. id)
        local iconFn = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
        button.icon:SetTexture(iconFn and iconFn(id) or 134400)
    end
    button.count:SetText(count and count > 1 and count or "")
    return button
end

local function UpdateButtons()
    if InCombatLockdown() then return end
    local shown = {}
    local enabled = XPBoostReminderDB.enabled and not UnitIsDeadOrGhost("player")
    if enabled and bagDueNow and not bagDismissed and itemID then
        table.insert(shown, Arm(bagButton, itemID))
    end
    if enabled then
        for name, entry in pairs(wornOff) do
            if not entry.dismissed then
                local id = SafeItemFor(name)
                if id then
                    foodButton.buffName = name
                    table.insert(shown, Arm(foodButton, id, ItemCount(id)))
                    break
                end
            end
        end
    end
    for _, b in ipairs({ bagButton, foodButton }) do
        local isShown = false
        for _, s in ipairs(shown) do isShown = isShown or s == b end
        if not isShown then b:Hide() end
    end
    local gap = BUTTON_SIZE + 40
    for i, b in ipairs(shown) do
        b:ClearAllPoints()
        b:SetPoint("CENTER", UIParent, "CENTER", (i - (#shown + 1) / 2) * gap, BUTTON_Y)
        b:Show()
    end
end

bagButton:SetScript("PostClick", function(self, button)
    if button == "RightButton" then bagDismissed = true UpdateButtons() end
end)
foodButton:SetScript("PreClick", function(self, button)
    if button == "LeftButton" then NoteUse(self.itemID) end
end)
foodButton:SetScript("PostClick", function(self, button)
    if button == "RightButton" and self.buffName and wornOff[self.buffName] then
        wornOff[self.buffName].dismissed = true
        UpdateButtons()
    end
end)

local readySince -- first time this ready stretch was seen
local wasDue     -- bag reminder already shown for this stretch (nil before the first check)

local function Check()
    if not XPBoostReminderDB.enabled then return end
    -- Never interrupt a fight or a corpse run: everything due waits, and the
    -- check after combat ends or you're alive again picks it up.
    local blocked = InCombat() or UnitIsDeadOrGhost("player")
    local messages = {}
    local t = GetTime()

    UpdateXPBuffs()
    if not blocked then
        for name, entry in pairs(wornOff) do
            if not entry.dismissed and entry.count < XP_REMINDERS and t >= entry.nextRemind then
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
            bagDueNow = due
            if not due then
                wasDue, bagDismissed = false, false
            elseif (not wasDue or t >= nextRemind) and not blocked and not bagDismissed then
                wasDue, nextRemind = true, t + REMIND_EVERY
                table.insert(messages, msg)
            end
        end
    end

    if #messages > 0 then Alert(messages) end
    UpdateButtons()
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("PLAYER_UNGHOST")
frame:RegisterEvent("PLAYER_ALIVE")
frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON then
            XPBoostReminderDB = XPBoostReminderDB or {}
            if XPBoostReminderDB.enabled == nil then XPBoostReminderDB.enabled = true end
            XPBoostReminderDB.items = XPBoostReminderDB.items or {} -- buff name -> item that gives it
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Combat is starting: last chance to hide the buttons until it ends.
        if not InCombatLockdown() then
            bagButton:Hide()
            foodButton:Hide()
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

SLASH_XPBOOSTREMINDER1 = "/xpb"
SLASH_XPBOOSTREMINDER2 = "/xpboost"
SlashCmdList.XPBOOSTREMINDER = function(input)
    local cmd = strtrim(input or ""):lower()
    if cmd == "test" then
        Alert({ DEFAULT_MSG, "Well Fed (+5% XP) has worn off. Put it back up!" }, true)
    elseif cmd == "status" then
        local ready = IsReady()
        Print((XPBoostReminderDB.enabled and "on" or "off") .. ", bag "
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
        if scanError then Print("|cffff6060buff scan failed:|r " .. scanError) end
        if #gone > 0 then Print("worn off, reminding: " .. table.concat(gone, ", ")) end
        local food = SafeItemFor("Well Fed")
        local link = food and ((ItemInfo and select(2, ItemInfo(food))) or ("item " .. food))
        Print("food for Well Fed: " .. (food and (link .. " x" .. ItemCount(food)
            .. (XPBoostReminderDB.items["Well Fed"] == food and " (the food you last ate)" or " (found in your bags)"))
            or "none found yet (eat XP food once and it's remembered)"))
    else
        XPBoostReminderDB.enabled = not XPBoostReminderDB.enabled
        wasDue, readySince, bagDismissed = nil, nil, false
        wornOff = {}
        Print(XPBoostReminderDB.enabled and "on" or "off")
        if XPBoostReminderDB.enabled then Check() else UpdateButtons() end
    end
end
