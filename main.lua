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

local HKVI_FilteredIndices = {}
local HKVI_FilteredPages = 1
local HKVI_KnownCache = {}
local HKVI_KNOWN_STR = (ITEM_SPELL_KNOWN or "Already known"):lower()

---------------------------------------------------------
-- Sync the "Page X of Y" label with our filtered pages
---------------------------------------------------------
local function HKVI_UpdatePageLabel()
    if not HideKnownVendorItemsDB.hideKnown then return end
    if not HKVI_FilteredPages then return end
    if not MerchantPageText then return end

    local page = MerchantFrame.page or 1
    MerchantPageText:SetText(string.format(MERCHANT_PAGE_NUMBER, page, HKVI_FilteredPages))
end

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

    local cached = HKVI_KnownCache[itemID]
    if cached ~= nil then
        return cached
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
            if text:find(HKVI_KNOWN_STR, 1, true) then
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
    HKVI_KnownCache[itemID] = res

    --@debug@
    HKVI_LogOnce(itemLink, "IsItemKnown ->", res and "true" or "false",
        "(known:", foundKnown, "pet:", foundCollectedPet, "uncollected:", foundUncollected, ")")
    --@end-debug@

    return res
end

---------------------------------------------------------
-- Vendor item refresh (with one-shot async retry)
---------------------------------------------------------
-- Force a merchant slot (1..MERCHANT_ITEMS_PER_PAGE) to display a specific
-- vendor index (1..GetMerchantNumItems()).
local function HKVI_SetMerchantSlot(slot, merchantIndex)
    local itemFrame = _G["MerchantItem"..slot]
    if not itemFrame then return end

    local itemButton = _G["MerchantItem"..slot.."ItemButton"]
    local nameText  = _G[itemFrame:GetName().."Name"]
    local moneyFrame = _G[itemFrame:GetName().."MoneyFrame"]

    local name, texture, price, quantity, numAvailable, isUsable, extendedCost = C_MerchantFrame.GetItemInfo(merchantIndex)
    local itemLink = GetMerchantItemLink(merchantIndex)

    itemFrame:Show()

    -- button basics
    itemButton:SetID(merchantIndex)
    SetItemButtonTexture(itemButton, texture)
    SetItemButtonCount(itemButton, quantity)
    SetItemButtonStock(itemButton, numAvailable)

    -- name
    if nameText then
        nameText:SetText(name or "")
        nameText:SetTextColor(1, 1, 1)
    end

    -- price
    if price and price > 0 then
        moneyFrame:Show()
        MoneyFrame_Update(moneyFrame, price)
    else
        moneyFrame:Hide()
    end

    -- icon state (we don't gray out anymore)
    if itemButton.icon then
        itemButton.icon:SetDesaturated(false)
    end
    itemButton:SetAlpha(1)

    -- extended cost indicator (if Blizzard skinned it)
    local altCurrencyFrame = _G[itemFrame:GetName().."AltCurrencyFrame"]
    if extendedCost and altCurrencyFrame then
        altCurrencyFrame:Show()
        MerchantFrame_UpdateAltCurrency(merchantIndex, altCurrencyFrame)
    elseif altCurrencyFrame then
        altCurrencyFrame:Hide()
    end
end

local retryScheduled = false
--@debug@ local hkvi_lastRefreshPrint = 0 --@end-debug@

local function RefreshMerchantItems()
    hkvi_seen = {}

    local active = HideKnownVendorItemsDB.hideKnown
    local numItems = GetMerchantNumItems()
    local needsRetry = false

    -- if disabled: just let Blizzard do its normal thing, show all 12
    if not active then
        wipe(HKVI_FilteredIndices)
        HKVI_FilteredPages = 1
        for i = 1, MERCHANT_ITEMS_PER_PAGE do
            local f = _G["MerchantItem"..i]
            if f then f:Show() end
        end
        -- let Blizzard's pagination be visible again
        HKVI_UpdatePageLabel()  -- this will early-return if not active
        return
    end

    -- 1) rebuild filtered list from scratch
    wipe(HKVI_FilteredIndices)

    for i = 1, numItems do
        local itemLink = GetMerchantItemLink(i)
        if itemLink then
            local known = IsItemKnown(itemLink)
            if known == nil then
                -- not cached yet -> we KEEP it so it can appear later, but we schedule retry
                needsRetry = true
                table.insert(HKVI_FilteredIndices, i)
            elseif known == false then
                -- show
                table.insert(HKVI_FilteredIndices, i)
            else
                -- known == true -> we don't add it (this is the hide)
            end
        else
            -- link not ready -> keep and retry
            needsRetry = true
            table.insert(HKVI_FilteredIndices, i)
        end
    end

    -- 2) compute page count based on filtered list
    local totalFiltered = #HKVI_FilteredIndices
    HKVI_FilteredPages = math.max(1, math.ceil(totalFiltered / MERCHANT_ITEMS_PER_PAGE))

    -- clamp merchant frame page to our page count
    local page = MerchantFrame.page or 1
    if page > HKVI_FilteredPages then
        page = HKVI_FilteredPages
        MerchantFrame.page = page
    elseif page < 1 then
        page = 1
        MerchantFrame.page = page
    end

    -- 3) render that page
    local startIndex = (page - 1) * MERCHANT_ITEMS_PER_PAGE + 1

    for slot = 1, MERCHANT_ITEMS_PER_PAGE do
        local filteredIndex = startIndex + slot - 1
        local merchantIndex = HKVI_FilteredIndices[filteredIndex]
        local itemFrame = _G["MerchantItem"..slot]

        if merchantIndex then
            HKVI_SetMerchantSlot(slot, merchantIndex)
        else
            if itemFrame then
                itemFrame:Hide()
            end
        end
    end

    HKVI_UpdatePageLabel()

    -- 4) schedule retry if needed
    if needsRetry and not retryScheduled then
        retryScheduled = true
        C_Timer.After(0.3, function()
            retryScheduled = false
            MerchantFrame_UpdateMerchantInfo()
        end)
    end
end

-- Keep merchant paging inside our filtered page range
local function HKVI_ClampPage()
    if not HideKnownVendorItemsDB.hideKnown then return end
    if not HKVI_FilteredPages then return end
    if MerchantFrame.page > HKVI_FilteredPages then
        MerchantFrame.page = HKVI_FilteredPages
    elseif MerchantFrame.page < 1 then
        MerchantFrame.page = 1
    end
end

-- Re-run after Blizzard’s pagination update
hooksecurefunc("MerchantFrame_UpdatePagination", function()
    HKVI_UpdatePageLabel()
end)

hooksecurefunc("MerchantPrevPageButton_OnClick", function()
    HKVI_ClampPage()
    -- force refresh because we changed page
    MerchantFrame_UpdateMerchantInfo()
end)

hooksecurefunc("MerchantNextPageButton_OnClick", function()
    HKVI_ClampPage()
    MerchantFrame_UpdateMerchantInfo()
end)

hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
    -- Defer a hair so merchant data/links settle
    C_Timer.After(0.05, RefreshMerchantItems)
end)

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
    local page = MerchantFrame.page or 1
    local filteredIndex = (page - 1) * MERCHANT_ITEMS_PER_PAGE + idx
    local merchantIndex = HKVI_FilteredIndices[filteredIndex]
    if not merchantIndex then
        print("|cffffcc00HKVI:|r No filtered item for slot", idx)
        return
    end
    local link = GetMerchantItemLink(merchantIndex)
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
