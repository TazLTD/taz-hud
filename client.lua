local QBCore = exports['qb-core']:GetCoreObject()
local hunger = 100
local thirst = 100
local stress = 0
local seatbeltOn = false
local istalking = false
local radioActive = false
local resetpausemenu = false
local huddata = {}
local config = Config
local speedMultiplier = config.UseMPH and 2.23694 or 3.6
local seatbeltOn = false
local cruiseOn = false
local showAltitude = false
local showSeatbelt = false
local cashAmount = 0
local bankAmount = 0
local playerDead = false
local showMenu = false
local showCircleB = false
local showSquareB = false
local Menu = config.Menu
local CinematicHeight = 0.2
local w = 0
local radioActive = false

RegisterCommand('hud', function()
    SetNuiFocus(true, true)

    SendNUIMessage({
        action = 'hudmenu',
        show = true,
        settings = huddata
    })
end)

AddEventHandler("pma-voice:radioActive", function(data)
    radioActive = data
end)

RegisterNetEvent('seatbelt:client:ToggleSeatbelt', function() -- Triggered in smallresources
    seatbeltOn = not seatbeltOn
end)

RegisterNetEvent('hud:client:UpdateNeeds', function(newHunger, newThirst) -- Triggered in qb-core
    hunger = newHunger
    thirst = newThirst
end)

RegisterNetEvent('hud:client:UpdateStress', function(newStress) -- Add this event with adding stress elsewhere
    stress = newStress
end)

-- Stress Gain

if not config.DisableStress then
    CreateThread(function() -- Speeding
        while true do
            if LocalPlayer.state.isLoggedIn then
                local ped = PlayerPedId()
                if IsPedInAnyVehicle(ped, false) then
                    local veh = GetVehiclePedIsIn(ped, false)
                    local vehClass = GetVehicleClass(veh)
                    local speed = GetEntitySpeed(veh) * speedMultiplier
                    local vehHash = GetEntityModel(veh)
                    if config.VehClassStress[tostring(vehClass)] and not config.WhitelistedVehicles[vehHash] then
                        local stressSpeed
                        if vehClass == 8 then -- Motorcycle exception for seatbelt
                            stressSpeed = config.MinimumSpeed
                        else
                            stressSpeed = seatbeltOn and config.MinimumSpeed or config.MinimumSpeedUnbuckled
                        end
                        if speed >= stressSpeed then
                            TriggerServerEvent('hud:server:GainStress', math.random(1, 3))
                        end
                    end
                end
            end
            Wait(10000)
        end
    end)

    CreateThread(function() -- Shooting
        while true do
            if LocalPlayer.state.isLoggedIn then
                local ped = PlayerPedId()
                local weapon = GetSelectedPedWeapon(ped)
                if weapon ~= `WEAPON_UNARMED` then
                    if IsPedShooting(ped) and not config.WhitelistedWeaponStress[weapon] then
                        if math.random() < config.StressChance then
                            TriggerServerEvent('hud:server:GainStress', math.random(1, 3))
                        end
                    end
                else
                    Wait(1000)
                end
            end
            Wait(0)
        end
    end)
end


local stressThreshold = 1 -- Adjust the stress threshold as needed
local pulseSoundPlaying = false

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(1000) -- Check the stress level every second (you can adjust the interval)

        if Config.EnableHeartbeatSound and stress > stressThreshold and not pulseSoundPlaying then
            TriggerServerEvent("InteractSound_SV:PlayOnSource", "Pulse", 0.03) -- Play the sound
            pulseSoundPlaying = true
        elseif stress <= stressThreshold and pulseSoundPlaying then
            pulseSoundPlaying = false
            -- You can add logic to stop the sound here if needed
        end
    end
end)


-- Stress Screen Effects

local function GetBlurIntensity(stresslevel)
    for _, v in pairs(config.Intensity['blur']) do
        if stresslevel >= v.min and stresslevel <= v.max then
            return v.intensity
        end
    end
    return 1500
end

local function GetEffectInterval(stresslevel)
    for _, v in pairs(config.EffectInterval) do
        if stresslevel >= v.min and stresslevel <= v.max then
            return v.timeout
        end
    end
    return 60000
end

CreateThread(function()
    while true do
        local ped = PlayerPedId()
        local effectInterval = GetEffectInterval(stress)
        if stress >= 100 then
            local BlurIntensity = GetBlurIntensity(stress)
            local FallRepeat = math.random(2, 4)
            local RagdollTimeout = FallRepeat * 1750
            TriggerScreenblurFadeIn(1000.0)
            Wait(BlurIntensity)
            TriggerScreenblurFadeOut(1000.0)

            if not IsPedRagdoll(ped) and IsPedOnFoot(ped) and not IsPedSwimming(ped) then
                SetPedToRagdollWithFall(ped, RagdollTimeout, RagdollTimeout, 1, GetEntityForwardVector(ped), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
            end

            Wait(1000)
            for _ = 1, FallRepeat, 1 do
                Wait(750)
                DoScreenFadeOut(200)
                Wait(1000)
                DoScreenFadeIn(200)
                TriggerScreenblurFadeIn(1000.0)
                Wait(BlurIntensity)
                TriggerScreenblurFadeOut(1000.0)
            end
        elseif stress >= config.MinimumStress then
            local BlurIntensity = GetBlurIntensity(stress)
            TriggerScreenblurFadeIn(1000.0)
            Wait(BlurIntensity)
            TriggerScreenblurFadeOut(1000.0)
        end
        Wait(effectInterval)
    end
end)

Citizen.CreateThread(function()
    TriggerServerEvent('taz-hud:get:data')

    DisplayRadar(false)

    while not GetVehiclePedIsIn(GetPlayerPed(-1), false) do
        Citizen.Wait(1000)
    end
end)

RegisterNetEvent('taz-hud:get:data', function(data)
    huddata = data

    LoadMap()
    Citizen.Wait(2000)
    LoadMap()

    huddata = data

    while true do
        if LocalPlayer.state.isLoggedIn and not IsPauseMenuActive() and IsScreenFadedIn() then
            local ped = GetPlayerPed(-1)
            local playerId = PlayerId()
            local oxygen = GetPlayerUnderwaterTimeRemaining(PlayerId()) * 10
            local inveh = IsPedInAnyVehicle(ped)
            local veh = GetVehiclePedIsIn(ped, false)
            local proxmity = nil
            local stamina = 100 - GetPlayerSprintStaminaRemaining(PlayerId())

            if not istalking and NetworkIsPlayerTalking(PlayerId()) == 1 then
                istalking = true

                SendNUIMessage({
                    action = 'updateStatusHud',
                    show = true,
                    talking = {
                        talking = istalking,
                        radio = radioActive,
                    },
                })
            elseif istalking and NetworkIsPlayerTalking(PlayerId()) == false then
                istalking = false

                SendNUIMessage({
                    action = 'updateStatusHud',
                    show = true,
                    talking = {
                        talking = istalking,
                        radio = radioActive,
                    },
                })
            end

            if LocalPlayer.state['proximity'] then
                proxmity = LocalPlayer.state['proximity'].distance
            end

            SendNUIMessage({
                action = 'UpdateProximity',
                proxmity = tonumber(proxmity),
            })

            if inveh then
                local speed = math.floor(GetEntitySpeed(veh) * 3.6)

                    if speed == 0 then
                        speed = 1
                    end

                    if Config.SpeedType == 'mph' then
                        speed = math.floor(GetEntitySpeed(veh) * 2.23694)
                    elseif Config.SpeedType ~= 'km/h' then
                    end
                    

                PauseMenuReset()

                DisplayRadar(true)

                SendNUIMessage({
                    action = 'updateStatusHud',
                    show = true,
                    talking = nil,
                    health = GetEntityHealth(ped) - 100,
                    armour = GetPedArmour(ped),
                    hunger = hunger,
                    thirst = thirst,
                    stress = stress,
                    oxygen = oxygen,
                    speed = speed,
                    alt = math.floor(GetEntityHeightAboveGround(veh)),
                    fuel = GetVehicleFuelLevel(veh),
                    stamina = stamina,
                })

                SendNUIMessage({
                    action = 'car',
                    show = true,
                })

                SendNUIMessage({
                    action = 'seatbelt',
                    toggle = seatbeltOn,
                })

                SendNUIMessage({
                    action = 'air',
                    show = IsPedInAnyHeli(ped) or IsPedInAnyPlane(ped)
                })
            else
                DisplayRadar(false)

                SendNUIMessage({
                    action = 'updateStatusHud',
                    show = true,
                    talking = nil,
                    health = GetEntityHealth(ped) - 100,
                    armour = GetPedArmour(ped),
                    hunger = hunger,
                    thirst = thirst,
                    stress = stress,
                    oxygen = oxygen,
                    speed = 1,
                    stamina = stamina,
                })

                SendNUIMessage({
                    action = 'car',
                    show = false,
                })

                SendNUIMessage({
                    action = 'seatbelt',
                    toggle = false,
                })

                SendNUIMessage({
                    action = 'air',
                    show = false
                })
            end
        else
            SendNUIMessage({
                action = 'updateStatusHud',
                show = false,
            })
        end

        Citizen.Wait(250)
    end
end)

function PauseMenuReset()
    if not resetpausemenu then
        Citizen.CreateThread(function()
            local count = 0

            resetpausemenu = true

            ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_MP_PAUSE'),0,-1)

            while 10 > count do
                count = count + 1

                if IsPauseMenuActive() then
                    ActivateFrontendMenu(GetHashKey('FE_MENU_VERSION_MP_PAUSE'),0,-1)
                end

                Citizen.Wait(100)
            end
        end)
    end
end

function LoadMap()
    local defaultAspectRatio = 1920/1080 -- Don't change this.
    local resolutionX, resolutionY = GetActiveScreenResolution()
    local aspectRatio = resolutionX/resolutionY
    local minimapOffset = 0

    if aspectRatio > defaultAspectRatio then
        minimapOffset = ((defaultAspectRatio-aspectRatio)/3.6)-0.008
    end

    SetBlipAlpha(GetNorthRadarBlip(), 0)

    Citizen.CreateThread(function()
        SetBlipAlpha(GetNorthRadarBlip(), 0)

        print("Current Minimap Shape: " .. huddata.minimap)

        if huddata.minimap == 2 then
            RequestStreamedTextureDict("circlemap", false)
            while not HasStreamedTextureDictLoaded("circlemap") do
                Wait(100)
            end

            AddReplaceTexture("platform:/textures/graphics", "radarmasksm", "circlemap", "radarmasksm")
            AddReplaceTexture("platform:/textures/graphics", "radarmask1g", "circlemap", "radarmasksm")

            SetMinimapClipType(1)
            SetMinimapComponentPosition("minimap", "L", "B", 0.025 - 0.03, -0.06, 0.153, 0.27)
            SetMinimapComponentPosition("minimap_mask", "L", "B", 0.135 - 0.03, 0.24, 0.093, 0.164)
            SetMinimapComponentPosition("minimap_blur", "L", "B", 0.012 - 0.03, 0.044, 0.256, 0.337)

        else
            RequestStreamedTextureDict("squaremap", false)
            while not HasStreamedTextureDictLoaded("squaremap") do
                Wait(0)
            end

            local minimap = RequestScaleformMovie("minimap")

            while not HasScaleformMovieLoaded(minimap) do
                Wait(0)
            end

            local minimapOffset = -0.015
            if aspectRatio > defaultAspectRatio then
                minimapOffset = ((defaultAspectRatio - aspectRatio) / 3.6) - 0.008
            end

            AddReplaceTexture("platform:/textures/graphics", "radarmasksm", "squaremap", "radarmasksm")
            AddReplaceTexture("platform:/textures/graphics", "radarmask1g", "squaremap", "radarmasksm")

            SetMinimapComponentPosition('minimap', 'L', 'B', 0.0 + minimapOffset, -0.047, 0.1638, 0.183)

        -- icons within map
        SetMinimapComponentPosition('minimap_mask', 'L', 'B', 0.0 + minimapOffset, 0.0, 0.128, 0.20)

        -- -0.01 = map pulled left
        -- 0.025 = map raised up
        -- 0.262 = map stretched
        -- 0.315 = map shorten
        SetMinimapComponentPosition('minimap_blur', 'L', 'B', -0.01 + minimapOffset, 0.025, 0.262, 0.300)

        end
    end)
end

RegisterNUICallback('closeui', function(data, cb)
    SetNuiFocus(false, false)

    SendNUIMessage({
        action = 'hudmenu',
        show = false,
        settings = {}
    })

    cb('ok')
end)

RegisterNUICallback('SaveHudSettings', function(data, cb)
    SetNuiFocus(false, false)

    huddata = data.settings

    TriggerServerEvent('taz-hud:update', huddata)

    SendNUIMessage({
        action = 'hudmenu',
        show = false,
        settings = {}
    })

    LoadMap()
    Citizen.Wait(500)
    LoadMap()
    resetpausemenu = false

    cb('ok')
end)
