--[[
    Local ESP — Boxes + Name + Distance
    Targets: workspace.SCPs.Humanoids + workspace.SCPs.Objects
    Fully client-sided — no server detection.
--]]

local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local UserInput    = game:GetService("UserInputService")
local CoreGui      = game:GetService("CoreGui")
local Workspace    = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- ─── Config ───────────────────────────────────────────────────────────────────

local CFG = {
    NameColor     = Color3.fromRGB(255, 100, 100),
    DistColor     = Color3.fromRGB(180, 180, 180),

    -- Highlights (Humanoid SCPs = red, Object SCPs = orange)
    CharHL_Fill         = Color3.fromRGB(220, 40,  40),
    CharHL_Outline      = Color3.fromRGB(255, 80,  80),
    CharHL_FillTransp   = 0.72,  -- mostly transparent tint
    CharHL_OutlineTransp= 0.0,

    ObjHL_Fill          = Color3.fromRGB(255, 140,  0),
    ObjHL_Outline       = Color3.fromRGB(255, 210, 60),
    ObjHL_FillTransp    = 0.78,
    ObjHL_OutlineTransp = 0.0,
}

-- ─── Per-SCP toggles (set false to hide that SCP entirely) ────────────────────

local ENABLED = {
    -- Humanoids
    SCP049  = true,
    SCP096  = true,
    SCP106  = true,
    SCP173  = true,
    SCP689  = true,
    Unclean = false,
    -- Objects
    SCP008   = false,
    SCP018   = true,
    SCP035   = true,
    SCP093   = false,
    SCP1182  = true,
    SCP151   = false,
    SCP2207  = true,
    SCP409   = true,
    SCP427   = true,
    SCP513   = true,
    SCP714   = true,
    SCP914   = false,
    SCP963   = true,
}

-- ─── Debris name → SCP display name ──────────────────────────────────────────
-- When an Object SCP is dropped it lands in workspace.Debris under a new name.
-- Add entries here for every droppable object SCP.

local DEBRIS_MAP = {
    ["Plastic Knife"]  = "SCP2207",
    ["Ornate Locket"] = "SCP427",
    ["Ornate Amulet"] = "SCP963",
    ["Apparatus"] = "SCP1182",
    ["Disc"] = "SCP093",
    ["Jade Bracelet"] = "SCP714",
    ["Porcelain Mask"] = "SCP035",
    ["Rubber Ball"] = "SCP018",
    ["Rusty Bell"] = "SCP513",




    

    
    -- add more as needed:
    -- ["Example Name"] = "SCP###",
}

-- ─── Custom Debris items (non-SCP objects in workspace.Debris) ───────────────
-- Any model whose name appears here will get ESP when it lands in workspace.Debris.
-- The display label is what shows on the billboard and in the menu.
-- Toggle each entry on/off in the menu at runtime, or set ENABLED["DEBRIS_<name>"]
-- to false in the script to start it disabled.

local DEBRIS_EXTRA = {
    -- Pistols
    ["FN Five-Seven"]  = "FN Five-Seven",
    ["Glock 17"]       = "Glock 17",
    ["HK USP"]         = "HK USP",
    ["M1911"]          = "M1911",
    -- Rifles
    ["AK-12"]          = "AK-12",
    ["AUG A2"]         = "AUG A2",
    ["FN FAL"]         = "FN FAL",
    ["FN FNC"]         = "FN FNC",
    ["FN SCAR-H"]      = "FN SCAR-H",
    ["HK416"]          = "HK416",
    ["M240B"]          = "M240B",
    ["M4A1"]           = "M4A1",
    ["ShAK-12"]        = "ShAK-12",
    -- SMGs
    ["AS VAL"]         = "AS VAL",
    ["FN P90"]         = "FN P90",
    ["MP5A3"]          = "MP5A3",
    ["MP7A2"]          = "MP7A2",
    ["SR2M"]           = "SR2M",
    ["UMP-45"]         = "UMP-45",
    -- Shotguns
    ["M1014"]          = "M1014",
    ["M870 MLOK"]      = "M870 MLOK",
    ["Mossberg 500"]   = "Mossberg 500",
    ["SPAS-12"]        = "SPAS-12",
    -- Crafting / Misc
    ["Battery"]        = "Battery",
    ["Cog"]            = "Cog",
    ["Fabric"]         = "Fabric",
    ["Glass Pane"]     = "Glass Pane",
    ["Metal Scrap"]    = "Metal Scrap",
    ["Plastic Scrap"]  = "Plastic Scrap",
    ["Putty"]          = "Putty",
    ["Spring"]         = "Spring",
    ["Wires"]          = "Wires",
    ["Wooden Plank"]   = "Wooden Plank",
}

-- Register DEBRIS_EXTRA keys into ENABLED (default true) so the menu can toggle them
for modelName in DEBRIS_EXTRA do
    local key = "DEBRIS_" .. modelName
    if ENABLED[key] == nil then
        ENABLED[key] = true
    end
end

-- ─── Toggle (H = hide/show ESP, Insert = open/close settings menu) ─────────────
-- Insert is used for the menu because Shift keys are often consumed by game
-- sprint bindings, making gameProcessed = true and blocking the handler.

local espVisible = true
local ppEnabled  = true  -- toggle ProximityPrompt infinite-range patching

-- forward-declared; assigned after buildMenu is defined below
local toggleMenu = nil

UserInput.InputBegan:Connect(function(input, gameProcessed)
    -- H: toggle ESP visibility (respect gameProcessed so chat doesn't interfere)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.H then
        espVisible = not espVisible
        print("[ESP] " .. (espVisible and "Shown" or "Hidden"))
    end
    -- J: open/close menu — intentionally ignores gameProcessed so it always works
    if input.KeyCode == Enum.KeyCode.J then
        if toggleMenu then toggleMenu() end
    end
end)

-- ─── State ────────────────────────────────────────────────────────────────────

local tracked = {}

-- ─── Group Checker Config + Alert System ────────────────────────────────────
local GROUP_ID     = 4743750
local TARGET_RANKS = {[7]=true,[8]=true,[9]=true,[10]=true,[11]=true,[255]=true}

-- Toast notification that slides in from the top-right and auto-dismisses after 5 s
local function showAlert(message)
    local ag            = Instance.new("ScreenGui")
    ag.Name             = "ESP_Alert"
    ag.ResetOnSpawn     = false
    ag.DisplayOrder     = 1000
    ag.IgnoreGuiInset   = true
    ag.Parent           = CoreGui

    local f             = Instance.new("Frame")
    f.Size              = UDim2.new(0, 290, 0, 44)
    f.Position          = UDim2.new(1, -300, 0, 12)
    f.BackgroundColor3  = Color3.fromRGB(18, 52, 22)
    f.BorderSizePixel   = 0
    f.Parent            = ag
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 7); c.Parent = f end

    -- drop shadow
    local sh            = Instance.new("Frame")
    sh.Size             = UDim2.new(1, 6, 1, 6)
    sh.Position         = UDim2.new(0, -3, 0, -3)
    sh.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    sh.BackgroundTransparency = 0.6
    sh.BorderSizePixel  = 0
    sh.ZIndex           = f.ZIndex - 1
    sh.Parent           = f
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 9); c.Parent = sh end

    -- green left accent
    local strip         = Instance.new("Frame")
    strip.Size          = UDim2.new(0, 4, 1, -10)
    strip.Position      = UDim2.new(0, 5, 0, 5)
    strip.BackgroundColor3 = Color3.fromRGB(60, 220, 90)
    strip.BorderSizePixel = 0
    strip.Parent        = f
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 2); c.Parent = strip end

    local icon          = Instance.new("TextLabel")
    icon.Size           = UDim2.new(0, 24, 1, 0)
    icon.Position       = UDim2.new(0, 16, 0, 0)
    icon.BackgroundTransparency = 1
    icon.Text           = "!"
    icon.TextColor3     = Color3.fromRGB(60, 220, 90)
    icon.Font           = Enum.Font.GothamBold
    icon.TextSize       = 18
    icon.TextYAlignment = Enum.TextYAlignment.Center
    icon.Parent         = f

    local lbl           = Instance.new("TextLabel")
    lbl.Size            = UDim2.new(1, -48, 1, 0)
    lbl.Position        = UDim2.new(0, 42, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text            = message
    lbl.TextColor3      = Color3.fromRGB(110, 255, 130)
    lbl.Font            = Enum.Font.GothamBold
    lbl.TextSize        = 13
    lbl.TextXAlignment  = Enum.TextXAlignment.Left
    lbl.TextYAlignment  = Enum.TextYAlignment.Center
    lbl.TextWrapped     = true
    lbl.Parent          = f

    -- fade out after 4 s
    task.delay(4, function()
        if not ag.Parent then return end
        local ts = game:GetService("TweenService")
        ts:Create(f, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
        ts:Create(lbl, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
        ts:Create(icon, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
        task.delay(0.5, function() ag:Destroy() end)
    end)
end

-- Checks a single player's rank and fires an alert if they match
local function checkPlayerRank(plr)
    local ok, rank = pcall(function() return plr:GetRankInGroup(GROUP_ID) end)
    if ok and TARGET_RANKS[rank] then
        showAlert("Player found: " .. plr.Name .. "  [rank " .. rank .. "]")
    end
end

-- ─── Team Checker Config ─────────────────────────────────────────────────────
local TARGET_TEAMS = {["Trainer"] = true, ["Trainee"] = true}

local function checkPlayerTeam(plr)
    local team = plr.Team
    if team and TARGET_TEAMS[team.Name] then
        showAlert("Team member found: " .. plr.Name .. "  [" .. team.Name .. "]")
    end
end

-- Check everyone already in the server on script load
for _, plr in Players:GetPlayers() do
    task.spawn(checkPlayerRank, plr)
    task.spawn(checkPlayerTeam, plr)
end
-- Alert whenever a new player joins mid-session
Players.PlayerAdded:Connect(function(plr)
    task.spawn(checkPlayerRank, plr)
    task.spawn(checkPlayerTeam, plr)
end)

-- ─── Settings Menu ───────────────────────────────────────────────────────────
-- RightShift opens/closes the menu.
-- Every toggle writes directly into the live ENABLED table, espVisible, or ppEnabled.
-- CFG colors/transparencies are script-side only (edit them at the top of this file).

local menuVisible = false
local _menuGui    = nil

local function closeMenu()
    menuVisible = false
    if _menuGui then
        _menuGui:Destroy()
        _menuGui = nil
    end
end

local function buildMenu()
    -- Destroy any existing instance first
    if _menuGui then _menuGui:Destroy() end

    local sg                    = Instance.new("ScreenGui")
    sg.Name                     = "ESP_Menu"
    sg.ResetOnSpawn             = false
    sg.ZIndexBehavior           = Enum.ZIndexBehavior.Sibling
    sg.IgnoreGuiInset           = true
    sg.DisplayOrder             = 999          -- render above all game UI
    sg.Parent                   = CoreGui

    local main                  = Instance.new("Frame")
    main.Name                   = "Main"
    main.Size                   = UDim2.new(0, 320, 0, 500)
    main.Position               = UDim2.new(0.5, -160, 0.5, -250)
    main.BackgroundColor3       = Color3.fromRGB(15, 15, 15)
    main.BackgroundTransparency = 0.08
    main.BorderSizePixel        = 0
    main.ClipsDescendants       = false
    main.Active                 = true
    main.Parent                 = sg
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = main end
    do  -- drop shadow
        local sh = Instance.new("Frame")
        sh.Size = UDim2.new(1, 8, 1, 8)
        sh.Position = UDim2.new(0, -4, 0, -4)
        sh.BackgroundColor3 = Color3.fromRGB(0,0,0)
        sh.BackgroundTransparency = 0.55
        sh.BorderSizePixel = 0
        sh.ZIndex = main.ZIndex - 1
        sh.Parent = main
        do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = sh end
    end

    -- ── Draggable header ──────────────────────────────────────────────────────
    local hdr                   = Instance.new("Frame")
    hdr.Name                    = "Header"
    hdr.Size                    = UDim2.new(1, 0, 0, 36)
    hdr.BackgroundColor3        = Color3.fromRGB(28, 28, 32)
    hdr.BorderSizePixel         = 0
    hdr.Active                  = true
    hdr.Parent                  = main
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = hdr end

    -- Extend header rect down to cover corner gap between header and body
    local hdrFill = Instance.new("Frame")
    hdrFill.Size = UDim2.new(1, 0, 0, 10)
    hdrFill.Position = UDim2.new(0, 0, 1, -10)
    hdrFill.BackgroundColor3 = Color3.fromRGB(28, 28, 32)
    hdrFill.BorderSizePixel = 0
    hdrFill.Parent = hdr

    local title                 = Instance.new("TextLabel")
    title.Size                  = UDim2.new(1, -80, 1, 0)
    title.Position              = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text                  = "ESP Settings"
    title.TextColor3            = Color3.fromRGB(230, 230, 230)
    title.Font                  = Enum.Font.GothamBold
    title.TextSize              = 15
    title.TextXAlignment        = Enum.TextXAlignment.Left
    title.Parent                = hdr

    local hint                  = Instance.new("TextLabel")
    hint.Size                   = UDim2.new(1, -80, 0, 12)
    hint.Position               = UDim2.new(0, 12, 1, -13)
    hint.BackgroundTransparency = 1
    hint.Text                   = "J = toggle menu  |  drag header to move"
    hint.TextColor3             = Color3.fromRGB(120, 120, 120)
    hint.Font                   = Enum.Font.Gotham
    hint.TextSize               = 10
    hint.TextXAlignment         = Enum.TextXAlignment.Left
    hint.Parent                 = hdr

    -- Close button (X)
    local closeBtn              = Instance.new("TextButton")
    closeBtn.Size               = UDim2.new(0, 28, 0, 28)
    closeBtn.Position           = UDim2.new(1, -34, 0.5, -14)
    closeBtn.BackgroundColor3   = Color3.fromRGB(180, 45, 45)
    closeBtn.BorderSizePixel    = 0
    closeBtn.Text               = "X"
    closeBtn.TextColor3         = Color3.fromRGB(255, 255, 255)
    closeBtn.Font               = Enum.Font.GothamBold
    closeBtn.TextSize           = 14
    closeBtn.Parent             = hdr
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = closeBtn end
    closeBtn.MouseButton1Click:Connect(closeMenu)

    -- Drag logic
    local dragging, dragStart, startPos = false, nil, nil
    hdr.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging  = true
            dragStart = inp.Position
            startPos  = main.Position
        end
    end)
    hdr.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
    UserInput.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = inp.Position - dragStart
            main.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)

    -- ── Scrollable body ───────────────────────────────────────────────────────
    local scroll                        = Instance.new("ScrollingFrame")
    scroll.Size                         = UDim2.new(1, -10, 1, -44)
    scroll.Position                     = UDim2.new(0, 5, 0, 40)
    scroll.BackgroundTransparency       = 1
    scroll.BorderSizePixel              = 0
    scroll.ScrollBarThickness           = 4
    scroll.ScrollBarImageColor3         = Color3.fromRGB(80, 80, 80)
    scroll.CanvasSize                   = UDim2.new(0, 0, 0, 0)
    scroll.AutomaticCanvasSize          = Enum.AutomaticSize.Y
    scroll.ElasticBehavior              = Enum.ElasticBehavior.Never
    scroll.Parent                       = main

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 4); pad.PaddingBottom = UDim.new(0, 4)
    pad.PaddingLeft = UDim.new(0, 2); pad.PaddingRight = UDim.new(0, 2)
    pad.Parent = scroll

    local layout        = Instance.new("UIListLayout")
    layout.Padding      = UDim.new(0, 3)
    layout.SortOrder    = Enum.SortOrder.LayoutOrder
    layout.Parent       = scroll

    local rowIdx = 0

    local function section(title)
        rowIdx += 1
        local f             = Instance.new("Frame")
        f.Size              = UDim2.new(1, 0, 0, 24)
        f.BackgroundColor3  = Color3.fromRGB(28, 28, 34)
        f.BorderSizePixel   = 0
        f.LayoutOrder       = rowIdx
        f.Parent            = scroll
        do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 5); c.Parent = f end
        -- left accent bar
        local accent        = Instance.new("Frame")
        accent.Size         = UDim2.new(0, 3, 1, -6)
        accent.Position     = UDim2.new(0, 4, 0, 3)
        accent.BackgroundColor3 = Color3.fromRGB(255, 190, 40)
        accent.BorderSizePixel  = 0
        accent.Parent       = f
        do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 2); c.Parent = accent end
        local lbl           = Instance.new("TextLabel")
        lbl.Size            = UDim2.new(1, -18, 1, 0)
        lbl.Position        = UDim2.new(0, 14, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text            = title
        lbl.TextColor3      = Color3.fromRGB(255, 200, 60)
        lbl.Font            = Enum.Font.GothamBold
        lbl.TextSize        = 12
        lbl.TextXAlignment  = Enum.TextXAlignment.Left
        lbl.Parent          = f
    end

    local function toggle(label, getter, setter)
        rowIdx += 1
        local f             = Instance.new("Frame")
        f.Size              = UDim2.new(1, 0, 0, 26)
        f.BackgroundColor3  = Color3.fromRGB(22, 22, 25)
        f.BackgroundTransparency = 0.3
        f.BorderSizePixel   = 0
        f.LayoutOrder       = rowIdx
        f.Parent            = scroll
        do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 5); c.Parent = f end

        local lbl           = Instance.new("TextLabel")
        lbl.Size            = UDim2.new(1, -62, 1, 0)
        lbl.Position        = UDim2.new(0, 10, 0, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text            = label
        lbl.TextColor3      = Color3.fromRGB(210, 210, 210)
        lbl.Font            = Enum.Font.Gotham
        lbl.TextSize        = 12
        lbl.TextXAlignment  = Enum.TextXAlignment.Left
        lbl.TextYAlignment  = Enum.TextYAlignment.Center
        lbl.Parent          = f

        local btn           = Instance.new("TextButton")
        btn.Size            = UDim2.new(0, 48, 0, 20)
        btn.Position        = UDim2.new(1, -54, 0.5, -10)
        btn.BorderSizePixel = 0
        btn.Font            = Enum.Font.GothamBold
        btn.TextSize        = 12
        btn.AutoButtonColor = false
        btn.Parent          = f
        do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = btn end

        local function refresh()
            local v = getter()
            btn.Text             = v and "ON" or "OFF"
            btn.BackgroundColor3 = v and Color3.fromRGB(40, 160, 60) or Color3.fromRGB(160, 40, 40)
            btn.TextColor3       = Color3.fromRGB(255, 255, 255)
        end
        refresh()
        btn.MouseButton1Click:Connect(function()
            setter(not getter())
            refresh()
        end)
        -- Hover tint
        btn.MouseEnter:Connect(function()
            btn.BackgroundTransparency = 0.25
        end)
        btn.MouseLeave:Connect(function()
            btn.BackgroundTransparency = 0
        end)
    end

    -- ── Global ────────────────────────────────────────────────────────────────
    section("  GLOBAL")
    toggle("ESP Visible  (H key)",
        function() return espVisible end,
        function(v) espVisible = v end)
    toggle("PP Patcher  (infinite range / instant)",
        function() return ppEnabled end,
        function(v) ppEnabled = v end)

    -- ── Humanoid SCPs ─────────────────────────────────────────────────────────
    section("  HUMANOID SCPs")
    for _, k in {"SCP049","SCP096","SCP106","SCP173","SCP689","Unclean"} do
        local kk = k  -- capture for closure
        toggle(kk,
            function() return ENABLED[kk] ~= false end,
            function(v) ENABLED[kk] = v end)
    end

    -- ── Object SCPs ───────────────────────────────────────────────────────────
    section("  OBJECT SCPs")
    for _, k in {"SCP008","SCP018","SCP035","SCP093","SCP1182","SCP151",
                  "SCP2207","SCP409","SCP427","SCP513","SCP714","SCP914","SCP963"} do
        local kk = k
        toggle(kk,
            function() return ENABLED[kk] ~= false end,
            function(v) ENABLED[kk] = v end)
    end

    -- ── Custom Debris ─────────────────────────────────────────────────────────
    section("  CUSTOM DEBRIS")
    local hasExtra = false
    for modelName, displayLabel in DEBRIS_EXTRA do
        hasExtra = true
        local key = "DEBRIS_" .. modelName
        toggle(displayLabel .. "  (" .. modelName .. ")",
            function() return ENABLED[key] ~= false end,
            function(v) ENABLED[key] = v end)
    end
    if not hasExtra then
        rowIdx += 1
        local noneHint                  = Instance.new("TextLabel")
        noneHint.Size                   = UDim2.new(1, 0, 0, 22)
        noneHint.BackgroundTransparency = 1
        noneHint.Text                   = "  Add entries to DEBRIS_EXTRA in the script"
        noneHint.TextColor3             = Color3.fromRGB(90, 90, 90)
        noneHint.Font                   = Enum.Font.Gotham
        noneHint.TextSize               = 11
        noneHint.TextXAlignment         = Enum.TextXAlignment.Left
        noneHint.LayoutOrder            = rowIdx
        noneHint.Parent                 = scroll
    end

    -- ── Server Checker ────────────────────────────────────────────────────────
    -- Scans all players for target ranks in group 4743750. Also runs on menu open.

    section("  SERVER CHECKER")

    -- Status label
    rowIdx += 1
    local statusFrame                    = Instance.new("Frame")
    statusFrame.Size                     = UDim2.new(1, 0, 0, 28)
    statusFrame.BackgroundColor3         = Color3.fromRGB(18, 18, 22)
    statusFrame.BackgroundTransparency   = 0.2
    statusFrame.BorderSizePixel          = 0
    statusFrame.LayoutOrder              = rowIdx
    statusFrame.Parent                   = scroll
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 5); c.Parent = statusFrame end

    local statusLbl                      = Instance.new("TextLabel")
    statusLbl.Size                       = UDim2.new(1, -10, 1, 0)
    statusLbl.Position                   = UDim2.new(0, 10, 0, 0)
    statusLbl.BackgroundTransparency     = 1
    statusLbl.Text                       = "Press SCAN to check the server"
    statusLbl.TextColor3                 = Color3.fromRGB(130, 130, 130)
    statusLbl.Font                       = Enum.Font.Gotham
    statusLbl.TextSize                   = 11
    statusLbl.TextXAlignment             = Enum.TextXAlignment.Left
    statusLbl.TextYAlignment             = Enum.TextYAlignment.Center
    statusLbl.Parent                     = statusFrame

    -- Results container (grows with results)
    rowIdx += 1
    local resultsContainer               = Instance.new("Frame")
    resultsContainer.Size                = UDim2.new(1, 0, 0, 0)
    resultsContainer.AutomaticSize       = Enum.AutomaticSize.Y
    resultsContainer.BackgroundTransparency = 1
    resultsContainer.BorderSizePixel     = 0
    resultsContainer.LayoutOrder         = rowIdx
    resultsContainer.Parent              = scroll
    do
        local rl = Instance.new("UIListLayout")
        rl.Padding = UDim.new(0, 2)
        rl.SortOrder = Enum.SortOrder.LayoutOrder
        rl.Parent = resultsContainer
    end

    -- Scan button
    rowIdx += 1
    local scanBtn                        = Instance.new("TextButton")
    scanBtn.Size                         = UDim2.new(1, 0, 0, 30)
    scanBtn.BackgroundColor3             = Color3.fromRGB(35, 110, 200)
    scanBtn.BorderSizePixel              = 0
    scanBtn.Text                         = "SCAN SERVER"
    scanBtn.TextColor3                   = Color3.fromRGB(255, 255, 255)
    scanBtn.Font                         = Enum.Font.GothamBold
    scanBtn.TextSize                     = 13
    scanBtn.AutoButtonColor              = false
    scanBtn.LayoutOrder                  = rowIdx
    scanBtn.Parent                       = scroll
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 5); c.Parent = scanBtn end
    scanBtn.MouseEnter:Connect(function() scanBtn.BackgroundTransparency = 0.2 end)
    scanBtn.MouseLeave:Connect(function() scanBtn.BackgroundTransparency = 0   end)

    local function doScan()
        for _, ch in resultsContainer:GetChildren() do
            if not ch:IsA("UIListLayout") then ch:Destroy() end
        end
        statusLbl.Text       = "Scanning " .. #Players:GetPlayers() .. " players..."
        statusLbl.TextColor3 = Color3.fromRGB(220, 200, 60)
        scanBtn.Text         = "SCANNING..."
        scanBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)

        task.spawn(function()
            local found = {}
            for _, plr in Players:GetPlayers() do
                local ok, rank = pcall(function() return plr:GetRankInGroup(GROUP_ID) end)
                if ok and TARGET_RANKS[rank] then
                    table.insert(found, {name = plr.Name, rank = rank})
                end
            end

            if #found == 0 then
                statusLbl.Text       = "No target-rank members in server"
                statusLbl.TextColor3 = Color3.fromRGB(180, 80, 80)
            else
                statusLbl.Text       = "FOUND  —  " .. #found .. " member" .. (#found == 1 and "" or "s")
                statusLbl.TextColor3 = Color3.fromRGB(80, 230, 100)
                for ri, entry in found do
                    local row            = Instance.new("Frame")
                    row.Size             = UDim2.new(1, 0, 0, 26)
                    row.BackgroundColor3 = Color3.fromRGB(20, 55, 25)
                    row.BorderSizePixel  = 0
                    row.LayoutOrder      = ri
                    row.Parent           = resultsContainer
                    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = row end
                    local strip          = Instance.new("Frame")
                    strip.Size           = UDim2.new(0, 3, 1, -6)
                    strip.Position       = UDim2.new(0, 4, 0, 3)
                    strip.BackgroundColor3 = Color3.fromRGB(60, 220, 90)
                    strip.BorderSizePixel  = 0
                    strip.Parent         = row
                    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 2); c.Parent = strip end
                    local nameLbl        = Instance.new("TextLabel")
                    nameLbl.Size         = UDim2.new(1, -18, 1, 0)
                    nameLbl.Position     = UDim2.new(0, 14, 0, 0)
                    nameLbl.BackgroundTransparency = 1
                    nameLbl.Text         = entry.name .. "  [rank " .. entry.rank .. "]"
                    nameLbl.TextColor3   = Color3.fromRGB(100, 245, 120)
                    nameLbl.Font         = Enum.Font.GothamBold
                    nameLbl.TextSize     = 12
                    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
                    nameLbl.TextYAlignment = Enum.TextYAlignment.Center
                    nameLbl.Parent       = row
                end
            end
            scanBtn.Text             = "SCAN SERVER"
            scanBtn.BackgroundColor3 = Color3.fromRGB(35, 110, 200)
        end)
    end

    scanBtn.MouseButton1Click:Connect(doScan)

    -- Auto-scan when the menu opens
    doScan()

    -- ── Team Checker ──────────────────────────────────────────────────────────
    -- Scans all players for "Trainer" or "Trainee" team membership.

    section("  TEAM CHECKER")

    rowIdx += 1
    local teamStatusFrame                  = Instance.new("Frame")
    teamStatusFrame.Size                   = UDim2.new(1, 0, 0, 28)
    teamStatusFrame.BackgroundColor3       = Color3.fromRGB(18, 18, 22)
    teamStatusFrame.BackgroundTransparency = 0.2
    teamStatusFrame.BorderSizePixel        = 0
    teamStatusFrame.LayoutOrder            = rowIdx
    teamStatusFrame.Parent                 = scroll
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 5); c.Parent = teamStatusFrame end

    local teamStatusLbl                    = Instance.new("TextLabel")
    teamStatusLbl.Size                     = UDim2.new(1, -10, 1, 0)
    teamStatusLbl.Position                 = UDim2.new(0, 10, 0, 0)
    teamStatusLbl.BackgroundTransparency   = 1
    teamStatusLbl.Text                     = "Press SCAN to check teams"
    teamStatusLbl.TextColor3               = Color3.fromRGB(130, 130, 130)
    teamStatusLbl.Font                     = Enum.Font.Gotham
    teamStatusLbl.TextSize                 = 11
    teamStatusLbl.TextXAlignment           = Enum.TextXAlignment.Left
    teamStatusLbl.TextYAlignment           = Enum.TextYAlignment.Center
    teamStatusLbl.Parent                   = teamStatusFrame

    rowIdx += 1
    local teamResultsContainer             = Instance.new("Frame")
    teamResultsContainer.Size              = UDim2.new(1, 0, 0, 0)
    teamResultsContainer.AutomaticSize     = Enum.AutomaticSize.Y
    teamResultsContainer.BackgroundTransparency = 1
    teamResultsContainer.BorderSizePixel   = 0
    teamResultsContainer.LayoutOrder       = rowIdx
    teamResultsContainer.Parent            = scroll
    do
        local rl = Instance.new("UIListLayout")
        rl.Padding = UDim.new(0, 2)
        rl.SortOrder = Enum.SortOrder.LayoutOrder
        rl.Parent = teamResultsContainer
    end

    rowIdx += 1
    local teamScanBtn                      = Instance.new("TextButton")
    teamScanBtn.Size                       = UDim2.new(1, 0, 0, 30)
    teamScanBtn.BackgroundColor3           = Color3.fromRGB(100, 55, 180)
    teamScanBtn.BorderSizePixel            = 0
    teamScanBtn.Text                       = "SCAN TEAMS"
    teamScanBtn.TextColor3                 = Color3.fromRGB(255, 255, 255)
    teamScanBtn.Font                       = Enum.Font.GothamBold
    teamScanBtn.TextSize                   = 13
    teamScanBtn.AutoButtonColor            = false
    teamScanBtn.LayoutOrder                = rowIdx
    teamScanBtn.Parent                     = scroll
    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 5); c.Parent = teamScanBtn end
    teamScanBtn.MouseEnter:Connect(function() teamScanBtn.BackgroundTransparency = 0.2 end)
    teamScanBtn.MouseLeave:Connect(function() teamScanBtn.BackgroundTransparency = 0   end)

    local function doTeamScan()
        for _, ch in teamResultsContainer:GetChildren() do
            if not ch:IsA("UIListLayout") then ch:Destroy() end
        end
        teamStatusLbl.Text       = "Scanning " .. #Players:GetPlayers() .. " players..."
        teamStatusLbl.TextColor3 = Color3.fromRGB(220, 200, 60)
        teamScanBtn.Text         = "SCANNING..."
        teamScanBtn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)

        task.spawn(function()
            local found = {}
            for _, plr in Players:GetPlayers() do
                local team = plr.Team
                if team and TARGET_TEAMS[team.Name] then
                    table.insert(found, {name = plr.Name, team = team.Name})
                end
            end

            if #found == 0 then
                teamStatusLbl.Text       = "No Trainer / Trainee in server"
                teamStatusLbl.TextColor3 = Color3.fromRGB(180, 80, 80)
            else
                teamStatusLbl.Text       = "FOUND  —  " .. #found .. " member" .. (#found == 1 and "" or "s")
                teamStatusLbl.TextColor3 = Color3.fromRGB(80, 230, 100)
                for ri, entry in found do
                    local row            = Instance.new("Frame")
                    row.Size             = UDim2.new(1, 0, 0, 26)
                    row.BackgroundColor3 = Color3.fromRGB(35, 20, 60)
                    row.BorderSizePixel  = 0
                    row.LayoutOrder      = ri
                    row.Parent           = teamResultsContainer
                    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = row end
                    local strip          = Instance.new("Frame")
                    strip.Size           = UDim2.new(0, 3, 1, -6)
                    strip.Position       = UDim2.new(0, 4, 0, 3)
                    strip.BackgroundColor3 = Color3.fromRGB(160, 100, 255)
                    strip.BorderSizePixel  = 0
                    strip.Parent         = row
                    do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 2); c.Parent = strip end
                    local nameLbl        = Instance.new("TextLabel")
                    nameLbl.Size         = UDim2.new(1, -18, 1, 0)
                    nameLbl.Position     = UDim2.new(0, 14, 0, 0)
                    nameLbl.BackgroundTransparency = 1
                    nameLbl.Text         = entry.name .. "  [" .. entry.team .. "]"
                    nameLbl.TextColor3   = Color3.fromRGB(195, 155, 255)
                    nameLbl.Font         = Enum.Font.GothamBold
                    nameLbl.TextSize     = 12
                    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
                    nameLbl.TextYAlignment = Enum.TextYAlignment.Center
                    nameLbl.Parent       = row
                end
            end
            teamScanBtn.Text             = "SCAN TEAMS"
            teamScanBtn.BackgroundColor3 = Color3.fromRGB(100, 55, 180)
        end)
    end

    teamScanBtn.MouseButton1Click:Connect(doTeamScan)
    doTeamScan()

    _menuGui = sg
end

-- Assigned here so InputBegan can resolve it after full script load
toggleMenu = function()
    if menuVisible then
        closeMenu()
    else
        menuVisible = true
        buildMenu()
    end
end

-- Auto-open the menu on script load
toggleMenu()

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function getPivot(model)
    return model:FindFirstChild("HumanoidRootPart", true)
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart", true)
end

-- Returns true if at least one BasePart in the model is not fully transparent
local function computeVisible(model)
    for _, part in model:GetDescendants() do
        if part:IsA("BasePart") and part.Transparency < 1 then
            return true
        end
    end
    return false
end

-- Wires up Transparency Changed listeners on all current + future parts,
-- keeping t.visCache updated so the render loop never has to scan descendants.
local function hookVisibility(model, t)
    local function onPartChanged(part)
        part:GetPropertyChangedSignal("Transparency"):Connect(function()
            t.visCache = computeVisible(model)
        end)
    end
    for _, desc in model:GetDescendants() do
        if desc:IsA("BasePart") then onPartChanged(desc) end
    end
    model.DescendantAdded:Connect(function(desc)
        if desc:IsA("BasePart") then
            onPartChanged(desc)
            t.visCache = computeVisible(model)
        end
    end)
end

-- ─── ProximityPrompt reach patcher ─────────────────────────────────────────────
-- Forces all ProximityPrompts to be usable from anywhere, instantly (no hold),
-- with no cooldown and no line-of-sight requirement.
--
-- SCPs spawn WITHOUT a ProximityPrompt — the server adds one dynamically only
-- when a player walks nearby. The global Workspace.DescendantAdded watcher below
-- catches every PP the moment it appears anywhere in the game, so proximity-gated
-- spawning is bypassed automatically.

local PP_DISTANCE = 9e9

local function applyPP(desc)
    if not ppEnabled then return end  -- respect the menu toggle
    if desc:IsA("ProximityPrompt") then
        local pp = desc
        pp.MaxActivationDistance = PP_DISTANCE  -- clickable from anywhere
        pp.HoldDuration          = 0            -- no hold required, instant activation
        pp.Cooldown              = 0            -- no cooldown between uses
        pp.RequiresLineOfSight   = false        -- works through walls
    end
end

-- Patch all existing ProximityPrompts already in Workspace at load time
for _, desc in Workspace:GetDescendants() do
    applyPP(desc)
end

-- Global watcher: catches ANY ProximityPrompt added anywhere in Workspace at any time
-- This handles server-side dynamic PP spawning when a player walks near an SCP
Workspace.DescendantAdded:Connect(applyPP)

local function patchProximityPrompts(_model)
    -- No-op: the global watcher above handles all cases.
    -- Kept so existing addESP call sites don't need to change.
end

-- ─── Add / Remove ─────────────────────────────────────────────────────────────

local function addESP(model, isObject, labelOverride)
    if tracked[model] then return end
    local displayName = labelOverride or model.Name
    if not labelOverride and ENABLED[displayName] == false then return end

    local pivot = getPivot(model)
    if not pivot then
        warn("[ESP] No pivot for: " .. model.Name)
        return
    end

    local gui             = Instance.new("BillboardGui")
    gui.Name              = "ESP_" .. model.Name
    gui.Size              = UDim2.new(0, 80, 0, 26)
    gui.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
    gui.AlwaysOnTop       = true
    gui.LightInfluence    = 0
    gui.ResetOnSpawn      = false
    gui.Adornee           = pivot
    gui.Parent            = CoreGui

    local bg              = Instance.new("Frame")
    bg.Size               = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3   = Color3.fromRGB(0, 0, 0)
    bg.BackgroundTransparency = 0.55
    bg.BorderSizePixel    = 0
    bg.Parent             = gui

    local corner          = Instance.new("UICorner")
    corner.CornerRadius   = UDim.new(0, 3)
    corner.Parent         = bg

    local nameL           = Instance.new("TextLabel")
    nameL.Size            = UDim2.new(1, -6, 0.54, 0)
    nameL.Position        = UDim2.new(0, 3, 0, 1)
    nameL.BackgroundTransparency = 1
    nameL.Text            = displayName
    nameL.TextColor3      = CFG.NameColor
    nameL.TextScaled      = true
    nameL.Font            = Enum.Font.GothamBold
    nameL.TextXAlignment  = Enum.TextXAlignment.Left
    nameL.Parent          = bg

    local distL           = Instance.new("TextLabel")
    distL.Size            = UDim2.new(1, -6, 0.40, 0)
    distL.Position        = UDim2.new(0, 3, 0.56, 0)
    distL.BackgroundTransparency = 1
    distL.Text            = "--"
    distL.TextColor3      = CFG.DistColor
    distL.TextScaled      = true
    distL.Font            = Enum.Font.Gotham
    distL.TextXAlignment  = Enum.TextXAlignment.Left
    distL.Parent          = bg

    -- Highlight (works through walls, tsright transparent glow)
    local hl                    = Instance.new("Highlight")
    hl.FillColor                = isObject and CFG.ObjHL_Fill         or CFG.CharHL_Fill
    hl.OutlineColor             = isObject and CFG.ObjHL_Outline      or CFG.CharHL_Outline
    hl.FillTransparency         = isObject and CFG.ObjHL_FillTransp   or CFG.CharHL_FillTransp
    hl.OutlineTransparency      = isObject and CFG.ObjHL_OutlineTransp or CFG.CharHL_OutlineTransp
    hl.DepthMode                = Enum.HighlightDepthMode.AlwaysOnTop  -- visible through walls
    hl.Adornee                  = model
    hl.Parent                   = CoreGui

    local entry = { gui = gui, hl = hl, dist = distL, pivot = pivot, isObject = isObject, visCache = true }
    tracked[model] = entry
    if isObject then
        entry.visCache = computeVisible(model)
        hookVisibility(model, entry)
        patchProximityPrompts(model)
    end
    print("[ESP] Added: " .. displayName)
end

local function removeESP(model)
    local t = tracked[model]
    if not t then return end
    t.gui:Destroy()
    t.hl:Destroy()
    tracked[model] = nil
end

-- ─── Folder watcher ───────────────────────────────────────────────────────────

local function watchFolder(folder, isObject)
    for _, child in folder:GetChildren() do
        if child:IsA("Model") then
            addESP(child, isObject)
        end
    end
    folder.ChildAdded:Connect(function(child)
        if child:IsA("Model") then
            task.wait(0.2)
            addESP(child, isObject)
        end
    end)
    folder.ChildRemoved:Connect(function(child)
        removeESP(child)
    end)
end

-- ─── Init: wait for workspace.SCPs then its subfolders ────────────────────────

task.spawn(function()
    local scps = Workspace:FindFirstChild("SCPs") or Workspace:WaitForChild("SCPs", 60)
    if not scps then warn("[ESP] workspace.SCPs not found") return end
    print("[ESP] Found workspace.SCPs")

    local humanoids = scps:FindFirstChild("Humanoids") or scps:WaitForChild("Humanoids", 30)
    local objects   = scps:FindFirstChild("Objects")   or scps:WaitForChild("Objects",   30)

    if humanoids then
        print("[ESP] Watching Humanoids (" .. #humanoids:GetChildren() .. " children)")
        watchFolder(humanoids, false)
    else
        warn("[ESP] Humanoids folder not found")
    end

    if objects then
        print("[ESP] Watching Objects (" .. #objects:GetChildren() .. " children)")
        watchFolder(objects, true)
    else
        warn("[ESP] Objects folder not found")
    end
end)

-- ─── Per-frame: distance + billboard above bounding box top ───────────────────

RunService.RenderStepped:Connect(function()
    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local myPos = root.Position

    for model, t in tracked do
        if not model.Parent then
            removeESP(model)
            continue
        end

        local pivot = t.pivot
        if not pivot or not pivot.Parent then
            pivot = getPivot(model)
            if not pivot then continue end
            t.pivot       = pivot
            t.gui.Adornee = pivot
        end

        local dist = math.round((myPos - pivot.Position).Magnitude)
        t.dist.Text = dist .. "m"

        -- Hide if ESP toggled off, SCP disabled, or Object is currently invisible
        local show = espVisible
            and (ENABLED[model.Name] ~= false)
            and (not t.isObject or t.visCache)
        t.gui.Enabled = show
        t.hl.Enabled  = show
        if not show then continue end

        local ok, cf, sz = pcall(function()
            return model:GetBoundingBox()
        end)
        if ok and cf and sz then
            local topY   = cf.Position.Y + sz.Y / 2
            local offset = topY - pivot.Position.Y + 1
            t.gui.StudsOffsetWorldSpace = Vector3.new(0, offset, 0)
        end
    end
end)

-- ─── Debris watcher (dropped Object SCPs) ───────────────────────────────────

task.spawn(function()
    local debris = Workspace:FindFirstChild("Debris") or Workspace:WaitForChild("Debris", 60)
    if not debris then warn("[ESP] workspace.Debris not found") return end
    print("[ESP] Watching workspace.Debris")

    local function tryDebris(child)
        if not child:IsA("Model") then return end

        -- Known SCP Debris entries (DEBRIS_MAP)
        local scpName = DEBRIS_MAP[child.Name]
        if scpName then
            if ENABLED[scpName] ~= false then
                task.wait(0.1)
                addESP(child, true, scpName)
            end
            return
        end

        -- Custom non-SCP Debris entries (DEBRIS_EXTRA)
        local extraLabel = DEBRIS_EXTRA[child.Name]
        if extraLabel then
            local key = "DEBRIS_" .. child.Name
            if ENABLED[key] ~= false then
                task.wait(0.1)
                addESP(child, true, extraLabel)
            end
        end
    end

    for _, child in debris:GetChildren() do tryDebris(child) end
    debris.ChildAdded:Connect(tryDebris)
    debris.ChildRemoved:Connect(function(child) removeESP(child) end)
end)

-- ─── Scrap Spawns watcher (crafting items in workspace.Interactable.scrapSpawns) ──
-- Structure: workspace.Interactable > scrapSpawns > <SpawnPart> > <Item Model>
-- Items are matched against DEBRIS_EXTRA so their menu toggles apply here too.

task.spawn(function()
    local interactable = Workspace:FindFirstChild("Interactable") or Workspace:WaitForChild("Interactable", 60)
    if not interactable then warn("[ESP] workspace.Interactable not found") return end

    local scrapSpawns = interactable:FindFirstChild("ScrapSpawns") or interactable:WaitForChild("ScrapSpawns", 30)
    if not scrapSpawns then warn("[ESP] ScrapSpawns not found") return end
    print("[ESP] Watching workspace.Interactable.ScrapSpawns")

    local function tryScrap(item)
        if not item:IsA("PVInstance") then return end  -- covers Model and Tool
        local extraLabel = DEBRIS_EXTRA[item.Name]
        if extraLabel then
            local key = "DEBRIS_" .. item.Name
            if ENABLED[key] ~= false then
                task.wait(0.1)
                addESP(item, true, extraLabel)
            end
        end
    end

    local function watchSpawnPoint(spawnPart)
        for _, item in spawnPart:GetChildren() do
            tryScrap(item)
        end
        spawnPart.ChildAdded:Connect(function(item)
            tryScrap(item)
        end)
        spawnPart.ChildRemoved:Connect(function(item)
            removeESP(item)
        end)
    end

    -- Watch all existing spawn points
    for _, spawnPart in scrapSpawns:GetChildren() do
        watchSpawnPoint(spawnPart)
    end
    -- Watch for new spawn points added at runtime
    scrapSpawns.ChildAdded:Connect(function(spawnPart)
        task.wait(0.1)
        watchSpawnPoint(spawnPart)
    end)
end)

print("[ESP] Script loaded — waiting for workspace.SCPs")
