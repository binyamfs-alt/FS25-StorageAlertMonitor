StorageAlertMonitor = { modDir = g_currentModDirectory, modName = g_currentModName }
local M = StorageAlertMonitor
function M:tr(key, ...)
    local value = g_i18n:getText("sam_" .. key, self.modName)
    if select("#", ...) > 0 then
        return string.format(value, ...)
    end
    return value
end

local labelKeys = {
    ["Storage"] = "storage",
    ["Input / output"] = "inputOutput",
    ["Input"] = "input",
    ["Output"] = "output",
    ["Productivity"] = "productivity",
    ["Animal production"] = "animalProduction",
    ["Feed (shared)"] = "feedShared",
    ["Total Capacity (effectiveness)"] = "totalEffectiveness",
    ["Feed effectiveness"] = "feedEffectiveness",
    ["Food"] = "food",
    ["Shared feed pool"] = "sharedFeedPool",
    ["Output buffer"] = "outputBuffer",
    ["Robot bunker"] = "robotBunker",
    ["Animals"] = "animals",
    ["Occupancy"] = "occupancy",
    ["Production"] = "production",
    ["Husbandry"] = "husbandry",
    ["Pallet storage"] = "palletStorage",
    ["Pallet / bale slots"] = "slots",
    ["Shared occupancy"] = "sharedOccupancy",
    ["Stored product"] = "storedProduct",
}
function M:label(value)
    local key = labelKeys[value]
    return key and self:tr(key) or value
end

source(M.modDir .. "Data.lua")
source(M.modDir .. "gui/MonitorPage.lua")

function M:warn(key, err)
    if not self.warnings[key] then
        self.warnings[key] = true
        Logging.warning("[StorageAlertMonitor] %s: %s", key, tostring(err))
    end
end
function M:loadMap()
    self.rules, self.assets, self.alerts, self.icons, self.warnings = {}, {}, {}, {}, {}
    self.x, self.y, self.width, self.maxRows, self.hudEnabled = 0.648, 0.033, 0.157, 10, true
    self.elapsed, self.catalogElapsed, self.pageElapsed, self.scrollElapsed = 5000, 15000, 0, 0
    self.farmId, self.pageNumber, self.enabled = nil, 1, true
    self.scopeId, self.settingsPath, self.editHud, self.dragging, self.menuFailed = nil, nil, false, false, false
    self.background = Overlay.new(self.modDir .. "gui/white.dds", 0, 0, 1, 1)
    self.actionEvents = {}
    self.hudVehicle, self.hudWalking, self.lastHudVehicle = true, false, nil
    addConsoleCommand("samDump", "List current Storage Alert Monitor readings", "consoleDump", self)
end
function M:scope()
    local mission = g_currentMission
    local farm = mission:getFarmId() or 0
    local info = mission.missionInfo or {}
    local id = info.savegameDirectory
        or info.mapId
        or mission.missionDynamicInfo and mission.missionDynamicInfo.mapId
        or "farm"
    -- Distinguish saves and farms without relying on renameable building labels.
    local hash = 7
    for i = 1, #tostring(id) do
        hash = (hash * 31 + tostring(id):byte(i)) % 2147483647
    end
    return farm, tostring(hash) .. "_" .. tostring(farm)
end
function M:loadPreferences()
    local farm, scope = self:scope()
    if self.farmId == farm and self.scopeId == scope then
        return
    end
    if self.farmId ~= nil then
        self:savePreferences()
    end
    self.farmId, self.scopeId = farm, scope
    self.rules, self.alerts = {}, {}
    local dir = getUserProfileAppPath() .. "modSettings/StorageAlertMonitor/"
    createFolder(dir)
    self.settingsPath = dir .. scope .. ".xml"
    self.x, self.y, self.width, self.maxRows, self.hudEnabled = 0.648, 0.033, 0.157, 10, true
    self.hudVehicle, self.hudWalking, self.lastHudVehicle = true, false, nil
    self:syncHudContext()
    if not fileExists(self.settingsPath) then
        return
    end
    local xml = loadXMLFile("samSettings", self.settingsPath)
    if xml == nil or xml == 0 then
        return
    end
    self.x = math.max(0, math.min(0.82, getXMLFloat(xml, "storageAlertMonitor.hud#x") or self.x))
    self.y = math.max(0, math.min(0.65, getXMLFloat(xml, "storageAlertMonitor.hud#y") or self.y))
    if math.abs(self.x - 0.635) < 0.00001 and math.abs(self.y - 0.033) < 0.00001 then
        self.x, self.y = 0.648, 0.033
    end
    if math.abs(self.x - 0.615) < 0.00001 and math.abs(self.y - 0.018) < 0.00001 then
        self.x, self.y = 0.648, 0.033
    end
    if
        (math.abs(self.x - 0.66) < 0.00001 and math.abs(self.y - 0.055) < 0.00001)
        or (math.abs(self.x - 0.64) < 0.00001 and math.abs(self.y - 0.035) < 0.00001)
    then
        self.x, self.y = 0.648, 0.033
    end
    if math.abs(self.x - 0.630) < 0.00001 and math.abs(self.y - 0.033) < 0.00001 then
        self.x, self.y = 0.648, 0.033
    end
    self.maxRows = math.max(1, math.min(10, getXMLInt(xml, "storageAlertMonitor.hud#rows") or 10))
    if (getXMLInt(xml, "storageAlertMonitor#version") or 1) < 2 then
        self.maxRows = 10
    end
    self:syncHudContext()
    local i = 0
    while hasXMLProperty(xml, "storageAlertMonitor.rule(" .. i .. ")") do
        local k = "storageAlertMonitor.rule(" .. i .. ")"
        local key = getXMLString(xml, k .. "#key")
        if key then
            key = key:gsub("|effectiveness$", "|food:effectiveness")
            if (getXMLInt(xml, "storageAlertMonitor#version") or 1) < 3 then
                key = key:gsub("|food:total$", "|food:effectiveness")
            end
            local mode = getXMLString(xml, k .. "#mode")
            local threshold = getXMLFloat(xml, k .. "#threshold")
            if (mode == "low" or mode == "high") and threshold then
                self.rules[key] = { mode = mode, threshold = math.max(0, math.min(100, threshold)) }
            end
        end
        i = i + 1
    end
    delete(xml)
end
function M:savePreferences()
    if not self.settingsPath then
        return
    end
    local xml = createXMLFile("samSettings", self.settingsPath, "storageAlertMonitor")
    if xml == nil or xml == 0 then
        return
    end
    setXMLInt(xml, "storageAlertMonitor#version", 3)
    setXMLFloat(xml, "storageAlertMonitor.hud#x", self.x)
    setXMLFloat(xml, "storageAlertMonitor.hud#y", self.y)
    setXMLInt(xml, "storageAlertMonitor.hud#rows", self.maxRows)
    local keys = {}
    for key in pairs(self.rules) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for i, key in ipairs(keys) do
        local r = self.rules[key]
        local k = "storageAlertMonitor.rule(" .. (i - 1) .. ")"
        setXMLString(xml, k .. "#key", key)
        setXMLString(xml, k .. "#mode", r.mode)
        setXMLFloat(xml, k .. "#threshold", r.threshold)
    end
    saveXMLFile(xml)
    delete(xml)
end
function M:scanAssets()
    self.assets = SAMData.enumerate(self.farmId or 0)
end
function M:products(asset)
    return SAMData.products(asset)
end
function M.isTriggered(rule, pct)
    if not rule or type(pct) ~= "number" or pct ~= pct then
        return false
    end
    return rule.mode == "low" and pct <= rule.threshold or rule.mode == "high" and pct >= rule.threshold
end
function M:refreshAlerts()
    local alerts = {}
    for _, a in ipairs(self.assets) do
        -- Resolve products only for buildings with a selected monitor.
        local prefix = a.key .. "|"
        local watched = false
        for key in pairs(self.rules) do
            if key:sub(1, #prefix) == prefix then
                watched = true
                break
            end
        end
        if watched then
            for _, row in ipairs(self:products(a)) do
                local rule = self.rules[row.key]
                if M.isTriggered(rule, row.pct) then
                    row.rule = rule
                    alerts[#alerts + 1] = row
                end
            end
        end
    end
    table.sort(alerts, function(a, b)
        if a.rule.mode ~= b.rule.mode then
            return a.rule.mode == "low"
        end
        if a.asset.name ~= b.asset.name then
            return a.asset.name < b.asset.name
        end
        return a.title < b.title
    end)
    self.alerts = alerts
    local pages = math.max(1, math.ceil(#alerts / self.maxRows))
    self.pageNumber = math.min(self.pageNumber, pages)
end
function M:setRule(row, mode, threshold)
    if not row then
        return
    end
    if mode == "off" then
        self.rules[row.key] = nil
    elseif row.capacity then
        self.rules[row.key] = { mode = mode, threshold = math.max(0, math.min(100, threshold)) }
    end
    self:savePreferences()
    self:refreshAlerts()
end
function M:update(dt)
    if not self.enabled or g_dedicatedServer then
        return
    end
    self:loadPreferences()
    self:syncHudContext()
    if not self.page and not self.menuFailed then
        self:setupPage()
    end
    self.elapsed = self.elapsed + dt
    self.catalogElapsed = self.catalogElapsed + dt
    if self.catalogElapsed >= 15000 then
        self.catalogElapsed = 0
        self:scanAssets()
    end
    if self.elapsed >= 5000 then
        self.elapsed = 0
        self:refreshAlerts()
        if self.page and self.page.monitorOpen then
            self.page:refresh(false)
        end
    end
    self.scrollElapsed = self.scrollElapsed + dt
    if self.scrollElapsed >= 8000 and not self.editHud then
        self.scrollElapsed = 0
        self.pageNumber = self.pageNumber % math.max(1, math.ceil(#self.alerts / self.maxRows)) + 1
    end
end
function M:fit(text, size, width)
    if getTextWidth(size, text) <= width then
        return text
    end
    -- Remove complete UTF-8 characters, preserving localized product names.
    while #text > 0 and getTextWidth(size, text .. "...") > width do
        text = text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
    end
    return text .. "..."
end
function M:box(x, y, w, h, r, g, b, a)
    self.background:setPosition(x, y)
    self.background:setDimension(w, h)
    self.background:setColor(r, g, b, a)
    self.background:render()
end
function M:inVehicle()
    return g_localPlayer ~= nil and g_localPlayer:getIsInVehicle() == true
end
function M:syncHudContext()
    local inVehicle = self:inVehicle()
    if self.lastHudVehicle ~= inVehicle then
        self.lastHudVehicle = inVehicle
    end
    if inVehicle then
        self.hudEnabled = self.hudVehicle ~= false
    else
        self.hudEnabled = self.hudWalking == true
    end
end
function M:setHudEnabled(value)
    if self:inVehicle() then
        self.hudVehicle = value
    else
        self.hudWalking = value
    end
    self:syncHudContext()
end
function M:toggleHud()
    self:syncHudContext()
    self:setHudEnabled(not self.hudEnabled)
    self:savePreferences()
end
function M:adjustRows(delta)
    self.maxRows = math.max(1, math.min(10, self.maxRows + delta))
    self.pageNumber = 1
    self:savePreferences()
end
function M:inputAction(action)
    if not self.enabled or (g_gui and g_gui:getIsGuiVisible()) then
        return
    end
    if action == InputAction.SAM_TOGGLE_HUD then
        self:toggleHud()
    elseif action == InputAction.SAM_MOUSE_TOGGLE then
        if self.editHud then
            self:stopMove()
        else
            self:startMove()
        end
    elseif action == InputAction.SAM_MORE_ROWS then
        self:adjustRows(1)
    elseif action == InputAction.SAM_FEWER_ROWS then
        self:adjustRows(-1)
    end
end
function M:hudVisible()
    return self.enabled
        and self.hudEnabled
        and not g_dedicatedServer
        and g_currentMission
        and not (g_gui and g_gui:getIsGuiVisible())
        and (#self.alerts > 0 or self.editHud)
end
function M:draw()
    if not self:hudVisible() then
        return
    end
    local x, y, w = self.x, self.y, self.width
    local count = math.min(self.maxRows, math.max(0, #self.alerts - (self.pageNumber - 1) * self.maxRows))
    local rowH = 0.042
    local headerH = 0.017
    local h = headerH + math.max(1, count) * rowH
    y = math.min(y, 1 - h - 0.01)
    self.drawY, self.drawH = y, h
    self:box(x, y, w, h, 0, 0, 0, 0.67)
    self:box(x, y + h - headerH, w, headerH, 0, 0, 0, 0.67)
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(true)
    setTextColor(0.9, 0.97, 0.9, 1)
    local pages = math.max(1, math.ceil(#self.alerts / self.maxRows))
    renderText(
        x + 0.006,
        y + h - 0.012,
        0.010,
        self:tr("hudTitle") .. (pages > 1 and " " .. self.pageNumber .. "/" .. pages or "")
    )
    setTextBold(false)
    if count == 0 then
        setTextColor(0.8, 0.8, 0.8, 1)
        renderText(x + 0.006, y + 0.018, 0.011, self:fit(self:tr("dragHint"), 0.011, w - 0.012))
    end
    for i = 1, count do
        local row = self.alerts[(self.pageNumber - 1) * self.maxRows + i]
        if row then
            local ry = y + h - headerH - i * rowH
            local iw = 0.021 * (g_screenHeight / g_screenWidth)
            if row.icon then
                if not self.icons[row.icon] then
                    self.icons[row.icon] = Overlay.new(row.icon, 0, 0, iw, 0.021)
                end
                local icon = self.icons[row.icon]
                icon:setPosition(x + 0.005, ry + 0.010)
                icon:render()
            end
            local tx = x + iw + 0.01
            setTextColor(1, 1, 1, 1)
            renderText(tx, ry + 0.024, 0.011, self:fit(row.title, 0.011, w - iw - 0.046))
            setTextColor(0.76, 0.79, 0.76, 1)
            renderText(tx, ry + 0.009, 0.010, self:fit(row.asset.name, 0.010, w - iw - 0.016))
            setTextAlignment(RenderText.ALIGN_RIGHT)
            if row.rule.mode == "low" then
                setTextColor(1, 0.48, 0.28, 1)
            else
                setTextColor(1, 0.82, 0.22, 1)
            end
            renderText(x + w - 0.005, ry + 0.024, 0.012, string.format("%.0f%%", row.pct))
            setTextAlignment(RenderText.ALIGN_LEFT)
        end
    end
    setTextColor(1, 1, 1, 1)
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end
function M:startMove()
    if self.editHud then
        return
    end
    self:setHudEnabled(true)
    self.editHud = true
    self:savePreferences()
    self.previousCursor = g_inputBinding:getShowMouseCursor()
    g_inputBinding:setShowMouseCursor(true)
end
function M:stopMove()
    if not self.editHud then
        return
    end
    self.editHud, self.dragging = false, false
    g_inputBinding:setShowMouseCursor(self.previousCursor or false)
    self:savePreferences()
end
function M:mouseEvent(posX, posY, isDown, isUp, button)
    if not self.editHud or not self:hudVisible() then
        return
    end
    local left = Input.MOUSE_BUTTON_LEFT or 1
    if isDown and button == left then
        local y, h = self.drawY or self.y, self.drawH or 0.072
        if posX >= self.x and posX <= self.x + self.width and posY >= y + h - 0.017 and posY <= y + h then
            self.dragging = true
            self.dragDX, self.dragDY = posX - self.x, posY - y
        else
            self:stopMove()
            return
        end
    end
    if self.dragging then
        self.x = math.max(0.005, math.min(1 - self.width - 0.005, posX - self.dragDX))
        self.y = math.max(0.005, math.min(1 - (self.drawH or 0.35) - 0.005, posY - self.dragDY))
    end
    if isUp and button == left then
        self.dragging = false
        self:savePreferences()
    end
end
function M:consoleDump()
    self:scanAssets()
    self:refreshAlerts()
    for _, a in ipairs(self.assets) do
        for _, r in ipairs(self:products(a)) do
            Logging.info(
                "[StorageAlertMonitor] %s | %s | held=%s capacity=%s percent=%s",
                a.name,
                r.title,
                tostring(r.held),
                tostring(r.capacity),
                tostring(r.pct)
            )
        end
    end
    return "Storage Alert Monitor readings written to log.txt"
end
function M:deleteMap()
    self:stopMove()
    self:savePreferences()
    self.enabled = false
    removeConsoleCommand("samDump")
    if self.background then
        self.background:delete()
    end
    for _, icon in pairs(self.icons or {}) do
        icon:delete()
    end
    self.page = nil
end
if PlayerInputComponent and PlayerInputComponent.registerGlobalPlayerActionEvents then
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents,
        function()
            if not M.enabled then
                return
            end
            for _, name in ipairs({ "SAM_TOGGLE_HUD", "SAM_MORE_ROWS", "SAM_FEWER_ROWS", "SAM_MOUSE_TOGGLE" }) do
                local _, eventId = g_inputBinding:registerActionEvent(
                    InputAction[name],
                    M,
                    M.inputAction,
                    false,
                    true,
                    false,
                    true,
                    nil,
                    true
                )
                if eventId then
                    g_inputBinding:setActionEventTextVisibility(eventId, name == "SAM_MOUSE_TOGGLE")
                end
            end
        end
    )
end
-- Keep mouse motion available to the HUD while suppressing mouse camera look.
-- Other input devices still pass through the original game callbacks.
for _, entry in ipairs({
    { PlayerInputComponent, "onInputLookLeftRight" },
    { PlayerInputComponent, "onInputLookUpDown" },
    { VehicleCamera, "actionEventLookLeftRight" },
    { VehicleCamera, "actionEventLookUpDown" },
}) do
    local cameraType, method = entry[1], entry[2]
    local original = cameraType and cameraType[method]
    if original then
        cameraType[method] = function(camera, action, value, state, analog, isMouse, ...)
            if M.enabled and isMouse and g_inputBinding:getShowMouseCursor() then
                return
            end
            return original(camera, action, value, state, analog, isMouse, ...)
        end
    end
end
addModEventListener(M)
