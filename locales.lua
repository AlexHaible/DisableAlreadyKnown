HideKnownVendorItems_Locales = {
    ["enUS"] = {
        ALREADY_KNOWN = "Already known",
        CHECKBOX_LABEL = "Hide Known",
        CHECKBOX_TOOLTIP = "Gray out and block known recipes, pets, and mounts.",
        ERROR_KNOWN = "You already know this item!",
        ERROR_OVERRIDE = "Override: purchasing known item.",
        TOOLTIP_OVERRIDE = "Shift+Right-Click to override",
        CMD_USAGE = "Usage: /hideknown [on|off|toggle]",
        CMD_ON = "Hiding known items enabled.",
        CMD_OFF = "Hiding known items disabled.",
        CMD_TOGGLE = "Now %s.",
        ENABLED = "enabled",
        DISABLED = "disabled",
    },

    ["deDE"] = {
        ALREADY_KNOWN = "Bereits bekannt",
        CHECKBOX_LABEL = "Bekannte ausblenden",
        CHECKBOX_TOOLTIP = "Blendet bekannte Rezepte, Haustiere und Reittiere aus.",
        ERROR_KNOWN = "Ihr kennt diesen Gegenstand bereits!",
        ERROR_OVERRIDE = "Überschreiben: Bekannten Gegenstand kaufen.",
        TOOLTIP_OVERRIDE = "Shift+Rechtsklick zum Überschreiben",
        CMD_USAGE = "Verwendung: /hideknown [on|off|toggle]",
        CMD_ON = "Bekannte Gegenstände werden ausgeblendet.",
        CMD_OFF = "Bekannte Gegenstände werden angezeigt.",
        CMD_TOGGLE = "Jetzt %s.",
        ENABLED = "aktiviert",
        DISABLED = "deaktiviert",
    },

    ["frFR"] = {
        ALREADY_KNOWN = "Déjà connu",
        CHECKBOX_LABEL = "Masquer connus",
        CHECKBOX_TOOLTIP = "Grise et bloque les recettes, familiers et montures déjà connus.",
        ERROR_KNOWN = "Vous connaissez déjà cet objet !",
        ERROR_OVERRIDE = "Forcer : achat d’un objet déjà connu.",
        TOOLTIP_OVERRIDE = "Maj+Clic droit pour forcer",
        CMD_USAGE = "Utilisation : /hideknown [on|off|toggle]",
        CMD_ON = "Masquage des objets connus activé.",
        CMD_OFF = "Masquage des objets connus désactivé.",
        CMD_TOGGLE = "Maintenant %s.",
        ENABLED = "activé",
        DISABLED = "désactivé",
    },
}

-- === Locale Accessor ===
function HideKnownVendorItems_GetLocaleString(key)
    local loc = GetLocale()
    local tbl = HideKnownVendorItems_Locales[loc] or HideKnownVendorItems_Locales["enUS"]
    return tbl[key] or HideKnownVendorItems_Locales["enUS"][key] or ("<missing " .. key .. ">")
end

--@debug@
-- === Validation ===
local function ValidateLocales()
    local baseLocale = "enUS"
    local base = HideKnownVendorItems_Locales[baseLocale]
    local baseCount = 0
    for _ in pairs(base) do baseCount = baseCount + 1 end

    print("|cffffcc00HideKnownVendorItems:|r Locale validation starting...")

    for locale, data in pairs(HideKnownVendorItems_Locales) do
        if locale ~= baseLocale then
            local missing, extra = {}, {}
            local translatedCount = 0

            for key in pairs(base) do
                if not data[key] then
                    table.insert(missing, key)
                else
                    translatedCount = translatedCount + 1
                end
            end

            for key in pairs(data) do
                if not base[key] then
                    table.insert(extra, key)
                end
            end

            local coverage = math.floor((translatedCount / baseCount) * 100)
            print(string.format("  %s: %d/%d (%d%%) translated", locale, translatedCount, baseCount, coverage))

            for _, key in ipairs(missing) do
                print(string.format("    |cffffff00Missing:|r %s", key))
            end
            for _, key in ipairs(extra) do
                print(string.format("    |cffff6666Extra:|r %s", key))
            end
        end
    end

    print("|cffffcc00HideKnownVendorItems:|r Locale validation complete.")
end

ValidateLocales()
--@end-debug@
