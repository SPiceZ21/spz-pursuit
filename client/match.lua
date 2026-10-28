-- client/match.lua — Hot Pursuit match
--
-- The server drives the phases (setup → chase → over) and owns the bust bar and
-- the result; this file spawns you, shows the HUD, sends "ready" and "holding
-- the bust key", respawns dead cops and puts you back afterwards.

local M = nil   -- current match; nil when not in one
local HUD = exports["spz-minigames"]   -- shared in-game HUD (all on-screen text)


function Pursuit.InMatch() return M ~= nil end

-- ── Helpers ──────────────────────────────────────────────────────────────────

local function fadeOut()
    DoScreenFadeOut(400)
    while not IsScreenFadedOut() do Wait(0) end
end

local function playerPed(src)
    local p = GetPlayerFromServerId(src)
    if p == -1 then return 0 end
    return GetPlayerPed(p)
end

local function speedKmh(ped)
    if ped == 0 then return 0.0 end
    local veh = GetVehiclePedIsIn(ped, false)
    return GetEntitySpeed(veh ~= 0 and veh or ped) * 3.6
end

local function fmt(s) return ("%d:%02d"):format(math.floor(s / 60), s % 60) end

--- Where a cop spawns: their point, shifted sideways one car-width per `slot`.
local function copSpot(spawn, slot)
    if not slot or slot == 0 then return spawn end
    local h = math.rad(spawn.w)
    local off = 4.0 * slot
    return { x = spawn.x + math.cos(h) * off, y = spawn.y + math.sin(h) * off, z = spawn.z, w = spawn.w }
end

local function bigMessage(title, sub, color, ms)
    HUD:Shard(title, sub, color, ms or 4000)
end

-- ── Spawning ─────────────────────────────────────────────────────────────────

local function spawnPolice()
    local at = M.role == "cop" and copSpot(M.spawn, M.slot) or M.spawn
    local ped = PlayerPedId()
    SetEntityCoords(ped, at.x, at.y, at.z, false, false, false, false)
    Pursuit.LoadArea(at.x, at.y, at.z)

    if M.veh ~= 0 and DoesEntityExist(M.veh) then DeleteEntity(M.veh) end
    M.veh = Pursuit.SpawnCar(M.model, at, M.preset)
    if M.veh ~= 0 then
        SetPedIntoVehicle(ped, M.veh, -1)
        if M.role == "pilot" then SetHeliBladesFullSpeed(M.veh) end
    end
end

local function spawnRobber()
    local ped = PlayerPedId()
    local car = M.car
    -- Robber first: the car is 12 m away, so this streams its ground in too.
    SetEntityCoords(ped, M.spawn.x, M.spawn.y, M.spawn.z, false, false, false, false)
    SetEntityHeading(ped, M.spawn.w)
    Pursuit.LoadArea(M.spawn.x, M.spawn.y, M.spawn.z)

    M.veh = Pursuit.SpawnCar(M.model, car, M.preset)
    if M.veh ~= 0 then
        -- Random base-game chameleon paint (161-222, build 2944+), whole body.
        local paint = math.random(161, 222)
        SetVehicleColours(M.veh, paint, paint)
        SetVehicleExtraColours(M.veh, paint, select(2, GetVehicleExtraColours(M.veh)))
        -- The getaway car is the robber's alone, and stays locked (to them
        -- too) until GO, so it can't be taken early.
        SetVehicleDoorsLockedForAllPlayers(M.veh, true)
        SetVehicleEngineOn(M.veh, false, true, true)
    end
    -- Free to move, but the bank doors are shut until GO (see the hold thread).
    M.holdInterior, M.lastInside = nil, nil
end

-- ── Setup: robber walks around inside the bank, can't leave it ──────────────
CreateThread(function()
    while true do
        if M and M.phase == "setup" and M.role == "robber" then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local int = GetInteriorFromEntity(ped)
            if not M.holdInterior and int ~= 0 then M.holdInterior = int end

            local inside
            if M.holdInterior then
                inside = (int == M.holdInterior)
            else
                inside = #(pos - vector3(M.spawn.x, M.spawn.y, M.spawn.z)) <= (Config.BankHoldRadius or 9.0)
            end

            if inside then
                M.lastInside = pos
            elseif M.lastInside then
                SetEntityCoords(ped, M.lastInside.x, M.lastInside.y, M.lastInside.z - 0.95, false, false, false, false)
                SetEntityVelocity(ped, 0.0, 0.0, 0.0)
            end
            if not inside or IsPedTryingToEnterALockedVehicle(ped) then
                M.doorMsgUntil = GetGameTimer() + 2500
            end
            Wait(0)   -- the "doors locked" warning is shown by the HUD thread
        else
            Wait(300)
        end
    end
end)


-- Countdown / GO clips from spz-raceUI (ui/public/aud), game audio as fallback.
local function playClip(name)
    if GetResourceState("spz-raceUI") == "started" then
        local ok = pcall(function() exports["spz-raceUI"]:PlaySound(name, 1.0) end)
        if ok then return end
    end
    if name == "go" then
        PlaySoundFrontend(-1, "GO", "HUD_MINI_GAME_SOUNDSET", true)
    else
        PlaySoundFrontend(-1, "3_2_1", "HUD_MINI_GAME_SOUNDSET", true)
    end
end

-- Big centred number for the 3-2-1, shown for ~0.9 s.
local function flashCount(txt, color)
    HUD:Flash(txt, color, 900)
end


-- Joining a minigame: despawn the freeroam car the player was driving, so it
-- isn't left abandoned in freeroam (or dragged into the minigame world).
local function despawnFreeroamCar()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= ped then return end
    local dl = GetGameTimer() + 1000
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < dl do
        NetworkRequestControlOfEntity(veh); Wait(0)
    end
    SetEntityAsMissionEntity(veh, true, true)
    DeleteVehicle(veh)
    if DoesEntityExist(veh) then DeleteEntity(veh) end
end

-- ── Lifecycle ────────────────────────────────────────────────────────────────

RegisterNetEvent("spz-pursuit:begin", function(d)
    lib.hideContext(false)
    local ped = PlayerPedId()

    M = {
        role = d.role, spawn = d.spawn, car = d.car, slot = d.slot,
        model = d.model, preset = d.preset,
        robber = d.robber, roster = d.roster,
        phase = "setup", remain = d.setupSec, ready = 0, police = 0, bust = 0.0,
        veh = 0, sentReady = false, holding = false, blips = {}, dead = false,
        back = GetEntityCoords(ped), backHeading = GetEntityHeading(ped),
    }
    -- After the match everyone spawns at the hub's shared return point (DK garage).
    if GetResourceState("spz-minigames") == "started" then
        local ok, p = pcall(function() return exports["spz-minigames"]:ReturnPoint() end)
        if ok and p then M.back, M.backHeading = vector3(p.x, p.y, p.z), p.w end
    end

    -- Tells spz-races to hide its "[E] JOIN RACE" pill and ignore E, which
    -- would otherwise fire alongside HOLD E TO BUST.
    TriggerServerEvent("spz:setPlayerFlag", "inMinigame", "Hot Pursuit")
    TriggerEvent("spz:minigameChanged")

    fadeOut()
    despawnFreeroamCar()
    -- Drops the phasing exclusions spz-core put on this ped, so contact works.
    SetEntityCollision(ped, true, true)

    if M.role == "robber" then spawnRobber() else spawnPolice() end
    Wait(500)
    DoScreenFadeIn(600)

    if M.role == "robber" then
        Pursuit.Notify("The doors open when the countdown ends. Then get in your car and lose them.", "inform", "ROBBER")
    elseif M.role == "cop" then
        Pursuit.Notify("Get into position — the chase starts when the countdown ends.", "inform", "POLICE")
    else
        Pursuit.Notify("Get the chopper in position — the chase starts when the countdown ends.", "inform", "PD CHOPPER")
    end
end)

RegisterNetEvent("spz-pursuit:state", function(s)
    if not M then return end
    M.phase, M.remain, M.ready, M.police, M.bust = s.phase, s.remain, s.ready, s.police, s.bust
    M.robberPos = s.robberPos
    M.board = s.board
end)

RegisterNetEvent("spz-pursuit:countdown", function(n)
    if not M then return end
    flashCount(tostring(n))
    playClip("countdown")
end)

RegisterNetEvent("spz-pursuit:go", function(d)
    if not M then return end
    M.phase = "chase"
    M.graceEnd = GetGameTimer() + ((d and d.headStart) or 0) * 1000
    if M.role == "robber" then
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, false)
        -- Police are all ready: straight into the getaway car, engine running.
        if M.veh ~= 0 and DoesEntityExist(M.veh) then
            SetVehicleDoorsLockedForPlayer(M.veh, PlayerId(), false)
            TaskWarpPedIntoVehicle(ped, M.veh, -1)
            SetVehicleEngineOn(M.veh, true, true, false)
            SetVehicleUndriveable(M.veh, false)
        end
        bigMessage("Go!", ("%ds head start — lose the police"):format((d and d.headStart) or 0), "bad", 3000)
        playClip("go")
    else
        bigMessage("Robber is moving", "Chase them down", "#3b82f6", 3000)
        playClip("go")
    end
end)

RegisterNetEvent("spz-pursuit:over", function(r)
    if not M then return end
    M.phase = "over"
    if M.holding then TriggerServerEvent("spz-pursuit:bustHold", false); M.holding = false end
    FreezeEntityPosition(PlayerPedId(), false)

    local title = r.winner == "police" and "Busted" or "Escaped"
    local sub = (r.won and "You win" or "You lose") .. (r.payout and r.payout > 0 and ("  ·  +%d credits"):format(r.payout) or "")
    if r.reason and r.reason ~= "busted" and r.reason ~= "escaped" then sub = r.reason .. " · " .. sub end
    bigMessage(title, sub, r.winner == "police" and "#3b82f6" or "bad", 5000)
end)

local function cleanup()
    if not M then return end
    for _, b in pairs(M.blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    if M.veh ~= 0 and DoesEntityExist(M.veh) then
        SetEntityAsMissionEntity(M.veh, true, true)
        DeleteEntity(M.veh)
    end
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    lib.hideTextUI()
    HUD:Hud(nil)
    TriggerServerEvent("spz:setPlayerFlag", "inMinigame", false)
    TriggerEvent("spz:minigameChanged")
    M = nil
end

RegisterNetEvent("spz-pursuit:finish", function()
    if not M then return end
    fadeOut()
    local back, heading = M.back, M.backHeading
    cleanup()

    local ped = PlayerPedId()
    if IsEntityDead(ped) then
        NetworkResurrectLocalPlayer(back.x, back.y, back.z, heading, 0, false)
        ped = PlayerPedId()
    end
    ClearPedTasksImmediately(ped)
    SetEntityCoords(ped, back.x, back.y, back.z, false, false, false, false)
    SetEntityHeading(ped, heading)
    Pursuit.LoadArea(back.x, back.y, back.z)
    DoScreenFadeIn(600)
end)

-- ── Input: ready + bust ──────────────────────────────────────────────────────

CreateThread(function()
    while true do
        if M and M.phase ~= "over" then
            local sleep = 0

            -- Busting is automatic now (server-side, by distance + speed).
            if M.phase ~= "chase" then
                sleep = (M.role == "robber") and 100 or 0
            end

            Wait(sleep)
        else
            Wait(250)
        end
    end
end)

-- ── HUD ──────────────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        if M and M.phase == "over" then
            HUD:Hud(nil)
            Wait(100)
        elseif M then
            local hud = { chips = {
                { text = Pursuit.RoleLabel(M.role), hot = true },
                ({ setup = "Setup", chase = "Chase" })[M.phase] or "",
                fmt(M.remain or 0),
            } }
            local now = GetGameTimer()

            if M.phase == "setup" then
                -- setup is a plain countdown (no ready-up)
                local left = fmt(M.remain or 0)
                if M.role == "robber" then
                    hud.status = { label = "Chase starts in", value = left, sub = "Walk the bank — the doors open at GO" }
                else
                    hud.status = { label = "Get in position", value = left, sub = "The chase starts at zero" }
                end
                if M.doorMsgUntil and now < M.doorMsgUntil then
                    hud.alert = "The doors are locked until the chase starts"
                end

            elseif M.phase == "chase" then
                if M.role == "robber" then
                    local kmh = speedKmh(PlayerPedId())
                    local slow = kmh <= Config.BustMaxSpeedKmh
                    hud.status = { label = "Speed", value = ("%d km/h"):format(math.floor(kmh + 0.5)), color = slow and "bad" or nil }
                    if slow then hud.alert = "Too slow — the police can bust you" end
                    if M.veh ~= 0 and DoesEntityExist(M.veh) then
                        local hp = math.max(0.0, math.min(GetVehicleEngineHealth(M.veh), GetVehicleBodyHealth(M.veh))) / 1000.0
                        hud.bar = { label = "Car", pct = math.floor(hp * 100) / 100 }
                    end
                else
                    local rped = playerPed(M.robber)
                    if rped ~= 0 then
                        local d = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(rped))
                        local kmh = speedKmh(rped)
                        hud.status = { label = "Robber", value = ("%dm"):format(math.floor(d)),
                                       sub = ("%d km/h"):format(math.floor(kmh + 0.5)) }
                        if M.role == "cop" and d <= Config.BustDistance then
                            if kmh <= Config.BustMaxSpeedKmh then
                                hud.hint = { text = "Busting — keep them boxed in", color = "#3b82f6" }
                            else
                                hud.hint = "Stop them to bust"
                            end
                        end
                    else
                        hud.status = { label = "Robber", value = "Out of range", color = "dim", sub = "Follow the blip" }
                    end
                end

                if (M.bust or 0) > 0 then
                    hud.bar = { label = "Busting", pct = M.bust, color = "#3b82f6" }
                end

                -- Head start (police are walled off by the thread below).
                if M.graceEnd and now < M.graceEnd then
                    local left = math.ceil((M.graceEnd - now) / 1000)
                    if M.role == "robber" then
                        hud.hint = { text = ("Head start %ds — police can't close in"):format(left), color = "ok" }
                    elseif playerPed(M.robber) ~= 0 then
                        hud.alert = ("Head start %ds — stay %dm back"):format(left, math.floor(Config.HeadStartRadius or 60.0))
                    end
                end
            end
            hud.board = M.board
            -- key bar (live bindings, resolved by spz-minigames)
            hud.keys = hud.keys or {}
            hud.keys[#hud.keys + 1] = { control = 200, default = "ESC", pad = "START_INDEX", label = "Menu · leave" }
            HUD:Hud(hud)
            Wait(100)
        else
            Wait(400)
        end
    end
end)

-- ── Blips ────────────────────────────────────────────────────────────────────
-- Police see the robber once the chase is on; the robber always sees the police.

CreateThread(function()
    while true do
        if M and M.phase ~= "over" then
            for _, r in ipairs(M.roster) do
                local show
                if M.role == "robber" then
                    show = r.role ~= "robber"
                else
                    show = r.role == "robber" and M.phase == "chase"
                end

                local ped = playerPed(r.src)
                local blip = M.blips[r.src]
                -- Robber out of streaming range (ped gone on this client): keep
                -- them on the map with a position blip from the server instead.
                if show and ped == 0 and r.role == "robber" and M.robberPos then
                    local p = M.robberPos
                    if not (blip and DoesBlipExist(blip)) or GetBlipInfoIdEntityIndex(blip) ~= 0 then
                        if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
                        blip = AddBlipForCoord(p.x, p.y, p.z)
                        SetBlipSprite(blip, 1)
                        SetBlipColour(blip, 1)
                        SetBlipScale(blip, 1.0)
                        SetBlipAsShortRange(blip, false)
                        BeginTextCommandSetBlipName("STRING")
                        AddTextComponentSubstringPlayerName("Robber")
                        EndTextCommandSetBlipName(blip)
                        M.blips[r.src] = blip
                    else
                        SetBlipCoords(blip, p.x, p.y, p.z)
                    end
                elseif show and ped ~= 0 then
                    if not (blip and DoesBlipExist(blip)) or GetBlipInfoIdEntityIndex(blip) ~= ped then
                        if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
                        local robber = r.role == "robber"
                        blip = AddBlipForEntity(ped)
                        SetBlipSprite(blip, robber and 1 or (r.role == "pilot" and 422 or 56))
                        SetBlipColour(blip, robber and 1 or 3)
                        SetBlipScale(blip, robber and 1.0 or 0.8)
                        SetBlipAsShortRange(blip, false)
                        BeginTextCommandSetBlipName("STRING")
                        AddTextComponentSubstringPlayerName(robber and "Robber" or r.name)
                        EndTextCommandSetBlipName(blip)
                        M.blips[r.src] = blip
                    end
                elseif blip then
                    if DoesBlipExist(blip) then RemoveBlip(blip) end
                    M.blips[r.src] = nil
                end
            end
        end
        Wait(500)
    end
end)

-- ── Head start: police kept out of the robber's radius ──────────────────────

CreateThread(function()
    while true do
        local now = GetGameTimer()
        if M and M.phase == "chase" and M.graceEnd and now < M.graceEnd then
            local rped = playerPed(M.robber)
            local R = Config.HeadStartRadius or 60.0
            local left = math.ceil((M.graceEnd - now) / 1000)
            if rped ~= 0 then
                local rc = GetEntityCoords(rped)
                if M.role ~= "robber" then
                    -- Red wall around the robber, so cops can see the line.
                    DrawMarker(1, rc.x, rc.y, rc.z - 20.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        R * 2.0, R * 2.0, 60.0, 255, 40, 40, 45, false, false, 2, false, nil, nil, false)
                    local ped = PlayerPedId()
                    local veh = GetVehiclePedIsIn(ped, false)
                    local ent = veh ~= 0 and veh or ped
                    local me = GetEntityCoords(ent)
                    local dx, dy = me.x - rc.x, me.y - rc.y
                    local d = math.sqrt(dx * dx + dy * dy)
                    if d < R and M.role == "cop" then
                        -- Invisible wall: cancel only the speed TOWARD the
                        -- robber, keep the sideways part, so the cop slides
                        -- along the edge instead of being thrown. Someone who
                        -- starts inside (robber drove at them) is eased out.
                        if d < 0.1 then dx, dy, d = 1.0, 0.0, 1.0 end
                        local nx, ny = dx / d, dy / d
                        local v = GetEntityVelocity(ent)
                        local radial = v.x * nx + v.y * ny          -- + = moving away
                        local vx, vy = v.x, v.y
                        if radial < 0.0 then vx, vy = vx - radial * nx, vy - radial * ny end
                        if d < R - 4.0 then
                            local out = math.min(6.0, (R - d) * 0.5)   -- gentle, never a launch
                            vx, vy = vx + nx * out * 0.1, vy + ny * out * 0.1
                        end
                        SetEntityVelocity(ent, vx, vy, v.z)
                    end
                end
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

-- ── Real damage, every frame ─────────────────────────────────────────────────
-- vMenu's Vehicle God Mode (everyone has vMenu.VehicleOptions.All) re-protects
-- the player's car every frame, which beat the one-time reset at spawn -- so
-- cars never took damage and the robber could never be wrecked. Undo it just as
-- often, on whatever car we're driving in the match.

CreateThread(function()
    while true do
        if M and M.phase ~= "over" and Config.VehicleDamage ~= false then
            local ped = PlayerPedId()
            local veh = GetVehiclePedIsIn(ped, false)
            if veh == 0 and M.veh ~= 0 and DoesEntityExist(M.veh) then veh = M.veh end
            if veh ~= 0 then
                SetEntityInvincible(veh, false)
                SetEntityCanBeDamaged(veh, true)
                SetEntityProofs(veh, false, false, false, false, false, false, false, false)
                SetVehicleCanBeVisiblyDamaged(veh, true)
                SetVehicleStrong(veh, false)
                SetVehicleTyresCanBurst(veh, true)
                SetVehicleWheelsCanBreak(veh, true)
                SetVehicleEngineCanDegrade(veh, true)
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

-- ── Wrecked getaway car ──────────────────────────────────────────────────────
-- The robber's own client watches its car; a wreck during the chase = busted.

CreateThread(function()
    while true do
        if M and M.role == "robber" and M.phase == "chase" and not M.wreckSent
        and M.veh ~= 0 and DoesEntityExist(M.veh) and Config.VehicleDamage ~= false then
            local v = M.veh
            local engine, body = GetVehicleEngineHealth(v), GetVehicleBodyHealth(v)
            if IsEntityDead(v) or engine <= (Config.WreckEngineHealth or 0.0) or body <= (Config.WreckBodyHealth or 0.0) then
                M.wreckSent = true
                TriggerServerEvent("spz-pursuit:wrecked")
            end
            Wait(250)
        else
            Wait(750)
        end
    end
end)

-- ── Deaths ───────────────────────────────────────────────────────────────────

CreateThread(function()
    while true do
        if M and M.phase ~= "over" and not M.dead and IsEntityDead(PlayerPedId()) then
            M.dead = true
            if M.role == "robber" then
                TriggerServerEvent("spz-pursuit:died")
            else
                Pursuit.Notify(("Respawning in %ds"):format(Config.CopRespawnSec), "warning")
                SetTimeout(Config.CopRespawnSec * 1000, function()
                    if not M or M.phase == "over" then return end
                    fadeOut()
                    local at = M.role == "cop" and copSpot(M.spawn, M.slot) or M.spawn
                    NetworkResurrectLocalPlayer(at.x, at.y, at.z, at.w, 0, false)
                    local ped = PlayerPedId()
                    ClearPedBloodDamage(ped)
                    SetEntityCollision(ped, true, true)
                    AnimpostfxStopAll()
                    spawnPolice()
                    M.dead = false
                    DoScreenFadeIn(500)
                end)
            end
        end
        Wait(500)
    end
end)

-- Esc menu / radial "Leave minigame". The server removes us from the room and
-- sends spz-pursuit:finish back, which does the actual teleport home.
AddEventHandler("spz:leaveMinigame", function()
    if M then TriggerServerEvent("spz-pursuit:leaveMatch") end
end)

AddEventHandler("onResourceStop", function(res)
    if res == GetCurrentResourceName() and M then cleanup() end
end)
