local _, note = ...
local prefix = "FDNPVPRelay1"
local maxAge, inboxLimit, retrySeconds = 30 * 86400, 4000, 90
local listener = CreateFrame("Frame")
local registered, ticker, scope, region, realm, ownName, ownKey
local inboxIndex, unsaved, sentTimes, outstanding, lastProbeAt = {}, {}, {}, {}, {}
local lastReportAt = {}
local cursor = 0
local probe

-- Configure a collector for each supported region, realm and faction when releasing.
-- The pilot uses a per-scope /fdn relay target override instead.
local collectors = {
    -- ["3/PvP/Alliance"] = "Collector-PvP",
}

local function identity(value)
    local text = note.Text(value)
    if not text or text:find("%s") then return end
    local name, home = text:match("^([^%-]+)%-(.+)$")
    name, home = name or text, home or realm
    if not home then return end
    home = home:gsub("[%s%-]", "")
    if name == "" or home == "" then return end
    return name .. "-" .. home, name
end

local function sameName(left, right)
    left, right = identity(left), identity(right)
    return left ~= nil and right ~= nil and left:lower() == right:lower()
end

local function target()
    local root = ForeverDeathNoteDB
    if not scope or not root then return end
    return (root.mapRelayTargets or {})[scope] or collectors[scope]
end

function note.MapRelayHasTarget()
    return target() ~= nil
end

function note.MapRelayIsCollector()
    local root = ForeverDeathNoteDB
    return root and note.owner and (root.mapRelayCollectors or {})[note.owner] == true
end

local function reportId(row)
    return ("%d:%s:%s:%s"):format(row.at, row.kind, row.killerId, row.victimId)
end

local function delivered()
    local root = ForeverDeathNoteDB
    root.mapRelayDelivered = root.mapRelayDelivered or {}
    return root.mapRelayDelivered
end

local function inbox()
    local root = ForeverDeathNoteDB
    root.mapRelayInbox = root.mapRelayInbox or {}
    return root.mapRelayInbox
end

local function send(recipient, message)
    if not registered or not recipient or #message > 250 then return end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, prefix, message, "WHISPER", recipient)
    if not ok then return end
    local codes = Enum and Enum.SendAddonMessageResult
    return result == nil or result == true or result == (codes and codes.Success or 0)
end

local function encode(row)
    local fields = {
        "O", row.region, row.realm, row.at, row.kind, row.killerId, row.victimId,
        row.mapId or "", row.x or "", row.y or "", row.killerFaction or "",
        row.killer or "", row.victim or "", row.zone or "",
    }
    local message = table.concat(fields, ";")
    if #message <= 250 then return message end
    fields[14] = ""
    message = table.concat(fields, ";")
    if #message <= 250 then return message end
    fields[12], fields[13] = "", ""
    return table.concat(fields, ";")
end

local function playerKey(value)
    return #value == 18 and value:match("^p%-%x+$") and value:lower()
end

local function coordinate(value)
    local number = tonumber(value)
    if number and number >= 0 and number <= 10000 and number == math.floor(number) then return number end
end

local function decode(message, sender, displayName)
    local fields = {}
    for field in (message .. ";"):gmatch("(.-);") do fields[#fields + 1] = field end
    if #fields ~= 14 or tonumber(fields[2]) ~= region or fields[3] ~= realm then return end
    local at = note.PositiveInteger(tonumber(fields[4]), 2147483647)
    local now = GetServerTime()
    if not at or at < now - maxAge or at > now + 30 then return end
    local kind, killerId, victimId = fields[5], playerKey(fields[6]), playerKey(fields[7])
    if (kind ~= "K" and kind ~= "D") or not killerId or not victimId or killerId == victimId then return end
    local mapId = note.PositiveInteger(tonumber(fields[8]), 1000000)
    local x, y = coordinate(fields[9]), coordinate(fields[10])
    if not (mapId and x and y) then x, y = nil, nil end
    return {
        region = region, realm = realm, at = at, kind = kind, killerId = killerId, victimId = victimId,
        killerFaction = note.Faction(fields[11]), killer = kind == "K" and displayName or note.Text(fields[12]),
        victim = kind == "D" and displayName or note.Text(fields[13]), zone = note.Text(fields[14]),
        mapId = mapId, x = x, y = y, relayReporter = sender,
    }
end

local function accept(message, sender, displayName)
    local senderRealm = sender:match("%-(.+)$")
    if senderRealm:lower() ~= realm:gsub("[%s%-]", ""):lower() then return end
    local row = decode(message, sender, displayName)
    if not row then return end
    local now = GetTime()
    if lastReportAt[sender] and now - lastReportAt[sender] < 0.6 then return end
    lastReportAt[sender] = now
    local id = reportId(row)
    local key = sender:lower() .. "/" .. region .. "/" .. realm .. "/" .. id
    if inboxIndex[key] then
        -- A copy received in this session is still in memory until WoW saves it.
        if not unsaved[key] then send(sender, "D;" .. id) end
        return
    end
    local rows = inbox()
    if #rows >= inboxLimit then
        local old = table.remove(rows, 1)
        local oldKey = old.relayReporter:lower() .. "/" .. old.region .. "/" .. old.realm .. "/" .. reportId(old)
        inboxIndex[oldKey], unsaved[oldKey] = nil, nil
    end
    rows[#rows + 1] = row
    inboxIndex[key], unsaved[key] = true, true
end

local function tick()
    if not note.MapSyncEnabled() or note.MapRelayIsCollector() or not target() or InCombatLockdown() then return end
    local inside = IsInInstance()
    if inside then return end
    local rows = ForeverDeathNoteDB.mapObservations or {}
    local now = GetServerTime()
    local accepted = delivered()
    for _ = 1, #rows do
        cursor = (cursor % #rows) + 1
        local row = rows[cursor]
        local observer = row.kind == "K" and row.killerId or row.victimId
        if observer == ownKey and row.region == region and row.realm == realm and row.at >= now - maxAge then
            local id = reportId(row)
            local key = scope .. "/" .. id
            if not accepted[key] and now - (sentTimes[key] or 0) >= retrySeconds then
                sentTimes[key] = now
                outstanding[id] = key
                send(target(), encode(row))
                return
            end
        end
    end
end

local function incoming(_, _, eventPrefix, message, channel, rawSender)
    if note.Public(eventPrefix) ~= prefix or note.Public(channel) ~= "WHISPER" then return end
    message = note.Public(message)
    if type(message) ~= "string" or #message > 250 then return end
    local sender, displayName = identity(rawSender)
    if not sender or sameName(sender, ownName) then return end
    local kind, value = message:match("^(%u);(.+)$")
    if kind == "P" and note.MapRelayIsCollector() and value:match("^%d%d%d%d%d%d%d%d$") then
        local now = GetTime()
        if lastProbeAt[sender] and now - lastProbeAt[sender] < 3 then return end
        lastProbeAt[sender] = now
        if send(sender, "A;" .. value) then print("Forever Death Note · relay probe received from " .. sender) end
    elseif kind == "A" and probe and probe.id == value and sameName(sender, probe.target) then
        probe = nil
        print("Forever Death Note · relay reply received from " .. sender)
    elseif kind == "O" and note.MapRelayIsCollector() then
        accept(message, sender, displayName)
    elseif kind == "D" and outstanding[value] and sameName(sender, target()) then
        delivered()[outstanding[value]] = GetServerTime()
        outstanding[value] = nil
    end
end

function note.MapRelayAppendSaved(rows, cutoff, collector)
    for key, at in pairs(delivered()) do
        if at < cutoff then delivered()[key] = nil end
    end
    if not collector then return end
    local retained = {}
    for _, row in ipairs(inbox()) do
        local key = row.relayReporter:lower() .. "/" .. row.region .. "/" .. row.realm .. "/" .. reportId(row)
        if row.at >= cutoff then
            retained[#retained + 1] = row
            rows[#rows + 1] = row
        else
            inboxIndex[key], unsaved[key] = nil, nil
        end
    end
    ForeverDeathNoteDB.mapRelayInbox = retained
end

function note.StartMapRelay()
    if ticker or not note.db or not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix
        or not C_ChatInfo.SendAddonMessage or not C_Timer or not C_Timer.NewTicker or not C_Timer.After then return end
    region = note.PositiveInteger(GetCurrentRegion(), 5)
    realm = note.Text(GetRealmName())
    local faction = note.Faction(UnitFactionGroup("player"))
    if not (region and realm and faction) then return end
    scope = region .. "/" .. realm .. "/" .. faction
    ownKey = note.MapRelayPlayerKey(realm, note.owner)
    local first, home = UnitFullName("player")
    if first then ownName = identity(home and home ~= "" and first .. "-" .. home or first) end
    local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, prefix)
    local codes = Enum and Enum.RegisterAddonMessagePrefixResult
    if not ok or result == false or (type(result) == "number"
        and result ~= (codes and codes.Success or 0) and result ~= (codes and codes.DuplicatePrefix or 1)) then return end
    registered = true
    for _, row in ipairs(inbox()) do
        inboxIndex[row.relayReporter:lower() .. "/" .. row.region .. "/" .. row.realm .. "/" .. reportId(row)] = true
    end
    listener:RegisterEvent("CHAT_MSG_ADDON")
    listener:SetScript("OnEvent", incoming)
    ticker = C_Timer.NewTicker(1.5, tick)
end

function note.MapRelayCommand(command, argument)
    local root = ForeverDeathNoteDB
    if command == "collector" and (argument == "on" or argument == "off") then
        root.mapRelayCollectors = root.mapRelayCollectors or {}
        root.mapRelayCollectors[note.owner] = argument == "on" or nil
        if argument == "off" then ForeverDeathNoteMapExport = nil end
    elseif command == "target" and scope then
        if argument == "clear" or identity(argument) then
            root.mapRelayTargets = root.mapRelayTargets or {}
            root.mapRelayTargets[scope] = argument ~= "clear" and identity(argument) or nil
            root.mapRelayDelivered, sentTimes, outstanding = {}, {}, {}
        else
            print("Forever Death Note · /fdn relay target PLAYER-REALM")
            return
        end
    elseif command == "test" then
        local recipient = target()
        if not recipient or sameName(recipient, ownName) or not registered then
            print("Forever Death Note · set a different online collector before testing")
            return
        end
        local id = ("%08d"):format(math.random(0, 99999999))
        if not send(recipient, "P;" .. id) then
            print("Forever Death Note · client rejected the relay probe")
            return
        end
        probe = { id = id, target = recipient }
        print("Forever Death Note · waiting for relay reply from " .. recipient)
        C_Timer.After(15, function()
            if probe and probe.id == id then
                probe = nil
                print("Forever Death Note · no relay reply within 15 seconds")
            end
        end)
        return
    end
    print(("Forever Death Note · relay %s · collector %s · target %s · inbox %d"):format(
        registered and "ready" or "unavailable", note.MapRelayIsCollector() and "on" or "off",
        target() or "-", #inbox()))
end
