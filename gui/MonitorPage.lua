SAMPage = {}
local SAMPage_mt = Class(SAMPage, TabbedMenuFrameElement)
function SAMPage.new()
    local self = SAMPage:superClass().new(nil, SAMPage_mt)
    self.name = "SAMPage"
    self.hasCustomMenuButtons = true
    self.rows = {}
    return self
end
function SAMPage:text(id, value)
    local e = self:getDescendantById(id)
    if e then
        e:setText(tostring(value))
    end
end
function SAMPage:onGuiSetupFinished()
    SAMPage:superClass().onGuiSetupFinished(self)
    local m = StorageAlertMonitor
    self:text("label_pageTitle", m:tr("pageTitle"))
    self:text("label_buildings", m:tr("buildings"))
    self:text("label_productType", m:tr("productType"))
    self:text("label_current", m:tr("current"))
    self:text("label_threshold", m:tr("threshold"))
    self:text("label_alertType", m:tr("alertType"))
    self:text("lowButton", m:tr("low"))
    self:text("highButton", m:tr("high"))
    self:text("offButton", m:tr("off"))
    self:text("hudButton", m:tr("hudOn"))
    self:text("moveButton", m:tr("moveHud"))
    self:text("resetButton", m:tr("resetPosition"))
    -- Reuse the sidebar artwork in the standard menu header badge slot.
    local headerIcon = self:getDescendantById("monitorHeaderIcon")
    if headerIcon then
        local iconPath = StorageAlertMonitor.modDir .. "tabIcon.dds"
        local iconUVs = GuiUtils.getUVs({ 0, 0, 512, 512 }, { 512, 512 })
        for _, state in ipairs({ "", "Focused", "Highlighted", "Selected", "Pressed", "Disabled" }) do
            headerIcon.overlay["uvs" .. state] = iconUVs
            headerIcon.overlay["color" .. state] = { 0, 0, 0, 1 }
            if state ~= "" then
                headerIcon.overlay["filename" .. state] = iconPath
            end
        end
        headerIcon:setImageFilename(iconPath)
    end
    self.assetList = self:getDescendantById("assetList")
    self.productList = self:getDescendantById("productList")
    self.assetList:setDataSource(self)
    self.assetList:setDelegate(self)
    self.productList:setDataSource(self)
    self.productList:setDelegate(self)
    self:setMenuButtonInfo({ { inputAction = InputAction.MENU_BACK } })
    local divider = self:getDescendantById("alertDivider")
    if divider then
        divider:setImageFilename(StorageAlertMonitor.modDir .. "gui/white.dds")
    end
    self:refresh(true)
end
function SAMPage:onFrameOpen()
    StorageAlertMonitor:stopMove()
    SAMPage:superClass().onFrameOpen(self)
    self.monitorOpen = true
    StorageAlertMonitor:scanAssets()
    self:refresh(true)
    FocusManager:setFocus(self.assetList)
end
function SAMPage:onFrameClose()
    self.monitorOpen = false
    StorageAlertMonitor:savePreferences()
    SAMPage:superClass().onFrameClose(self)
end
function SAMPage:refresh(catalog)
    local m = StorageAlertMonitor
    if catalog then
        self.assetList:reloadData()
    end
    local selected
    for _, a in ipairs(m.assets or {}) do
        if a.key == self.assetKey then
            selected = a
            break
        end
    end
    if not selected then
        selected = m.assets[1]
        self.assetKey = selected and selected.key
    end
    self.selectedAsset = selected
    self.rows = selected and m:products(selected) or {}
    self:text(
        "buildingTitle",
        selected and selected.name .. " (" .. m:label(selected.role) .. ")" or m:tr("noBuildings")
    )
    self.productList:reloadData()
    self:text("hudButton", m:tr(m.hudEnabled and "hudOn" or "hudOff"))
    self:text("rowsReadout", m:tr("hudRows", m.maxRows))
    self:selectionHint()
    self:styleButtons()
end
function SAMPage:getNumberOfItemsInSection(list)
    return list == self.assetList and #StorageAlertMonitor.assets or #self.rows
end
function SAMPage:getCellTypeForItemInSection()
    return "default"
end
function SAMPage:populateCellForItemInSection(list, section, index, item)
    local m = StorageAlertMonitor
    local function text(name, value)
        local e = item:getAttribute(name)
        if e then
            e:setText(value)
        end
    end
    if list == self.assetList then
        local a = m.assets[index]
        text("name", a.name)
        text("role", m:label(a.role))
    else
        local r = self.rows[index]
        local rule = m.rules[r.key]
        text("name", r.title)
        text("direction", r.direction)
        text("level", r.pct and string.format("%.1f%%", r.pct) or "--")
        text(
            "amount",
            r.unit == "percent"
                    and (r.pct and string.format("%.1f%% %s", r.pct, r.metric or m:tr("metricProductivity")) or m:tr("unavailable"))
                or r.held and string.format(
                    "%.0f / %s",
                    r.held,
                    r.capacity and string.format("%.0f", r.capacity) or "?"
                )
                or m:tr("unavailable")
        )
        text(
            "rule",
            rule and m:tr(rule.mode == "low" and "atBelow" or "atAbove", rule.threshold) or m:tr("off")
        )
        local e = item:getAttribute("icon")
        if e then
            e:setVisible(r.icon ~= nil)
            if r.icon then
                e:setImageFilename(r.icon)
            end
        end
    end
end
function SAMPage:onSelectAsset(element)
    local a = StorageAlertMonitor.assets[element.indexInSection]
    self.assetKey = a and a.key
    self.productKey = nil
    self:refresh(false)
end
function SAMPage:onSelectProduct(element)
    local r = self.rows[element.indexInSection]
    self.productKey = r and r.key
    self:selectionHint()
    self:styleButtons()
end
function SAMPage:getSelectedProduct()
    for _, r in ipairs(self.rows) do
        if r.key == self.productKey then
            return r
        end
    end
end
function SAMPage:selectionHint()
    local m = StorageAlertMonitor
    local r = self:getSelectedProduct()
    local rule = r and StorageAlertMonitor.rules[r.key]
    self:text(
        "hint",
        r
                and (r.title .. ": " .. (rule and m:tr(rule.mode == "low" and "atBelow" or "atAbove", rule.threshold) or m:tr("monitorOff")) .. (not r.capacity and m:tr("capacityUnknown") or ""))
            or m:tr("selectHint")
    )
end
function SAMPage:mode(mode)
    local r = self:getSelectedProduct()
    if not r then
        return
    end
    local old = StorageAlertMonitor.rules[r.key]
    StorageAlertMonitor:setRule(r, mode, old and old.mode == mode and old.threshold or mode == "low" and 20 or 90)
    self:refresh(false)
end
function SAMPage:onLow()
    self:mode("low")
end
function SAMPage:onHigh()
    self:mode("high")
end
function SAMPage:onOff()
    self:mode("off")
end
function SAMPage:adjust(amount)
    local r = self:getSelectedProduct()
    if not r then
        return
    end
    local old = StorageAlertMonitor.rules[r.key]
    if old then
        StorageAlertMonitor:setRule(r, old.mode, old.threshold + amount)
        self:refresh(false)
    end
end
function SAMPage:onMinus()
    self:adjust(-1)
end
function SAMPage:onPlus()
    self:adjust(1)
end
function SAMPage:onMinusFive()
    self:adjust(-5)
end
function SAMPage:onPlusFive()
    self:adjust(5)
end
function SAMPage:styleButtons()
    local r = self:getSelectedProduct()
    local rule = r and StorageAlertMonitor.rules[r.key]
    for _, id in ipairs({
        "lowButton",
        "highButton",
        "offButton",
        "minusFive",
        "minus",
        "plus",
        "plusFive",
        "hudButton",
        "moveButton",
        "resetButton",
        "rowsButton",
        "rowsLessButton",
    }) do
        local button = self:getDescendantById(id)
        if button and button.overlay then
            local active = (id == "lowButton" and rule and rule.mode == "low")
                or (id == "highButton" and rule and rule.mode == "high")
                or (id == "hudButton" and StorageAlertMonitor.hudEnabled)
            local path = StorageAlertMonitor.modDir .. "gui/" .. (active and "buttonWideActive.dds" or "buttonWide.dds")
            local pressed = StorageAlertMonitor.modDir .. "gui/buttonWidePressed.dds"
            local uvs = GuiUtils.getUVs({ 0, 0, 1, 1 }, { 1, 1 })
            for _, state in ipairs({ "", "Focused", "Highlighted", "Selected", "Pressed", "Disabled" }) do
                button.overlay["color" .. state] = { 1, 1, 1, 1 }
                button.overlay["uvs" .. state] = uvs
                if state ~= "" then
                    button.overlay["filename" .. state] = state == "Pressed" and pressed or path
                end
            end
            button:setImageFilename(path)
        end
    end
end
function SAMPage:onHud()
    local m = StorageAlertMonitor
    m:toggleHud()
    self:refresh(false)
end
function SAMPage:adjustRows(delta)
    local m = StorageAlertMonitor
    m:adjustRows(delta)
    self:refresh(false)
end
function SAMPage:onRows()
    self:adjustRows(1)
end
function SAMPage:onRowsLess()
    self:adjustRows(-1)
end
function SAMPage:onResetHud()
    local m = StorageAlertMonitor
    m.x, m.y = 0.630, 0.033
    m:savePreferences()
end
function SAMPage:onMove()
    g_gui:changeScreen(nil)
    StorageAlertMonitor:startMove()
end
function StorageAlertMonitor:setupPage()
    if self.page or not g_gui or not g_gui.screenControllers or g_dedicatedServer then
        return
    end
    local menu = g_gui.screenControllers[InGameMenu]
    if not menu then
        return
    end
    g_gui:loadProfiles(self.modDir .. "gui/profiles.xml")
    local page = SAMPage.new()
    g_gui:loadGui(self.modDir .. "gui/monitor.xml", "storageAlertMonitorPage", page, true)
    menu.controlIDs.storageAlertMonitorPage = nil
    menu.storageAlertMonitorPage = page
    menu.pagingElement:addElement(page)
    menu:exposeControlsAsFields("storageAlertMonitorPage")
    menu.pagingElement:updateAbsolutePosition()
    menu.pagingElement:updatePageMapping()
    local before = menu.pageSettings or menu.pageControls
    local position = #menu.pageFrames + 1
    for i, frame in ipairs(menu.pageFrames) do
        if frame == before then
            position = i
            break
        end
    end
    menu:registerPage(page, position, nil)
    local function reorder(items, getFrame)
        local a, b
        for i, item in ipairs(items or {}) do
            local frame = getFrame(item)
            if frame == page then
                a = i
            end
            if frame == before then
                b = i
            end
        end
        if a and b and a > b then
            table.insert(items, b, table.remove(items, a))
        end
    end
    reorder(menu.pagingElement.elements, function(item)
        return item
    end)
    reorder(menu.pagingElement.pages, function(item)
        return item.element
    end)
    menu.pagingElement:updateAbsolutePosition()
    menu.pagingElement:updatePageMapping()
    menu:addPageTab(page, self.modDir .. "tabIcon.dds", GuiUtils.getUVs({ 0, 0, 512, 512 }, { 512, 512 }))
    local list = menu.pagingTabList
    if list and type(list.draw) == "function" then
        local original = list.draw
        local path = self.modDir .. "tabIcon.dds"
        local function keepIcon(element)
            for _, name in ipairs({ "overlay", "icon" }) do
                local overlay = element[name]
                if overlay and overlay.filename == path then
                    for _, state in ipairs({ "", "Selected", "Focused", "Highlighted", "Pressed", "Disabled" }) do
                        overlay["color" .. state] = { 1, 1, 1, 1 }
                    end
                end
            end
            for _, child in ipairs(element.elements or {}) do
                keepIcon(child)
            end
        end
        list.draw = function(element, ...)
            keepIcon(element)
            return original(element, ...)
        end
    end
    menu:rebuildTabList()
    self.page = page
end
