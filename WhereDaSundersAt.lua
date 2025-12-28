WhereDaSundersAt = WhereDaSundersAt or {}
WDSA_DB = WDSA_DB or {}

local _G = _G or getfenv(0)
local addon = WhereDaSundersAt
local getn = table.getn

local S_FIND = (string and string.find) or (strfind)
local S_LOWER = (string and string.lower) or (strlower)
local S_GSUB = (string and string.gsub) or (gsub)
local S_SUB = (string and string.sub) or (strsub)

local ADDON_NAME = "WhereDaSundersAt"
local ADDON_PREFIX = "|cffC79C6EWDSA|r: "
local MAX_SUNDER_STACKS = 5

local SUNDER_PATTERNS = {
    "Sunder Armor",
    "sunder armor",
}

local currentStacks = 0
local lastStacks = 0
local lastSoundTime = 0
local lastNoSunderSoundTime = 0
local soundCooldown = 3.0
local noSunderCooldown = 5.0
local soundFiles = {}
local numSoundFiles = 0

local sessionTotalSunders = 0
local sundersByPlayer = {}
local lastSunderTime = 0

local mainFrame
local counterText
local targetText
local totalText
local whoText
local bgTexture

local defaults = {
    enabled = true,
    showName = true,
    showWho = true,
    locked = false,
    posX = 0,
    posY = 100,
    scale = 1.0,
    soundEnabled = true,
    soundCooldown = 3.0,
    bossLevel = 63,
}

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(ADDON_PREFIX .. tostring(msg))
end

local function round(num)
    return math.floor(num + 0.5)
end

local function GetShortName(name)
    if not name then return "" end
    if string.len(name) > 10 then
        return S_SUB(name, 1, 8) .. ".."
    end
    return name
end

local function InitSounds()
    soundFiles = {}
    numSoundFiles = 0
    for i = 1, 10 do
        local path = "Interface\\AddOns\\WhereDaSundersAt\\sounds\\sunders" .. tostring(i) .. ".mp3"
        table.insert(soundFiles, path)
        numSoundFiles = numSoundFiles + 1
    end
end

local function PlayRandomSound()
    if not WDSA_DB or not WDSA_DB.soundEnabled then return end
    local now = GetTime()
    local cd = WDSA_DB.soundCooldown or soundCooldown
    if (now - lastSoundTime) < cd then return end
    if numSoundFiles > 0 then
        math.randomseed(GetTime() * 1000)
        local randomIndex = math.random(1, numSoundFiles)
        local soundPath = soundFiles[randomIndex]
        PlaySoundFile(soundPath)
        lastSoundTime = now
    end
end

local function PlayNoSunderSound()
    if not WDSA_DB or not WDSA_DB.soundEnabled then return end
    local now = GetTime()
    if (now - lastNoSunderSoundTime) < noSunderCooldown then return end
    local soundPath = "Interface\\AddOns\\WhereDaSundersAt\\sounds\\no-sunders.mp3"
    PlaySoundFile(soundPath)
    lastNoSunderSoundTime = now
end

local function RecordSunder(playerName)
    if not playerName or playerName == "" then
        playerName = "Unknown"
    end
    sessionTotalSunders = sessionTotalSunders + 1
    if not sundersByPlayer[playerName] then
        sundersByPlayer[playerName] = 0
    end
    sundersByPlayer[playerName] = sundersByPlayer[playerName] + 1
    lastSunderTime = GetTime()
    PlayRandomSound()
end

local function GetWhoSunderedText()
    local sorted = {}
    for name, count in pairs(sundersByPlayer) do
        table.insert(sorted, { name = name, count = count })
    end
    table.sort(sorted, function(a, b) return a.count > b.count end)
    local parts = {}
    for i = 1, math.min(3, getn(sorted)) do
        local entry = sorted[i]
        table.insert(parts, tostring(entry.count) .. "-" .. GetShortName(entry.name))
    end
    if getn(parts) == 0 then
        return ""
    end
    return table.concat(parts, " ")
end

local function ParseCombatMessage(msg)
    if not msg then return nil end
    local hasSunder = false
    for _, pattern in ipairs(SUNDER_PATTERNS) do
        if S_FIND(msg, pattern) then
            hasSunder = true
            break
        end
    end
    if not hasSunder then return nil end
    local playerName = nil
    if S_FIND(msg, "^Your ") or S_FIND(msg, "^your ") then
        playerName = UnitName("player")
    else
        local _, _, name = S_FIND(msg, "^([%w]+)'s Sunder")
        if name then
            playerName = name
        else
            local _, _, name2 = S_FIND(msg, "^([%w]+) casts Sunder")
            if name2 then
                playerName = name2
            end
        end
    end
    return playerName
end

local function GetSunderStacks(unit)
    if not unit or not UnitExists(unit) then
        return 0
    end
    for i = 1, 40 do
        local texture, count = UnitDebuff(unit, i)
        if not texture then break end
        WDSATooltip:SetOwner(UIParent, "ANCHOR_NONE")
        WDSATooltip:ClearLines()
        WDSATooltip:SetUnitDebuff(unit, i)
        local debuffName = WDSATooltipTextLeft1:GetText()
        if debuffName then
            local lowerName = S_LOWER(debuffName)
            if S_FIND(lowerName, "sunder") then
                return count or 1
            end
        end
    end
    return 0
end

local function CheckTargetForNoSunders()
    if not WDSA_DB then return end
    if not WDSA_DB.enabled then return end
    if not WDSA_DB.soundEnabled then return end
    if not UnitExists("target") then return end
    if UnitIsFriend("player", "target") then return end
    if UnitIsDead("target") then return end
    local level = UnitLevel("target")
    if level == -1 then level = 63 end
    local minLevel = WDSA_DB.bossLevel
    if not minLevel or minLevel < 1 then minLevel = 63 end
    if level < minLevel then return end
    local stacks = GetSunderStacks("target")
    if stacks == 0 then
        PlayNoSunderSound()
    end
end

local function CreateUI()
    mainFrame = CreateFrame("Frame", "WDSAFrame", UIParent)
    mainFrame:SetWidth(130)
    mainFrame:SetHeight(80)
    mainFrame:SetPoint("CENTER", UIParent, "CENTER", WDSA_DB.posX or 0, WDSA_DB.posY or 100)
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:SetFrameStrata("HIGH")
    mainFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    mainFrame:SetBackdropColor(0, 0, 0, 0.8)
    mainFrame:SetBackdropBorderColor(0.78, 0.61, 0.43, 1)

    local titleText = mainFrame:CreateFontString(nil, "OVERLAY")
    titleText:SetPoint("TOP", mainFrame, "TOP", 0, -5)
    titleText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    titleText:SetTextColor(0.78, 0.61, 0.43, 0.9)
    titleText:SetText("SUNDERS")

    counterText = mainFrame:CreateFontString(nil, "OVERLAY")
    counterText:SetPoint("TOP", titleText, "BOTTOM", 0, -2)
    counterText:SetFont("Fonts\\FRIZQT__.TTF", 28, "OUTLINE")
    counterText:SetTextColor(0.78, 0.61, 0.43, 1)
    counterText:SetText("0/5")

    targetText = mainFrame:CreateFontString(nil, "OVERLAY")
    targetText:SetPoint("TOP", counterText, "BOTTOM", 0, -1)
    targetText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    targetText:SetTextColor(1, 1, 1, 0.7)
    targetText:SetText("")

    totalText = mainFrame:CreateFontString(nil, "OVERLAY")
    totalText:SetPoint("TOP", targetText, "BOTTOM", 0, -2)
    totalText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    totalText:SetTextColor(0.6, 0.8, 1, 0.9)
    totalText:SetText("Session: 0")

    whoText = mainFrame:CreateFontString(nil, "OVERLAY")
    whoText:SetPoint("TOP", totalText, "BOTTOM", 0, -1)
    whoText:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    whoText:SetTextColor(0.7, 0.7, 0.7, 0.8)
    whoText:SetText("")

    mainFrame:SetScript("OnMouseDown", function()
        if not WDSA_DB.locked and arg1 == "LeftButton" then
            mainFrame:StartMoving()
        end
    end)

    mainFrame:SetScript("OnMouseUp", function()
        mainFrame:StopMovingOrSizing()
        local _, _, _, x, y = mainFrame:GetPoint()
        WDSA_DB.posX = round(x)
        WDSA_DB.posY = round(y)
    end)

    if not WDSA_DB.enabled then
        mainFrame:Hide()
    end
end

local function CreateScanTooltip()
    CreateFrame("GameTooltip", "WDSATooltip", UIParent, "GameTooltipTemplate")
    WDSATooltip:SetOwner(UIParent, "ANCHOR_NONE")
    WDSATooltip:Hide()
end

local function IsValidSunderTarget(unit)
    if not unit or not UnitExists(unit) then return false end
    if UnitIsFriend("player", unit) then return false end
    if UnitIsDead(unit) then return false end
    local level = UnitLevel(unit)
    if level == -1 then level = 63 end
    local minLevel = WDSA_DB and WDSA_DB.bossLevel
    if not minLevel or minLevel < 1 then minLevel = 63 end
    return level >= minLevel
end

local function UpdateDisplay()
    if not WDSA_DB or not WDSA_DB.enabled or not mainFrame then
        if mainFrame then mainFrame:Hide() end
        return
    end
    local hasValidTarget = IsValidSunderTarget("target")
    if not hasValidTarget then
        mainFrame:Hide()
        currentStacks = 0
        return
    end
    mainFrame:Show()
    currentStacks = GetSunderStacks("target")
    counterText:SetText(tostring(currentStacks) .. "/5")
    if currentStacks == 0 then
        counterText:SetTextColor(1, 0.3, 0.3, 1)
    elseif currentStacks < 5 then
        counterText:SetTextColor(1, 0.82, 0, 1)
    else
        counterText:SetTextColor(0.3, 1, 0.3, 1)
    end
    if WDSA_DB.showName then
        local name = UnitName("target") or ""
        targetText:SetText(GetShortName(name))
    else
        targetText:SetText("")
    end
    totalText:SetText("Session: " .. tostring(sessionTotalSunders))
    if WDSA_DB.showWho then
        whoText:SetText(GetWhoSunderedText())
    else
        whoText:SetText("")
    end
    lastStacks = currentStacks
end

local eventFrame = CreateFrame("Frame", "WDSAEventFrame")

local function OnEvent()
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        if not WDSA_DB.initialized then
            WDSA_DB = {
                initialized = true,
                enabled = defaults.enabled,
                showName = defaults.showName,
                showWho = defaults.showWho,
                locked = defaults.locked,
                posX = defaults.posX,
                posY = defaults.posY,
                scale = defaults.scale,
                soundEnabled = defaults.soundEnabled,
                soundCooldown = defaults.soundCooldown,
                bossLevel = defaults.bossLevel,
            }
        end
        if WDSA_DB.showWho == nil then
            WDSA_DB.showWho = true
        end
        if WDSA_DB.soundCooldown == nil then
            WDSA_DB.soundCooldown = defaults.soundCooldown
        end
        if WDSA_DB.bossLevel == nil then
            WDSA_DB.bossLevel = defaults.bossLevel
        end
        CreateScanTooltip()
        CreateUI()
        InitSounds()
        Print("loaded! Type |cff00ff00/wdsa|r for commands.")

    elseif event == "PLAYER_LOGIN" then
        UpdateDisplay()

    elseif event == "PLAYER_TARGET_CHANGED" then
        lastStacks = 0
        UpdateDisplay()
        CheckTargetForNoSunders()

    elseif event == "UNIT_AURA" then
        if arg1 == "target" then
            local newStacks = GetSunderStacks("target")
            UpdateDisplay()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateDisplay()

    elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        local playerName = ParseCombatMessage(arg1)
        if playerName then
            RecordSunder(playerName)
            UpdateDisplay()
        end

    elseif event == "CHAT_MSG_SPELL_PARTY_DAMAGE" then
        local playerName = ParseCombatMessage(arg1)
        if playerName then
            RecordSunder(playerName)
            UpdateDisplay()
        end

    elseif event == "CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE" then
        local playerName = ParseCombatMessage(arg1)
        if playerName then
            RecordSunder(playerName)
            UpdateDisplay()
        end

    elseif event == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" then
        local playerName = ParseCombatMessage(arg1)
        if playerName then
            RecordSunder(playerName)
            UpdateDisplay()
        end

    elseif event == "CHAT_MSG_COMBAT_SELF_HITS" then
        if arg1 and S_FIND(S_LOWER(arg1), "sunder") then
            RecordSunder(UnitName("player"))
            UpdateDisplay()
        end

    elseif event == "CHAT_MSG_COMBAT_PARTY_HITS" then
        local playerName = ParseCombatMessage(arg1)
        if playerName then
            RecordSunder(playerName)
            UpdateDisplay()
        end

    elseif event == "CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS" then
        local playerName = ParseCombatMessage(arg1)
        if playerName then
            RecordSunder(playerName)
            UpdateDisplay()
        end
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_PARTY_HITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLYPLAYER_HITS")

eventFrame:SetScript("OnEvent", OnEvent)

local updateTimer = 0
eventFrame:SetScript("OnUpdate", function()
    updateTimer = updateTimer + arg1
    if updateTimer >= 0.25 then
        updateTimer = 0
        if WDSA_DB and WDSA_DB.enabled then
            UpdateDisplay()
        end
    end
end)

local function SlashHandler(msg)
    local cmd = S_LOWER(msg or "")

    if cmd == "" or cmd == "help" then
        Print("Commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa on|r - Enable")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa off|r - Disable")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa toggle|r - Toggle on/off")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa reset|r - Reset position & counters")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa name|r - Toggle target name")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa who|r - Toggle who sundered display")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa lock|r - Lock/unlock frame")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa sound|r - Toggle sounds")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa stats|r - Show full breakdown")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa cd <1-30>|r - Sound cooldown")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa test|r - Test sunder sound")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa testno|r - Test no-sunders alert")
        DEFAULT_CHAT_FRAME:AddMessage("  |cff00ff00/wdsa level|r - Toggle 62/63 (default 63)")
        return
    end

    if cmd == "on" then
        WDSA_DB.enabled = true
        if mainFrame then mainFrame:Show() end
        UpdateDisplay()
        Print("Enabled")

    elseif cmd == "off" then
        WDSA_DB.enabled = false
        if mainFrame then mainFrame:Hide() end
        Print("Disabled")

    elseif cmd == "toggle" then
        WDSA_DB.enabled = not WDSA_DB.enabled
        if WDSA_DB.enabled then
            if mainFrame then mainFrame:Show() end
            UpdateDisplay()
        else
            if mainFrame then mainFrame:Hide() end
        end
        Print(WDSA_DB.enabled and "Enabled" or "Disabled")

    elseif cmd == "reset" then
        WDSA_DB.posX = 0
        WDSA_DB.posY = 100
        if mainFrame then
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
        end
        sessionTotalSunders = 0
        sundersByPlayer = {}
        UpdateDisplay()
        Print("Position and counters reset")

    elseif cmd == "name" then
        WDSA_DB.showName = not WDSA_DB.showName
        UpdateDisplay()
        Print("Target name " .. (WDSA_DB.showName and "shown" or "hidden"))

    elseif cmd == "who" then
        WDSA_DB.showWho = not WDSA_DB.showWho
        UpdateDisplay()
        Print("Who sundered display " .. (WDSA_DB.showWho and "shown" or "hidden"))

    elseif cmd == "lock" then
        WDSA_DB.locked = not WDSA_DB.locked
        Print("Frame " .. (WDSA_DB.locked and "locked" or "unlocked"))

    elseif cmd == "sound" then
        WDSA_DB.soundEnabled = not WDSA_DB.soundEnabled
        Print("Sounds " .. (WDSA_DB.soundEnabled and "enabled" or "disabled"))

    elseif cmd == "stats" then
        Print("Session Total: |cff00ff00" .. tostring(sessionTotalSunders) .. "|r")
        local sorted = {}
        for name, count in pairs(sundersByPlayer) do
            table.insert(sorted, { name = name, count = count })
        end
        table.sort(sorted, function(a, b) return a.count > b.count end)
        if getn(sorted) == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("  No sunders recorded yet")
        else
            for i = 1, getn(sorted) do
                local entry = sorted[i]
                DEFAULT_CHAT_FRAME:AddMessage("  |cffC79C6E" .. tostring(entry.count) .. "|r - " .. entry.name)
            end
        end

    elseif cmd == "test" then
        Print("Testing sunder sound...")
        lastSoundTime = 0
        PlayRandomSound()

    elseif cmd == "testno" then
        Print("Testing no-sunders alert...")
        lastNoSunderSoundTime = 0
        PlayNoSunderSound()

    elseif cmd == "level" then
        if WDSA_DB.bossLevel == 63 then
            WDSA_DB.bossLevel = 62
            Print("Alert level: 62+ (bosses & elites)")
        else
            WDSA_DB.bossLevel = 63
            Print("Alert level: 63 (bosses only)")
        end

    elseif S_FIND(cmd, "^cd ") or S_FIND(cmd, "^cooldown ") then
        local _, _, numStr = S_FIND(cmd, "^c[od]+ (.+)")
        local num = tonumber(numStr)
        if num and num >= 1 and num <= 30 then
            WDSA_DB.soundCooldown = num
            Print("Sound cooldown set to " .. tostring(num) .. " seconds")
        else
            Print("Usage: /wdsa cd <1-30>  (current: " .. tostring(WDSA_DB.soundCooldown) .. "s)")
        end

    else
        Print("Unknown command. Type |cff00ff00/wdsa|r for help.")
    end
end

SLASH_WDSA1 = "/wdsa"
SLASH_WDSA2 = "/wheredasundersat"
SlashCmdList["WDSA"] = SlashHandler

function addon:GetSessionTotal()
    return sessionTotalSunders
end

function addon:GetCurrentStacks()
    return currentStacks
end

function addon:GetSundersByPlayer()
    return sundersByPlayer
end

function addon:ResetCounters()
    sessionTotalSunders = 0
    sundersByPlayer = {}
    UpdateDisplay()
end

local minimapButton = CreateFrame("Button", "WDSAMinimapButton", Minimap)
minimapButton:SetWidth(31)
minimapButton:SetHeight(31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
minimapButton:SetMovable(true)
minimapButton:EnableMouse(true)
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")

local mmOverlay = minimapButton:CreateTexture(nil, "OVERLAY")
mmOverlay:SetWidth(53)
mmOverlay:SetHeight(53)
mmOverlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmOverlay:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)

local mmIcon = minimapButton:CreateTexture(nil, "BACKGROUND")
mmIcon:SetWidth(20)
mmIcon:SetHeight(20)
mmIcon:SetTexture("Interface\\Icons\\Ability_Warrior_Sunder")
mmIcon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
minimapButton.icon = mmIcon

local mmDragging = false

local function UpdateMinimapPosition()
    local angle = WDSA_DB and WDSA_DB.minimapAngle or 220
    local radius = 80
    local rads = math.rad(angle)
    local x = math.cos(rads) * radius
    local y = math.sin(rads) * radius
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

minimapButton:SetScript("OnDragStart", function()
    mmDragging = true
    minimapButton:LockHighlight()
end)

minimapButton:SetScript("OnDragStop", function()
    mmDragging = false
    minimapButton:UnlockHighlight()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    px, py = px / scale, py / scale
    local angle = math.deg(math.atan2(py - my, px - mx))
    if WDSA_DB then
        WDSA_DB.minimapAngle = angle
    end
    UpdateMinimapPosition()
end)

minimapButton:SetScript("OnUpdate", function()
    if mmDragging then
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        px, py = px / scale, py / scale
        local angle = math.deg(math.atan2(py - my, px - mx))
        local radius = 80
        local x = math.cos(math.rad(angle)) * radius
        local y = math.sin(math.rad(angle)) * radius
        minimapButton:ClearAllPoints()
        minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
end)

minimapButton:SetScript("OnEnter", function()
    GameTooltip:SetOwner(minimapButton, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cffC79C6EWhere Da Sunders At?|r")
    if WDSA_DB then
        if WDSA_DB.enabled then
            GameTooltip:AddLine("Status: |cff00ff00Enabled|r", 1, 1, 1)
        else
            GameTooltip:AddLine("Status: |cffff0000Disabled|r", 1, 1, 1)
        end
        GameTooltip:AddLine("Level: " .. tostring(WDSA_DB.bossLevel or 63) .. "+", 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: Config", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: Toggle", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Drag: Move button", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

local configFrame = CreateFrame("Frame", "WDSAConfigFrame", UIParent)
configFrame:SetWidth(280)
configFrame:SetHeight(320)
configFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
configFrame:SetFrameStrata("DIALOG")
configFrame:EnableMouse(true)
configFrame:SetMovable(true)
configFrame:RegisterForDrag("LeftButton")
configFrame:SetScript("OnDragStart", function() configFrame:StartMoving() end)
configFrame:SetScript("OnDragStop", function() configFrame:StopMovingOrSizing() end)
configFrame:Hide()

configFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 }
})
configFrame:SetBackdropColor(0, 0, 0, 0.9)

local cfgTitleBg = configFrame:CreateTexture(nil, "ARTWORK")
cfgTitleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
cfgTitleBg:SetWidth(220)
cfgTitleBg:SetHeight(64)
cfgTitleBg:SetPoint("TOP", configFrame, "TOP", 0, 12)

local cfgTitle = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
cfgTitle:SetPoint("TOP", configFrame, "TOP", 0, -4)
cfgTitle:SetText("Where Da Sunders At?")

local cfgClose = CreateFrame("Button", nil, configFrame, "UIPanelCloseButton")
cfgClose:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -5, -5)
cfgClose:SetScript("OnClick", function() configFrame:Hide() end)

local function CreateWDSACheckbox(name, label, x, y, onClick, tooltip)
    local cb = CreateFrame("CheckButton", name, configFrame, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", configFrame, "TOPLEFT", x, y)
    cb:SetWidth(26)
    cb:SetHeight(26)
    local text = getglobal(name .. "Text")
    if text then
        text:SetText(label)
        text:SetFontObject(GameFontNormal)
    end
    if onClick then
        cb:SetScript("OnClick", onClick)
    end
    if tooltip then
        cb:SetScript("OnEnter", function()
            GameTooltip:SetOwner(cb, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return cb
end

local cbEnabled = CreateWDSACheckbox(
    "WDSA_CB_Enabled",
    "|cff00ff00Enable Addon|r",
    20, -40,
    function()
        WDSA_DB.enabled = getglobal("WDSA_CB_Enabled"):GetChecked()
        if WDSA_DB.enabled then
            minimapButton.icon:SetDesaturated(nil)
        else
            minimapButton.icon:SetDesaturated(1)
        end
        UpdateDisplay()
    end,
    "Master toggle for the sunder tracker"
)

local cbShowName = CreateWDSACheckbox(
    "WDSA_CB_ShowName",
    "Show Target Name",
    20, -70,
    function()
        WDSA_DB.showName = getglobal("WDSA_CB_ShowName"):GetChecked()
        UpdateDisplay()
    end,
    "Display the target's name on the tracker"
)

local cbShowWho = CreateWDSACheckbox(
    "WDSA_CB_ShowWho",
    "Show Who Sundered",
    20, -100,
    function()
        WDSA_DB.showWho = getglobal("WDSA_CB_ShowWho"):GetChecked()
        UpdateDisplay()
    end,
    "Display who applied sunders (top 3)"
)

local cbSound = CreateWDSACheckbox(
    "WDSA_CB_Sound",
    "Enable Sounds",
    20, -130,
    function()
        WDSA_DB.soundEnabled = getglobal("WDSA_CB_Sound"):GetChecked()
    end,
    "Play sounds when sunders are applied"
)

local cbLocked = CreateWDSACheckbox(
    "WDSA_CB_Locked",
    "Lock Frame Position",
    20, -160,
    function()
        WDSA_DB.locked = getglobal("WDSA_CB_Locked"):GetChecked()
    end,
    "Prevent dragging the tracker frame"
)

local lvlHeader = configFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lvlHeader:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 20, -200)
lvlHeader:SetText("Boss Level Threshold:")
lvlHeader:SetTextColor(1, 0.82, 0)

local rb63 = CreateFrame("CheckButton", "WDSA_RB_63", configFrame, "UIRadioButtonTemplate")
rb63:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 30, -220)
rb63:SetWidth(20)
rb63:SetHeight(20)
local rb63Text = getglobal("WDSA_RB_63Text")
if rb63Text then
    rb63Text:SetText("Level 63 (Bosses only)")
    rb63Text:SetFontObject(GameFontHighlight)
end

local rb62 = CreateFrame("CheckButton", "WDSA_RB_62", configFrame, "UIRadioButtonTemplate")
rb62:SetPoint("TOPLEFT", configFrame, "TOPLEFT", 30, -242)
rb62:SetWidth(20)
rb62:SetHeight(20)
local rb62Text = getglobal("WDSA_RB_62Text")
if rb62Text then
    rb62Text:SetText("Level 62+ (Bosses & Elites)")
    rb62Text:SetFontObject(GameFontHighlight)
end

rb63:SetScript("OnClick", function()
    rb63:SetChecked(true)
    rb62:SetChecked(false)
    WDSA_DB.bossLevel = 63
end)

rb62:SetScript("OnClick", function()
    rb62:SetChecked(true)
    rb63:SetChecked(false)
    WDSA_DB.bossLevel = 62
end)

local resetBtn = CreateFrame("Button", "WDSA_ResetBtn", configFrame, "UIPanelButtonTemplate")
resetBtn:SetWidth(120)
resetBtn:SetHeight(24)
resetBtn:SetPoint("BOTTOMLEFT", configFrame, "BOTTOMLEFT", 20, 20)
resetBtn:SetText("Reset Counters")
resetBtn:SetScript("OnClick", function()
    sessionTotalSunders = 0
    sundersByPlayer = {}
    UpdateDisplay()
    Print("Counters reset")
end)

local testBtn = CreateFrame("Button", "WDSA_TestBtn", configFrame, "UIPanelButtonTemplate")
testBtn:SetWidth(100)
testBtn:SetHeight(24)
testBtn:SetPoint("BOTTOMRIGHT", configFrame, "BOTTOMRIGHT", -20, 20)
testBtn:SetText("Test Sound")
testBtn:SetScript("OnClick", function()
    lastSoundTime = 0
    PlayRandomSound()
end)

local function LoadConfigUI()
    if not WDSA_DB then return end
    getglobal("WDSA_CB_Enabled"):SetChecked(WDSA_DB.enabled)
    getglobal("WDSA_CB_ShowName"):SetChecked(WDSA_DB.showName)
    getglobal("WDSA_CB_ShowWho"):SetChecked(WDSA_DB.showWho)
    getglobal("WDSA_CB_Sound"):SetChecked(WDSA_DB.soundEnabled)
    getglobal("WDSA_CB_Locked"):SetChecked(WDSA_DB.locked)
    if WDSA_DB.bossLevel == 62 then
        rb62:SetChecked(true)
        rb63:SetChecked(false)
    else
        rb63:SetChecked(true)
        rb62:SetChecked(false)
    end
end

function WDSA_ToggleConfig()
    if configFrame:IsVisible() then
        configFrame:Hide()
    else
        LoadConfigUI()
        configFrame:Show()
    end
end

minimapButton:SetScript("OnClick", function()
    local click = arg1
    if click == "LeftButton" then
        WDSA_ToggleConfig()
    elseif click == "RightButton" then
        WDSA_DB.enabled = not WDSA_DB.enabled
        if WDSA_DB.enabled then
            minimapButton.icon:SetDesaturated(nil)
            Print("Enabled")
        else
            minimapButton.icon:SetDesaturated(1)
            Print("Disabled")
        end
        UpdateDisplay()
    end
end)

function WDSA_UpdateMinimapButton()
    if WDSA_DB and WDSA_DB.enabled then
        minimapButton.icon:SetDesaturated(nil)
    else
        minimapButton.icon:SetDesaturated(1)
    end
    UpdateMinimapPosition()
end

minimapButton:SetScript("OnShow", UpdateMinimapPosition)

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    WDSA_UpdateMinimapButton()
end)
