-- client/customize.lua — full tuner on a preview of your room car
--
-- You go into a private bucket, sit in a preview of the car, and get the normal
-- spz-tunners menu on it. When you close the tuner the setup is sent to the
-- room (it's applied when the car spawns in the match) and you're put back
-- exactly where you were — in your own car if you were driving.

local busy = false

local function tunerOpen()
    local m = lib.getOpenMenu()
    return type(m) == "string" and m:sub(1, 10) == "spz_tuner_"
end

function Pursuit.Customize(model, onDone)
    if busy then return end
    if GetResourceState("spz-tunners") ~= "started" then
        return Pursuit.Notify("The tuner (spz-tunners) isn't running", "error")
    end
    busy = true

    local ped = PlayerPedId()
    local backVeh = GetVehiclePedIsIn(ped, false)
    local backSeat = nil
    if backVeh ~= 0 then
        for seat = -1, GetVehicleMaxNumberOfPassengers(backVeh) - 1 do
            if GetPedInVehicleSeat(backVeh, seat) == ped then backSeat = seat break end
        end
    end
    local back = GetEntityCoords(ped)
    local backHeading = GetEntityHeading(ped)

    DoScreenFadeOut(300)
    while not IsScreenFadedOut() do Wait(0) end

    if not lib.callback.await("spz-pursuit:previewBucket", false, true) then
        DoScreenFadeIn(300)
        busy = false
        return Pursuit.Notify("Can't open the tuner right now", "error")
    end

    local preset = lib.callback.await("spz-pursuit:getPreset", false, model)
    local veh = Pursuit.SpawnCar(model, { x = back.x, y = back.y, z = back.z, w = backHeading }, preset)

    if veh ~= 0 then
        SetPedIntoVehicle(PlayerPedId(), veh, -1)
        FreezeEntityPosition(veh, true)
        DoScreenFadeIn(300)

        exports["spz-tunners"]:OpenTunerMenu(veh)

        -- Wait for the tuner to close (submenu hops leave a short gap).
        Wait(500)
        local closedFor = 0
        while closedFor < 800 do
            if tunerOpen() then closedFor = 0 else closedFor = closedFor + 100 end
            Wait(100)
        end

        local props = exports["spz-tunners"]:GetVehicleMods(veh)
        if props then
            lib.callback.await("spz-pursuit:savePreset", false, model, props)
            Pursuit.Notify(Pursuit.CarLabel(model) .. " setup saved", "success")
        end

        DoScreenFadeOut(300)
        while not IsScreenFadedOut() do Wait(0) end
        DeleteEntity(veh)
    end

    lib.callback.await("spz-pursuit:previewBucket", false, false)

    ped = PlayerPedId()
    if backVeh ~= 0 and DoesEntityExist(backVeh) and backSeat and IsVehicleSeatFree(backVeh, backSeat) then
        SetPedIntoVehicle(ped, backVeh, backSeat)
    else
        SetEntityCoords(ped, back.x, back.y, back.z, false, false, false, false)
        SetEntityHeading(ped, backHeading)
    end
    DoScreenFadeIn(400)

    busy = false
    if onDone then onDone() end
end
