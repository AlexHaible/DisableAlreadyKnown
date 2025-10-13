local addonName = ...
local frame = CreateFrame("Frame")
local vendorCheckbox
HideKnownVendorItemsDB = HideKnownVendorItemsDB or { hideKnown = false }

-- === Forward declarations ===
local IsItemKnown

-- === Checkbox on vendor frame ===
local function CreateVendorCheckbox()
    if vendorCheckbox then return end

    local label = HideKnownVendorItems_GetLocaleString("CHECKBOX_LABEL")
    local tooltip = HideKnownVendorItems_GetLocaleString("CHECKBOX_TOOLTIP")

    vendorCheckbox = CreateFrame("CheckButton", nil, MerchantFrame, "UICheckButtonTemplate")
    vendorCheckbox.text:SetText(label)
    vendorCheckbox.tooltip = tooltip
    vendorCheckbox:SetChecked(HideKnownVendorItemsDB.hideKnown)

    -- Smart positioning:
    if MerchantFrameLootFilter and MerchantFrameLootFilter:IsShown() then
        vendorCheckbox:SetPoint("TOPRIGHT", MerchantFrameLootFilter, "BOTTOMRIGHT", 0, -4)
    else
        vendorCheckbox:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -40, -40)
    end

    vendorCheckbox:HookScript("OnClick", function(self)
        HideKnownVendorItemsDB.hideKnown = self:GetChecked()
        MerchantFrame_UpdateMerchantInfo()
    end)
end


-- === Known item detection ===
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

-- === Main vendor update hook ===
hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
    if not vendorCheckbox then
        CreateVendorCheckbox()
    end

    local active = HideKnownVendorItemsDB.hideKnown
    local numItems = GetMerchantNumItems()

    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local itemContainer = _G["MerchantItem" .. i]
        if itemContainer then
            local itemButton = _G["MerchantItem" .. i .. "ItemButton"]
            if itemButton then
                itemButton:Enable()
                itemButton.icon:SetDesaturated(false)
                itemButton:SetAlpha(1)
            end

            local name = _G[itemContainer:GetName() .. "Name"]
            name:SetTextColor(1, 1, 1)
        end
    end

    if active then
        for i = 1, numItems do
            local itemLink = GetMerchantItemLink(i)
            if itemLink and IsItemKnown(itemLink) then
                local index = i - (MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE
                local itemButton = _G["MerchantItem" .. index .. "ItemButton"]
                if itemButton then
                    itemButton.icon:SetDesaturated(true)
                    itemButton:SetAlpha(0.5)
                    itemButton:Disable()
                    local name = _G["MerchantItem" .. index .. "Name"]
                    name:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end
    end
end)

-- === Click hook with Shift+Right override ===
hooksecurefunc("MerchantItemButton_OnClick", function(self, button, ...)
    if not HideKnownVendorItemsDB.hideKnown then return end
    local index = (MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE + self:GetID()
    local link = GetMerchantItemLink(index)
    if not link or not IsItemKnown(link) then return end

    if IsShiftKeyDown() and button == "RightButton" then
        UIErrorsFrame:AddMessage(HideKnownVendorItems_GetLocaleString("ERROR_OVERRIDE"), 0.5, 1, 0.5)
        return
    end

    UIErrorsFrame:AddMessage(HideKnownVendorItems_GetLocaleString("ERROR_KNOWN"), 1, 0, 0)
    PlaySound(SOUNDKIT.IG_PLAYER_INVITE_DECLINE)
    return
end)

-- === Tooltip hint for override ===
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if GameTooltip and GameTooltip.HookScript then
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            local name, link = tooltip:GetItem()
            if not link then return end
            if not HideKnownVendorItemsDB.hideKnown then return end
            if not IsItemKnown(link) then return end

            tooltip:AddLine(HideKnownVendorItems_GetLocaleString("TOOLTIP_OVERRIDE"), 0.7, 0.7, 0.7, true)
            tooltip:Show()
        end)
    end
end)

-- === Slash command ===
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

-- === Modern Settings API Panel (Dragonflight+ compatible) ===
local function CreateSettingsPanel()
    local categoryName = "Hide Known Vendor Items"
    local panel = CreateFrame("Frame")
    panel.name = categoryName

    -- Create layout builder
    local layout = SettingsPanelUtil.CreateSettingsListCategory(categoryName)
    local category = Settings.RegisterCanvasLayoutCategory(layout, categoryName)

    -- Create checkbox
    local settingName = HideKnownVendorItems_GetLocaleString("CHECKBOX_LABEL")
    local tooltipText = HideKnownVendorItems_GetLocaleString("CHECKBOX_TOOLTIP")

    -- Create a variable-backed setting
    local setting = Settings.RegisterAddOnSetting(
        category,
        settingName,
        "HideKnownVendorItemsDB",
        "hideKnown",
        type(HideKnownVendorItemsDB.hideKnown),
        HideKnownVendorItemsDB.hideKnown
    )

    -- Create control checkbox
    local control = Settings.CreateCheckBox(category, setting, settingName, tooltipText)

    -- On setting change
    control:SetScript("OnClick", function(self)
        HideKnownVendorItemsDB.hideKnown = self:GetChecked()
        MerchantFrame_UpdateMerchantInfo()
    end)

--@debug@
    -------------------------------------------------------------------------
    -- Debug-only: add translation coverage info for developers/testers
    -------------------------------------------------------------------------
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
        local info = layout:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        info:SetText("Translation coverage — " .. table.concat(infoLines, ", "))
        layout:AddVerticalSpacing(8)
        layout:AddWidget(info)
    end
--@end-debug@

    -- Add the category to the Settings menu
    Settings.RegisterAddOnCategory(category)

    return category
end

CreateSettingsPanel()


-- === Initialization ===
frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", function()
    CreateVendorCheckbox()
end)
