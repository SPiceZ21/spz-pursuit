-- client/match.lua — Hot Pursuit match
--
-- The server drives the phases (setup → chase → over) and owns the bust bar and
-- the result; this file spawns you, shows the HUD, sends "ready" and "holding
-- the bust key", respawns dead cops and puts you back afterwards.

local M = nil   -- current match; nil when not in one

local KEY_BUST, KEY_READY = Config.Keys.bust.control, Config.Keys.ready.control

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

local function text(str, x, y, scale, r, g, b)
    SetTextFont(4)
    SetTextScale(0.0, scale)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(r or 255, g or 255, b or 255, 235)
    BeginTextCommandDisplayText("STRING")
    AddTextComponentSubstringPlayerName(str)
    EndTextCommandDisplayText(x, y)
end

local function bar(x, y, w, h, pct, r, g, b)
    DrawRect(x, y, w, h, 10, 11, 14, 200)
    if pct > 0 then DrawRect(x - w / 2 + (w * pct) / 2, y, w * pct, h * 0.65, r, g, b, 235) end
end

--- Where a cop spawns: their point, shifted sideways one car-width per `slot`.
local function copSpot(spawn, slot)
    if not slot or slot == 0 then return spawn end
    local h = math.rad(spawn.w)
    local off = 4.0 * slot
    return { x = spawn.x + math.cos(h) * off, y = spawn.y + math.sin(h) * off, z = spawn.z, w = spawn.w }
end

local function bigMessage(title, sub, ms)
    CreateThread(function()
        local sf = RequestScaleformMovie("MP_BIG_MESSAGE_FREEMODE")
        local deadline = GetGameTimer() + 2000
        while not HasScaleformMovieLoaded(sf) and GetGameTimer() < deadline do Wait(0) end
        if not HasScaleformMovieLoaded(sf) then return end
        BeginScaleformMovieMethod(sf, "SHOW_SHARD_WASTED_MP_MESSAGE")
        ScaleformMovieMethodAddParamTextureNameString(title)
        ScaleformMovieMethodAddParamTextureNameString(sub or "")
        EndScaleformMovieMethod()
        local untilAt = GetGameTimer() + (ms or 4000)
        while GetGameTimer() < untilAt do
            DrawScaleformMovieFullscreen(sf, 255, 255, 255, 255, 0)
            Wait(0)
        end
        SetScaleformMovieAsNoLongerNeeded(sf)
    end)
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
        -- The getaway car is the robber's alone.
        SetVehicleDoorsLockedForAllPlayers(M.veh, true)
        SetVehicleDoorsLockedForPlayer(M.veh, PlayerId(), false)
        SetVehicleEngineOn(M.veh, false, true, true)
    end
    FreezeEntityPosition(ped, true)   -- held in the bank until the police are set
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

    fadeOut()
    -- Drops the phasing exclusions spz-core put on this ped, so contact works.
    SetEntityCollision(ped, true, true)

    if M.role == "robber" then spawnRobber() else spawnPolice() end
    Wait(500)
    DoScreenFadeIn(600)

    if M.role == "robber" then
        Pursuit.Notify("You're inside Pacific Standard. The police are setting up — when they're ready you're released. Get to your car and lose them.", "inform", "ROBBER")
    elseif M.role == "cop" then
        Pursuit.Notify(("Set up your position, then press [%s] when ready."):format(Config.Keys.ready.label), "inform", "POLICE")
    else
        Pursuit.Notify(("Get the chopper in position, then press [%s] when ready."):format(Config.Keys.ready.label), "inform", "PD CHOPPER")
    end
end)

RegisterNetEvent("spz-pursuit:state", function(s)
    if not M then return end
    M.phase, M.remain, M.ready, M.police, M.bust = s.phase, s.remain, s.ready, s.police, s.bust
end)

RegisterNetEvent("spz-pursuit:go", function()
    if not M then return end
    M.phase = "chase"
    if M.role == "robber" then
        FreezeEntityPosition(PlayerPedId(), false)
        bigMessage("~r~GO!", "Get to your car and lose the police")
        PlaySoundFrontend(-1, "Mission_Pass_Notify", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
    else
        bigMessage("~b~ROBBER IS MOVING", "Chase them down")
        PlaySoundFrontend(-1, "Mission_Pass_Notify", "DLC_HEISTS_GENERAL_FRONTEND_SOUNDS", true)
    end
end)

RegisterNetEvent("spz-pursuit:over", function(r)
    if not M then return end
    M.phase = "over"
    if M.holding then TriggerServerEvent("spz-pursuit:bustHold", false); M.holding = false end
    FreezeEntityPosition(PlayerPedId(), false)

    local title = r.winner == "police" and "~b~BUSTED" or "~r~ESCAPED"
    local sub = (r.won and "You win" or "You lose") .. (r.payout and r.payout > 0 and ("  +%d credits"):format(r.payout) or "")
    if r.reason and r.reason ~= "busted" and r.reason ~= "escaped" then sub = r.reason .. " · " .. sub end
    bigMessage(title, sub, 5000)
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

            if M.phase == "setup" and M.role ~= "robber" and not M.sentReady then
                if IsControlJustPressed(0, KEY_READY) then
                    M.sentReady = true
                    TriggerServerEvent("spz-pursuit:setupReady")
                    PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", true)
                end
            end

            -- Bust: a cop near a robber who has (nearly) stopped holds the key.
            -- The server re-checks distance and speed before the bar moves.
            if M.phase == "chase" and M.role == "cop" and not M.dead then
                local rped = playerPed(M.robber)
                local near = rped ~= 0 and #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(rped)) <= Config.BustDistance
                if near then DisableControlAction(0, 86, true) end       -- E is also the horn
                local want = near and (IsControlPressed(0, KEY_BUST) or IsDisabledControlPressed(0, KEY_BUST))
                if want ~= M.holding then
                    M.holding = want
                    TriggerServerEvent("spz-pursuit:bustHold", want)
                end
            elseif M.phase ~= "chase" then
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
        if M then
            local phaseLabel = ({ setup = "SETUP", chase = "CHASE", over = "" })[M.phase] or ""
            local roleLabel = Pursuit.RoleLabel(M.role):upper()
            if M.phase ~= "over" then
                text(("HOT PURSUIT · %s · %s · %s"):format(roleLabel, phaseLabel, fmt(M.remain or 0)), 0.5, 0.025, 0.46)
            end

            if M.phase == "setup" then
                local line
                if M.role == "robber" then
                    line = ("Held in the bank — police ready %d/%d"):format(M.ready, M.police)
                elseif M.sentReady then
                    line = ("Ready — waiting for the others (%d/%d)"):format(M.ready, M.police)
                else
                    line = ("Get in position · press [%s] when ready  (%d/%d)"):format(Config.Keys.ready.label, M.ready, M.police)
                end
                text(line, 0.5, 0.058, 0.36, 200, 200, 200)

            elseif M.phase == "chase" then
                if M.role == "robber" then
                    local kmh = speedKmh(PlayerPedId())
                    local slow = kmh <= Config.BustMaxSpeedKmh
                    text(("%d km/h"):format(math.floor(kmh + 0.5)), 0.5, 0.058, 0.55, slow and 255 or 255, slow and 70 or 255, slow and 70 or 255)
                    if slow then text("TOO SLOW — THE POLICE CAN BUST YOU", 0.5, 0.098, 0.34, 255, 70, 70) end
                else
                    local rped = playerPed(M.robber)
                    if rped ~= 0 then
                        local d = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(rped))
                        local kmh = speedKmh(rped)
                        text(("Robber %dm · %d km/h"):format(math.floor(d), math.floor(kmh + 0.5)), 0.5, 0.058, 0.4)
                        if M.role == "cop" and d <= Config.BustDistance then
                            if kmh <= Config.BustMaxSpeedKmh then
                                text(("HOLD [%s] TO BUST"):format(Config.Keys.bust.label), 0.5, 0.098, 0.42, 90, 170, 255)
                            else
                                text("Stop them to bust", 0.5, 0.098, 0.34, 200, 200, 200)
                            end
                        end
                    else
                        text("Robber out of range — follow the blip", 0.5, 0.058, 0.36, 200, 200, 200)
                    end
                end

                if (M.bust or 0) > 0 then
                    bar(0.5, 0.135, 0.22, 0.02, M.bust, 90, 170, 255)
                    text(("BUSTING %d%%"):format(math.floor(M.bust * 100)), 0.5, 0.147, 0.32)
                end
            end
            Wait(0)
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
                if show and ped ~= 0 then
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

AddEventHandler("onResourceStop", function(res)
    if res == GetCurrentResourceName() and M then cleanup() end
end)
