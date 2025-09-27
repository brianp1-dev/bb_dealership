Config = {}

-- Job required to sell vehicles
Config.DealerJob = 'cardealer'

-- Commission percent (e.g. 0.1 = 10%) paid to seller (bank)
Config.CommissionRate = 0.10

-- Society account name (Renewed-Banking) to receive full vehicle price (before commission)
Config.SocietyAccount = 'cardealer'
Config.EnableSociety = true

-- Allow ANY player to browse & test drive
Config.PublicBrowse = true
Config.EnableTestDrive = true
Config.TestDriveMinutes = 2        -- base included minutes per test drive
Config.TestDriveExtraMinuteCost = 100 -- amount charged per minute beyond base
Config.TestDriveSpawn = vec4(-18.83, -1112.05, 25.67, 163.95) -- forced spawn/teleport for test drive
Config.TestDriveUseInstance = true  -- put player & vehicle in separate routing bucket during test drive
Config.TestDriveServerFallback = true -- if client callback spawn fails, try spawn server-side and set entity owner
-- Spawn mode for test drive: 'client' (callback to client) | 'server' (server creates vehicle). 'server' is more robust.
Config.TestDriveSpawnMode = 'server'
Config.TestDrivePlatePrefix = 'TEST'
-- Distância máxima antes de terminar test drive. Defina 0 ou nil para desativar limite.
Config.TestDriveReturnDistance = 0
Config.TestDriveCooldown = 120      -- seconds between test drives per player

-- Distance / zones
Config.ShowroomCenter = vec3(-56.80, -1096.60, 26.42)
Config.ShowroomRadius = 45.0
Config.InteractDistance = 2.5

-- Specific ponto de interação principal (para abrir menu com E)
Config.InteractPoint = vec3(-32.22, -1114.5, 25.42)
Config.InteractRadius = 3.5

-- Permitir /dealership em qualquer lugar?
Config.AllowCommandAnywhere = false

-- Vehicle spawn points for purchased vehicles
Config.SpawnPoints = {
    vec4(-45.64, -1094.92, 26.0, 71.0),
    vec4(-47.90, -1096.44, 26.0, 71.0),
    vec4(-50.47, -1097.72, 26.0, 71.0),
}

-- Local fixo de entrega (se definido ignora SpawnPoints)
Config.DeliveryPoint = vec4(-16.6, -1085.73, 25.67, 68.26)

-- Showroom static display vehicles (rotating models player can inspect)
Config.ShowroomVehicles = {
    { model = 'asbo',  coords = vec4(-45.65, -1093.66, 25.44, 69.5) },
}

-- Client-only marker over showroom vehicles (instead of a map blip). If true, draws a small 3D marker & floating label.
Config.ShowroomLocalMarker = true
Config.ShowroomMarkerColor = { r = 0, g = 170, b = 255, a = 150 }
Config.ShowroomMarkerType = 36 -- 1 = cylinder, 36 = vertical car icon style marker
Config.ShowroomMarkerScale = vec3(0.5, 0.5, 0.5)
Config.ShowroomLabelOffset = 1.0

-- Fallback price if vehicle not found (avoid exploit spam)
Config.FallbackPrice = 50000

-- Minimum & maximum price limits enforced (sanity)
Config.MinPrice = 1000
Config.MaxPrice = 5000000

-- Permitir que vendedor defina preço manual? (false = usa preço base do veículo)
Config.AllowCustomPrice = false

-- Confirmação do comprador antes de concluir venda
Config.RequireBuyerConfirmation = true
Config.OfferTimeout = 30 -- segundos para aceitar/recusar

-- Sistema de stock (inventário de cada modelo)
Config.UseStock = true
Config.DefaultStock = 10              -- stock inicial se não especificado
Config.StockPerVehicle = {            -- sobrescrever específicos (model = quantidade)
    -- ex: sultan = 5,
}
Config.AllowNegativeStock = false     -- se true, deixa vender mesmo em zero (apenas decrementa)

-- Cooldown between seller sales (seconds)
Config.SaleCooldown = 0

-- Use ox_target for showroom entity interactions
Config.UseTarget = true

-- Logging
Config.Debug = false
Config.PrintSales = true

-- Group menu by brand (shows lista de marcas primeiro)
Config.GroupByBrand = true

-- Mostrar marker visual no chão (independente do Debug)
Config.ShowMarker = false

-- Optional: restrict test drive to list (nil = any from shared vehicles list)
Config.TestDriveWhitelist = nil -- { 'sultan', 'adder' }

-- Export providing vehicles (qbx_vehicles style). Fallback onto qbcore vehicles if absent
Config.VehicleExport = function()
    if exports.qbx_core and exports.qbx_core.GetVehiclesByName then
        return exports.qbx_core:GetVehiclesByName()
    end
    return {}
end
