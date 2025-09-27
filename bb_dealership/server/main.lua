local vehiclesCache
local activeTestDrives = {}
local lastTestDrive = {}
local lastSale = {}
local pendingOffers = {}
local stockCache = {}

-- Debug printer defined first so all helpers can use it
local function dbg(...)
    if not Config or not Config.Debug then return end
    local out = {}
    for i=1,select('#', ...) do out[#out+1] = tostring(select(i, ...)) end
    print('^3[custom_dealership]^7 '..table.concat(out, ' '))
end

-- Safe checker: some FXServer builds / environments may not expose IsModelInCdimage server-side.
-- We fall back to IsModelValid if available, otherwise optimistic true (CreateVehicle will still fail if invalid).
local function modelExists(hash)
    if type(hash) == 'string' then hash = joaat(hash) end
    if IsModelInCdimage then return IsModelInCdimage(hash) end
    if IsModelValid then return IsModelValid(hash) end
    return true
end

-- Safe model request (some servers lack RequestModel server-side; spawning anyway may still work if model is base game)
local function safeRequestModel(hash)
    if RequestModel then
        pcall(RequestModel, hash)
    else
    end
end

-- Safe wrappers for vehicle entity operations (some builds may not expose these server-side)
local function safeSetPlate(veh, plate)
    if SetVehicleNumberPlateText then pcall(SetVehicleNumberPlateText, veh, plate) end
end
local function safeMissionEntity(veh)
    if SetEntityAsMissionEntity then pcall(SetEntityAsMissionEntity, veh, true, true) end
end
local function safeOnGround(veh)
    if SetVehicleOnGroundProperly then pcall(SetVehicleOnGroundProperly, veh) end
end

local function getVehicles()
    if not vehiclesCache then
        vehiclesCache = Config.VehicleExport() or {}
    end
    return vehiclesCache
end

local function ensureStockTable()
    if not Config.UseStock then return end
    MySQL.query([[CREATE TABLE IF NOT EXISTS dealer_stock (
        id INT AUTO_INCREMENT PRIMARY KEY,
        model VARCHAR(50) NOT NULL UNIQUE,
        stock INT NOT NULL DEFAULT 0,
        updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])
end

local function loadStock()
    if not Config.UseStock then return end
    local result = MySQL.query.await('SELECT model, stock FROM dealer_stock') or {}
    for _, row in ipairs(result) do
        stockCache[row.model] = row.stock
    end
end

local function seedStock(model)
    if not Config.UseStock then return end
    local default = Config.StockPerVehicle[model] or Config.DefaultStock
    if stockCache[model] == nil then
        stockCache[model] = default
        MySQL.insert('INSERT INTO dealer_stock (model, stock) VALUES (?, ?) ON DUPLICATE KEY UPDATE stock = VALUES(stock)', { model, default })
    end
end

local function getStock(model)
    if not Config.UseStock then return 999999 end -- effectively unlimited
    local s = stockCache[model]
    if s == nil then
        seedStock(model)
        s = stockCache[model] or 0
    end
    return s
end

local function takeStock(model)
    if not Config.UseStock then return true end
    local current = getStock(model)
    if current <= 0 and not Config.AllowNegativeStock then
        return false, current
    end
    local newVal = current - 1
    stockCache[model] = newVal
    MySQL.update('INSERT INTO dealer_stock (model, stock) VALUES (?, ?) ON DUPLICATE KEY UPDATE stock = VALUES(stock)', { model, newVal })
    return true, newVal
end

local function addStock(model, amount)
    if not Config.UseStock then return end
    local current = getStock(model)
    local newVal = current + amount
    stockCache[model] = newVal
    MySQL.update('INSERT INTO dealer_stock (model, stock) VALUES (?, ?) ON DUPLICATE KEY UPDATE stock = VALUES(stock)', { model, newVal })
    return newVal
end

local function getVehiclePrice(model)
    local vehs = getVehicles()
    local entry = vehs[model]
    if entry and entry.price then return entry.price end
    return Config.FallbackPrice
end

local function findFreeSpawn()
    if Config.DeliveryPoint then
        local sp = Config.DeliveryPoint
        return { x = sp.x, y = sp.y, z = sp.z, w = sp.w }
    end
    for _, sp in ipairs(Config.SpawnPoints) do
        local vehicles = GetGamePool('CVehicle')
        local occupied = false
        for i = 1, #vehicles do
            if #(GetEntityCoords(vehicles[i]) - sp.xyz) < 2.5 then
                occupied = true
                break
            end
        end
        if not occupied then
            return { x = sp.x, y = sp.y, z = sp.z, w = sp.w }
        end
    end
    local sp = Config.SpawnPoints[1]
    return { x = sp.x, y = sp.y, z = sp.z, w = sp.w }
end

local function giveKeys(src, netId)
    if GetResourceState('qbx_vehiclekeys'):find('started') then
        local ent = NetworkGetEntityFromNetworkId(netId)
        if ent and ent ~= 0 then
            exports.qbx_vehiclekeys:GiveKeys(src, ent)
        end
    end
end

-- Reliable key grant after client confirms vehicle exists & player seated
RegisterNetEvent('custom_dealership:requestTestDriveKeys', function(netId)
    local src = source
    if not netId then return end
    giveKeys(src, netId)
end)

local function depositSociety(amount)
    if not Config.EnableSociety or amount <= 0 then return end
    if GetResourceState('Renewed-Banking'):find('started') then
        exports['Renewed-Banking']:addAccountMoney(Config.SocietyAccount, amount)
    end
end

local function payCommission(src, amount)
    if amount <= 0 then return end
    local player = exports.qbx_core:GetPlayer(src)
    if player then
        player.Functions.AddMoney('bank', amount, 'vehicle-sale-commission')
    end
end

lib.callback.register('custom_dealership:getVehicleData', function()
    local out = {}
    local vehs = getVehicles()
    for model, data in pairs(vehs) do
        local stock = getStock(model)
        out[#out+1] = { model = model, name = data.name or model, brand = data.brand or '', price = data.price or getVehiclePrice(model), stock = stock }
    end
    table.sort(out, function(a,b) return a.price < b.price end)
    return out
end)

local function clearTestDrive(src)
    local td = activeTestDrives[src]
    if not td then return end
    local veh = NetworkGetEntityFromNetworkId(td.netId)
    if veh and DoesEntityExist(veh) then
        DeleteEntity(veh)
    end
    activeTestDrives[src] = nil
    if Config.TestDriveUseInstance then
        SetPlayerRoutingBucket(src, 0)
    end
end

RegisterNetEvent('custom_dealership:endTestDrive', function(reason)
    local src = source
    local td = activeTestDrives[src]
    if not td then return end
    local ret = td.returnPos
    clearTestDrive(src)
    if ret then
        local ped = GetPlayerPed(src)
        SetEntityCoords(ped, ret.x, ret.y, ret.z, false, false, false, true)
        SetEntityHeading(ped, ret.h or 0.0)
    end
    TriggerClientEvent('custom_dealership:endTestDriveClient', src)
    if reason then
        lib.notify(src, { title = 'Test Drive', description = reason, type = 'inform' })
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    clearTestDrive(src)
end)

RegisterNetEvent('custom_dealership:startTestDrive', function(model, targetSrc)
    local src = targetSrc or source
    src = tonumber(src)
    if not src or src <= 0 then return end
    if not Config.EnableTestDrive then return end
    local now = os.time()
    if lastTestDrive[src] and now - lastTestDrive[src] < Config.TestDriveCooldown then
        return lib.notify(src, { title = 'Concessionária', description = 'Aguarda cooldown de test drive.', type = 'error' })
    end
    if Config.TestDriveWhitelist then
        local allowed = false
        for _,m in ipairs(Config.TestDriveWhitelist) do if m == model then allowed = true break end end
        if not allowed then
            return lib.notify(src, { title = 'Concessionária', description = 'Modelo não permitido em test drive.', type = 'error' })
        end
    end
    clearTestDrive(src)
    -- Guardar posição original para retorno
    local pedOrig = GetPlayerPed(src)
    local orig = GetEntityCoords(pedOrig)
    local origH = GetEntityHeading(pedOrig)
    local plate = (Config.TestDrivePlatePrefix or 'TEST') .. tostring(math.random(1111,9999))
    local ped = GetPlayerPed(src)
    local coords
    if Config.TestDriveSpawn then
        local sp = Config.TestDriveSpawn
        SetEntityCoords(ped, sp.x, sp.y, sp.z, false, false, false, true)
        SetEntityHeading(ped, sp.w)
        coords = { x = sp.x, y = sp.y, z = sp.z, w = sp.w }
    else
        local c = GetEntityCoords(ped)
        coords = { x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) }
    end
    local bucket
    if Config.TestDriveUseInstance then
        bucket = src + 9000
        SetPlayerRoutingBucket(src, bucket)
    end
    local vehHash = joaat(model)
    if not modelExists(vehHash) then
        return lib.notify(src, { title = 'Concessionária', description = 'Modelo inválido.', type = 'error' })
    end
    local netId
    local forceClient = (Config.TestDriveSpawnMode == 'client') or (not SetEntityAsMissionEntity) or (not CreateVehicle)
    if Config.TestDriveSpawnMode == 'server' and not forceClient then
        local attempts = 0
        local hash = joaat(model)
        if not modelExists(hash) then
            return lib.notify(src, { title = 'Concessionária', description = 'Modelo inválido.', type = 'error' })
        end
        safeRequestModel(hash)
        -- Not all servers support HasModelLoaded server-side; skip strict wait to avoid nil global errors
        if HasModelLoaded and not HasModelLoaded(hash) then
            local waited = 0
            while HasModelLoaded and not HasModelLoaded(hash) and waited < 2000 do
                Wait(50)
                waited = waited + 50
            end
            if HasModelLoaded and not HasModelLoaded(hash) then
            end
        end
        while attempts < 3 and not netId do
            attempts = attempts + 1
            local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w or 0.0, true, true)
            if veh and veh ~= 0 then
                safeSetPlate(veh, plate)
                safeMissionEntity(veh)
                safeOnGround(veh)
                if bucket then SetEntityRoutingBucket(veh, bucket) end
                netId = NetworkGetNetworkIdFromEntity(veh)
                -- pede ao cliente para se colocar dentro (mais confiável lado cliente)
                TriggerClientEvent('custom_dealership:warpIntoTestDrive', src, netId)
                -- dar chaves (se recurso existir)
                if giveKeys then
                    giveKeys(src, netId)
                end
                break
            else
                Wait(250)
            end
        end
        if not netId then
            return lib.notify(src, { title = 'Concessionária', description = 'Falha a criar veículo.', type = 'error' })
        end
    else
        netId = lib.callback.await('custom_dealership:spawnLocalVehicle', src, model, coords, plate)
        if not netId then
            if Config.TestDriveServerFallback then
                local veh = CreateVehicle(joaat(model), coords.x, coords.y, coords.z, coords.w or 0.0, true, true)
                if veh and veh ~= 0 then
                    safeSetPlate(veh, plate)
                    safeMissionEntity(veh)
                    safeOnGround(veh)
                    if bucket then SetEntityRoutingBucket(veh, bucket) end
                    netId = NetworkGetNetworkIdFromEntity(veh)
                else
                    return lib.notify(src, { title = 'Concessionária', description = 'Falha a criar veículo.', type = 'error' })
                end
            else
                return lib.notify(src, { title = 'Concessionária', description = 'Falha a criar veículo.', type = 'error' })
            end
        end
        -- garantir warp (cliente já faz) e chaves
        if giveKeys and netId then giveKeys(src, netId) end
    end
    -- aplicar bucket ao veículo se instanciado
    if bucket then
        local veh = NetworkGetEntityFromNetworkId(netId)
        if veh and veh ~= 0 then
            SetEntityRoutingBucket(veh, bucket)
        else
        end
    end
    activeTestDrives[src] = { netId = netId, started = now, model = model, plate = plate, origin = vector3(coords.x, coords.y, coords.z), chargedExtra = 0, bucket = bucket, returnPos = { x = orig.x, y = orig.y, z = orig.z, h = origH } }
    lastTestDrive[src] = now
    lib.notify(src, { title = 'Test Drive', description = ('%s: %d minutos incluídos'):format(model, Config.TestDriveMinutes), type = 'inform' })
    TriggerClientEvent('custom_dealership:startTestDriveTimer', src, {
        baseMinutes = Config.TestDriveMinutes,
        started = now
    })
    TriggerClientEvent('custom_dealership:testDriveInfo', src, { netId = netId, model = model, returnPos = activeTestDrives[src].returnPos })
    -- thread para billing e limite
    CreateThread(function()
        while activeTestDrives[src] do
            Wait(60000)
            local td = activeTestDrives[src]
            if not td then break end
            local elapsedMin = math.floor((os.time() - td.started) / 60)
            if elapsedMin >= Config.TestDriveMinutes then
                local extra = elapsedMin - Config.TestDriveMinutes + 1
                if extra > td.chargedExtra then
                    td.chargedExtra = extra
                    if Config.TestDriveExtraMinuteCost and Config.TestDriveExtraMinuteCost > 0 then
                        local ply = exports.qbx_core:GetPlayer(src)
                        if ply then
                            local ok = ply.Functions.RemoveMoney('bank', Config.TestDriveExtraMinuteCost, 'testdrive-extra')
                            if ok then
                                lib.notify(src, { title = 'Test Drive', description = ('$%d cobrado (minuto extra %d)'):format(Config.TestDriveExtraMinuteCost, extra), type = 'inform' })
                            else
                                lib.notify(src, { title = 'Test Drive', description = 'Sem fundos para continuar. Test drive encerrado.', type = 'error' })
                                clearTestDrive(src)
                                break
                            end
                        end
                    end
                end
                if extra >= 3 then
                    lib.notify(src, { title = 'Test Drive', description = 'Tempo máximo atingido.', type = 'warning' })
                    clearTestDrive(src)
                    break
                end
            end
        end
    end)
end)

RegisterNetEvent('custom_dealership:sellVehicle', function(data)
    local src = source
    local seller = exports.qbx_core:GetPlayer(src)
    if not seller or seller.PlayerData.job.name ~= Config.DealerJob then
        return lib.notify(src, { title = 'Concessionária', description = 'Sem permissão.', type = 'error' })
    end
    local now = os.time()
    if Config.SaleCooldown > 0 then
        if lastSale[src] and now - lastSale[src] < Config.SaleCooldown then
            return lib.notify(src, { title = 'Concessionária', description = 'Aguarda cooldown de venda.', type = 'error' })
        end
        lastSale[src] = now
    end
    local buyerId = tonumber(data.buyer)
    local model = data.model
    local price = tonumber(data.price)
    if not buyerId or not model then return end
    local vehPrice = getVehiclePrice(model)
    if not Config.AllowCustomPrice then
        price = vehPrice -- força preço base
    else
        if not price then return end
        if price < Config.MinPrice or price > Config.MaxPrice then
            return lib.notify(src, { title = 'Concessionária', description = 'Preço inválido.', type = 'error' })
        end
    end
    local buyer = exports.qbx_core:GetPlayer(buyerId)
    if not buyer then
        return lib.notify(src, { title = 'Concessionária', description = 'Comprador offline.', type = 'error' })
    end

    if Config.RequireBuyerConfirmation then
        if pendingOffers[buyerId] then
            return lib.notify(src, { title = 'Concessionária', description = 'Comprador já tem oferta pendente.', type = 'error' })
        end
        if Config.UseStock then
            local stk = getStock(model)
            if stk <= 0 and not Config.AllowNegativeStock then
                return lib.notify(src, { title = 'Concessionária', description = 'Sem stock deste modelo.', type = 'error' })
            end
        end
        pendingOffers[buyerId] = {
            seller = src,
            model = model,
            price = price,
            ts = os.time()
        }
        lib.notify(src, { title = 'Concessionária', description = 'Oferta enviada ao comprador.', type = 'inform' })
        TriggerClientEvent('custom_dealership:receiveOffer', buyerId, {
            seller = src,
            model = model,
            price = price,
            timeout = Config.OfferTimeout
        })
        SetTimeout((Config.OfferTimeout or 30) * 1000, function()
            local offer = pendingOffers[buyerId]
            if offer and offer.seller == src then
                pendingOffers[buyerId] = nil
                lib.notify(src, { title = 'Concessionária', description = 'Oferta expirada.', type = 'warning' })
                lib.notify(buyerId, { title = 'Concessionária', description = 'Oferta expirada.', type = 'warning' })
            end
        end)
        return -- wait confirmation
    end
    -- Se custom price permitido, validar limites relativos
    if Config.AllowCustomPrice then
        if price > vehPrice * 5 or price < vehPrice * 0.2 then
            return lib.notify(src, { title = 'Concessionária', description = 'Preço fora dos limites.', type = 'error' })
        end
    end
    if not buyer.Functions.RemoveMoney('bank', price, 'vehicle-purchase') then
        return lib.notify(src, { title = 'Concessionária', description = 'Comprador sem fundos.', type = 'error' })
    end
    if Config.UseStock then
        local ok = takeStock(model)
        if not ok then
            return lib.notify(src, { title = 'Concessionária', description = 'Sem stock.', type = 'error' })
        end
    end
    local vehicleId = exports.qbx_vehicles:CreatePlayerVehicle({ model = model, citizenid = buyer.PlayerData.citizenid })
    if not vehicleId then
        buyer.Functions.AddMoney('bank', price, 'refund-failed-create')
        return lib.notify(src, { title = 'Concessionária', description = 'Erro a criar veículo.', type = 'error' })
    end
    local spawn = findFreeSpawn()
    local netId = lib.callback.await('custom_dealership:spawnOwnedVehicle', buyerId, vehicleId, model, spawn)
    if not netId then
        -- rollback funds & stock
        buyer.Functions.AddMoney('bank', price, 'refund-spawn-failed')
        if Config.UseStock then
            addStock(model, 1)
        end
        MySQL.update('DELETE FROM player_vehicles WHERE id = ?', { vehicleId })
        return lib.notify(src, { title = 'Concessionária', description = 'Falha ao spawnar veículo.', type = 'error' })
    end
    giveKeys(buyerId, netId)
    local commission = math.floor(price * Config.CommissionRate)
    payCommission(src, commission)
    depositSociety(price)
    if Config.PrintSales then
        print(('^2[SALE]^7 %s vendeu %s por $%d (comissão $%d) para %s'):format(seller.PlayerData.name, model, price, commission, buyer.PlayerData.name))
    end
    lib.notify(src, { title = 'Venda', description = ('Vendido por $%d (comissão $%d)'):format(price, commission), type = 'success' })
    lib.notify(buyerId, { title = 'Concessionária', description = ('Compraste %s por $%d'):format(model, price), type = 'success' })
end)

RegisterNetEvent('custom_dealership:respondOffer', function(accept)
    local buyerId = source
    local offer = pendingOffers[buyerId]
    if not offer then
        return lib.notify(buyerId, { title = 'Concessionária', description = 'Sem oferta ativa.', type = 'error' })
    end
    local sellerSrc = offer.seller
    local seller = exports.qbx_core:GetPlayer(sellerSrc)
    local buyer = exports.qbx_core:GetPlayer(buyerId)
    if not seller or not buyer then
        pendingOffers[buyerId] = nil
        return
    end
    if not accept then
        pendingOffers[buyerId] = nil
        lib.notify(sellerSrc, { title = 'Concessionária', description = 'Oferta recusada.', type = 'error' })
        lib.notify(buyerId, { title = 'Concessionária', description = 'Recusaste a oferta.', type = 'inform' })
        return
    end
    -- Revalidate cooldown & job & funds & price
    if seller.PlayerData.job.name ~= Config.DealerJob then
        pendingOffers[buyerId] = nil
        return lib.notify(sellerSrc, { title = 'Concessionária', description = 'Sem permissão (job mudou).', type = 'error' })
    end
    local now = os.time()
    if Config.SaleCooldown > 0 then
        if lastSale[sellerSrc] and now - lastSale[sellerSrc] < Config.SaleCooldown then
            pendingOffers[buyerId] = nil
            return lib.notify(sellerSrc, { title = 'Concessionária', description = 'Cooldown de venda ativo.', type = 'error' })
        end
        lastSale[sellerSrc] = now
    end
    local model = offer.model
    local basePrice = getVehiclePrice(model)
    local price = Config.AllowCustomPrice and offer.price or basePrice
    if not Config.AllowCustomPrice then price = basePrice end
    if not buyer.Functions.RemoveMoney('bank', price, 'vehicle-purchase') then
        pendingOffers[buyerId] = nil
        return lib.notify(sellerSrc, { title = 'Concessionária', description = 'Comprador sem fundos.', type = 'error' })
    end
    if Config.UseStock then
        local ok = takeStock(model)
        if not ok then
            pendingOffers[buyerId] = nil
            return lib.notify(sellerSrc, { title = 'Concessionária', description = 'Sem stock.', type = 'error' })
        end
    end
    local vehicleId = exports.qbx_vehicles:CreatePlayerVehicle({ model = model, citizenid = buyer.PlayerData.citizenid })
    if not vehicleId then
        buyer.Functions.AddMoney('bank', price, 'refund-failed-create')
        pendingOffers[buyerId] = nil
        return lib.notify(sellerSrc, { title = 'Concessionária', description = 'Erro a criar veículo.', type = 'error' })
    end
    local spawn = findFreeSpawn()
    local netId = lib.callback.await('custom_dealership:spawnOwnedVehicle', buyerId, vehicleId, model, spawn)
    if not netId then
        buyer.Functions.AddMoney('bank', price, 'refund-spawn-failed')
        if Config.UseStock then addStock(model, 1) end
        MySQL.update('DELETE FROM player_vehicles WHERE id = ?', { vehicleId })
        pendingOffers[buyerId] = nil
        return lib.notify(sellerSrc, { title = 'Concessionária', description = 'Falha ao spawnar veículo.', type = 'error' })
    end
    giveKeys(buyerId, netId)
    local commission = math.floor(price * Config.CommissionRate)
    payCommission(sellerSrc, commission)
    depositSociety(price)
    pendingOffers[buyerId] = nil
    if Config.PrintSales then
        print(('^2[SALE]^7 %s vendeu %s por $%d (comissão $%d) para %s'):format(seller.PlayerData.name, model, price, commission, buyer.PlayerData.name))
    end
    lib.notify(sellerSrc, { title = 'Venda', description = ('Vendido por $%d (comissão $%d)'):format(price, commission), type = 'success' })
    lib.notify(buyerId, { title = 'Concessionária', description = ('Compraste %s por $%d'):format(model, price), type = 'success' })
end)

-- Periodic monitor to cleanup rogue test drives
CreateThread(function()
    while true do
        local now = os.time()
        for src, td in pairs(activeTestDrives) do
            local ply = GetPlayerPed(src)
            if not ply or ply == 0 then clearTestDrive(src) goto continue end
            local veh = NetworkGetEntityFromNetworkId(td.netId)
            if not veh or veh == 0 or not DoesEntityExist(veh) then clearTestDrive(src) goto continue end
            -- Distância desativada: se quiser reativar, defina Config.TestDriveReturnDistance > 0
            if Config.TestDriveReturnDistance and Config.TestDriveReturnDistance > 0 then
                local dist = #(GetEntityCoords(ply) - td.origin)
                if dist > Config.TestDriveReturnDistance then
                    lib.notify(src, { title = 'Test Drive', description = 'Distância excedida.', type = 'warning' })
                    clearTestDrive(src)
                end
            end
            ::continue::
        end
        Wait(5000)
    end
end)

-- Force menu open command (debug / fallback if key hint not showing)
lib.addCommand('dealership', {
    help = 'Abrir menu da concessionária (debug)'
}, function(source, args)
    local src = source
    if src == 0 then
        print('[custom_dealership] Comando não disponível na console')
        return
    end
    TriggerClientEvent('custom_dealership:openMenu', src)
end)

-- Restock command (for dealer job or server console)
lib.addCommand('restockveh', { help = 'Repor stock de um modelo: /restockveh modelo quantidade' }, function(source, args)
    local src = source
    if not Config.UseStock then return end
    local model = args[1]
    local amount = tonumber(args[2] or '0')
    if not model or not amount or amount == 0 then
        return lib.notify(src, { title = 'Concessionária', description = 'Uso: /restockveh modelo quantidade', type = 'error' })
    end
    if src ~= 0 then
        local ply = exports.qbx_core:GetPlayer(src)
        if not ply or ply.PlayerData.job.name ~= Config.DealerJob then
            return lib.notify(src, { title = 'Concessionária', description = 'Sem permissão.', type = 'error' })
        end
    end
    local newVal = addStock(model, amount)
    if src == 0 then
        print(('[restockveh] %s => %d'):format(model, newVal))
    else
        lib.notify(src, { title = 'Concessionária', description = ('Stock %s = %d'):format(model, newVal), type = 'success' })
    end
end)

-- Restock all models to a fixed value
lib.addCommand('restockall', { help = 'Definir stock de TODOS os modelos: /restockall quantidade' }, function(source, args)
    if not Config.UseStock then return end
    local src = source
    local amount = tonumber(args[1] or '0')
    if not amount or amount < 0 then
        return lib.notify(src, { title = 'Concessionária', description = 'Quantidade inválida.', type = 'error' })
    end
    if src ~= 0 then
        local ply = exports.qbx_core:GetPlayer(src)
        if not ply or ply.PlayerData.job.name ~= Config.DealerJob then
            return lib.notify(src, { title = 'Concessionária', description = 'Sem permissão.', type = 'error' })
        end
    end
    local vehs = getVehicles()
    for model, _ in pairs(vehs) do
        stockCache[model] = amount
        MySQL.update('INSERT INTO dealer_stock (model, stock) VALUES (?, ?) ON DUPLICATE KEY UPDATE stock = VALUES(stock)', { model, amount })
    end
    if src == 0 then
        print(('[restockall] todos = %d'):format(amount))
    else
        lib.notify(src, { title = 'Concessionária', description = ('Todos os modelos agora têm %d de stock'):format(amount), type = 'success' })
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    ensureStockTable()
    loadStock()
end)

-- Diagnostic command to force a test drive without menu
lib.addCommand('cd_td', { help = '/cd_td [modelo] - iniciar test drive forçado' }, function(source, args)
    local src = source
    if src == 0 then print('Use in-game') return end
    local model = args[1] or 'sultan'
    TriggerEvent('custom_dealership:startTestDrive', model, src)
end)
