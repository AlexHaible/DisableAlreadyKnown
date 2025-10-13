local addonName = ...
local frame = CreateFrame("Frame")
local vendorCheckbox
local initialized = false
HideKnownVendorItemsDB = HideKnownVendorItemsDB or { hideKnown = false }

-- === Forward declarations ===
local IsItemKnown

--@debug@
-- ==== Debug controls =========================================================
local HKVI_DBG = false
local function HKVI_Log(...)
    if HKVI_DBG then print("|cffffcc00HKVI:|r", ...) end
end
-- rate-limit protection: prints once per link per refresh
local hkvi_seen = {}
local function HKVI_LogOnce(link, ...)
    if not HKVI_DBG or not link then return end
    if not hkvi_seen[link] then
        hkvi_seen[link] = true
        print("|cffffcc00HKVI:|r", ...)
    end
end
--@end-debug@

---------------------------------------------------------
-- Checkbox on vendor frame
---------------------------------------------------------
local function CreateVendorCheckbox()
    if vendorCheckbox then return end

    local label = HideKnownVendorItems_GetLocaleString("CHECKBOX_LABEL")
    local tooltip = HideKnownVendorItems_GetLocaleString("CHECKBOX_TOOLTIP")

    vendorCheckbox = CreateFrame("CheckButton", nil, MerchantFrame, "UICheckButtonTemplate")
    vendorCheckbox.text:SetText(label)
    vendorCheckbox.tooltip = tooltip
    vendorCheckbox:SetChecked(HideKnownVendorItemsDB.hideKnown)

    -- Anchor in blank space between portrait and dropdown
    vendorCheckbox:ClearAllPoints()
    vendorCheckbox:SetPoint("TOPLEFT", MerchantFrame, "TOPLEFT", 55, -25)

    vendorCheckbox.text:ClearAllPoints()
    vendorCheckbox.text:SetPoint("LEFT", vendorCheckbox, "RIGHT", 2, 0)
    vendorCheckbox.text:SetWidth(110)
    vendorCheckbox.text:SetJustifyH("LEFT")

    vendorCheckbox:HookScript("OnClick", function(self)
        HideKnownVendorItemsDB.hideKnown = self:GetChecked()
        MerchantFrame_UpdateMerchantInfo()
    end)
end

---------------------------------------------------------
-- Modern reliable known-item detection (includes pets)
---------------------------------------------------------
local function IsItemKnown(itemLink)
    if not itemLink then
        --@debug@ HKVI_Log("IsItemKnown: no link") --@end-debug@
        return false
    end

    local itemID = C_Item.GetItemInfoInstant(itemLink)
    if not itemID then
        --@debug@ HKVI_Log("IsItemKnown: no itemID for", itemLink) --@end-debug@
        return false
    end

    if C_Item and not C_Item.IsItemDataCachedByID(itemID) then
        C_Item.RequestLoadItemDataByID(itemID)
        --@debug@ HKVI_LogOnce(itemLink, "Item data not yet cached") --@end-debug@
        return nil
    end

    local tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
    if not tooltipData or not tooltipData.lines then
        --@debug@ HKVI_LogOnce(itemLink, "TooltipInfo missing lines") --@end-debug@
        return nil
    end

    local knownStr = (ITEM_SPELL_KNOWN or "Already known"):lower()
    local foundKnown, foundUncollected, foundCollectedPet = false, false, false

    for _, line in ipairs(tooltipData.lines) do
        if line.leftText then
            local text = line.leftText:lower()

            -- detect false positives
            if text:find("uncollected", 1, true)
            or text:find("not collected", 1, true)
            or text:find("unlearned", 1, true) then
                foundUncollected = true
            end

            -- detect standard "Already known"
            if text:find(knownStr, 1, true) then
                foundKnown = true
            end

            -- detect pet collections like "Collected (1/3)"
            local countStr = text:match("collected%s*%((%d+)%s*/%s*(%d+)%)")
            if countStr then
                local owned = tonumber(countStr)
                if owned and owned > 0 then
                    foundCollectedPet = true
                end
            end
        end
    end

    local res = ((foundKnown or foundCollectedPet) and not foundUncollected) or false
    --@debug@
    HKVI_LogOnce(itemLink, "IsItemKnown ->", res and "true" or "false",
        "(known:", foundKnown, "pet:", foundCollectedPet, "uncollected:", foundUncollected, ")")
    --@end-debug@
    return res
end

---------------------------------------------------------
-- Vendor item refresh (with one-shot async retry)
---------------------------------------------------------
local retryScheduled = false
--@debug@ local hkvi_lastRefreshPrint = 0 --@end-debug@

local function RefreshMerchantItems()
    --@debug@
    hkvi_seen = {}
    if GetTime() - (hkvi_lastRefreshPrint or 0) > 0.5 then
        HKVI_Log("RefreshMerchantItems start")
        hkvi_lastRefreshPrint = GetTime()
    end
    --@end-debug@

    local active = HideKnownVendorItemsDB.hideKnown
    local numItems = GetMerchantNumItems()
    local needsRetry = false

    -- Reset visuals
    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local itemContainer = _G["MerchantItem" .. i]
        if itemContainer then
            local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
            if itemButton then
                itemButton.__HIDEKNOWN_LOCKED = nil
                itemButton:Enable()
                if itemButton.icon then
                    itemButton.icon:SetDesaturated(false)
                end
                itemButton:SetAlpha(1)
            end
            local nameFS = _G[itemContainer:GetName() .. "Name"]
            if nameFS then nameFS:SetTextColor(1, 1, 1) end
        end
    end

    if not active then
        --@debug@ HKVI_Log("Feature disabled, returning.") --@end-debug@
        return
    end

    for i = 1, numItems do
        local itemLink = GetMerchantItemLink(i)
        if itemLink then
            local index = i - (MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE
            if index >= 1 and index <= MERCHANT_ITEMS_PER_PAGE then
                local known = IsItemKnown(itemLink)

                if known == nil then
                    --@debug@ HKVI_Log("Item not ready:", itemLink) --@end-debug@
                    needsRetry = true

                elseif known == true then
                    local itemButton = _G["MerchantItem" .. index .. "ItemButton"]
                    if itemButton then
                        if itemButton.icon then itemButton.icon:SetDesaturated(true) end
                        itemButton:SetAlpha(0.5)
                        itemButton.__HIDEKNOWN_LOCKED = true
                        local nameFS = _G["MerchantItem" .. index .. "Name"]
                        if nameFS then nameFS:SetTextColor(0.5, 0.5, 0.5) end
                        --@debug@ HKVI_Log("Grayed out:", itemLink) --@end-debug@
                    end
                else
                    --@debug@ HKVI_Log("Not known:", itemLink) --@end-debug@
                end
            end
        else
            needsRetry = true
        end
    end

    if needsRetry and not retryScheduled then
        retryScheduled = true
        --@debug@ HKVI_Log("Scheduling one retry in 0.3s") --@end-debug@
        C_Timer.After(0.3, function()
            retryScheduled = false
            MerchantFrame_UpdateMerchantInfo()
        end)
    end
end

hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
    -- Defer a hair so merchant data/links settle
    C_Timer.After(0.05, RefreshMerchantItems)
end)

---------------------------------------------------------
-- Merchant click feedback (no blocking, just feedback + override)
---------------------------------------------------------
local function HookMerchantButtons()
    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local btn = _G["MerchantItem" .. i .. "ItemButton"]
        if btn and not btn.__HideKnownHooked then
            btn.__HideKnownHooked = true

            btn:HookScript("OnClick", function(self, button)
                if not HideKnownVendorItemsDB.hideKnown then return end
                if not self.__HIDEKNOWN_LOCKED then return end

                if IsShiftKeyDown() and button == "RightButton" then
                    UIErrorsFrame:AddMessage(HideKnownVendorItems_GetLocaleString("ERROR_OVERRIDE"), 0.5, 1, 0.5)
                    self.__HIDEKNOWN_LOCKED = nil
                    return
                end

                UIErrorsFrame:AddMessage(HideKnownVendorItems_GetLocaleString("ERROR_KNOWN"), 1, 0, 0)
            end)
        end
    end
end

hooksecurefunc("MerchantFrame_UpdateMerchantInfo", HookMerchantButtons)

---------------------------------------------------------
-- Tooltip hint for override (modern, no OnTooltipSetItem)
---------------------------------------------------------
local function TryAddOverrideHint(tooltip)
    -- Some tooltips (e.g. ShoppingTooltip1) don't have GetItem
    if type(tooltip.GetItem) ~= "function" then return end

    local _, link = tooltip:GetItem()
    if not link then return end
    if not HideKnownVendorItemsDB.hideKnown then return end

    local known = IsItemKnown(link)
    if known == true then
        tooltip:AddLine(HideKnownVendorItems_GetLocaleString("TOOLTIP_OVERRIDE"), 0.7, 0.7, 0.7, true)
        tooltip:Show()
    end
end

-- Prefer modern TooltipDataProcessor; fallback to SetHyperlink/SetMerchantItem hooks
if TooltipDataProcessor and Enum and Enum.TooltipDataType and TooltipDataProcessor.AddTooltipPostCall then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, TryAddOverrideHint)
else
    hooksecurefunc(GameTooltip, "SetHyperlink", TryAddOverrideHint)
    hooksecurefunc(GameTooltip, "SetMerchantItem", TryAddOverrideHint)
end

---------------------------------------------------------
-- Slash command
---------------------------------------------------------
SLASH_HIDEKNOWN1 = "/hideknown"
SlashCmdList["HIDEKNOWN"] = function(msg)
    msg = msg and msg:lower() or ""
    local onMsg = HideKnownVendorItems_GetLocaleString("CMD_ON")
    local offMsg = HideKnownVendorItems_GetLocaleString("CMD_OFF")
    local toggleMsg = HideKnownVendorItems_GetLocaleString("CMD_TOGGLE")
    local usageMsg = HideKnownVendorItems_GetLocaleString("CMD_USAGE")
    local enabled = HideKnownVendorItems_GetLocaleString("ENABLED")
    local disabled = HideKnownVendorItems_GetLocaleString("DISABLED")

    if msg == "on" then
        HideKnownVendorItemsDB.hideKnown = true
        print("|cffffcc00HideKnownVendorItems:|r " .. onMsg)
    elseif msg == "off" then
        HideKnownVendorItemsDB.hideKnown = false
        print("|cffffcc00HideKnownVendorItems:|r " .. offMsg)
    elseif msg == "toggle" then
        HideKnownVendorItemsDB.hideKnown = not HideKnownVendorItemsDB.hideKnown
        print("|cffffcc00HideKnownVendorItems:|r " ..
            string.format(toggleMsg, (HideKnownVendorItemsDB.hideKnown and enabled or disabled)))
    else
        print("|cffffcc00HideKnownVendorItems:|r " .. usageMsg)
        print(string.format("Current: %s", (HideKnownVendorItemsDB.hideKnown and enabled or disabled)))
    end
    MerchantFrame_UpdateMerchantInfo()
end

--@debug@
-- /hkvidbg -> toggle debug
SLASH_HKVIDBG1 = "/hkvidbg"
SlashCmdList["HKVIDBG"] = function()
    HKVI_DBG = not HKVI_DBG
    print("|cffffcc00HKVI:|r Debug is now", HKVI_DBG and "|cff20ff20ON|r" or "|cffff2020OFF|r")
end

-- /hkvidump <slot> -> dump tooltip lines for the merchant slot (1..MERCHANT_ITEMS_PER_PAGE)
SLASH_HKVIDUMP1 = "/hkvidump"
SlashCmdList["HKVIDUMP"] = function(msg)
    local idx = tonumber(msg)
    if not idx then
        print("|cffffcc00HKVI:|r Usage: /hkvidump <slot 1-"..(MERCHANT_ITEMS_PER_PAGE or 10)..">")
        return
    end
    local link = GetMerchantItemLink((MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE + idx)
    if not link then
        print("|cffffcc00HKVI:|r No link for slot", idx)
        return
    end
    print("|cffffcc00HKVI:|r Dump for slot", idx, link)
    local tip = C_TooltipInfo.GetHyperlink(link)
    if not tip or not tip.lines then
        print("|cffffcc00HKVI:|r (no tooltip data)")
        return
    end
    for i, line in ipairs(tip.lines) do
        print(i, line.leftText or "")
    end
end
--@end-debug@

---------------------------------------------------------
-- Modern Settings Panel
---------------------------------------------------------
local function CreateSettingsPanel()
    local categoryName = HideKnownVendorItems_GetLocaleString("ADDON_TITLE")
    local panel = CreateFrame("Frame")
    panel.name = categoryName

    -- Title
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(categoryName)

    -- Checkbox
    local cb = CreateFrame("CheckButton", nil, panel, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
    cb.Text:SetText(HideKnownVendorItems_GetLocaleString("CHECKBOX_LABEL"))
    cb.tooltip = HideKnownVendorItems_GetLocaleString("CHECKBOX_TOOLTIP")
    cb:SetChecked(HideKnownVendorItemsDB.hideKnown)

    cb:SetScript("OnClick", function(self)
        HideKnownVendorItemsDB.hideKnown = self:GetChecked()
        MerchantFrame_UpdateMerchantInfo()
    end)

--@debug@
    -----------------------------------------------------
    -- Debug-only: translation coverage info
    -----------------------------------------------------
    local base = HideKnownVendorItems_Locales["enUS"]
    local baseCount = 0
    for _ in pairs(base) do baseCount = baseCount + 1 end

    local infoLines = {}
    for locale, data in pairs(HideKnownVendorItems_Locales) do
        if locale ~= "enUS" then
            local translatedCount = 0
            for key in pairs(base) do
                if data[key] then
                    translatedCount = translatedCount + 1
                end
            end
            local pct = math.floor((translatedCount / baseCount) * 100)
            table.insert(infoLines, string.format("%s: %d%%", locale, pct))
        end
    end

    if #infoLines > 0 then
        local info = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        info:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 0, -8)
        info:SetText("Translation coverage — " .. table.concat(infoLines, ", "))
    end
--@end-debug@

    local category = Settings.RegisterCanvasLayoutCategory(panel, categoryName)
    Settings.RegisterAddOnCategory(category)
end

---------------------------------------------------------
-- Initialization
---------------------------------------------------------
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName and not initialized then
        initialized = true
        HideKnownVendorItemsDB = HideKnownVendorItemsDB or { hideKnown = false }
        CreateSettingsPanel()
    elseif event == "MERCHANT_SHOW" then
        CreateVendorCheckbox()
        -- Kick one refresh a tick later to ensure item info is cached
        C_Timer.After(0.05, function()
            MerchantFrame_UpdateMerchantInfo()
        end)
    end
end)
