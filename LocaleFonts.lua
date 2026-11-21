local _, note = ...

local bundledFont = "Interface\\AddOns\\ForeverDeathNote\\Fonts\\FDNUISans-Regular.ttf"
local friz = "Fonts\\FRIZQT___CYR.TTF"
local morpheus = "Fonts\\MORPHEUS_CYR.TTF"
local korean = "Fonts\\2002.TTF"
local narrow = "Fonts\\ARIALN.TTF"
local buttonFonts = {}
local fontCount = 0

function note.FontPreference()
    return ForeverDeathNoteDB and ForeverDeathNoteDB.fontPreference == "compact" and "compact" or "warcraft"
end

function note.ApplyFontPreference(preset)
    if (preset ~= "warcraft" and preset ~= "compact") or not ForeverDeathNoteDB
        or preset == note.FontPreference() then return end
    if InCombatLockdown() then return false, note.L["Сменить шрифт можно после выхода из боя."] end
    ForeverDeathNoteDB.fontPreference = preset
    if ReloadUI then ReloadUI() end
    return true, note.L["Шрифт сохранён. Введите /reload."]
end

local function family(force, role)
    if force or note.FontPreference() == "compact" then return bundledFont end
    if role == "numbers" then return narrow, friz end
    local locale = note.GetLanguage()
    if locale == "koKR" then return korean end
    if role == "heading" then
        if locale == "ruRU" then return morpheus, friz end
        return "Fonts\\MORPHEUS.TTF", friz
    end
    return friz
end

local function sameFile(a, b)
    return type(a) == "string" and a:lower() == b:lower()
end

local function tryFont(region, file, size, flags)
    local ok, applied = pcall(region.SetFont, region, file, size, flags or "")
    return ok and (applied or applied == nil and sameFile(region:GetFont(), file))
end

local function setFont(region, file, size, flags, primary, alternate)
    if sameFile(file, primary) then return end
    if tryFont(region, primary, size, flags) then return true end
    if alternate then
        if sameFile(file, alternate) then return end
        if tryFont(region, alternate, size, flags) then return true end
    end
    if primary ~= bundledFont and not sameFile(file, bundledFont) then
        return tryFont(region, bundledFont, size, flags)
    end
end

local function replaceFont(region, primary, alternate)
    if not region then return end
    local file, size, flags = region:GetFont()
    if file and size and setFont(region, file, size, flags, primary, alternate) then
        return file, size, flags
    end
end

function note.StyleLocaleFont(region, force)
    return replaceFont(region, family(force))
end

function note.StyleHeadingFont(region)
    return replaceFont(region, family(false, "heading"))
end

function note.StyleNumberFont(region)
    return replaceFont(region, family(false, "numbers"))
end

function note.CreateFontString(parent, ...)
    local region = parent:CreateFontString(...)
    note.StyleLocaleFont(region)
    return region
end

local function localizedFont(source, force)
    if not source or not CreateFont then return source end
    local primary, alternate = family(force)
    local file, size, flags = source:GetFont()
    if not file or not size or sameFile(file, primary) then return source end
    local variants = buttonFonts[source]
    local font = variants and variants[primary]
    if font then return font end
    variants = variants or {}
    buttonFonts[source] = variants
    fontCount = fontCount + 1
    font = CreateFont("ForeverDeathNoteFont" .. fontCount)
    font:SetFontObject(source)
    variants[primary] = setFont(font, file, size, flags, primary, alternate) and font or source
    if variants[primary] == font then buttonFonts[font] = { [primary] = font } end
    return variants[primary]
end

function note.StyleLocaleButton(button, force)
    if note.StyleWarcraftButton then note.StyleWarcraftButton(button) end
    local normal, highlight, disabled = button:GetNormalFontObject(), button:GetHighlightFontObject(), button:GetDisabledFontObject()
    if normal then button:SetNormalFontObject(localizedFont(normal, force)) end
    if highlight then button:SetHighlightFontObject(localizedFont(highlight, force)) end
    if disabled then button:SetDisabledFontObject(localizedFont(disabled, force)) end
    note.StyleLocaleFont(button:GetFontString(), force)
end

function note.StyleLocaleMenu(description, force)
    if not description or not description.AddInitializer then return end
    description:AddInitializer(function(frame)
        local text = frame.fontString
        if not text then return end
        local font = text:GetFontObject()
        if font then text:SetFontObject(localizedFont(font, force)) end
        if text.SetTextToFit then text:SetTextToFit(text:GetText()) end
    end)
end

local tooltipStyles = {}
local function resetTooltip(tooltip)
    for region, font in pairs(tooltipStyles[tooltip]) do region:SetFont(unpack(font)) end
    wipe(tooltipStyles[tooltip])
end

function note.StyleLocaleTooltip(tooltip, first)
    if tooltip:IsForbidden() then return end
    local name, count = tooltip:GetName(), tooltip:NumLines()
    if not name or not count then return end
    local styles = tooltipStyles[tooltip]
    if not styles then
        styles = {}
        tooltipStyles[tooltip] = styles
        tooltip:HookScript("OnHide", resetTooltip)
        if tooltip:HasScript("OnTooltipCleared") then tooltip:HookScript("OnTooltipCleared", resetTooltip) end
    end
    for index = first or 1, count do
        for _, column in ipairs({ "Left", "Right" }) do
            local region = _G[name .. "Text" .. column .. index]
            if region then
                local file, size, flags = note.StyleLocaleFont(region)
                if file and not styles[region] then styles[region] = { file, size, flags } end
            end
        end
    end
end
