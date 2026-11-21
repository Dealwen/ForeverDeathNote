local _, note = ...
-- Guild beacons establish a scoped session. Whispers request inventory pages,
-- ask for missing positions, return report fragments, and close the session.
local prefix = "FDN_GSYNC1"
local maxPacket, maxPayload = 240, 880
local maxPeers, maxQueue = 24, 96
local offerSeconds, responseSeconds = 6, 20
local serviceSeconds, sessionSeconds = 75, 1200
local sendInterval, requestInterval, cooldown = 0.35, 480, 8
local retention = 30 * 86400
local listener = CreateFrame("Frame")
local current, result, context, registered, started, offerSnapshot
local providers, queue = {}, {}
local scheduled, nextRequest, nextManual, serial = false, 0, 0, 0

local function guild()
    return note.db and note.CurrentGuild and note.CurrentGuild()
end

local function allowed()
    return not InCombatLockdown() and not IsInInstance()
end

local function savedFor(name)
    local root = ForeverDeathNoteDB
    root.guildSync = root.guildSync or {}
    local realm = root.guildSync[note.scope] or {}
    root.guildSync[note.scope] = realm
    local key = (strlower or string.lower)(name)
    realm[key] = realm[key] or {}
    return realm[key]
end

local function refreshStatus()
    if note.RefreshGuildSyncStatus then note.RefreshGuildSyncStatus()
    elseif note.RefreshLadder then note.RefreshLadder() end
end

function note.GuildSyncStatus()
    local name = guild()
    local saved = name and savedFor(name)
    local status = current and current.guild == name and "syncing"
        or result and result.guild == name and result.state
        or saved and saved.lastSuccess and "ready" or "waiting"
    if not name then status = "no_guild"
    elseif not note.db.sharing then status = "disabled"
    elseif not registered then status = "unavailable" end
    return {
        state = status,
        added = current and current.guild == name and current.added
            or result and result.guild == name and result.added or saved and saved.added or 0,
        lastSuccess = saved and saved.lastSuccess,
        canRefresh = registered and name ~= nil and note.db.sharing and not current
            and allowed() and GetTime() >= nextManual or false,
    }
end

local function pump()
    if scheduled or #queue == 0 or not allowed() then return end
    local name = guild()
    while #queue > 0 do
        local packet = table.remove(queue, 1)
        if name == packet.guild and note.db.sharing and packet.valid() then
            scheduled = true
            local response = C_ChatInfo.SendAddonMessage(prefix, packet.text, packet.channel, packet.target)
            local codes = Enum and Enum.SendAddonMessageResult
            local throttled = type(response) == "number" and codes
                and (response == codes.AddonMessageThrottle or response == codes.ChannelThrottle)
            local delay = sendInterval
            if throttled and (packet.retries or 0) < 3 and #queue < maxQueue then
                packet.retries = (packet.retries or 0) + 1
                table.insert(queue, 1, packet)
                delay = 0.9
            end
            C_Timer.After(delay, function()
                scheduled = false
                pump()
            end)
            return
        end
    end
end

local function send(name, valid, text, target)
    if #text > maxPacket or #queue >= maxQueue then return end
    queue[#queue + 1] = {
        guild = name, valid = valid, text = text, channel = target and "WHISPER" or "GUILD", target = target,
    }
    pump()
    return true
end

local function validNonce(nonce)
    return nonce and #nonce <= 44 and nonce:match("^%x+%.%x+%.%x+$")
end

local function integer(value, minimum, maximum)
    local n = tonumber(value)
    if n and n >= minimum and n <= maximum and n == math.floor(n) then return n end
end

local function keyStamp(key)
    if #key > 148 then return end
    local stamp, killer, victim = key:match("^[KD];(%d+);([^;]+);([^;]+)$")
    if stamp and note.GUID(killer) and note.GUID(victim) and killer ~= victim then
        return integer(stamp, 1, 0xFFFFFFFF)
    end
end

local function fingerprint(records, now)
    -- Compact set comparison for already synchronized peers. Differing sets
    -- still exchange exact keys before requesting any report.
    local count, totalA, totalB = 0, 0, 0
    local modA, modB = 4294967291, 4294967279
    for key in pairs(records) do
        local stamp = keyStamp(key)
        if stamp and stamp >= now - retention and stamp <= now + 30 then
            local hashA, hashB = 17, 101
            for i = 1, #key do
                local c = key:byte(i)
                hashA = (hashA * 131 + c) % modA
                hashB = (hashB * 257 + c) % modB
            end
            -- Nonlinear finalization keeps an additive set digest sensitive
            -- to swaps between otherwise equal-length report fields.
            local lowA, lowB = hashA % 65536, hashB % 65536
            local highA, highB = math.floor(hashA / 65536), math.floor(hashB / 65536)
            hashA = (hashA * 65521 + lowA * lowA * 1277 + lowA * highA * 241 + highA * highA * 97) % modA
            hashB = (hashB * 65519 + lowB * lowB * 1151 + lowB * highB * 239 + highB * highB * 89) % modB
            count = count + 1
            totalA, totalB = (totalA + hashA) % modA, (totalB + hashB) % modB
        end
    end
    return ("%d.%x.%x"):format(count, totalA, totalB)
end

local function sortedKeys(records)
    local keys, stamps, now = {}, {}, GetServerTime()
    for key in pairs(records) do
        local stamp = keyStamp(key)
        if stamp and stamp >= now - retention and stamp <= now + 30 then
            keys[#keys + 1], stamps[key] = key, stamp
        end
    end
    table.sort(keys, function(a, b)
        if stamps[a] ~= stamps[b] then return stamps[a] > stamps[b] end
        return a < b
    end)
    return keys
end

local function providerSend(provider, message, target)
    return send(provider.guild, function() return providers[provider.sender] == provider end, message, target)
end

local function publishPage(provider, offset)
    if not provider.keys then provider.keys = sortedKeys(provider.records) end
    local keys = provider.keys
    if offset > #keys + 1 then return end
    local header = "I|" .. provider.nonce .. "|" .. offset .. "|"
    local page, size = {}, #header + 2
    for index = offset, #keys do
        local key = keys[index]
        if size + #key + 1 > maxPacket then break end
        size = size + #key + 1
        page[#page + 1] = key
    end
    local last = offset + #page > #keys
    provider.offset, provider.page = offset, page
    providerSend(provider, header .. (last and "1|" or "0|") .. table.concat(page, ","), provider.sender)
end

local function fragments(payload)
    local parts, first = {}, 1
    while first <= #payload do
        local last = math.min(first + 174, #payload)
        while last >= first do
            local following = payload:byte(last + 1)
            if not following or following < 128 or following >= 192 then break end
            last = last - 1
        end
        if last < first then return end
        parts[#parts + 1] = payload:sub(first, last)
        first = last + 1
    end
    return parts
end

local function publishRecords(provider, offset, selection)
    if provider.offset ~= offset or not provider.page then return end
    local requested, seen = {}, {}
    for position in selection:gmatch("[^,]+") do
        local index = integer(position, 1, #provider.page)
        if not index or seen[index] then return end
        requested[#requested + 1], seen[index] = index, true
    end
    if #requested == 0 or table.concat(requested, ",") ~= selection then return end
    for _, index in ipairs(requested) do
        local key = provider.page[index]
        local payload = provider.records[key]
        if type(payload) == "string" and #payload > 0 and #payload <= maxPayload then
            local parts = fragments(payload)
            if parts then
                for part, text in ipairs(parts) do
                    local header = table.concat({ "D", provider.nonce, offset, index, part, #parts }, "|")
                    providerSend(provider, header .. "|" .. text, provider.sender)
                end
            end
        end
    end
end

local function flushChanges(session)
    if not session.changed then return end
    session.changed = nil
    if note.RefreshGuildHistory then note.RefreshGuildHistory()
    elseif note.RefreshLadder then note.RefreshLadder() end
end

local function finish(session)
    if current ~= session then return end
    current = nil
    if session.completed > 0 and not session.failed then
        local saved = savedFor(session.guild)
        saved.lastSuccess, saved.added = GetServerTime(), session.added
    end
    result = {
        guild = session.guild, added = session.added,
        state = session.failed and "partial" or session.completed > 0 and "ready" or "waiting",
    }
    flushChanges(session)
    refreshStatus()
end

local function clientSend(session, opcode, arguments)
    local message = opcode .. "|" .. session.nonce .. (arguments and "|" .. arguments or "")
    return send(session.guild, function() return current == session end, message, session.peer)
end

local function nextPeer(session, failed)
    if session.peer then
        local oldPeer = session.peer
        send(session.guild, function() return true end, "X|" .. session.nonce, oldPeer)
        if failed then
            session.failed = true
        else
            session.completed = session.completed + 1
            session.confirmed[session.peerFingerprint] = true
        end
    end
    flushChanges(session)
    session.peerIndex = session.peerIndex + 1
    local offer = session.offers[session.peerIndex]
    while offer and session.confirmed[offer.fingerprint] do
        session.completed = session.completed + 1
        send(session.guild, function() return true end, "X|" .. session.nonce, offer.sender)
        session.peerIndex = session.peerIndex + 1
        offer = session.offers[session.peerIndex]
    end
    if not offer then finish(session); return end
    session.peer, session.peerFingerprint = offer.sender, offer.fingerprint
    session.offset, session.wanted = 1, nil
    session.retries, session.deadline = 0, GetTime() + responseSeconds
    clientSend(session, "P", "1")
end

local function nextPage(session)
    if session.last then nextPeer(session); return end
    flushChanges(session)
    session.offset = session.offset + session.pageCount
    session.wanted, session.retries, session.deadline = nil, 0, GetTime() + responseSeconds
    clientSend(session, "P", tostring(session.offset))
end

local function requestMissing(session)
    local indices = {}
    for index, item in ipairs(session.wanted) do
        if item.key and not item.done then indices[#indices + 1] = index end
    end
    if #indices == 0 then nextPage(session); return end
    clientSend(session, "W", session.offset .. "|" .. table.concat(indices, ","))
end

local function acceptPage(session, body)
    local position, last, packed = body:match("^(%d+)|([01])|(.*)$")
    if session.wanted or tonumber(position) ~= session.offset then return end
    local items, seen, now = {}, {}, GetServerTime()
    for key in packed:gmatch("[^,]+") do
        local stamp = keyStamp(key)
        if not stamp or seen[key] then return end
        local missing = stamp >= now - retention and stamp <= now + 30 and not session.known[key]
        items[#items + 1] = { key = missing and key or nil }
        seen[key] = true
    end
    if (#items == 0 and last ~= "1") or packed:find("^,") or packed:find(",,") or packed:find(",$") then return end
    session.wanted, session.pageCount, session.last = items, #items, last == "1"
    session.deadline, session.retries = GetTime() + responseSeconds, 0
    requestMissing(session)
end

local function acceptFragment(session, body)
    local offset, index, part, total, text = body:match("^(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
    if not session.wanted or tonumber(offset) ~= session.offset then return end
    index, part, total = tonumber(index), tonumber(part), tonumber(total)
    local item = index and session.wanted[index]
    if not item or not item.key or item.done or not part or part < 1 or not total or total > 6 or part > total
        or text == "" or #text > 175 or (item.total and item.total ~= total) then return end
    item.total, item.parts = total, item.parts or {}
    if item.parts[part] then return end
    item.parts[part] = text
    item.received = (item.received or 0) + 1
    session.deadline = GetTime() + responseSeconds
    if item.received ~= total then return end
    local payload = table.concat(item.parts)
    local key = payload:match("^[^;]+;([KD];%d+;[^;]+;[^;]+);")
    local added, changed
    if #payload <= maxPayload and key == item.key then added, changed = note.ReceiveGuildHistory(payload, session.guild) end
    if added == nil then
        item.total, item.parts, item.received = nil, nil, 0
        return
    end
    item.done, item.parts = true, nil
    session.known[key] = true
    if added then session.added = session.added + 1 end
    if changed then session.changed = true end
    for _, other in ipairs(session.wanted) do
        if other.key and not other.done then return end
    end
    nextPage(session)
end

local function offer(guildName, sender, nonce)
    if not allowed() or (current and current.nonce == nonce) then return end
    local now = GetTime()
    local existing = providers[sender]
    if existing and (existing.nonce == nonce or now - existing.offeredAt < cooldown) then return end
    local count = 0
    for _ in pairs(providers) do count = count + 1 end
    if count >= maxPeers and not existing then return end
    if not offerSnapshot or offerSnapshot.guild ~= guildName or now - offerSnapshot.at > 2 then
        local stamp = GetServerTime()
        local records = note.GuildHistoryRecords(guildName, stamp) or {}
        offerSnapshot = { guild = guildName, at = now, records = records, fingerprint = fingerprint(records, stamp) }
    end
    local provider = {
        guild = guildName, sender = sender, nonce = nonce, touched = now, offeredAt = now,
        records = offerSnapshot.records, fingerprint = offerSnapshot.fingerprint,
    }
    providers[sender] = provider
    C_Timer.After(math.random(2, 15) / 10, function()
        providerSend(provider, "O|" .. nonce .. "|" .. provider.fingerprint)
    end)
end

local function onMessage(text, channel, sender)
    local name = guild()
    if not name or not note.db.sharing or type(text) ~= "string" or #text > maxPacket
        or (channel ~= "GUILD" and channel ~= "WHISPER") then return end
    sender = note.Text(sender)
    if not sender then return end
    if not sender:find("-", 1, true) and GetNormalizedRealmName then
        local realm = note.Text(GetNormalizedRealmName())
        if realm then sender = sender .. "-" .. realm end
    end
    local kind, nonce, body = text:match("^(%u)|([^|]+)|?(.*)$")
    if not validNonce(nonce) then return end
    if channel == "GUILD" then
        if kind == "Q" and body == note.scope then offer(name, sender, nonce)
        elseif kind == "O" and current and current.guild == name and current.nonce == nonce
            and #body <= 29 and body:match("^%d+%.%x+%.%x+$")
            and not current.peer and #current.offers < maxPeers and not current.offered[sender] then
            current.offered[sender] = true
            current.offers[#current.offers + 1] = { sender = sender, fingerprint = body }
        end
        return
    end
    local provider = providers[sender]
    if provider and provider.guild == name and provider.nonce == nonce then
        if kind == "P" then
            local offset = body:match("^(%d+)$") and integer(body, 1, 1000000)
            if offset then
                provider.touched = GetTime()
                publishPage(provider, offset)
            end
        elseif kind == "W" then
            local offset, selected = body:match("^(%d+)|([%d,]+)$")
            if offset then
                provider.touched = GetTime()
                publishRecords(provider, tonumber(offset), selected)
            end
        elseif kind == "X" and body == "" then
            providers[sender] = nil
        end
    end
    local session = current
    if not session or session.guild ~= name or session.peer ~= sender or session.nonce ~= nonce then return end
    if kind == "I" then acceptPage(session, body)
    elseif kind == "D" then acceptFragment(session, body) end
end

local function request()
    local name, now = guild(), GetTime()
    if context ~= name then note.GuildSharingChanged() end
    if not registered or not name or not note.db.sharing or not allowed() or current or now < nextManual then return false end
    serial = serial + 1
    local character = (note.owner:match("%x+$") or "0"):sub(-8)
    local nonce = ("%x.%s.%x"):format(GetServerTime(), character, serial + math.random(1, 0xFFFFFF))
    local stamp = GetServerTime()
    local known = note.GuildHistoryRecords(name, stamp) or {}
    nextManual, nextRequest = now + cooldown, now + requestInterval + math.random(1, 40)
    current = {
        nonce = nonce, guild = name, offers = {}, offered = {}, peerIndex = 0,
        known = known, confirmed = { [fingerprint(known, stamp)] = true },
        deadline = now + offerSeconds, expires = now + sessionSeconds, added = 0, completed = 0,
    }
    clientSend(current, "Q", note.scope)
    if note.RequestGuildHunts then note.RequestGuildHunts() end
    refreshStatus()
    C_Timer.After(cooldown, refreshStatus)
    return true
end

function note.RequestGuildSync()
    return request()
end

local function scheduleSoon(delay)
    nextRequest = GetTime() + delay
end

function note.GuildSharingChanged()
    context = guild()
    if current then flushChanges(current) end
    current, result = nil, nil
    providers, queue, offerSnapshot = {}, {}, nil
    nextManual = 0
    scheduleSoon(2)
    refreshStatus()
end

local function update()
    local now, name = GetTime(), guild()
    if context ~= name then note.GuildSharingChanged() end
    if not name or not note.db.sharing or not allowed() then return end
    pump()
    for sender, provider in pairs(providers) do
        -- Untouched offers remain available while the requester works through
        -- other peers. Stop keeping the snapshot if an active transfer stalls.
        local timeout = provider.offset and serviceSeconds or sessionSeconds
        if now - provider.touched >= timeout then providers[sender] = nil end
    end
    local session = current
    if not session then
        if now >= nextRequest then request() end
        return
    end
    if now >= session.expires then
        session.failed = true
        finish(session)
    elseif now >= session.deadline then
        if not session.peer then nextPeer(session)
        elseif session.retries >= 2 then nextPeer(session, true)
        else
            session.retries, session.deadline = session.retries + 1, now + responseSeconds
            if session.wanted then requestMissing(session)
            else clientSend(session, "P", tostring(session.offset)) end
        end
    end
end

listener:SetScript("OnEvent", function(_, event, incoming, text, channel, sender)
    if event == "CHAT_MSG_ADDON" then
        if note.Public(incoming) == prefix then
            onMessage(note.Public(text), note.Public(channel), note.Public(sender))
        end
    else
        update()
        refreshStatus()
    end
end)

function note.StartGuildSync()
    if started or not note.db or not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix
        or not C_ChatInfo.SendAddonMessage or not C_Timer.After or not C_Timer.NewTicker then return end
    started = true
    local response = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    local codes = Enum and Enum.RegisterAddonMessagePrefixResult
    registered = response ~= false and (type(response) ~= "number"
        or response == (codes and codes.Success or 0) or response == (codes and codes.DuplicatePrefix or 1))
    if not registered then return end
    listener:RegisterEvent("CHAT_MSG_ADDON")
    listener:RegisterEvent("PLAYER_GUILD_UPDATE")
    listener:RegisterEvent("PLAYER_ENTERING_WORLD")
    listener:RegisterEvent("PLAYER_REGEN_ENABLED")
    context = guild()
    scheduleSoon(4 + math.random(1, 8))
    C_Timer.NewTicker(1, update)
end
