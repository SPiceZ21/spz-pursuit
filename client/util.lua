-- client/util.lua — shared client helpers

Pursuit = Pursuit or {}

function Pursuit.Notify(msg, t, title)
    lib.notify({ title = title or "Hot Pursuit", description = msg, type = t or "inform" })
end

function Pursuit.CarLabel(model)
    local hash = GetHashKey(model)
    local make = GetLabelText(GetMakeNameFromVehicleModel(hash))
    local name = GetLabelText(GetDisplayNameFromVehicleModel(hash))
    if name == "NULL" or name == "" then name = model end
    if make ~= "NULL" and make ~= "" then return make .. " " .. name end
    return name
end

function Pursuit.RoleLabel(role)
    return ({ robber = "Robber", cop = "Cop", pilot = "PD Chopper" })[role] or "No role"
end

--- Wait for the world at a point to stream in (so a spawn doesn't fall through).
function Pursuit.LoadArea(x, y, z)
    RequestCollisionAtCoord(x, y, z)
    local deadline = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(x, y, z)
        Wait(0)
    end
end

--- Networked car at a vec4-like {x,y,z,w}, with the player's tuner setup.
function Pursuit.SpawnCar(model, at, preset)
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) then
        Pursuit.Notify(("Car model '%s' isn't available"):format(model), "error")
        return 0
    end
    RequestModel(hash)
    local deadline = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(0) end
    if not HasModelLoaded(hash) then return 0 end

    local veh = CreateVehicle(hash, at.x, at.y, at.z, at.w or 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)
    if veh == 0 then return 0 end

    SetVehicleOnGroundProperly(veh)
    SetVehicleModKit(veh, 0)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehicleEngineOn(veh, true, true, false)
    if preset and GetResourceState("spz-tunners") == "started" then
        pcall(function() exports["spz-tunners"]:ApplyVehicleMods(veh, preset) end)
    end
    return veh
end
