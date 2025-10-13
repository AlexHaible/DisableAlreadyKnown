local addonName = ...
local frame = CreateFrame("Frame")
local vendorCheckbox
local initialized = false
HideKnownVendorItemsDB = HideKnownVendorItemsDB or { hideKnown = false }

-- === Forward declarations ===
local IsItemKnown

---------------------------------------------------------
-- Known item detection
---------------------------------------------------------
IsItemKnown = function(itemLink)
    if not itemLink then return false end

    local tooltipData = C_TooltipInfo.GetHyperlink(itemLink)
    if not tooltipData or not tooltipData.lines then return false end

    local searchStr = HideKnownVendorItems_GetLocaleString("ALREADY_KNOWN")
    for _, line in ipairs(tooltipData.lines) do
        if line.leftText and line.leftText:find(searchStr) then
            return true
        end
    end
    return false
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
-- Vendor item refresh
---------------------------------------------------------
hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
    if not vendorCheckbox then
        CreateVendorCheckbox()
    end

    local active = HideKnownVendorItemsDB.hideKnown
    local numItems = GetMerchantNumItems()

    -- Reset visuals
    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local itemContainer = _G["MerchantItem" .. i]
        if itemContainer then
            local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
            if itemButton then
                itemButton.__HIDEKNOWN_LOCKED = nil
                itemButton:Enable()
                itemButton.icon:SetDesaturated(false)
                itemButton:SetAlpha(1)
            end
            local name = _G[itemContainer:GetName() .. "Name"]
            name:SetTextColor(1, 1, 1)
        end
    end

    if not active then return end

    for i = 1, numItems do
        local itemLink = GetMerchantItemLink(i)
        if itemLink and IsItemKnown(itemLink) then
            local index = math.max(1, i - (MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE)
            local itemButton = _G["MerchantItem" .. index .. "ItemButton"]
            if itemButton then
                itemButton:SetMouseClickEnabled(true)
                itemButton:SetAlpha(0.5)
                itemButton.icon:SetDesaturated(true)
                itemButton.__HIDEKNOWN_LOCKED = true
                local name = _G["MerchantItem" .. index .. "Name"]
                name:SetTextColor(0.5, 0.5, 0.5)
            end
        end
    end
end)

---------------------------------------------------------
-- Merchant click feedback
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
                    UIErrorsFrame:AddMessage(
                        HideKnownVendorItems_GetLocaleString("ERROR_OVERRIDE"),
                        0.5, 1, 0.5)
                    self.__HIDEKNOWN_LOCKED = nil
                    return
                end

                UIErrorsFrame:AddMessage(
                    HideKnownVendorItems_GetLocaleString("ERROR_KNOWN"),
                    1, 0, 0)
            end)
        end
    end
end

hooksecurefunc("MerchantFrame_UpdateMerchantInfo", HookMerchantButtons)

---------------------------------------------------------
-- Tooltip hint for override
---------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if not GameTooltip then return end
    local ok = pcall(function()
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            local _, link = tooltip:GetItem()
            if not link then return end
            if not HideKnownVendorItemsDB.hideKnown then return end
            if not IsItemKnown(link) then return end

            tooltip:AddLine(HideKnownVendorItems_GetLocaleString("TOOLTIP_OVERRIDE"),
                0.7, 0.7, 0.7, true)
            tooltip:Show()
        end)
    end)

    if not ok then
        print("|cffff6600HideKnownVendorItems:|r Skipped GameTooltip hook (OnTooltipSetItem unavailable).")
    end

    -- Edge case: reload while vendor is open
    if MerchantFrame and MerchantFrame:IsShown() then
        MerchantFrame_UpdateMerchantInfo()
    end
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
    end
end)
