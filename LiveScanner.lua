-- ============================================
-- FULL LIVE SCANNER v10.1 — LIGHTWEIGHT FINAL FIXED
-- Anti-spam + Smart diff + Hemat resource
-- Fix: typeof() removed untuk Delta Executor
-- ============================================

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local Stats = game:GetService("Stats")
local lp = Players.LocalPlayer

-- ============ CLEANUP OLD ============
if _G._LiveScanner_v10_Cleanup then pcall(_G._LiveScanner_v10_Cleanup) end
for _, g in ipairs(game:GetService("CoreGui"):GetChildren()) do
    if g.Name == "FullLiveScan" then g:Destroy() end
end
for _, g in ipairs(lp:WaitForChild("PlayerGui"):GetChildren()) do
    if g.Name == "FullLiveScan" then g:Destroy() end
end

-- ============ CONFIG ============
local CFG = {
    -- Performance
    ScanInterval = 1.5,
    RenderInterval = 1.5,
    InfoInterval = 5,
    HookInterval = 5,
    MaxLines = 25,
    MaxBuffer = 400,
    Radius = 100,

    -- Trackers
    TrackAttrs = true,
    TrackStats = true,
    TrackHumanoid = true,
    TrackModels = true,
    TrackRemotes = true,
    TrackInventory = true,
    TrackPosition = false,
    TrackPlayers = true,
    TrackHealth = true,
    TrackNetwork = false,
    TrackToolEquip = true,

    -- Overpower
    AlertMode = true,
    CurrencyRadar = true,
    SpeedHackDetect = true,
    PatternDetect = true,

    -- Anti-spam
    IgnoreRemotes = {
        "ReplicaSet", "Replica", "ReplicaCreated", "ReplicaRemoved",
    },
    IgnorePatterns = {
        "replica", "heartbeat", "tick", "ping", "update",
        "coinschanged", "leaderboard", "income", "dailyreset",
        "seasonpass", "lasttick", "lastpush",
    },
    IgnoreAttrPatterns = {
        "LBTHIncomeLastTick", "LBTHPlotDailyIncomeLastPush",
        "LastDailyReset", "LastSeasonPassReset",
        "LastWeeklyReset", "LastSeasonPassHourlyReset",
    },
    IgnoreEquipItems = {
        "Humanoid", "HumanoidRootPart", "Head", "Torso", "LowerTorso", "UpperTorso",
        "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand",
        "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
        "Health", "Animate", "Body Colors", "Shirt", "Pants", "Accessory",
    },

    SmartDiff = true,
    DedupeRemote = true,
    DedupeWindow = 3,
    NumericTolerance = 0.5,
    HighFreqThreshold = 8,
    HighFreqWindow = 3,
    MaxArgLen = 200,

    AlertKeywords = {"admin","kick","ban","give","cash","coin","token",
                     "win","prize","reward","hack","exploit","detected"},
    CurrencyKeywords = {"cash","coin","gem","token","money","gold",
                        "credit","crystal","diamond","point","xp","level"},
    MaxSpeedNormal = 100,
    MaxJumpNormal = 150,
}

-- ============ STATE ============
local State = {running = true, paused = false, destroyed = false}

-- ============ LOG ============
local Logs = {entries = {}, totalCount = 0, categoryCount = {}}

local function pushLog(text, color, category)
    if State.destroyed then return end
    local entry = {
        text = "[" .. os.date("%H:%M:%S") .. "] " .. text,
        raw = text,
        color = color or Color3.fromRGB(200,200,200),
        category = category or "SYS",
        time = tick(),
    }
    table.insert(Logs.entries, entry)
    if #Logs.entries > CFG.MaxBuffer then table.remove(Logs.entries, 1) end
    Logs.totalCount = Logs.totalCount + 1
    Logs.categoryCount[category] = (Logs.categoryCount[category] or 0) + 1
end

-- ============ HELPERS ============
local function truncate(s, max)
    s = tostring(s)
    if #s > max then return string.sub(s, 1, max) .. "...(+" .. (#s - max) .. ")" end
    return s
end

local function fmt(v, depth)
    depth = depth or 0
    if depth > 3 then return "..." end
    if type(v) == "Instance" then return v.Name end
    if type(v) == "table" then
        local p = {}
        for k, val in pairs(v) do table.insert(p, tostring(k).."="..fmt(val, depth + 1)) end
        return "{"..table.concat(p,",").."}"
    end
    return tostring(v)
end

local function hasKwWord(text, list)
    local low = string.lower(text)
    for _, kw in ipairs(list) do
        local kwLow = string.lower(kw)
        local padded = " " .. low .. " "
        if string.find(padded, "[^%a%d]" .. kwLow .. "[^%a%d]") then return kw end
    end
end

local function isIgnoredName(name, patterns)
    local low = string.lower(name)
    for _, pat in ipairs(patterns) do
        if string.find(low, string.lower(pat), 1, true) then return true end
    end
    return false
end

local function isIgnoredEquipItem(name)
    for _, item in ipairs(CFG.IgnoreEquipItems) do
        if name == item then return true end
    end
    return false
end

local function numAlmostEqual(a, b, tol)
    tol = tol or CFG.NumericTolerance
    if type(a) ~= "number" or type(b) ~= "number" then return false end
    return math.abs(a - b) < tol
end

local function isNumericNoise(oldStr, newStr)
    local o1, o2 = string.match(oldStr, "^([%d%.%-]+),(.+)$")
    local n1, n2 = string.match(newStr, "^([%d%.%-]+),(.+)$")
    if o1 and o2 and n1 and n2 then
        local a, b = tonumber(o1), tonumber(n1)
        if a and b and numAlmostEqual(a, b) and o2 == n2 then return true end
    end
    return false
end

local function diffTables(old, new, path)
    path = path or ""
    if type(old) ~= "table" or type(new) ~= "table" then
        if tostring(old) ~= tostring(new) then
            return {path..": "..fmt(old).." → "..fmt(new)}
        end
        return {}
    end
    local changes = {}
    local allKeys = {}
    for k in pairs(old) do allKeys[k] = true end
    for k in pairs(new) do allKeys[k] = true end
    for k in pairs(allKeys) do
        local o, n = old[k], new[k]
        local childPath = path == "" and tostring(k) or (path.."."..tostring(k))
        if type(o) == "table" and type(n) == "table" then
            local sub = diffTables(o, n, childPath)
            for _, s in ipairs(sub) do table.insert(changes, s) end
        elseif tostring(o) ~= tostring(n) then
            table.insert(changes, childPath..": "..fmt(o).." → "..fmt(n))
        end
    end
    return changes
end

local function addLog(text, color, category)
    if State.destroyed then return end
    if CFG.AlertMode then
        local kw = hasKwWord(text, CFG.AlertKeywords)
        if kw then
            color = Color3.fromRGB(255, 60, 60)
            text = "🚨 ["..kw.."] "..text
        end
    end
    pushLog(text, color, category or "SYS")
end

-- ============ GUI ============
local gui = Instance.new("ScreenGui")
gui.Name = "FullLiveScan"
gui.ResetOnSpawn = false
gui.DisplayOrder = 997
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = lp:WaitForChild("PlayerGui") end

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 310, 0, 420)
frame.Position = UDim2.new(0, 10, 0.05, 0)
frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.Active = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", frame)
stroke.Color = Color3.fromRGB(100, 200, 255)
stroke.Thickness = 1.5
stroke.Transparency = 0.4

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 30)
header.BackgroundTransparency = 1
header.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -140, 1, 0)
title.Position = UDim2.new(0, 8, 0, 0)
title.BackgroundTransparency = 1
title.Text = "⚡ LIVE SCAN v10"
title.TextColor3 = Color3.fromRGB(100, 200, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = header

local powerBtn = Instance.new("TextButton")
powerBtn.Size = UDim2.new(0, 42, 0, 22)
powerBtn.Position = UDim2.new(1, -102, 0, 4)
powerBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 40)
powerBtn.TextColor3 = Color3.new(1,1,1)
powerBtn.Text = "ON"
powerBtn.Font = Enum.Font.GothamBold
powerBtn.TextSize = 11
powerBtn.BorderSizePixel = 0
powerBtn.Parent = header
Instance.new("UICorner", powerBtn).CornerRadius = UDim.new(0, 6)

local collapse = Instance.new("TextButton")
collapse.Size = UDim2.new(0, 26, 0, 22)
collapse.Position = UDim2.new(1, -58, 0, 4)
collapse.BackgroundColor3 = Color3.fromRGB(60, 60, 70)
collapse.TextColor3 = Color3.new(1,1,1)
collapse.Text = "−"
collapse.Font = Enum.Font.GothamBold
collapse.TextSize = 16
collapse.BorderSizePixel = 0
collapse.Parent = header
Instance.new("UICorner", collapse).CornerRadius = UDim.new(0, 6)

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 26, 0, 22)
closeBtn.Position = UDim2.new(1, -30, 0, 4)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50)
closeBtn.TextColor3 = Color3.new(1,1,1)
closeBtn.Text = "×"
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 18
closeBtn.BorderSizePixel = 0
closeBtn.Parent = header
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local function fullKill()
    State.destroyed = true
    State.running = false
    -- v10.1 FIX: hapus typeof() check → langsung pcall
    for r, conn in pairs(_G._LS_hooks or {}) do
        pcall(function() conn:Disconnect() end)
    end
    _G._LS_hooks = nil
    pcall(function() gui:Destroy() end)
    print("[LiveScan v10] Full stop.")
end
_G._LiveScanner_v10_Cleanup = fullKill
closeBtn.MouseButton1Click:Connect(fullKill)

local function updatePowerBtn()
    if State.running and not State.paused then
        powerBtn.BackgroundColor3 = Color3.fromRGB(40, 130, 40)
        powerBtn.Text = "ON"
    elseif State.paused then
        powerBtn.BackgroundColor3 = Color3.fromRGB(200, 130, 40)
        powerBtn.Text = "HOLD"
    else
        powerBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 40)
        powerBtn.Text = "OFF"
    end
end

powerBtn.MouseButton1Click:Connect(function()
    if State.running then
        State.running = false
        addLog("⏹ STOPPED", Color3.fromRGB(255,150,150), "SYS")
    else
        State.running = true
        addLog("▶ STARTED", Color3.fromRGB(150,255,150), "SYS")
    end
    updatePowerBtn()
end)

-- Tab bar
local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -12, 0, 26)
tabBar.Position = UDim2.new(0, 6, 0, 32)
tabBar.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
tabBar.BorderSizePixel = 0
tabBar.Parent = frame
Instance.new("UICorner", tabBar).CornerRadius = UDim.new(0, 6)

local tabs = {
    {name="LOG", color=Color3.fromRGB(100, 200, 255)},
    {name="CFG", color=Color3.fromRGB(255, 200, 100)},
    {name="INFO", color=Color3.fromRGB(200, 255, 100)},
    {name="HOOK", color=Color3.fromRGB(255, 130, 200)},
}
local activeTab = "LOG"
local tabButtons = {}

for i, t in ipairs(tabs) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0.25, -4, 1, -4)
    btn.Position = UDim2.new((i-1) * 0.25, 2, 0, 2)
    btn.BackgroundColor3 = i == 1 and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(25, 25, 32)
    btn.TextColor3 = t.color
    btn.Text = t.name
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.BorderSizePixel = 0
    btn.Parent = tabBar
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    tabButtons[t.name] = btn
end

-- Search + Filter
local searchFrame = Instance.new("Frame")
searchFrame.Size = UDim2.new(1, -12, 0, 26)
searchFrame.Position = UDim2.new(0, 6, 0, 62)
searchFrame.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
searchFrame.BorderSizePixel = 0
searchFrame.Parent = frame
Instance.new("UICorner", searchFrame).CornerRadius = UDim.new(0, 6)

local searchBox = Instance.new("TextBox")
searchBox.Size = UDim2.new(1, -70, 1, -4)
searchBox.Position = UDim2.new(0, 6, 0, 2)
searchBox.BackgroundTransparency = 1
searchBox.Text = ""
searchBox.PlaceholderText = "🔍 Cari log..."
searchBox.TextColor3 = Color3.fromRGB(220, 220, 220)
searchBox.PlaceholderColor3 = Color3.fromRGB(120, 120, 130)
searchBox.Font = Enum.Font.Code
searchBox.TextSize = 11
searchBox.TextXAlignment = Enum.TextXAlignment.Left
searchBox.ClearTextOnFocus = false
searchBox.Parent = searchFrame

local filterBtn = Instance.new("TextButton")
filterBtn.Size = UDim2.new(0, 60, 1, -4)
filterBtn.Position = UDim2.new(1, -64, 0, 2)
filterBtn.BackgroundColor3 = Color3.fromRGB(60, 80, 130)
filterBtn.TextColor3 = Color3.new(1,1,1)
filterBtn.Text = "ALL"
filterBtn.Font = Enum.Font.GothamBold
filterBtn.TextSize = 10
filterBtn.BorderSizePixel = 0
filterBtn.Parent = searchFrame
Instance.new("UICorner", filterBtn).CornerRadius = UDim.new(0, 4)

local filterCycle = {"ALL","ATTR","STAT","REMOTE","MODEL","INV","PLAYER",
                     "HEALTH","CURRENCY","PATTERN","NET","ANOMALY","SYS","TOOL"}
local filterIdx = 1
local searchText = ""

searchBox:GetPropertyChangedSignal("Text"):Connect(function()
    searchText = string.lower(searchBox.Text)
end)
filterBtn.MouseButton1Click:Connect(function()
    filterIdx = filterIdx + 1
    if filterIdx > #filterCycle then filterIdx = 1 end
    filterBtn.Text = filterCycle[filterIdx]
end)

-- Content
local content = Instance.new("Frame")
content.Size = UDim2.new(1, -12, 1, -160)
content.Position = UDim2.new(0, 6, 0, 92)
content.BackgroundTransparency = 1
content.Parent = frame

local function makeScroll()
    local s = Instance.new("ScrollingFrame")
    s.Size = UDim2.new(1, 0, 1, 0)
    s.BackgroundTransparency = 1
    s.BorderSizePixel = 0
    s.ScrollBarThickness = 4
    s.CanvasSize = UDim2.new(0, 0, 0, 0)
    s.AutomaticCanvasSize = Enum.AutomaticSize.Y
    s.Parent = content
    local l = Instance.new("UIListLayout", s)
    l.Padding = UDim.new(0, 2)
    return s
end

local scroll = makeScroll(); scroll.Visible = true
local cfgFrame = makeScroll(); cfgFrame.Visible = false
local infoFrame = makeScroll(); infoFrame.Visible = false
local hookFrame = makeScroll(); hookFrame.Visible = false

-- Buttons
local btnPause = Instance.new("TextButton")
btnPause.Size = UDim2.new(0, 90, 0, 26)
btnPause.Position = UDim2.new(0, 6, 1, -32)
btnPause.BackgroundColor3 = Color3.fromRGB(40, 130, 40)
btnPause.TextColor3 = Color3.new(1,1,1)
btnPause.Text = "PAUSE"
btnPause.Font = Enum.Font.GothamBold
btnPause.TextSize = 11
btnPause.BorderSizePixel = 0
btnPause.Parent = frame
Instance.new("UICorner", btnPause).CornerRadius = UDim.new(0, 6)

local btnClear = Instance.new("TextButton")
btnClear.Size = UDim2.new(0, 90, 0, 26)
btnClear.Position = UDim2.new(0, 102, 1, -32)
btnClear.BackgroundColor3 = Color3.fromRGB(130, 40, 40)
btnClear.TextColor3 = Color3.new(1,1,1)
btnClear.Text = "CLEAR"
btnClear.Font = Enum.Font.GothamBold
btnClear.TextSize = 11
btnClear.BorderSizePixel = 0
btnClear.Parent = frame
Instance.new("UICorner", btnClear).CornerRadius = UDim.new(0, 6)

local btnCopy = Instance.new("TextButton")
btnCopy.Size = UDim2.new(0, 90, 0, 26)
btnCopy.Position = UDim2.new(1, -96, 1, -32)
btnCopy.BackgroundColor3 = Color3.fromRGB(40, 80, 160)
btnCopy.TextColor3 = Color3.new(1,1,1)
btnCopy.Text = "COPY ALL"
btnCopy.Font = Enum.Font.GothamBold
btnCopy.TextSize = 11
btnCopy.BorderSizePixel = 0
btnCopy.Parent = frame
Instance.new("UICorner", btnCopy).CornerRadius = UDim.new(0, 6)

-- Draggable
local dragging, dragStart, startPos
header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch
       or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true; dragStart = input.Position; startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
header.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.Touch
                     or input.UserInputType == Enum.UserInputType.MouseMovement) then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                                    startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

local collapsed = false
collapse.MouseButton1Click:Connect(function()
    collapsed = not collapsed
    if collapsed then
        frame.Size = UDim2.new(0, 310, 0, 30)
        collapse.Text = "+"
    else
        frame.Size = UDim2.new(0, 310, 0, 420)
        collapse.Text = "−"
    end
end)

for name, btn in pairs(tabButtons) do
    btn.MouseButton1Click:Connect(function()
        activeTab = name
        scroll.Visible = name == "LOG"
        cfgFrame.Visible = name == "CFG"
        infoFrame.Visible = name == "INFO"
        hookFrame.Visible = name == "HOOK"
        searchFrame.Visible = name == "LOG"
        for n, b in pairs(tabButtons) do
            b.BackgroundColor3 = n == name and Color3.fromRGB(50, 50, 60) or Color3.fromRGB(25, 25, 32)
        end
    end)
end

-- ============ RENDER LOG ============
local function renderLog()
    if State.destroyed then return end
    for _, c in ipairs(scroll:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    local shown = 0
    local curFilter = filterCycle[filterIdx]
    for i = #Logs.entries, 1, -1 do
        if shown >= CFG.MaxLines then break end
        local e = Logs.entries[i]
        local pass = true
        if curFilter ~= "ALL" and e.category ~= curFilter then pass = false end
        if pass and searchText ~= "" and not string.find(string.lower(e.text), searchText) then
            pass = false
        end
        if not pass then continue end

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -4, 0, 14)
        lbl.BackgroundTransparency = 1
        lbl.Text = e.text
        lbl.TextColor3 = e.color
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        lbl.LayoutOrder = -i
        lbl.Parent = scroll
        shown = shown + 1
    end
end

-- ============ TOGGLE ============
local function makeToggle(name, key, parent)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -4, 0, 26)
    row.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -50, 1, 0)
    lbl.Position = UDim2.new(0, 6, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = name
    lbl.TextColor3 = Color3.fromRGB(220, 220, 220)
    lbl.Font = Enum.Font.Code
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 40, 0, 20)
    btn.Position = UDim2.new(1, -44, 0, 3)
    btn.BackgroundColor3 = CFG[key] and Color3.fromRGB(40, 130, 40) or Color3.fromRGB(80, 40, 40)
    btn.TextColor3 = Color3.new(1,1,1)
    btn.Text = CFG[key] and "ON" or "OFF"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.BorderSizePixel = 0
    btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    btn.MouseButton1Click:Connect(function()
        CFG[key] = not CFG[key]
        btn.BackgroundColor3 = CFG[key] and Color3.fromRGB(40, 130, 40) or Color3.fromRGB(80, 40, 40)
        btn.Text = CFG[key] and "ON" or "OFF"
    end)
end

makeToggle("Player Attributes", "TrackAttrs", cfgFrame)
makeToggle("Leaderstats", "TrackStats", cfgFrame)
makeToggle("Humanoid", "TrackHumanoid", cfgFrame)
makeToggle("Models Sekitar", "TrackModels", cfgFrame)
makeToggle("Remote Hooks", "TrackRemotes", cfgFrame)
makeToggle("Inventory", "TrackInventory", cfgFrame)
makeToggle("Position (spam)", "TrackPosition", cfgFrame)
makeToggle("Track Players", "TrackPlayers", cfgFrame)
makeToggle("Track Health", "TrackHealth", cfgFrame)
makeToggle("Track Network", "TrackNetwork", cfgFrame)
makeToggle("Track Tool Equip", "TrackToolEquip", cfgFrame)
makeToggle("Alert Mode", "AlertMode", cfgFrame)
makeToggle("Currency Radar", "CurrencyRadar", cfgFrame)
makeToggle("SpeedHack Detect", "SpeedHackDetect", cfgFrame)
makeToggle("Pattern Detect", "PatternDetect", cfgFrame)

-- ============ INFO ============
local function renderInfo()
    if State.destroyed then return end
    for _, c in ipairs(infoFrame:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    local data = {
        "PlaceId: " .. game.PlaceId,
        "JobId: " .. tostring(game.JobId),
        "MaxPlayers: " .. tostring(game.MaxPlayers),
        "Player: " .. lp.Name .. " (" .. lp.UserId .. ")",
        "Total logs: " .. tostring(Logs.totalCount),
        "Scanner: " .. (State.running and "RUNNING" or "STOPPED"),
        "Ignore list: " .. #CFG.IgnoreRemotes .. " remotes",
        "--- Category Count ---",
    }
    for k, v in pairs(Logs.categoryCount) do
        if v > 0 then table.insert(data, "  " .. k .. ": " .. v) end
    end
    table.insert(data, "--- Player Attributes ---")
    for k, v in pairs(lp:GetAttributes()) do
        table.insert(data, "  " .. k .. " = " .. tostring(v))
    end
    for _, txt in ipairs(data) do
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -4, 0, 14)
        lbl.BackgroundTransparency = 1
        lbl.Text = txt
        lbl.TextColor3 = Color3.fromRGB(200, 220, 255)
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        lbl.Parent = infoFrame
    end
end

-- ============ HOOK ============
_G._LS_hooks = _G._LS_hooks or {}
local hookedRemotes = _G._LS_hooks
local remoteStats = {}
local remoteLastArgs = {}
local remoteLastTime = {}

local function renderHook()
    if State.destroyed then return end
    for _, c in ipairs(hookFrame:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    local list = {}
    for r in pairs(hookedRemotes) do
        table.insert(list, r.Name .. " [" .. (remoteStats[r] and remoteStats[r].count or 0) .. "]")
    end
    table.sort(list)
    local lbl0 = Instance.new("TextLabel")
    lbl0.Size = UDim2.new(1, -4, 0, 14)
    lbl0.BackgroundTransparency = 1
    lbl0.Text = "Hooked: " .. #list .. " (ignored: " .. #CFG.IgnoreRemotes .. ")"
    lbl0.TextColor3 = Color3.fromRGB(255, 130, 200)
    lbl0.Font = Enum.Font.GothamBold
    lbl0.TextSize = 11
    lbl0.TextXAlignment = Enum.TextXAlignment.Left
    lbl0.Parent = hookFrame
    for _, txt in ipairs(list) do
        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, -4, 0, 13)
        lbl.BackgroundTransparency = 1
        lbl.Text = "  " .. txt
        lbl.TextColor3 = Color3.fromRGB(200, 200, 200)
        lbl.Font = Enum.Font.Code
        lbl.TextSize = 10
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        lbl.Parent = hookFrame
    end
end

local function hookRemote(r)
    if hookedRemotes[r] then return end
    if not r:IsA("RemoteEvent") then return end
    if isIgnoredName(r.Name, CFG.IgnoreRemotes)
       or isIgnoredName(r.Name, CFG.IgnorePatterns) then
        hookedRemotes[r] = "IGNORED"
        return
    end

    remoteStats[r] = {count = 0, first = tick(), timestamps = {}, skipped = 0, silent = false, lastArgStr = nil}
    remoteLastArgs[r] = nil
    remoteLastTime[r] = 0

    local conn = r.OnClientEvent:Connect(function(...)
        if State.destroyed or not State.running or State.paused then return end
        if not CFG.TrackRemotes then return end

        local args = {...}
        local rs = remoteStats[r]
        rs.count = rs.count + 1

        local now = tick()
        table.insert(rs.timestamps, now)
        while #rs.timestamps > 50 do table.remove(rs.timestamps, 1) end
        local recent = 0
        for _, t in ipairs(rs.timestamps) do
            if now - t < CFG.HighFreqWindow then recent = recent + 1 end
        end

        if recent >= CFG.HighFreqThreshold then
            if not rs.silent then
                rs.silent = true
                addLog("🔇 AUTO-SILENT: "..r.Name.." ("..recent.."x/"..CFG.HighFreqWindow.."s)",
                       Color3.fromRGB(150, 150, 200), "SYS")
            end
            rs.skipped = (rs.skipped or 0) + 1
            return
        end

        local argStr = ""
        for _, a in ipairs(args) do argStr = argStr .. "|" .. fmt(a) end
        argStr = truncate(argStr, CFG.MaxArgLen)

        if rs.lastArgStr and isNumericNoise(rs.lastArgStr, argStr) then
            rs.skipped = (rs.skipped or 0) + 1
            return
        end

        if CFG.DedupeRemote then
            if remoteLastArgs[r] == argStr and (now - (remoteLastTime[r] or 0)) < CFG.DedupeWindow then
                rs.skipped = (rs.skipped or 0) + 1
                return
            end
            remoteLastArgs[r] = argStr
            remoteLastTime[r] = now
        end

        rs.lastArgStr = argStr

        local display
        if CFG.SmartDiff and #args >= 2 and type(args[2]) == "table" then
            local old = rs.lastTable
            if old then
                local changes = diffTables(old, args[2], "")
                local filtered = {}
                for _, c in ipairs(changes) do
                    local oldNum, newNum = c:match("([%d%.%-]+) %→ ([%d%.%-]+)")
                    if oldNum and newNum then
                        local a, b = tonumber(oldNum), tonumber(newNum)
                        if a and b and numAlmostEqual(a, b) then
                            goto continue
                        end
                    end
                    table.insert(filtered, c)
                    ::continue::
                end
                if #filtered == 0 then
                    rs.skipped = (rs.skipped or 0) + 1
                    return
                end
                local parts = {}
                for i = 1, math.min(#filtered, 5) do table.insert(parts, filtered[i]) end
                if #filtered > 5 then table.insert(parts, "...(+" .. (#filtered - 5) .. " more)") end
                display = table.concat(parts, " | ")
            else
                display = argStr
            end
            rs.lastTable = args[2]
        else
            display = argStr
        end

        addLog("⬇ " .. r.Name .. " | " .. display, Color3.fromRGB(255, 130, 200), "REMOTE")
    end)
    hookedRemotes[r] = conn
end

local function scanRemotes(parent, depth)
    if depth > 4 then return end
    for _, obj in ipairs(parent:GetChildren()) do
        if obj:IsA("RemoteEvent") then hookRemote(obj) end
        pcall(function() scanRemotes(obj, depth + 1) end)
    end
end
scanRemotes(RS, 0)

-- Button handlers
btnPause.MouseButton1Click:Connect(function()
    State.paused = not State.paused
    btnPause.Text = State.paused and "RESUME" or "PAUSE"
    btnPause.BackgroundColor3 = State.paused and Color3.fromRGB(200, 130, 40) or Color3.fromRGB(40, 130, 40)
    updatePowerBtn()
end)

btnClear.MouseButton1Click:Connect(function()
    Logs.entries = {}
    Logs.categoryCount = {}
    renderLog()
    btnClear.Text = "OK!"
    task.wait(0.6)
    btnClear.Text = "CLEAR"
end)

btnCopy.MouseButton1Click:Connect(function()
    local lines = {}
    for _, e in ipairs(Logs.entries) do table.insert(lines, e.text) end
    local text = table.concat(lines, "\n")
    local ok = pcall(function() setclipboard(text) end)
    btnCopy.Text = ok and "COPIED!" or "FAIL"
    task.wait(1)
    btnCopy.Text = "COPY ALL"
end)

-- ============ SNAPSHOT STATE ============
local lastSnapshot = {
    attrs = {}, stats = {}, nearby = {}, inventory = {},
    walkspeed = nil, jumppower = nil, seat = nil, position = nil,
    health = nil, ping = nil, tool = nil, currency = {},
    walkspeedWarned = false, jumppowerWarned = false,
}
local trackedPlayers = {}

-- ============ CORE SCAN ============
local function scanOnce()
    if State.destroyed or not State.running or State.paused then return end
    if not gui or not gui.Parent then fullKill(); return end

    local char = lp.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")

    -- ATTRS
    if CFG.TrackAttrs then
        for k, v in pairs(lp:GetAttributes()) do
            if isIgnoredName(k, CFG.IgnoreAttrPatterns) then
                lastSnapshot.attrs[k] = v
                continue
            end
            local old = lastSnapshot.attrs[k]
            if old == nil then
                lastSnapshot.attrs[k] = v
            elseif tostring(old) ~= tostring(v) then
                if type(v) == "number" and type(old) == "number" and numAlmostEqual(old, v) then
                    lastSnapshot.attrs[k] = v
                    continue
                end
                local color = Color3.fromRGB(255, 220, 100)
                if type(v) == "number" and type(old) == "number" then
                    color = v > old and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
                end
                addLog("ATTR "..k..": "..fmt(old).." → "..fmt(v), color, "ATTR")
                lastSnapshot.attrs[k] = v
            end
        end
    end

    -- STATS
    if CFG.TrackStats then
        local ls = lp:FindFirstChild("leaderstats")
        if ls then
            for _, v in ipairs(ls:GetChildren()) do
                local old = lastSnapshot.stats[v.Name]
                if old == nil then
                    lastSnapshot.stats[v.Name] = tostring(v.Value)
                elseif tostring(old) ~= tostring(v.Value) then
                    addLog("STAT "..v.Name..": "..tostring(old).." → "..tostring(v.Value),
                           Color3.fromRGB(100, 200, 255), "STAT")
                    lastSnapshot.stats[v.Name] = tostring(v.Value)
                end
            end
        end
    end

    -- HUMANOID
    if hum then
        if CFG.TrackHumanoid and lastSnapshot.walkspeed ~= hum.WalkSpeed then
            if lastSnapshot.walkspeed ~= nil 
               and math.abs(hum.WalkSpeed - lastSnapshot.walkspeed) >= 1 then
                addLog("WalkSpeed: "..string.format("%.1f", lastSnapshot.walkspeed)..
                       " → "..string.format("%.1f", hum.WalkSpeed),
                       Color3.fromRGB(255, 180, 100), "HEALTH")
            end
            lastSnapshot.walkspeed = hum.WalkSpeed
        end
        local seatStr = hum.SeatPart and hum.SeatPart.Name or "nil"
        if CFG.TrackHumanoid and lastSnapshot.seat ~= seatStr then
            if lastSnapshot.seat ~= nil then
                addLog("Seat: "..tostring(lastSnapshot.seat).." → "..seatStr,
                       Color3.fromRGB(200, 150, 255), "HEALTH")
            end
            lastSnapshot.seat = seatStr
        end
        if CFG.TrackHealth then
            local hp = math.floor(hum.Health)
            if lastSnapshot.health ~= hp then
                if lastSnapshot.health ~= nil then
                    local diff = hp - lastSnapshot.health
                    local color = diff < 0 and Color3.fromRGB(255, 80, 80) or Color3.fromRGB(80, 255, 80)
                    addLog("❤ HP: "..lastSnapshot.health.." → "..hp..
                           " ("..(diff > 0 and "+" or "")..diff..")", color, "HEALTH")
                end
                lastSnapshot.health = hp
            end
        end
        if CFG.SpeedHackDetect then
            if hum.WalkSpeed > CFG.MaxSpeedNormal and not lastSnapshot.walkspeedWarned then
                addLog("⚡ SPEED WARN: "..math.floor(hum.WalkSpeed),
                       Color3.fromRGB(255,200,50), "ANOMALY")
                lastSnapshot.walkspeedWarned = true
            elseif hum.WalkSpeed <= CFG.MaxSpeedNormal then
                lastSnapshot.walkspeedWarned = false
            end
            if hum.JumpPower and hum.JumpPower > CFG.MaxJumpNormal and not lastSnapshot.jumppowerWarned then
                addLog("⚡ JUMP WARN: "..math.floor(hum.JumpPower),
                       Color3.fromRGB(255,200,50), "ANOMALY")
                lastSnapshot.jumppowerWarned = true
            elseif hum.JumpPower and hum.JumpPower <= CFG.MaxJumpNormal then
                lastSnapshot.jumppowerWarned = false
            end
        end
    end

    -- NETWORK
    if CFG.TrackNetwork then
        pcall(function()
            local ping = Stats.Network.ServerStatsItem["Data Ping"]
            if ping then
                local val = math.floor(ping:GetValue())
                if lastSnapshot.ping ~= val then
                    if lastSnapshot.ping ~= nil and math.abs(val - lastSnapshot.ping) > 30 then
                        local color = val > 200 and Color3.fromRGB(255,100,100) or Color3.fromRGB(150,200,255)
                        addLog("📡 Ping: "..lastSnapshot.ping.." → "..val.."ms", color, "NET")
                    end
                    lastSnapshot.ping = val
                end
            end
        end)
    end

    -- TOOL
    if char and CFG.TrackToolEquip then
        local tool = char:FindFirstChildOfClass("Tool")
        local tname = tool and tool.Name or nil
        if lastSnapshot.tool ~= tname then
            if lastSnapshot.tool ~= nil then
                addLog("🔧 Tool: "..tostring(lastSnapshot.tool).." → "..tostring(tname),
                       Color3.fromRGB(255,220,100), "TOOL")
            end
            lastSnapshot.tool = tname
        end
    end

    -- PLAYERS
    if CFG.TrackPlayers then
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local current = {}
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= lp then
                    local pc = p.Character
                    local pr = pc and pc:FindFirstChild("HumanoidRootPart")
                    if pr and (pr.Position - root.Position).Magnitude < CFG.Radius then
                        current[p.UserId] = true
                    end
                end
            end
            for uid in pairs(current) do
                if not trackedPlayers[uid] then
                    trackedPlayers[uid] = true
                    local p = Players:GetPlayerByUserId(uid)
                    addLog("👤 + "..(p and p.Name or uid), Color3.fromRGB(100,255,200), "PLAYER")
                end
            end
            for uid in pairs(trackedPlayers) do
                if not current[uid] then
                    trackedPlayers[uid] = nil
                    local p = Players:GetPlayerByUserId(uid)
                    addLog("👤 − "..(p and p.Name or uid), Color3.fromRGB(255,150,150), "PLAYER")
                end
            end
        end
    end

    -- NEARBY MODELS
    if CFG.TrackModels then
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local current = {}
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj:IsA("Model") and obj ~= char
                   and not Players:GetPlayerFromCharacter(obj) then
                    local p = obj.PrimaryPart or obj:FindFirstChild("HumanoidRootPart")
                               or obj:FindFirstChildWhichIsA("BasePart", true)
                    if p and (p.Position - root.Position).Magnitude < CFG.Radius then
                        current[obj.Name] = true
                    end
                end
            end
            for n in pairs(current) do
                if not lastSnapshot.nearby[n] then
                    addLog("+ "..n, Color3.fromRGB(100,255,200), "MODEL")
                end
            end
            for n in pairs(lastSnapshot.nearby) do
                if not current[n] then
                    addLog("− "..n, Color3.fromRGB(255,150,150), "MODEL")
                end
            end
            lastSnapshot.nearby = current
        end
    end

    -- INVENTORY
    if CFG.TrackInventory then
        local function scanContainer(c, label)
            if not c then return end
            for _, item in ipairs(c:GetChildren()) do
                if label == "EQ" and isIgnoredEquipItem(item.Name) then continue end
                local id = label..":"..item.Name
                if not lastSnapshot.inventory[id] then
                    lastSnapshot.inventory[id] = true
                    addLog("INV + "..id, Color3.fromRGB(150,255,150), "INV")
                end
            end
        end
        scanContainer(lp:FindFirstChild("Backpack"), "BP")
        if char then scanContainer(char, "EQ") end
    end

    -- CURRENCY
    if CFG.CurrencyRadar then
        local function check(name, value)
            local lower = string.lower(name)
            for _, kw in ipairs(CFG.CurrencyKeywords) do
                if string.find(lower, kw, 1, true) then
                    local old = lastSnapshot.currency[name]
                    local num = tonumber(value)
                    if num and old then
                        local diff = num - old
                        if math.abs(diff) >= 1 then
                            local color = diff > 0 and Color3.fromRGB(100,255,100) or Color3.fromRGB(255,120,120)
                            addLog((diff > 0 and "📈 " or "📉 ")..name..": "..old.." → "..num..
                                   " ("..(diff>0 and "+" or "")..diff..")", color, "CURRENCY")
                        end
                    end
                    if num then lastSnapshot.currency[name] = num end
                    return
                end
            end
        end
        local ls = lp:FindFirstChild("leaderstats")
        if ls then
            for _, v in ipairs(ls:GetChildren()) do check(v.Name, v.Value) end
        end
        for k, v in pairs(lp:GetAttributes()) do check(k, v) end
    end

    -- POSITION
    if CFG.TrackPosition then
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            local posStr = string.format("(%.0f,%.0f,%.0f)",
                root.Position.X, root.Position.Y, root.Position.Z)
            if lastSnapshot.position ~= posStr then
                addLog("POS "..posStr, Color3.fromRGB(180,180,180), "POS")
                lastSnapshot.position = posStr
            end
        end
    end
end

-- ============ SCAN LOOP ============
task.spawn(function()
    while not State.destroyed do
        task.wait(CFG.ScanInterval)
        if State.running and not State.paused then
            pcall(scanOnce)
        end
    end
end)

-- ============ RENDER LOOPS ============
task.spawn(function()
    while not State.destroyed do
        task.wait(CFG.RenderInterval)
        if State.running and activeTab == "LOG" then renderLog() end
    end
end)

task.spawn(function()
    while not State.destroyed do
        task.wait(CFG.InfoInterval)
        if State.destroyed then break end
        if activeTab == "INFO" then renderInfo() end
    end
end)

task.spawn(function()
    while not State.destroyed do
        task.wait(CFG.HookInterval)
        if State.destroyed then break end
        if activeTab == "HOOK" then renderHook() end
    end
end)

-- Initial render
renderLog()
renderInfo()
renderHook()

print("⚡ [LiveScan v10] Loaded! Lightweight + Anti-spam AKTIF.")
print("   × = full stop | ON/OFF = toggle | PAUSE = pause scan")
