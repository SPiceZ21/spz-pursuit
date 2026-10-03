-- server/rooms.lua — Hot Pursuit rooms (the soft launch)
--
-- A host creates a room and invites players. In the room everyone picks a car
-- for each role, customises it in the tuner, and presses ready. Roles are NOT
-- picked: once every member is ready the match starts by itself after a short
-- countdown and the server deals roles at random (1 robber, a PD chopper pilot
-- when there are more than Config.ChopperAbove players, the rest cops). When
-- the match ends the room comes back to the lobby, so the group can go again.

Pursuit = Pursuit or {}
Rooms   = {}            -- [roomId] = room
local MemberRoom = {}   -- [src] = roomId
local Invites    = {}   -- [targetSrc] = { [roomId] = true }
local nextRoomId = 1

local ROLES = { robber = true, cop = true, pilot = true }

-- ── Helpers ──────────────────────────────────────────────────────────────────

function Pursuit.Notify(src, msg, t)
    TriggerClientEvent("ox_lib:notify", src, { title = "Hot Pursuit", description = msg, type = t or "inform" })
end
local notify = Pursuit.Notify

function Pursuit.Profile(src)
    local ok, p = pcall(function() return exports["spz-identity"]:GetProfile(src) end)
    return ok and p or nil
end

function Pursuit.NameOf(src)
    local p = Pursuit.Profile(src)
    return (p and p.username) or GetPlayerName(src) or ("Player " .. src)
end

function Pursuit.RoomOf(src)
    local id = MemberRoom[src]
    return id and Rooms[id] or nil
end

local function inList(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
end

local function count(room, role)
    local n = 0
    for _, m in pairs(room.members) do
        if not role or m.role == role then n = n + 1 end
    end
    return n
end

local function busy(src)
    local st = Player(src).state
    if st.inRace or st.inQueue then return "in a race or race queue" end
    if GetResourceState("spz-races") == "started" then
        local ok, tt = pcall(function() return exports["spz-races"]:IsInTimeTrial(src) end)
        if ok and tt then return "in a time trial" end
    end
    return nil
end

--- The whole room as the client needs it to draw the lobby.
function Pursuit.RoomView(room, viewer)
    local members = {}
    for src, m in pairs(room.members) do
        members[#members + 1] = {
            src = src, name = m.name, role = m.role, ready = m.ready,
            car = m.role and m.cars[m.role] or nil,
            host = src == room.host, me = src == viewer,
        }
    end
    table.sort(members, function(a, b)
        if a.host ~= b.host then return a.host end
        return a.name < b.name
    end)

    local me = room.members[viewer]
    local tuned = {}
    if me then for model in pairs(me.presets) do tuned[model] = true end end
    return {
        id = room.id,
        state = room.state,
        countdown = room.countdown and true or false,
        host = room.host,
        isHost = viewer == room.host,
        members = members,
        me = me and { role = me.role, ready = me.ready, cars = me.cars, tuned = tuned } or nil,
        counts = { robber = count(room, "robber"), cop = count(room, "cop"), pilot = count(room, "pilot"), total = count(room) },
        limits = { cops = Config.MaxCops, minCops = Config.MinCops, pilots = Config.MaxPilots, size = Config.MaxRoomSize },
        cars = Config.Cars,
    }
end

--- Push the fresh room view to every member (open lobby menus redraw).
function Pursuit.Broadcast(room)
    for src in pairs(room.members) do
        TriggerClientEvent("spz-pursuit:room", src, Pursuit.RoomView(room, src))
    end
end

local function unreadyAll(room)
    for _, m in pairs(room.members) do m.ready = false end
end

--- Why the room can't start yet, or nil.
function Pursuit.StartBlocker(room)
    if count(room) < 1 + Config.MinCops then return ("Need at least %d players"):format(1 + Config.MinCops) end
    for _, m in pairs(room.members) do
        if not m.ready then return m.name .. " isn't ready" end
    end
    return nil
end

--- Deal roles at random: 1 robber, 1 chopper pilot when the room has more than
--- Config.ChopperAbove players, everyone else a cop.
function Pursuit.AssignRoles(room)
    local pool = {}
    for src, m in pairs(room.members) do m.role = nil; pool[#pool + 1] = src end
    for i = #pool, 2, -1 do
        local j = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local pilots = (#pool > Config.ChopperAbove) and math.min(Config.MaxPilots, 1) or 0
    for i, src in ipairs(pool) do
        local m = room.members[src]
        if i == 1 then m.role = "robber"
        elseif i <= 1 + pilots then m.role = "pilot"
        else m.role = "cop" end
    end
end

-- ── Auto start ───────────────────────────────────────────────────────────────
-- Everyone ready -> countdown -> roles dealt -> match. Any change (un-ready,
-- join, leave) bumps room.startToken and cancels a running countdown.

local function startProblem(room)
    local blocked = Pursuit.StartBlocker(room)
    if blocked then return blocked end
    for s, m in pairs(room.members) do
        local b = busy(s)
        if b then return ("%s is %s"):format(m.name, b) end
        if Pursuit.InPreview(s) then return m.name .. " is still customising" end
    end
    return nil
end

function Pursuit.CheckAutoStart(room)
    room.startToken = (room.startToken or 0) + 1
    if room.state ~= "lobby" or startProblem(room) then
        if room.countdown then
            room.countdown = nil
            for s in pairs(room.members) do notify(s, "Countdown cancelled.", "warning") end
        end
        return
    end
    local token = room.startToken
    room.countdown = true
    for s in pairs(room.members) do
        notify(s, ("Everyone's ready — roles are dealt in %ds."):format(Config.AutoStartDelay), "success")
    end
    SetTimeout(Config.AutoStartDelay * 1000, function()
        if Rooms[room.id] ~= room or room.startToken ~= token or room.state ~= "lobby" then return end
        room.countdown = nil
        local why = startProblem(room)
        if why then
            for s in pairs(room.members) do notify(s, "Start cancelled: " .. why, "warning") end
            Pursuit.Broadcast(room)
            return
        end
        Pursuit.AssignRoles(room)
        Pursuit.StartMatch(room)
    end)
end

-- ── Membership ───────────────────────────────────────────────────────────────

local function addMember(room, src)
    MemberRoom[src] = room.id
    room.members[src] = {
        name = Pursuit.NameOf(src), role = nil, ready = false,
        cars = { robber = Config.Cars.robber[1], cop = Config.Cars.cop[1], pilot = Config.Cars.pilot[1] },
        presets = {},    -- [model] = tuner props
    }
    if Invites[src] then Invites[src][room.id] = nil end
end

function Pursuit.RemoveMember(src, why)
    local room = Pursuit.RoomOf(src)
    if not room then return end
    room.members[src] = nil
    MemberRoom[src] = nil

    if room.state == "match" and Pursuit.OnMemberGone then Pursuit.OnMemberGone(room, src) end

    if not next(room.members) then
        if room.state == "match" and Pursuit.AbortMatch then Pursuit.AbortMatch(room) end
        Rooms[room.id] = nil
        return
    end

    if room.state == "lobby" then Pursuit.CheckAutoStart(room) end
    if room.host == src then
        room.host = next(room.members)
        notify(room.host, "You are now the room host.", "inform")
    end
    for s in pairs(room.members) do
        notify(s, ("%s left the room%s."):format(Pursuit.NameOf(src), why and (" (" .. why .. ")") or ""), "warning")
    end
    Pursuit.Broadcast(room)
end

-- ── Callbacks ────────────────────────────────────────────────────────────────

lib.callback.register("spz-pursuit:state", function(src)
    local room = Pursuit.RoomOf(src)
    -- Rooms are PUBLIC: every lobby is listed, invited ones first.
    local lobbies = {}
    for roomId, r in pairs(Rooms) do
        if r.state == "lobby" and count(r) < Config.MaxRoomSize then
            lobbies[#lobbies + 1] = {
                id = roomId, host = Pursuit.NameOf(r.host), size = count(r),
                max = Config.MaxRoomSize, robber = count(r, "robber") > 0,
                invited = (Invites[src] and Invites[src][roomId]) and true or false,
            }
        end
    end
    table.sort(lobbies, function(a, b)
        if a.invited ~= b.invited then return a.invited end
        return a.size > b.size
    end)
    return { room = room and Pursuit.RoomView(room, src) or nil, invites = lobbies }
end)

lib.callback.register("spz-pursuit:create", function(src)
    if MemberRoom[src] then return false, "You're already in a room" end
    local b = busy(src)
    if b then return false, "You're " .. b end
    if not Pursuit.Profile(src) then return false, "Profile not ready" end

    local room = { id = nextRoomId, host = src, state = "lobby", members = {} }
    nextRoomId = nextRoomId + 1
    Rooms[room.id] = room
    addMember(room, src)
    Pursuit.Broadcast(room)
    return true
end)

local function joinRoom(src, room)
    addMember(room, src)
    for s in pairs(room.members) do
        if s ~= src then notify(s, Pursuit.NameOf(src) .. " joined the lobby.", "success") end
    end
    Pursuit.CheckAutoStart(room)
    Pursuit.Broadcast(room)
end

--- Public matchmaking: join the fullest open lobby, or open a new one.
lib.callback.register("spz-pursuit:quickJoin", function(src)
    if MemberRoom[src] then return false, "You're already in a lobby" end
    local b = busy(src)
    if b then return false, "You're " .. b end
    if not Pursuit.Profile(src) then return false, "Profile not ready" end

    local best
    for _, r in pairs(Rooms) do
        if r.state == "lobby" and count(r) < Config.MaxRoomSize and (not best or count(r) > count(best)) then
            best = r
        end
    end
    if best then joinRoom(src, best); return true end

    local room = { id = nextRoomId, host = src, state = "lobby", members = {} }
    nextRoomId = nextRoomId + 1
    Rooms[room.id] = room
    addMember(room, src)
    Pursuit.Broadcast(room)
    return true
end)

lib.callback.register("spz-pursuit:leave", function(src)
    local room = Pursuit.RoomOf(src)
    if not room then return false end
    if room.state == "match" then return false, "You can't leave during a match" end
    Pursuit.RemoveMember(src, "left")
    return true
end)

lib.callback.register("spz-pursuit:onlinePlayers", function(src)
    local list = {}
    for _, sid in ipairs(GetPlayers()) do
        local s = tonumber(sid)
        if s ~= src and not MemberRoom[s] then
            list[#list + 1] = { src = s, name = Pursuit.NameOf(s), busy = busy(s) }
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end)

lib.callback.register("spz-pursuit:invite", function(src, target)
    local room = Pursuit.RoomOf(src)
    target = tonumber(target)
    if not room or room.state ~= "lobby" then return false, "Not in a lobby" end
    if not target or not GetPlayerName(target) then return false, "Player is offline" end
    if MemberRoom[target] then return false, "They're already in a room" end
    if count(room) >= Config.MaxRoomSize then return false, "Room is full" end

    Invites[target] = Invites[target] or {}
    Invites[target][room.id] = true
    TriggerClientEvent("spz-pursuit:invited", target, { room = room.id, host = Pursuit.NameOf(src) })
    return true, "Invite sent to " .. Pursuit.NameOf(target)
end)

lib.callback.register("spz-pursuit:join", function(src, roomId)
    local room = Rooms[tonumber(roomId)]
    if not room or room.state ~= "lobby" then return false, "That room is gone or already playing" end
    if MemberRoom[src] then return false, "You're already in a room" end
    local b = busy(src)
    if b then return false, "You're " .. b end
    if count(room) >= Config.MaxRoomSize then return false, "Room is full" end

    addMember(room, src)
    for s in pairs(room.members) do
        if s ~= src then notify(s, Pursuit.NameOf(src) .. " joined the room.", "success") end
    end
    Pursuit.CheckAutoStart(room)
    Pursuit.Broadcast(room)
    return true
end)

lib.callback.register("spz-pursuit:kick", function(src, target)
    local room = Pursuit.RoomOf(src)
    target = tonumber(target)
    if not room or room.host ~= src or room.state ~= "lobby" then return false end
    if target == src or not room.members[target] then return false end
    notify(target, "You were removed from the room.", "error")
    Pursuit.RemoveMember(target, "removed by host")
    TriggerClientEvent("spz-pursuit:room", target, nil)
    return true
end)

lib.callback.register("spz-pursuit:setCar", function(src, role, model)
    local room = Pursuit.RoomOf(src)
    local m = room and room.members[src]
    if not m or room.state ~= "lobby" then return false end
    if not ROLES[role] or not inList(Config.Cars[role], model) then return false, "Not an available car" end
    m.cars[role] = model
    m.ready = false
    Pursuit.CheckAutoStart(room)
    Pursuit.Broadcast(room)
    return true
end)

--- Tuner result for a model, from client/customize.lua.
lib.callback.register("spz-pursuit:savePreset", function(src, model, props)
    local room = Pursuit.RoomOf(src)
    local m = room and room.members[src]
    if not m or type(props) ~= "table" then return false end
    local allowed = inList(Config.Cars.robber, model) or inList(Config.Cars.cop, model) or inList(Config.Cars.pilot, model)
    if not allowed then return false end
    m.presets[model] = props
    m.ready = false
    Pursuit.CheckAutoStart(room)
    Pursuit.Broadcast(room)
    return true
end)

lib.callback.register("spz-pursuit:ready", function(src)
    local room = Pursuit.RoomOf(src)
    local m = room and room.members[src]
    if not m or room.state ~= "lobby" then return false end
    m.ready = not m.ready
    Pursuit.CheckAutoStart(room)
    Pursuit.Broadcast(room)
    return true
end)

--- Saved tuner setup for one of my cars (the tuner preview starts from it).
lib.callback.register("spz-pursuit:getPreset", function(src, model)
    local room = Pursuit.RoomOf(src)
    local m = room and room.members[src]
    return m and m.presets[model] or nil
end)

-- ── Tuner preview bucket ─────────────────────────────────────────────────────
-- Customising spawns a preview car and sits you in it; doing that in freeroam
-- would show everyone a driver floating in a car only you can see. So the
-- preview happens in a private bucket, and you're put back afterwards.
local Preview = {}   -- [src] = { bucket, back }

function Pursuit.InPreview(src) return Preview[src] ~= nil end

lib.callback.register("spz-pursuit:previewBucket", function(src, on)
    local room = Pursuit.RoomOf(src)
    if on then
        if not room or room.state ~= "lobby" or Preview[src] then return false end
        local bucket = exports["spz-core"]:CreateBucket("pursuit-preview")
        SetRoutingBucketPopulationEnabled(bucket, false)
        Preview[src] = { bucket = bucket, back = GetPlayerRoutingBucket(src) }
        exports["spz-core"]:AssignPlayerToBucket(src, bucket)
        return true
    end

    local p = Preview[src]
    if not p then return false end
    Preview[src] = nil
    exports["spz-core"]:AssignPlayerToBucket(src, p.back or 0)
    pcall(function() exports["spz-core"]:DeleteBucket(p.bucket) end)
    if room then Pursuit.CheckAutoStart(room); Pursuit.Broadcast(room) end
    return true
end)

AddEventHandler("playerDropped", function()
    local p = Preview[source]
    if p then
        Preview[source] = nil
        pcall(function() exports["spz-core"]:DeleteBucket(p.bucket) end)
    end
end)

--- Called by match.lua when a match is over: back to the lobby, unready.
function Pursuit.BackToLobby(room)
    room.state = "lobby"
    room.match = nil
    unreadyAll(room)
    for _, m in pairs(room.members) do m.role = nil end
    Pursuit.Broadcast(room)
end

AddEventHandler("playerDropped", function()
    local src = source
    Invites[src] = nil
    Pursuit.RemoveMember(src, "disconnected")
end)
