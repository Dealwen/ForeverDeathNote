local _, note = ...
local windows = {}

-- Uniform scaling keeps the native controls and text aligned.
function note.ManageWindow(frame, key, handle, onLayout)
    local root = ForeverDeathNoteDB
    root.layout = root.layout or {}
    local saved = root.layout[key] or {}
    root.layout[key] = saved
    local width, height = frame:GetWidth(), frame:GetHeight()
    local function limit()
        return math.min(1.55, (UIParent:GetWidth() - 20) / width, (UIParent:GetHeight() - 20) / height)
    end
    local function scale(value)
        local maximum = limit()
        frame:SetScale(math.min(maximum, math.max(math.min(0.65, maximum), value)))
    end
    local function place()
        scale(saved.scale or 1)
        if saved.x and saved.y then
            frame:ClearAllPoints()
            local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
            frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
                saved.x * UIParent:GetWidth() * ratio, saved.y * UIParent:GetHeight() * ratio)
        end
        if onLayout then onLayout() end
    end
    local function save()
        local x, y = frame:GetCenter()
        if x and y then
            local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
            saved.x, saved.y = x * ratio / UIParent:GetWidth(), y * ratio / UIParent:GetHeight()
        end
        saved.scale = frame:GetScale()
        if onLayout then onLayout() end
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(20, 20)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    local moving, resizing, startX, startY, startScale, left, top
    local function finish()
        if moving then frame:StopMovingOrSizing() end
        if moving or resizing then
            moving, resizing = nil, nil
            grip:SetScript("OnUpdate", nil)
            save()
        end
    end
    local function update()
        if InCombatLockdown() or not IsMouseButtonDown("LeftButton") then finish(); return end
        if resizing then
            local x, y = GetCursorPosition()
            local unit = UIParent:GetEffectiveScale()
            scale(startScale + ((x - startX) / width + (startY - y) / height) / (2 * unit))
            local ratio = frame:GetEffectiveScale()
            frame:ClearAllPoints()
            frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / ratio, top / ratio)
        end
        if onLayout then onLayout() end
    end
    grip:SetScript("OnMouseDown", function(_, mouse)
        if mouse ~= "LeftButton" or InCombatLockdown() or not frame:GetLeft() then return end
        startX, startY = GetCursorPosition()
        startScale = frame:GetScale()
        left, top = frame:GetLeft() * frame:GetEffectiveScale(), frame:GetTop() * frame:GetEffectiveScale()
        resizing = true
        grip:SetScript("OnUpdate", update)
    end)
    grip:SetScript("OnMouseUp", finish)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    handle = handle or frame
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function()
        if InCombatLockdown() then return end
        frame:StartMoving()
        moving = true
        grip:SetScript("OnUpdate", update)
    end)
    handle:SetScript("OnDragStop", finish)
    frame:HookScript("OnHide", finish)
    windows[frame] = place
    place()
end

function note.WindowDragHandle(frame, height, width)
    local handle = CreateFrame("Frame", nil, frame)
    handle:SetPoint("TOPLEFT", 8, -4)
    handle:SetSize(width, height)
    return handle
end

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
watcher:RegisterEvent("UI_SCALE_CHANGED")
watcher:SetScript("OnEvent", function()
    for _, place in pairs(windows) do place() end
end)

-- Protected target buttons stay independent of the informational windows.
function note.PlaceTargetControl(button, frame, x, y)
    if not button or InCombatLockdown() then return end
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    button:SetScale(frame:GetEffectiveScale() / UIParent:GetEffectiveScale())
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left + x, top + y)
end
