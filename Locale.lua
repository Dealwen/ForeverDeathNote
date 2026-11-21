local _, note = ...

local languages = {
    { "auto", "Как в WoW" },
    { "enUS", "English" },
    { "ruRU", "Русский" },
    { "deDE", "Deutsch" },
    { "frFR", "Français" },
    { "esES", "Español" },
    { "ptBR", "Português (Brasil)" },
    { "koKR", "한국어" },
}
local labels = {}
for _, language in ipairs(languages) do labels[language[1]] = language[2] end
local aliases = { enGB = "enUS", esMX = "esES", ptPT = "ptBR" }
local clientLocale = GetLocale and GetLocale() or "enUS"
local active

note.languages = languages
note.translations = {}

function note.LanguagePreference()
    local saved = ForeverDeathNoteDB and ForeverDeathNoteDB.locale
    return labels[saved] and saved or "auto"
end

local function effectiveLocale()
    local choice = note.LanguagePreference()
    if choice ~= "auto" then return choice end
    return aliases[clientLocale] or (labels[clientLocale] and clientLocale) or "enUS"
end

function note.InitLocale()
    active = effectiveLocale()
end

function note.GetLanguage()
    return active or effectiveLocale()
end

note.L = setmetatable({}, { __index = function(_, key)
    local locale = note.GetLanguage()
    if locale == "ruRU" then return key end
    local catalog, fallback = note.translations[locale], note.translations.enUS
    return (catalog and catalog[key]) or (fallback and fallback[key]) or key
end })

function note.LanguageLabel(locale)
    if locale == "auto" then return note.L[labels.auto] end
    return labels[locale]
end

function note.ApplyLanguage(locale)
    if not labels[locale] or not ForeverDeathNoteDB or locale == note.LanguagePreference() then return end
    if InCombatLockdown() then return false, note.L["Сменить язык можно после выхода из боя."] end
    ForeverDeathNoteDB.locale = locale
    if ReloadUI then ReloadUI() end
    return true, note.L["Язык сохранён. Введите /reload."]
end

function note.SampleText(value, demo)
    if demo and value then return note.L[value] end
    return value
end

local classIndex = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5,
    SHAMAN = 6, MAGE = 7, WARLOCK = 8, DRUID = 9,
}
local classLabels = {
    enUS = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" },
    ruRU = { "Воин", "Паладин", "Охотник", "Разбойник", "Жрец", "Шаман", "Маг", "Чернокнижник", "Друид" },
    deDE = { "Krieger", "Paladin", "Jäger", "Schurke", "Priester", "Schamane", "Magier", "Hexenmeister", "Druide" },
    frFR = { "Guerrier", "Paladin", "Chasseur", "Voleur", "Prêtre", "Chaman", "Mage", "Démoniste", "Druide" },
    esES = { "Guerrero", "Paladín", "Cazador", "Pícaro", "Sacerdote", "Chamán", "Mago", "Brujo", "Druida" },
    ptBR = { "Guerreiro", "Paladino", "Caçador", "Ladino", "Sacerdote", "Xamã", "Mago", "Bruxo", "Druida" },
    koKR = { "전사", "성기사", "사냥꾼", "도적", "사제", "주술사", "마법사", "흑마법사", "드루이드" },
}
local raceKeys = {
    Human = "Человек", Dwarf = "Дворф", Gnome = "Гном", NightElf = "Ночной эльф",
    Tauren = "Таурен", Scourge = "Нежить", Troll = "Тролль", Orc = "Орк",
}

function note.ClassLabel(token, sex)
    if not token then return end
    local locale = note.GetLanguage()
    local gameLabels = sex == 3 and LOCALIZED_CLASS_NAMES_FEMALE or LOCALIZED_CLASS_NAMES_MALE
    if locale == (aliases[clientLocale] or clientLocale) and gameLabels and gameLabels[token] then
        return gameLabels[token]
    end
    return classLabels[locale][classIndex[token]] or (gameLabels and gameLabels[token]) or token
end

function note.RaceLabel(profile, demo)
    local key = raceKeys[profile.raceFile]
    if key then return note.L[key] end
    return note.SampleText(profile.race, demo)
end
