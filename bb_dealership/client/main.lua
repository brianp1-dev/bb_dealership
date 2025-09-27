local showroomEntities = {}
local vehicleData = {}
local browsing = false

-- Forward declaration to allow referencing inside spawned threads before definition
local openBrowseMenu

local function dbg(...)
    if Config.Debug then
        print('^3[custom_dealership]^7', ...)
    end
end

local function normalizeCoordStruct(spawn)
    if not spawn then return nil end
    -- if it's a vector4 userdata
    if type(spawn) == 'vector4' or (spawn.x and spawn.y and spawn.z) then
        return { x = spawn.x, y = spawn.y, z = spawn.z, w = spawn.w or spawn.heading or 0.0 }
    end
    return spawn
end

-- Test drive countdown display
local testDriveEnd = nil
local testDriveBaseMinutes = nil
local testDriveStart = nil
local testDriveNetId = nil
local testDriveReturnPos = nil
local testDriveMonitorActive = false
CreateThread(function()
    while true do
        if testDriveEnd then
            local now = GetGameTimer()
            local remaining = math.floor( (testDriveEnd - now) / 1000 )
            local txt
            if remaining >= 0 then
                local m = math.floor(remaining / 60)
                local s = remaining % 60
                txt = ('Test Drive: %02d:%02d'):format(m, s)
            else
                local elapsed = math.floor((now - testDriveEnd) / 1000)
                local extraMin = math.floor(elapsed / 60) + 1
                txt = ('Test Drive: Extra +%d min'):format(extraMin)
            end
            DrawTxt(txt, 0.5, 0.88)
        end
        Wait(0)
    end
end)

function DrawTxt(text, x, y)
    SetTextFont(4)
    SetTextScale(0.4, 0.4)
    SetTextColour(255,255,255,215)
    SetTextCentre(true)
    SetTextOutline()
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

local function spawnShowroomVehicles()
    for i, v in ipairs(Config.ShowroomVehicles) do
        local model = v.model
        lib.requestModel(model, 10000)
        local veh = CreateVehicle(joaat(model), v.coords.x, v.coords.y, v.coords.z, v.coords.w, false, false)
        SetVehicleOnGroundProperly(veh)
        SetEntityInvincible(veh, true)
        FreezeEntityPosition(veh, true)
        SetVehicleDirtLevel(veh, 0.0)
        SetVehicleDoorsLocked(veh, 10)
        SetVehicleNumberPlateText(veh, 'SHOWRM')
        showroomEntities[i] = veh
    end
    if Config.ShowroomLocalMarker then
        CreateThread(function()
            while #showroomEntities > 0 do
                local sleep = 500
                local ped = PlayerPedId()
                local pcoords = GetEntityCoords(ped)
                for idx, veh in ipairs(showroomEntities) do
                    if veh and DoesEntityExist(veh) then
                        local vpos = GetEntityCoords(veh)
                        local dist = #(pcoords - vpos)
                        if dist < 40.0 then
                            sleep = 0
                            -- Draw marker
                            DrawMarker(
                                Config.ShowroomMarkerType or 36,
                                vpos.x, vpos.y, vpos.z + 0.1,
                                0.0,0.0,0.0, 0.0,0.0,0.0,
                                (Config.ShowroomMarkerScale and Config.ShowroomMarkerScale.x) or 0.5,
                                (Config.ShowroomMarkerScale and Config.ShowroomMarkerScale.y) or 0.5,
                                (Config.ShowroomMarkerScale and Config.ShowroomMarkerScale.z) or 0.5,
                                (Config.ShowroomMarkerColor and Config.ShowroomMarkerColor.r) or 0,
                                (Config.ShowroomMarkerColor and Config.ShowroomMarkerColor.g) or 170,
                                (Config.ShowroomMarkerColor and Config.ShowroomMarkerColor.b) or 255,
                                (Config.ShowroomMarkerColor and Config.ShowroomMarkerColor.a) or 150,
                                false,false,2,false,nil,nil,false
                            )
                            if dist < 3.0 then
                                -- Floating label
                                local labelZ = vpos.z + (Config.ShowroomLabelOffset or 1.0)
                                SetDrawOrigin(vpos.x, vpos.y, labelZ, 0)
                                SetTextFont(4)
                                SetTextScale(0.35, 0.35)
                                SetTextColour(255,255,255,215)
                                SetTextCentre(true)
                                BeginTextCommandDisplayText('STRING')
                                AddTextComponentSubstringPlayerName('Ver Catálogo [E]')
                                EndTextCommandDisplayText(0.0, 0.0)
                                ClearDrawOrigin()
                                if IsControlJustPressed(0, 38) then
                                    openBrowseMenu()
                                end
                            end
                        end
                    end
                end
                Wait(sleep)
            end
        end)
    end
end

local function deleteShowroomVehicles()
    for _, ent in pairs(showroomEntities) do
        if ent and DoesEntityExist(ent) then
            DeleteEntity(ent)
        end
    end
    showroomEntities = {}
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    deleteShowroomVehicles()
end)

function openBrowseMenu()
    if browsing then return end
    browsing = true
    vehicleData = lib.callback.await('custom_dealership:getVehicleData') or {}
    if not vehicleData or #vehicleData == 0 then
        lib.notify({ title = 'Concessionária', description = 'Nenhum veículo carregado.', type = 'error' })
        browsing = false
        return
    end
    local function getPlayerJobName()
        if exports and exports.qbx_core and exports.qbx_core.GetPlayerData then
            local pdata = exports.qbx_core:GetPlayerData()
            if pdata and pdata.job and pdata.job.name then return pdata.job.name end
        end
        if QBX and QBX.PlayerData and QBX.PlayerData.job then
            return QBX.PlayerData.job.name
        end
        return nil
    end
    local playerJob = getPlayerJobName()

    local function buildVehicleOption(v)
        return {
            title = ('%s %s'):format(v.brand:upper(), v.name:upper()),
            description = ('$%s | Stock: %s'):format(lib.math.groupdigits(v.price), (v.stock ~= nil and v.stock or '∞')), 
            icon = 'car-side',
            onSelect = function()
                local actions = {}
                if Config.EnableTestDrive then
                    actions[#actions+1] = {
                        title = 'Test Drive',
                        icon = 'road',
                        onSelect = function()
                            TriggerServerEvent('custom_dealership:startTestDrive', v.model)
                        end
                    }
                end
                if playerJob and playerJob == Config.DealerJob then
                    if Config.UseStock and (v.stock or 0) <= 0 and not Config.AllowNegativeStock then
                        actions[#actions+1] = {
                            title = 'Sem Stock',
                            icon = 'triangle-exclamation',
                            disabled = true
                        }
                    else
                    actions[#actions+1] = {
                        title = 'Vender a Cliente',
                        icon = 'hand-holding-dollar',
                        onSelect = function()
                            local buyer
                            local price
                            if Config.AllowCustomPrice then
                                local dialog = lib.inputDialog('Venda de Veículo', {
                                    { type = 'number', label = 'ID Comprador' },
                                    { type = 'number', label = ('Preço (base: %s)'):format(lib.math.groupdigits(v.price)) }
                                })
                                if not dialog then return end
                                buyer = tonumber(dialog[1])
                                price = tonumber(dialog[2])
                                if not buyer or not price then return end
                            else
                                local dialog = lib.inputDialog('Venda de Veículo', {
                                    { type = 'number', label = 'ID Comprador' }
                                })
                                if not dialog then return end
                                buyer = tonumber(dialog[1])
                                if not buyer then return end
                                price = v.price -- fixed base price
                            end
                            TriggerServerEvent('custom_dealership:sellVehicle', { buyer = buyer, model = v.model, price = price })
                        end
                    }
                    end
                end
                lib.registerContext({
                    id = 'vehicle_actions_'..v.model,
                    title = v.name,
                    menu = Config.GroupByBrand and ('brand_'..(v.brand or 'OUTROS')) or 'dealership_main',
                    options = actions
                })
                lib.showContext('vehicle_actions_'..v.model)
            end
        }
    end

    if Config.GroupByBrand then
        local grouped = {}
        for _, v in ipairs(vehicleData) do
            local brand = (v.brand or 'Outros'):lower()
            grouped[brand] = grouped[brand] or { title = brand:upper(), options = {} }
            grouped[brand].options[#grouped[brand].options+1] = buildVehicleOption(v)
        end

        -- register each brand submenu
        local brandMainOptions = {}
        for brandKey, data in pairs(grouped) do
            local submenuId = 'brand_'..brandKey
            lib.registerContext({ id = submenuId, title = data.title, menu = 'dealership_main', options = data.options })
            brandMainOptions[#brandMainOptions+1] = {
                title = data.title,
                description = ('%d veículos'):format(#data.options),
                icon = 'folder-open',
                menu = submenuId
            }
        end
        table.sort(brandMainOptions, function(a,b) return a.title < b.title end)
        lib.registerContext({ id = 'dealership_main', title = 'Concessionária', options = brandMainOptions })
        lib.showContext('dealership_main')
    else
        local opts = {}
        for _, v in ipairs(vehicleData) do
            opts[#opts+1] = buildVehicleOption(v)
        end
        lib.registerContext({ id = 'dealership_main', title = 'Concessionária', options = opts })
        lib.showContext('dealership_main')
    end
    browsing = false
end

-- Event from server / command to force open menu
RegisterNetEvent('custom_dealership:openMenu', function()
    if not Config.AllowCommandAnywhere then
        local dist = #(GetEntityCoords(PlayerPedId()) - Config.InteractPoint)
        if dist > Config.InteractRadius then
            lib.notify({ title = 'Concessionária', description = 'Aproxime-se do balcão para abrir o menu.', type = 'error' })
            return
        end
    end
    openBrowseMenu()
end)

-- Remote spawn for test drive (server asks)
lib.callback.register('custom_dealership:spawnLocalVehicle', function(model, coords, plate)
    coords = normalizeCoordStruct(coords)
    if not coords then
        
        return
    end
    lib.requestModel(model, 10000)
    local heading = (coords and coords.w) or GetEntityHeading(PlayerPedId())
    local veh = CreateVehicle(joaat(model), coords.x, coords.y, coords.z, heading, true, true)
    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, plate)
    SetEntityAsMissionEntity(veh, true, true)
    if not veh or veh == 0 then
        
        return
    end
    -- Warp driver (test drive convenience) with retries
    local ped = PlayerPedId()
    TaskWarpPedIntoVehicle(ped, veh, -1)
    CreateThread(function()
        for i=1,20 do
            if GetVehiclePedIsIn(ped, false) == veh then break end
            TaskWarpPedIntoVehicle(ped, veh, -1)
            Wait(100)
        end
        -- Unlock & engine on for test drive even sem chaves
        SetVehicleDoorsLocked(veh, 1)
        SetVehicleDoorsLockedForAllPlayers(veh, false)
        SetVehicleEngineOn(veh, true, true, false)
        -- pedir chaves (fiabilidade extra)
        local netId = NetworkGetNetworkIdFromEntity(veh)
        TriggerServerEvent('custom_dealership:requestTestDriveKeys', netId)
    end)
    -- iniciar contagem base se test drive spawn
    testDriveEnd = GetGameTimer() + (Config.TestDriveMinutes * 60000)
    testDriveBaseMinutes = Config.TestDriveMinutes
    testDriveStart = GetGameTimer()
    return NetworkGetNetworkIdFromEntity(veh)
end)

-- Warp into server-spawned test drive vehicle
RegisterNetEvent('custom_dealership:warpIntoTestDrive', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if veh and veh ~= 0 and DoesEntityExist(veh) then
        local ped = PlayerPedId()
        TaskWarpPedIntoVehicle(ped, veh, -1)
        CreateThread(function()
            for i=1,20 do
                if GetVehiclePedIsIn(ped, false) == veh then break end
                TaskWarpPedIntoVehicle(ped, veh, -1)
                Wait(100)
            end
            SetVehicleDoorsLocked(veh, 1)
            SetVehicleDoorsLockedForAllPlayers(veh, false)
            SetVehicleEngineOn(veh, true, true, false)
            local netId2 = NetworkGetNetworkIdFromEntity(veh)
            TriggerServerEvent('custom_dealership:requestTestDriveKeys', netId2)
        end)
        -- start timer client-side if not already started (server also triggers startTestDriveTimer)
        if not testDriveStart then
            testDriveStart = GetGameTimer()
            testDriveEnd = testDriveStart + (Config.TestDriveMinutes * 60000)
            testDriveBaseMinutes = Config.TestDriveMinutes
        end
    else
        
    end
end)

-- Start test drive timer event (server side when server spawn mode active)
RegisterNetEvent('custom_dealership:startTestDriveTimer', function(data)
    local base = data and data.baseMinutes or Config.TestDriveMinutes or 2
    testDriveBaseMinutes = base
    testDriveStart = GetGameTimer()
    testDriveEnd = testDriveStart + (base * 60000)
    
end)

-- Receive test drive info (netId + return position)
RegisterNetEvent('custom_dealership:testDriveInfo', function(data)
    testDriveNetId = data and data.netId or nil
    testDriveReturnPos = data and data.returnPos or nil
    if testDriveNetId and not testDriveMonitorActive then
        testDriveMonitorActive = true
        CreateThread(function()
            
            while testDriveMonitorActive do
                Wait(1000)
                if not testDriveNetId then break end
                local veh = NetworkGetEntityFromNetworkId(testDriveNetId)
                local ped = PlayerPedId()
                if veh and veh ~= 0 and DoesEntityExist(veh) then
                    if GetVehiclePedIsIn(ped, false) ~= veh then
                        
                        TriggerServerEvent('custom_dealership:endTestDrive', 'Test drive terminado')
                        break
                    end
                else
                    
                    TriggerServerEvent('custom_dealership:endTestDrive', 'Test drive terminado')
                    break
                end
            end
            testDriveMonitorActive = false
        end)
    end
end)

-- Cleanup on end test drive (teleport feito server-side)
RegisterNetEvent('custom_dealership:endTestDriveClient', function()
    testDriveNetId = nil
    testDriveReturnPos = nil
    testDriveEnd = nil
    testDriveStart = nil
    testDriveBaseMinutes = nil
    testDriveMonitorActive = false
end)

-- Remote spawn for owned vehicle after sale
lib.callback.register('custom_dealership:spawnOwnedVehicle', function(vehicleId, model, spawn)
    spawn = normalizeCoordStruct(spawn)
    
    if not vehicleId or not model or not spawn then
        
        return
    end
    if not IsModelInCdimage(joaat(model)) then
        
        lib.notify({ title = 'Concessionária', description = 'Modelo inválido: '..tostring(model), type = 'error' })
        return
    end
    lib.requestModel(model, 10000)
    local veh = CreateVehicle(joaat(model), spawn.x, spawn.y, spawn.z, spawn.w, true, true)
    if not veh or veh == 0 then
        
        lib.notify({ title = 'Concessionária', description = 'Falha ao criar veículo.', type = 'error' })
        return
    end
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    Entity(veh).state:set('vehicleid', vehicleId, true)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    
    return netId
end)

-- Zone detection / key use
CreateThread(function()
    spawnShowroomVehicles()
    -- blip
    local blip = AddBlipForCoord(Config.InteractPoint.x, Config.InteractPoint.y, Config.InteractPoint.z)
    SetBlipSprite(blip, 326) -- car dealership icon (change if desired)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.85)
    SetBlipColour(blip, 3)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString('Concessionária')
    EndTextCommandSetBlipName(blip)

    while true do
        local sleep = 1000
        local ped = PlayerPedId()
        local dist = #(GetEntityCoords(ped) - Config.InteractPoint)
        
        if Config.ShowMarker then
            DrawMarker(1, Config.InteractPoint.x, Config.InteractPoint.y, Config.InteractPoint.z-0.95, 0.0,0.0,0.0, 0.0,0.0,0.0, 1.0,1.0,0.8, 0,150,255,120, false,false,2,false,nil,nil,false)
        end
        if dist < (Config.InteractRadius + 8.0) then
            sleep = 200
            if dist <= Config.InteractRadius then
                if IsControlJustPressed(0, 38) then
                    openBrowseMenu()
                end
                lib.showTextUI('[E] Concessionária')
            else
                lib.hideTextUI()
            end
        else
            lib.hideTextUI()
        end
        Wait(sleep)
    end
end)

-- ox_lib keybind fallback (usable mesmo se loop falhar)
if lib and lib.addKeybind then
    lib.addKeybind({
        name = 'dealership_open',
        description = 'Abrir Concessionária',
        defaultKey = 'E',
        onPressed = function()
            local dist = #(GetEntityCoords(PlayerPedId()) - Config.InteractPoint)
            if dist <= Config.InteractRadius then
                openBrowseMenu()
            end
        end
    })
end

-- Receber oferta de compra
RegisterNetEvent('custom_dealership:receiveOffer', function(data)
    local model = data.model
    local price = data.price
    local timeout = data.timeout or 30
    local expireAt = GetGameTimer() + timeout * 1000
    local title = ('Comprar %s por $%s?'):format(model, lib.math.groupdigits(price))

    local function stillValid()
        return GetGameTimer() < expireAt
    end

    lib.registerContext({
        id = 'dealership_offer',
        title = title,
        options = {
            {
                title = 'Aceitar',
                icon = 'check',
                onSelect = function()
                    if not stillValid() then
                        return lib.notify({ title = 'Concessionária', description = 'Oferta expirada.', type = 'error' })
                    end
                    TriggerServerEvent('custom_dealership:respondOffer', true)
                end
            },
            {
                title = 'Recusar',
                icon = 'xmark',
                onSelect = function()
                    TriggerServerEvent('custom_dealership:respondOffer', false)
                end
            }
        }
    })
    lib.showContext('dealership_offer')

    -- auto remover menu após timeout se ainda visível
    CreateThread(function()
        while stillValid() do Wait(500) end
        -- se ainda for o menu atual, fecha (ox_lib não tem close direto para context, mas podemos abrir vazio)
        -- Usuário será notificado pelo servidor se expirar.
    end)
end)

-- Optional ox_target integration for each showroom vehicle
CreateThread(function()
    if not Config.UseTarget or not exports.ox_target then return end
    for idx, ent in pairs(showroomEntities) do
        exports.ox_target:addLocalEntity(ent, {
            {
                name = 'dealership_vehicle_'..idx,
                icon = 'fa-solid fa-car',
                label = 'Ver Opções',
                onSelect = function()
                    openBrowseMenu()
                end
            }
        })
    end
end)
