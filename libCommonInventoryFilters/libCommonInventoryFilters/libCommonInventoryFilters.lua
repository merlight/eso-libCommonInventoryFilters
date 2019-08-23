local myNAME, myVERSION = "libCommonInventoryFilters", 1.40
LibCIF = LibCIF or {}

local libCIF = LibCIF
libCIF.name = myNAME
libCIF.version = myVERSION

local backpackLayouts
local searchBoxes

local function enableGuildStoreSellFilters()
    local tradingHouseLayout = BACKPACK_TRADING_HOUSE_LAYOUT_FRAGMENT.layoutData

    if not tradingHouseLayout.hiddenFilters then
        tradingHouseLayout.hiddenFilters = {}
    end
    tradingHouseLayout.hiddenFilters[ITEMFILTERTYPE_QUEST] = true
    tradingHouseLayout.inventoryTopOffsetY = 45
    tradingHouseLayout.sortByOffsetY = 63
    tradingHouseLayout.backpackOffsetY = 96

    local originalFilter = tradingHouseLayout.additionalFilter
    if originalFilter then
        function tradingHouseLayout.additionalFilter(slot)
            return originalFilter(slot) and not IsItemBound(slot.bagId, slot.slotIndex)
        end
    else
        function tradingHouseLayout.additionalFilter(slot)
            return not IsItemBound(slot.bagId, slot.slotIndex)
        end
    end

    local tradingHouseHiddenColumns = {statValue = true, age = true}
    local zorgGetTabFilterInfo = PLAYER_INVENTORY.GetTabFilterInfo

    function PLAYER_INVENTORY:GetTabFilterInfo(inventoryType, tabControl)
        if libCIF._tradingHouseModeEnabled then
            local filterType, activeTabText = zorgGetTabFilterInfo(self, inventoryType, tabControl)
            return filterType, activeTabText, tradingHouseHiddenColumns
        else
            return zorgGetTabFilterInfo(self, inventoryType, tabControl)
        end
    end
    -- ZO_InventoryManager:SetTradingHouseModeEnabled has been removed in 3.2
    -- from now on we have to listen to the scene state change and do the following:
    --  1) saves/restores the current filter
    --      - or would, if the filter wasn't reset in ApplyBackpackLayout
    --      - this simply doesn't work
    --  2) shows the search box and hides the filters tab, or vice versa
    --      - we want to show or hide them according to add-on requirements
    --        specified during start-up
    local function SetTradingHouseModeEnabled(enabled)
        libCIF._tradingHouseModeEnabled = enabled
    end
    --Trading house scene change
    local function SceneStateChange(oldState, newState)
        if newState == SCENE_SHOWING then
            SetTradingHouseModeEnabled(true)
        elseif newState == SCENE_HIDING then
            SetTradingHouseModeEnabled(false)
        end
    end
    TRADING_HOUSE_SCENE:RegisterCallback("StateChange", SceneStateChange)
end

--if the mouse is enabled, cycle its state to refresh the integrity of the control beneath it
local function SafeUpdateList(object, ...)
    local isMouseVisible = SCENE_MANAGER:IsInUIMode()
    if isMouseVisible then
        HideMouse()
    end
    object:UpdateList(...)
    if isMouseVisible then
        ShowMouse()
    end
end

local function fixSearchBoxBugs()
    -- http://www.esoui.com/forums/showthread.php?t=4551
    -- search box bug #1: stale searchData after swapping equipment
    SHARED_INVENTORY:RegisterCallback(
        "SlotUpdated",
        function(bagId, slotIndex, slotData)
            if slotData and slotData.searchData then
                slotData.searchData.cached = false
                slotData.searchData.cache = nil
            end
        end
    )

    -- guild bank search box bug #2: wrong inventory updated
    ZO_GuildBankSearchBox:SetHandler(
        "OnTextChanged",
        function(editBox)
            ZO_EditDefaultText_OnTextChanged(editBox)
            SafeUpdateList(PLAYER_INVENTORY, INVENTORY_GUILD_BANK)
        end
    )

    -- guild bank search box bug #3: wrong search box cleared
    local guildBankScene = SCENE_MANAGER:GetScene("guildBank")
    guildBankScene:RegisterCallback(
        "StateChange",
        function(oldState, newState)
            if newState == SCENE_HIDDEN then
                ZO_PlayerInventory_EndSearch(ZO_GuildBankSearchBox)
            end
        end
    )
end

local function showSearchBoxes()
    -- new in 3.2: player inventory fragments set the search bar visible when the layout is applied
    for i = 1, #backpackLayouts do
        backpackLayouts[i].layoutData.useSearchBar = true
    end

    local width = ZO_PlayerInventorySearch:GetWidth()
    for i = 1, #searchBoxes do
        searchBoxes[i]:SetWidth(width)
    end

    -- Also call ApplyBackpackLayout for those scenes to re-anchor searchBoxes as needed.
    SCENE_MANAGER:GetScene("bank"):AddFragment(BACKPACK_DEFAULT_LAYOUT_FRAGMENT)
    SCENE_MANAGER:GetScene("guildBank"):AddFragment(BACKPACK_DEFAULT_LAYOUT_FRAGMENT)
    SCENE_MANAGER:GetScene("houseBank"):AddFragment(BACKPACK_DEFAULT_LAYOUT_FRAGMENT)
end

local function enhanceSearchBoxes()
    --Enable search clear with right click on search box
    local function onMouseRightClickClearSearchBox(control, mouseButton, upInside)
        if upInside and mouseButton == MOUSE_BUTTON_INDEX_RIGHT and control and control.GetText and control:GetText() ~= "" then
            ZO_PlayerInventory_EndSearch(control)
        end
    end
    for i = 1, #searchBoxes do
        ZO_PreHookHandler(searchBoxes[i]:GetNamedChild("Box"), "OnMouseUp", onMouseRightClickClearSearchBox)
    end
end

local function onPlayerActivated(eventCode)
    EVENT_MANAGER:UnregisterForEvent(myNAME, eventCode)

    --Fix the errors in the search boxes
    fixSearchBoxBugs()
    --Enhance search boxes with right click
    enhanceSearchBoxes()
    --Show the search boxes
    if not libCIF._searchBoxesDisabled then
        showSearchBoxes()
    end
    --AwesomeGuildStore (and others) flag to disable the search filters at the trading house "inventory fragment"
    if not libCIF._guildStoreSellFiltersDisabled then
        -- note that this sets trading house layout offsets, so it
        -- has to be done before they are shifted
        enableGuildStoreSellFilters()
    end
    --Move the search boxes on their fragment layout
    local shiftY = libCIF._backpackLayoutShiftY
    if shiftY then
        local function doShift(layoutData)
            layoutData.sortByOffsetY = layoutData.sortByOffsetY + shiftY
            layoutData.backpackOffsetY = layoutData.backpackOffsetY + shiftY
        end
        for i = 1, #backpackLayouts do
            doShift(backpackLayouts[i].layoutData)
        end
    end

    local orgApplyBackpackLayout = PLAYER_INVENTORY.ApplyBackpackLayout
    local function applySearchBox(control, layoutData)
        if layoutData.searchBoxAnchor then
            layoutData.searchBoxAnchor:Set(control)
        end
        control:SetHidden(not layoutData.useSearchBar)
    end
    local function applySearchBoxes(manager, layoutData)
        local previousLayout = manager.appliedLayout
        if previousLayout == layoutData and not layoutData.alwaysReapplyLayout then
            return
        end
        for i = 1, #searchBoxes do
            applySearchBox(searchBoxes[i], layoutData)
        end
    end
    function PLAYER_INVENTORY.ApplyBackpackLayout(...)
        -- force context switch for mouse over control. The KEYBIND_STRIP needs it.
        local isMouseVisible = SCENE_MANAGER:IsInUIMode()
        if isMouseVisible then
            HideMouse(false)
        end
        applySearchBoxes(...)
        if isMouseVisible then
            ShowMouse(false)
        end
        return orgApplyBackpackLayout(...)
    end
end

-- shift backpack sort headers and item list down (shiftY > 0) or up (shiftY < 0)
-- add-ons should only call this from their EVENT_ADD_ON_LOADED handler
function libCIF:addBackpackLayoutShiftY(shiftY)
    libCIF._backpackLayoutShiftY = (libCIF._backpackLayoutShiftY or 0) + shiftY
end

-- tell libCIF to skip enabling inventory filters on guild store sell tab
-- add-ons should only call this from their EVENT_ADD_ON_LOADED handler
function libCIF:disableGuildStoreSellFilters()
    libCIF._guildStoreSellFiltersDisabled = true
end

-- tell libCIF to skip showing inventory search boxes outside guild store sell tab
-- add-ons should only call this from their EVENT_ADD_ON_LOADED handler
function libCIF:disableSearchBoxes()
    libCIF._searchBoxesDisabled = true
end

local function applyAnchorToLayoutFragment(layoutFragment, anchor)
    assert(layoutFragment and layoutFragment.layoutData, "Invalid layout fragment.")
    layoutFragment.layoutData.searchBoxAnchor = anchor
    if PLAYER_INVENTORY.appliedLayout == layoutFragment.layoutData then
        PLAYER_INVENTORY.appliedLayout = nil
    end
end

-- apply the given anchor to the given backpack layout fragments or all.
-- add-ons should only call this from their EVENT_ADD_ON_LOADED handler
-- Additional expert hint: anchor can be a ZO_Anchor or a table having a function :Set(control).
-- You are able to implement your own complex anchoring functions, using e.g. "mode" information from crafting tables
function libCIF:setSearchBoxAnchor(anchor, ...)
    assert(type(anchor) == "table" and anchor.Set, "Invalid anchor. Anchor must implement :Set(control)")
    local count = select("#", ...)
    if count == 0 then
        for i = 1, #backpackLayouts do
            backpackLayouts[i].layoutData.searchBoxAnchor = anchor
        end
        PLAYER_INVENTORY.appliedLayout = nil
    else
        for i = 1, count do
            applyAnchorToLayoutFragment(select(i, ...), anchor)
        end
    end
end

local function OnAddonLoaded(eventType, addonName)
    if addonName ~= myNAME then
        return
    end
    EVENT_MANAGER:UnregisterForEvent(myNAME, EVENT_ADD_ON_LOADED)

    --Backpack layout of fragments
    backpackLayouts = {
        BACKPACK_DEFAULT_LAYOUT_FRAGMENT,
        BACKPACK_MENU_BAR_LAYOUT_FRAGMENT,
        BACKPACK_BANK_LAYOUT_FRAGMENT,
        BACKPACK_GUILD_BANK_LAYOUT_FRAGMENT,
        BACKPACK_TRADING_HOUSE_LAYOUT_FRAGMENT,
        BACKPACK_MAIL_LAYOUT_FRAGMENT,
        BACKPACK_PLAYER_TRADE_LAYOUT_FRAGMENT,
        BACKPACK_STORE_LAYOUT_FRAGMENT,
        BACKPACK_FENCE_LAYOUT_FRAGMENT,
        BACKPACK_LAUNDER_LAYOUT_FRAGMENT
    }
    searchBoxes = {
        ZO_PlayerInventorySearch,
        ZO_CraftBagSearch,
        ZO_PlayerBankSearch,
        ZO_GuildBankSearch,
        ZO_HouseBankSearch
    }

    local anchor = ZO_Anchor:New(BOTTOMRIGHT, nil, TOPRIGHT, -15, -55)
    -- re-anchoring is necessary because they overlap with sort headers
    libCIF:setSearchBoxAnchor(anchor)
end

EVENT_MANAGER:UnregisterForEvent(myNAME, EVENT_ADD_ON_LOADED)
EVENT_MANAGER:RegisterForEvent(myNAME, EVENT_ADD_ON_LOADED, OnAddonLoaded)

EVENT_MANAGER:UnregisterForEvent(myNAME, EVENT_PLAYER_ACTIVATED)
EVENT_MANAGER:RegisterForEvent(myNAME, EVENT_PLAYER_ACTIVATED, onPlayerActivated)
