SAMData = {}
local D = SAMData
function D.call(object, name, ...)
    if not object or type(object[name]) ~= "function" then
        return nil
    end
    return object[name](object, ...)
end
function D.uid(p)
    local id = D.call(p, "getUniqueId") or p.uniqueId
    if id then
        return tostring(id)
    end
    -- Stable fallback for map placeables lacking a saved unique ID.
    if p.rootNode and getWorldTranslation then
        local x, y, z = getWorldTranslation(p.rootNode)
        return tostring(p.configFileName or p.xmlFilename or "") .. string.format("@%.2f,%.2f", x, z)
    end
end
function D.types(s)
    local out = {}
    for _, name in ipairs({ "fillLevels", "capacities" }) do
        for ft in pairs(type(s[name]) == "table" and s[name] or {}) do
            if type(ft) == "number" and g_fillTypeManager:getFillTypeByIndex(ft) then
                out[ft] = true
            end
        end
    end
    for key, value in pairs(s.supportedFillTypes or {}) do
        local ft = type(value) == "number" and value or key
        if type(ft) == "number" and g_fillTypeManager:getFillTypeByIndex(ft) then
            out[ft] = true
        end
    end
    return out
end
function D.capacity(s, ft)
    local cap = type(s.capacities) == "table" and s.capacities[ft] or nil
    if cap == nil then
        cap = D.call(s, "getCapacity", ft)
    end
    if (type(cap) ~= "number" or cap <= 0) and type(s.capacity) == "number" then
        cap = s.capacity
    end
    if type(cap) ~= "number" or cap <= 0 or cap >= math.huge then
        return nil
    end
    return cap
end
function D.level(s, ft)
    if type(s.fillLevels) == "table" then
        return s.fillLevels[ft] or 0
    end
    return D.call(s, "getFillLevel", ft)
end
function D.valid(value)
    return type(value) == "number" and value == value and value >= 0 and value < math.huge
end
function D.finish(row, held, capacity)
    row.held = D.valid(held) and held or nil
    row.capacity = D.valid(capacity) and capacity > 0 and capacity or nil
    row.pct = row.held and row.capacity and 100 * row.held / row.capacity or nil
    return row
end
function D.row(asset, id, ft, title, direction, read)
    local desc = ft and g_fillTypeManager:getFillTypeByIndex(ft)
    local row = {
        asset = asset,
        key = asset.key .. "|" .. id,
        ft = ft,
        title = title and StorageAlertMonitor:label(title) or desc and desc.title or id,
        icon = desc and desc.hudOverlayFilename,
        direction = StorageAlertMonitor:label(direction or "Storage"),
        read = read,
    }
    local held, cap = read()
    D.finish(row, held, cap)
    return row
end
function D.storageRows(asset, storage, rows, prefix)
    for ft in pairs(D.types(storage)) do
        local desc = g_fillTypeManager:getFillTypeByIndex(ft)
        rows[#rows + 1] = D.row(asset, prefix .. desc.name, ft, nil, "Storage", function()
            return D.level(storage, ft), D.capacity(storage, ft)
        end)
    end
end
function D.productionRows(asset, rows)
    local pp = asset.production
    local storage = pp.storage
    if not storage then
        return
    end
    local types = D.types(storage)
    local inputs, outputs = {}, {}
    for _, production in pairs(pp.productions or {}) do
        for _, item in pairs(production.inputs or {}) do
            if item.type then
                inputs[item.type] = true
                types[item.type] = true
            end
        end
        for _, item in pairs(production.outputs or {}) do
            if item.type then
                outputs[item.type] = true
                types[item.type] = true
            end
        end
    end
    for ft in pairs(types) do
        local desc = g_fillTypeManager:getFillTypeByIndex(ft)
        if desc then
            local direction = inputs[ft] and outputs[ft] and "Input / output"
                or inputs[ft] and "Input"
                or outputs[ft] and "Output"
                or "Storage"
            rows[#rows + 1] = D.row(asset, desc.name, ft, nil, direction, function()
                return D.level(storage, ft), D.capacity(storage, ft)
            end)
        end
    end
end
function D.foodEffectiveness(food)
    local system = g_currentMission and g_currentMission.animalFoodSystem
    local definition = D.call(system, "getAnimalFood", food.animalTypeIndex)
    if not definition or not definition.groups or not food.fillLevels then
        return nil
    end
    local constants = AnimalFoodSystem or {}
    local mode = definition.consumptionType
    local serial = mode == "SERIAL"
        or (constants.FOOD_CONSUME_TYPE_SERIAL ~= nil and mode == constants.FOOD_CONSUME_TYPE_SERIAL)
    local parallel = mode == "PARALLEL"
        or (constants.FOOD_CONSUME_TYPE_PARALLEL ~= nil and mode == constants.FOOD_CONSUME_TYPE_PARALLEL)
    if not serial and not parallel then
        return nil
    end
    local factor = 0
    for _, group in ipairs(definition.groups) do
        local available = false
        for _, ft in pairs(group.fillTypes or {}) do
            if (food.fillLevels[ft] or 0) > 0 then
                available = true
                break
            end
        end
        if available then
            local weight = group.productionWeight or 0
            if serial then
                factor = math.max(factor, weight)
            else
                factor = factor + weight
            end
        end
    end
    return math.min(1, factor) * 100
end
function D.husbandryRows(asset, rows)
    local p = asset.placeable
    local food = p.spec_husbandryFood
    if p.getGlobalProductionFactor or (p.spec_husbandry and p.spec_husbandry.globalProductionFactor ~= nil) then
        local effectiveness = D.row(asset, "productivity", nil, "Productivity", "Animal production", function()
            local factor = D.call(p, "getGlobalProductionFactor")
            if factor == nil then
                factor = p.spec_husbandry.globalProductionFactor
            end
            if not D.valid(factor) then
                return nil, nil
            end
            return factor * 100, 100
        end)
        effectiveness.unit = "percent"
        effectiveness.icon = StorageAlertMonitor and StorageAlertMonitor.modDir .. "icon_StorageAlertMonitor.dds"
        rows[#rows + 1] = effectiveness
    end
    if food then
        -- Per-product amounts share the feed pool; add a total-food monitor too.
        for ft in pairs(D.types(food)) do
            local desc = g_fillTypeManager:getFillTypeByIndex(ft)
            rows[#rows + 1] = D.row(asset, "food:" .. desc.name, ft, nil, "Feed (shared)", function()
                return type(food.fillLevels) == "table" and (food.fillLevels[ft] or 0) or nil,
                    food.capacity or D.call(p, "getFoodCapacity")
            end)
        end
        local quality = D.row(
            asset,
            "food:effectiveness",
            nil,
            "Total Capacity (effectiveness)",
            "Feed effectiveness",
            function()
                return D.foodEffectiveness(food), 100
            end
        )
        quality.unit = "percent"
        quality.metric = StorageAlertMonitor:tr("metricFeed")
        quality.icon = StorageAlertMonitor and StorageAlertMonitor.modDir .. "icon_StorageAlertMonitor.dds"
        rows[#rows + 1] = quality
        rows[#rows + 1] = D.row(asset, "food:total", nil, "Food", "Shared feed pool", function()
            local held = D.call(p, "getTotalFood")
            if held == nil and type(food.fillLevels) == "table" then
                held = 0
                for _, v in pairs(food.fillLevels) do
                    held = held + v
                end
            end
            return held, food.capacity or D.call(p, "getFoodCapacity")
        end)
    end
    for _, name in ipairs({ "Water", "Straw", "Milk", "LiquidManure", "Manure" }) do
        local spec = p["spec_husbandry" .. name]
        if spec and not (name == "Water" and spec.automaticWaterSupply) then
            local fillTypes = {}
            local single = spec.inputFillType or spec.fillType or spec.fillTypeIndex
            if single then
                fillTypes[single] = true
            end
            for _, ft in ipairs(spec.fillTypes or {}) do
                fillTypes[ft] = true
            end
            for ft in pairs(fillTypes) do
                if ft and g_fillTypeManager:getFillTypeByIndex(ft) then
                    local desc = g_fillTypeManager:getFillTypeByIndex(ft)
                    rows[#rows + 1] = D.row(
                        asset,
                        "husbandry:" .. desc.name,
                        ft,
                        nil,
                        (name == "Water" or name == "Straw") and "Input" or "Output",
                        function()
                            return D.call(p, "getHusbandryFillLevel", ft),
                                D.call(p, "getHusbandryCapacity", ft) or spec.capacity
                        end
                    )
                end
            end
        end
    end
    local ps = p.spec_husbandryPallets
    if ps then
        for _, ft in ipairs(ps.fillTypes or {}) do
            local desc = g_fillTypeManager:getFillTypeByIndex(ft)
            if desc then
                rows[#rows + 1] = D.row(asset, "pallet:" .. desc.name, ft, nil, "Output buffer", function()
                    return D.call(p, "getHusbandryFillLevel", ft),
                        type(ps.capacities) == "table" and ps.capacities[ft] or D.call(p, "getHusbandryCapacity", ft)
                end)
            end
        end
    end
    local robot = p.spec_husbandryFeedingRobot and p.spec_husbandryFeedingRobot.feedingRobot
    if robot then
        for ft, spot in pairs(robot.fillTypeToUnloadingSpot or {}) do
            local desc = g_fillTypeManager:getFillTypeByIndex(ft)
            if desc then
                rows[#rows + 1] = D.row(asset, "robot:" .. desc.name, ft, nil, "Robot bunker", function()
                    return D.call(robot, "getFillLevel", ft) or spot.fillLevel, spot.capacity
                end)
            end
        end
    end
    if p.getNumOfAnimals and p.getMaxNumOfAnimals then
        rows[#rows + 1] = D.row(asset, "animals", nil, "Animals", "Occupancy", function()
            return p:getNumOfAnimals(), p:getMaxNumOfAnimals()
        end)
    end
end
function D.productionPoint(placeable)
    local standard = placeable.spec_productionPoint
    if standard and standard.productionPoint then
        return standard.productionPoint
    end
    -- Custom production specializations use namespaced spec_* fields.
    for key, spec in pairs(placeable) do
        if
            type(key) == "string"
            and key:sub(1, 5) == "spec_"
            and type(spec) == "table"
            and type(spec.productionPoint) == "table"
        then
            return spec.productionPoint
        end
    end
end
function D.enumerate(farm)
    local assets = {}
    local placeables = g_currentMission.placeableSystem and g_currentMission.placeableSystem.placeables or {}
    for _, p in pairs(placeables) do
        local owner = D.call(p, "getOwnerFarmId") or p.ownerFarmId
        if owner == farm and farm > 0 then
            local uid = D.uid(p)
            if uid then
                local name = D.call(p, "getName") or p.name or StorageAlertMonitor:tr("storage")
                local function add(role, extra)
                    local a = { placeable = p, role = role, name = name, key = uid .. "|" .. role }
                    if extra then
                        for k, v in pairs(extra) do
                            a[k] = v
                        end
                    end
                    assets[#assets + 1] = a
                end
                local pp = D.productionPoint(p)
                if pp then
                    add("Production", { production = pp })
                end
                if p.spec_husbandry then
                    add("Husbandry")
                end
                -- Generic/native/modded Storage objects, including namespaced specs.
                local seen = {}
                if pp and pp.storage then
                    seen[pp.storage] = true
                end
                local storages = {}
                local function collect(s)
                    if type(s) == "table" and not seen[s] and (s.getFillLevel or s.fillLevels) then
                        local sfarm = D.call(s, "getOwnerFarmId") or s.ownerFarmId
                        if
                            not (p.spec_silo and p.spec_silo.storagePerFarm)
                            or not sfarm
                            or sfarm == 0
                            or sfarm == farm
                        then
                            seen[s] = true
                            storages[#storages + 1] = s
                        end
                    end
                end
                for key, spec in pairs(p) do
                    if
                        type(key) == "string"
                        and key:sub(1, 5) == "spec_"
                        and type(spec) == "table"
                        and not (p.spec_husbandry and key:sub(1, 14) == "spec_husbandry")
                    then
                        collect(spec.storage)
                        for _, s in pairs(spec.storages or {}) do
                            collect(s)
                        end
                    end
                end
                if #storages > 0 then
                    add("Storage", { storages = storages })
                end
                if p.spec_objectStorage then
                    add("Pallet storage", { objectStorage = p.spec_objectStorage })
                end
            end
        end
    end
    table.sort(assets, function(a, b)
        if a.name == b.name then
            if a.role == "Production" and b.role ~= "Production" then
                return true
            end
            if b.role == "Production" and a.role ~= "Production" then
                return false
            end
            return a.role < b.role
        end
        return a.name < b.name
    end)
    return assets
end
function D.products(asset)
    local rows = {}
    if asset.production then
        D.productionRows(asset, rows)
    elseif asset.role == "Husbandry" then
        D.husbandryRows(asset, rows)
    elseif asset.storages then
        -- Aggregate declared tanks for a building; repeated references are deduplicated at discovery.
        local types = {}
        for _, s in ipairs(asset.storages) do
            for ft in pairs(D.types(s)) do
                types[ft] = true
            end
        end
        for ft in pairs(types) do
            local desc = g_fillTypeManager:getFillTypeByIndex(ft)
            rows[#rows + 1] = D.row(asset, desc.name, ft, nil, "Storage", function()
                local held, cap = 0, 0
                for _, s in ipairs(asset.storages) do
                    if D.types(s)[ft] then
                        local lv, c = D.level(s, ft), D.capacity(s, ft)
                        if not D.valid(lv) or not D.valid(c) then
                            return nil, nil
                        end
                        held = held + lv
                        cap = cap + c
                    end
                end
                return held, cap
            end)
        end
    elseif asset.objectStorage then
        local spec = asset.objectStorage
        rows[#rows + 1] = D.row(asset, "slots", nil, "Pallet / bale slots", "Shared occupancy", function()
            return spec.numStoredObjects or type(spec.storedObjects) == "table" and #spec.storedObjects,
                spec.capacity or spec.maxNumObjects
        end)
        -- Product quantities have no fixed litre capacity when the shed stores mixed pallet sizes.
        -- Show the actual quantity, but do not invent a percentage denominator.
        local amounts = {}
        local function attributes(object)
            if type(object) ~= "table" then
                return nil
            end
            for _, a in pairs(object) do
                if type(a) == "table" and type(a.fillType) == "number" and type(a.fillLevel) == "number" then
                    return a
                end
            end
            if type(object.fillType) == "number" and type(object.fillLevel) == "number" then
                return object
            end
        end
        local infos = spec.objectInfos or {}
        for _, info in pairs(infos) do
            if type(info.objects) == "table" and #info.objects > 0 then
                -- Clients retain one representative object per group, plus its count.
                local multiplier = #info.objects == 1 and (info.numObjects or 1) or 1
                for _, object in ipairs(info.objects) do
                    local a = attributes(object)
                    if a then
                        amounts[a.fillType] = (amounts[a.fillType] or 0) + a.fillLevel * multiplier
                    end
                end
            else
                local a = attributes(info)
                if a then
                    amounts[a.fillType] = (amounts[a.fillType] or 0) + a.fillLevel * (info.numObjects or 1)
                end
            end
        end
        if next(amounts) == nil then
            for _, object in ipairs(spec.storedObjects or {}) do
                local a = attributes(object)
                if a then
                    amounts[a.fillType] = (amounts[a.fillType] or 0) + a.fillLevel
                end
            end
        end
        for ft, amount in pairs(amounts) do
            local desc = g_fillTypeManager:getFillTypeByIndex(ft)
            if desc then
                rows[#rows + 1] = D.row(asset, desc.name, ft, nil, "Stored product", function()
                    return amount, nil
                end)
            end
        end
    end
    table.sort(rows, function(a, b)
        return a.title < b.title
    end)
    return rows
end
