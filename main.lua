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

    -- Smart positioning that respects Blizzard’s filter dropdown
    local anchorFrame = MerchantFrameLootFilter or MerchantNameText

    vendorCheckbox:ClearAllPoints()
    if anchorFrame and anchorFrame:IsShown() then
        vendorCheckbox:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -6)
    else
        vendorCheckbox:SetPoint("TOPRIGHT", MerchantFrame, "TOPRIGHT", -42, -52)
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
                    itemButton:SetMouseClickEnabled(true)
                    itemButton:SetAlpha(0.5)
                    itemButton.icon:SetDesaturated(true)
                    itemButton.__HIDEKNOWN_LOCKED = true
                    local name = _G["MerchantItem" .. index .. "Name"]
                    name:SetTextColor(0.5, 0.5, 0.5)
                end
            end
        end
    end
end)

-- === Click hook with Shift+Right override ===
local function HookMerchantButtons()
    for i = 1, MERCHANT_ITEMS_PER_PAGE do
        local btn = _G["MerchantItem"..i.."ItemButton"]
        if btn and not btn.__HideKnownHooked then
            btn.__HideKnownHooked = true
            btn:HookScript("OnClick", function(self, button)
                if not HideKnownVendorItemsDB.hideKnown then return end
                if not self.__HIDEKNOWN_LOCKED then return end

                if IsShiftKeyDown() and button == "RightButton" then
                    UIErrorsFrame:AddMessage(HideKnownVendorItems_GetLocaleString("ERROR_OVERRIDE"), 0.5, 1, 0.5)
                    self.__HIDEKNOWN_LOCKED = nil -- one-time override
                    return
                end

                UIErrorsFrame:AddMessage(HideKnownVendorItems_GetLocaleString("ERROR_KNOWN"), 1, 0, 0)
                PlaySound(SOUNDKIT.IG_PLAYER_INVITE_DECLINE, "Master")
                -- Prevent Blizzard from processing this click
                self:SetPropagateKeyboardInput(false)
                self:SetPropagateMouseClicks(false)
            end)
        end
    end
end

hooksecurefunc("MerchantFrame_UpdateMerchantInfo", HookMerchantButtons)

-- === Tooltip hint for override ===
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if not GameTooltip then return end
    local ok = pcall(function()
        GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
            local name, link = tooltip:GetItem()
            if not link then return end
            if not HideKnownVendorItemsDB.hideKnown then return end
            if not IsItemKnown(link) then return end

            tooltip:AddLine(HideKnownVendorItems_GetLocaleString("TOOLTIP_OVERRIDE"), 0.7, 0.7, 0.7, true)
            tooltip:Show()
        end)
    end)

    if not ok then
        print("|cffff6600HideKnownVendorItems:|r Skipped GameTooltip hook (OnTooltipSetItem unavailable).")
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

-- === Modern Settings API Panel (simple, safe version) ===
local function CreateSettingsPanel()
    local categoryName = "Hide Known Vendor Items"
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
        local info = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        info:SetPoint("TOPLEFT", cb, "BOTTOMLEFT", 0, -8)
        info:SetText("Translation coverage — " .. table.concat(infoLines, ", "))
    end
--@end-debug@

    -- Register the panel with Blizzard Settings UI (modern way)
    local category = Settings.RegisterCanvasLayoutCategory(panel, categoryName)
    Settings.RegisterAddOnCategory(category)
end

CreateSettingsPanel()

-- === Initialization ===
frame:RegisterEvent("MERCHANT_SHOW")
frame:SetScript("OnEvent", function()
    CreateVendorCheckbox()
end)
