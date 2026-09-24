-- server/match.lua — Hot Pursuit match
--
--   SETUP  Everyone goes into a private bucket at Pacific Standard. The robber
--          is held inside the bank with the getaway car parked outside; police
--          spawn in their cars on the fixed points and drive off to set up.
--          The chase starts when every cop (and the pilot) is ready, or when
--          Config.SetupMaxSec runs out.
--   CHASE  The robber is released and runs for the car. Police bust by holding
--          the bust key within range while the robber is at walking pace
--          (Config.BustMaxSpeedKmh) — the bar is computed here, not trusted
--          from a client. Busted = police win; survive Config.ChaseSec = robber
--          wins.
--   OVER   Result, rewards, everyone back to freeroam and the room back to the
--          lobby.
--
-- Players in a match carry `spz:contact`, which spz-core's phasing honours, so
-- cop and robber cars actually collide and the robber can be boxed in.

local TICK_MS = 200

local function log(msg)
    print("^5[spz-pursuit]^7 " .. msg)
end

local function vec4t(v) return { x = v.x, y = v.y, z = v.z, w = v.w } end

local function setBucket(src, bucket)
    if GetResourceState("spz-core") == "started" then
        exports["spz-core"]:AssignPlayerToBucket(src, bucket)
    else
        SetPlayerRoutingBucket(src, bucket)
    end
end

local function setMatchState(src, on)
    local st = Player(src).state
    st:set("inPursuit", on or nil, true)
    st:set("spz:contact", on or nil, true)
end

local function each(match, fn)
    for src in pairs(match.players) do
        if GetPlayerName(src) then fn(src, match.players[src]) end
    end
end

local function speedKmh(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return 0.0 end
    local veh = GetVehiclePedIsIn(ped, false)
    local v = GetEntityVelocity(veh ~= 0 and veh or ped)
    return #v * 3.6
end

local function dist(a, b)
    local pa, pb = GetPlayerPed(a), GetPlayerPed(b)
    if not pa or pa == 0 or not pb or pb == 0 then return math.huge end
    return #(GetEntityCoords(pa) - GetEntityCoords(pb))
end

-- ── Start ────────────────────────────────────────────────────────────────────

function Pursuit.StartMatch(room)
    local bucket = 0
    if GetResourceState("spz-core") == "started" then
        bucket = exports["spz-core"]:CreateBucket("pursuit")
    end
    SetRoutingBucketPopulationEnabled(bucket, Config.Traffic == true)

    local now = GetGameTimer()
    local match = {
        bucket = bucket, phase = "setup",
        setupEndsAt = now + Config.SetupMaxSec * 1000,
        chaseEndsAt = nil,
        players = {}, robber = nil, ready = {}, holding = {}, bust = 0.0,
    }
    room.match = match
    room.state = "match"

    -- Cops take the spawn points in order; a sixth cop takes the first point
    -- again, one car-width over (the client applies `slot`).
    local copIndex = 0
    local roster = {}
    for src, m in pairs(room.members) do
        local p = { role = m.role, name = m.name, model = m.cars[m.role], preset = m.presets[m.cars[m.role]] }
        if m.role == "robber" then
            match.robber = src
            p.spawn = vec4t(Config.Robber.spawn)
            p.car   = vec4t(Config.Robber.car)
        elseif m.role == "cop" then
            copIndex = copIndex + 1
            local n = #Config.CopSpawns
            p.spawn = vec4t(Config.CopSpawns[((copIndex - 1) % n) + 1])
            p.slot  = math.floor((copIndex - 1) / n)
        else
            p.spawn = vec4t(Config.PilotSpawn)
        end
        match.players[src] = p
        roster[#roster + 1] = { src = src, name = m.name, role = m.role }
    end

    each(match, function(src, p)
        setBucket(src, bucket)
        setMatchState(src, true)
        TriggerClientEvent("spz-pursuit:begin", src, {
            role = p.role, spawn = p.spawn, car = p.car, slot = p.slot,
            model = p.model, preset = p.preset,
            robber = match.robber, roster = roster,
            setupSec = Config.SetupMaxSec, chaseSec = Config.ChaseSec,
        })
    end)

    Pursuit.Broadcast(room)
    log(("room %d: match started — %d players, bucket %d"):format(room.id, #roster, bucket))
end

-- ── Transitions ──────────────────────────────────────────────────────────────

local function startChase(room)
    local match = room.match
    match.phase = "chase"
    match.chaseEndsAt = GetGameTimer() + Config.ChaseSec * 1000
    each(match, function(src) TriggerClientEvent("spz-pursuit:go", src) end)
    log(("room %d: chase started"):format(room.id))
end

--- Clients delete their own cars first (they own them, and only while still
--- in the bucket), then everyone is moved out and anything left is swept.
local function releasePlayers(room, match)
    local players = {}
    each(match, function(src)
        players[#players + 1] = src
        TriggerClientEvent("spz-pursuit:finish", src)
    end)

    SetTimeout(1500, function()
        for _, src in ipairs(players) do
            if GetPlayerName(src) then
                setBucket(src, 0)
                setMatchState(src, false)
            end
        end
        if match.bucket ~= 0 then
            for _, veh in ipairs(GetAllVehicles()) do
                if GetEntityRoutingBucket(veh) == match.bucket then DeleteEntity(veh) end
            end
            if GetResourceState("spz-core") == "started" then
                pcall(function() exports["spz-core"]:DeleteBucket(match.bucket) end)
            end
        end
    end)
end

local function payWinner(src)
    local reward = Config.WinReward or 0
    if reward <= 0 or GetResourceState("spz-progression") ~= "started" then return 0 end
    pcall(function() exports["spz-progression"]:GrantBonus(src, { credits = reward, reason = "Hot Pursuit won" }) end)
    return reward
end

--- winner = "robber" | "police"
local function endMatch(room, winner, reason)
    local match = room.match
    if not match or match.phase == "over" then return end
    match.phase = "over"

    each(match, function(src, p)
        local police = p.role ~= "robber"
        local won = (winner == "police") == police
        TriggerClientEvent("spz-pursuit:over", src, {
            winner = winner, reason = reason, won = won, payout = won and payWinner(src) or 0,
        })
    end)

    pcall(function()
        exports["spz-log"]:Log("minigame", "Hot Pursuit", ("Room %d: %s won (%s)"):format(room.id, winner, reason), "success")
    end)
    log(("room %d: %s won (%s)"):format(room.id, winner, reason))

    SetTimeout(5000, function()
        releasePlayers(room, match)
        if Rooms[room.id] == room then Pursuit.BackToLobby(room) end
    end)
end

--- Everyone left mid-match: tidy up without a result.
function Pursuit.AbortMatch(room)
    local match = room.match
    if not match then return end
    match.phase = "over"
    releasePlayers(room, match)
end

--- A member dropped / left mid-match (called from rooms.lua).
function Pursuit.OnMemberGone(room, src)
    local match = room.match
    if not match or not match.players[src] then return end
    local p = match.players[src]
    match.players[src] = nil
    match.ready[src], match.holding[src] = nil, nil
    setMatchState(src, false)

    if match.phase == "over" then return end
    if p.role == "robber" then return endMatch(room, "police", "the robber left") end

    local police = 0
    for _, q in pairs(match.players) do if q.role ~= "robber" then police = police + 1 end end
    if police == 0 then endMatch(room, "robber", "the police left") end
end

-- ── Client reports ───────────────────────────────────────────────────────────

local function matchOf(src)
    local room = Pursuit.RoomOf(src)
    if not room or room.state ~= "match" or not room.match then return nil end
    return room, room.match, room.match.players[src]
end

RegisterNetEvent("spz-pursuit:setupReady", function()
    local room, match, p = matchOf(source)
    if not p or match.phase ~= "setup" or p.role == "robber" then return end
    match.ready[source] = true
end)

RegisterNetEvent("spz-pursuit:bustHold", function(holding)
    local room, match, p = matchOf(source)
    if not p or p.role ~= "cop" then return end
    match.holding[source] = holding == true or nil
end)

RegisterNetEvent("spz-pursuit:died", function()
    local room, match, p = matchOf(source)
    if not p or match.phase == "over" then return end
    if p.role == "robber" then endMatch(room, "police", "the robber went down") end
end)

-- ── Tick ─────────────────────────────────────────────────────────────────────

CreateThread(function()
    local lastBroadcast = 0
    while true do
        Wait(TICK_MS)
        local now = GetGameTimer()
        local broadcast = now - lastBroadcast >= 250
        if broadcast then lastBroadcast = now end

        for _, room in pairs(Rooms) do
            local match = room.match
            if room.state == "match" and match and match.phase ~= "over" then
                -- Setup → chase when every cop / pilot is ready, or time's up.
                local police, ready = 0, 0
                for src, p in pairs(match.players) do
                    if p.role ~= "robber" then
                        police = police + 1
                        if match.ready[src] then ready = ready + 1 end
                    end
                end
                if match.phase == "setup" and (ready >= police or now >= match.setupEndsAt) then
                    startChase(room)
                end

                if match.phase == "chase" then
                    local dt = TICK_MS / 1000
                    local speed = speedKmh(match.robber)
                    local busting = false
                    if speed <= Config.BustMaxSpeedKmh then
                        for src in pairs(match.holding) do
                            if dist(src, match.robber) <= Config.BustDistance then busting = true; break end
                        end
                    end

                    if busting then
                        match.bust = math.min(1.0, match.bust + dt / Config.BustHoldSec)
                    else
                        match.bust = math.max(0.0, match.bust - dt * Config.BustDrainPerSec)
                    end

                    if match.bust >= 1.0 then
                        endMatch(room, "police", "busted")
                    elseif now >= match.chaseEndsAt then
                        endMatch(room, "robber", "escaped")
                    end
                end

                if broadcast and match.phase ~= "over" then
                    local endsAt = match.phase == "setup" and match.setupEndsAt or match.chaseEndsAt
                    local state = {
                        phase = match.phase,
                        remain = math.max(0, math.ceil((endsAt - now) / 1000)),
                        ready = ready, police = police,
                        bust = match.bust,
                    }
                    each(match, function(src) TriggerClientEvent("spz-pursuit:state", src, state) end)
                end
            end
        end
    end
end)

AddEventHandler("onResourceStop", function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, room in pairs(Rooms) do
        if room.match then
            for src in pairs(room.match.players) do
                setMatchState(src, false)
                setBucket(src, 0)
            end
        end
    end
end)
