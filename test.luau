--[[
    ╔══════════════════════════════════════════════════════╗
    ║              ROBLOX ESP - Anti-Cheat Dev Tool        ║
    ║         Purpose: Understanding ESP for prevention    ║
    ╚══════════════════════════════════════════════════════╝

    FEATURES:
      • Chams (Highlight)
      • Box ESP
      • Username
      • Health + Health Bar
      • Current Tool Held (reads Character + Backpack)
      • Distance (studs)
      • Team-specific ESP  (configured via menu)
      • Toggle Menu (press RightShift)
--]]

-- ============================================================
--  SERVICES
-- ============================================================
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local TeamsService     = game:GetService("Teams")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

-- ============================================================
--  CONFIG  (all settings live here)
-- ============================================================
local Config = {
    -- Master toggle
    Enabled        = true,

    -- Feature toggles
    Chams          = true,
    BoxESP         = true,
    Username       = true,
    HealthBar      = true,
    HealthText     = false,   -- numeric HP next to bar
    ToolESP        = true,
    Distance       = true,

    -- Team filter
    TeamFilterEnabled = false,   -- when true, only show players on selected teams
    SelectedTeams     = {},      -- set: { ["TeamName"] = true }  (populated by menu)
    ShowTeamName      = true,    -- show team name tag under the username
    UseTeamColor      = true,    -- tint box/chams with the player's actual team color

    -- Visual settings
    BoxColorEnemy     = Color3.fromRGB(255,  60,  60),
    BoxColorTeammate  = Color3.fromRGB( 60, 200,  60),
    TextColor         = Color3.fromRGB(255, 255, 255),
    HealthColorHigh   = Color3.fromRGB( 60, 220,  60),
    HealthColorLow    = Color3.fromRGB(220,  60,  60),
    HealthBarBG       = Color3.fromRGB( 30,  30,  30),
    ChamsColorEnemy   = Color3.fromRGB(255,  30,  30),
    ChamsColorTeammate= Color3.fromRGB( 30, 255,  30),

    -- Misc
    MaxDistance    = 1000,    -- studs; beyond this nothing is drawn
    TextSize       = 15,      -- base label size
    NameTextSize   = 18,      -- larger bold nametag
    BoxThickness   = 2,       -- box outline thickness in px
    MenuKeybind    = Enum.KeyCode.RightShift,
    MenuOpen       = true,
}

-- ============================================================
--  UTILITIES
-- ============================================================
local function isTeammate(player)
    if LocalPlayer.Team and player.Team then
        return player.Team == LocalPlayer.Team
    end
    return false
end

-- Returns nil if player should be skipped entirely
local function shouldRender(player)
    if player == LocalPlayer then return nil end
    local char = player.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end

    -- Distance gate
    local lroot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local dist = lroot and (root.Position - lroot.Position).Magnitude or 0
    if dist > Config.MaxDistance then return nil end

    -- Team filter (per-team whitelist)
    if Config.TeamFilterEnabled then
        if not player.Team then return nil end
        if not Config.SelectedTeams[player.Team.Name] then return nil end
    end

    return dist
end

-- Project a 3-D world position to 2-D screen coords.
-- Returns (Vector2 screenPos, depth, onScreen)
local function worldToScreen(pos)
    local screenPos, inBounds = Camera:WorldToViewportPoint(pos)
    return Vector2.new(screenPos.X, screenPos.Y), screenPos.Z, inBounds
end

-- Get tight 2-D bounding box by projecting all part corners
local function getCharacterBounds(character)
    local minX, minY =  math.huge,  math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyOnScreen = false

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            local cf  = part.CFrame
            local sz  = part.Size / 2
            -- 8 corners of the part's AABB in world space
            local corners = {
                cf * Vector3.new( sz.X,  sz.Y,  sz.Z),
                cf * Vector3.new(-sz.X,  sz.Y,  sz.Z),
                cf * Vector3.new( sz.X, -sz.Y,  sz.Z),
                cf * Vector3.new(-sz.X, -sz.Y,  sz.Z),
                cf * Vector3.new( sz.X,  sz.Y, -sz.Z),
                cf * Vector3.new(-sz.X,  sz.Y, -sz.Z),
                cf * Vector3.new( sz.X, -sz.Y, -sz.Z),
                cf * Vector3.new(-sz.X, -sz.Y, -sz.Z),
            }
            for _, corner in ipairs(corners) do
                local sp, depth, onScreen = worldToScreen(corner)
                if depth > 0 then
                    anyOnScreen = true
                    if sp.X < minX then minX = sp.X end
                    if sp.X > maxX then maxX = sp.X end
                    if sp.Y < minY then minY = sp.Y end
                    if sp.Y > maxY then maxY = sp.Y end
                end
            end
        end
    end

    if not anyOnScreen or minX == math.huge then return nil end
    -- add small padding
    local pad = 3
    return {
        x = minX - pad,
        y = minY - pad,
        w = (maxX - minX) + pad * 2,
        h = (maxY - minY) + pad * 2,
    }
end

-- Get currently held tool name (checks Character then Backpack)
local function getToolName(player)
    local held = nil
    if player.Character then
        local t = player.Character:FindFirstChildOfClass("Tool")
        if t then held = t.Name end
    end
    if not held then
        -- Check backpack for all tools
        local bp = player:FindFirstChild("Backpack")
        if bp then
            local list = {}
            for _, v in ipairs(bp:GetChildren()) do
                if v:IsA("Tool") then
                    table.insert(list, v.Name)
                end
            end
            if #list > 0 then
                held = table.concat(list, ", ")
            end
        end
    end
    return held or "None"
end

-- Returns the player's actual team Color3 (from BrickColor), or nil
local function getTeamColor(player)
    if player.Team then
        return player.Team.TeamColor.Color
    end
    return nil
end

-- Lerp between two Color3 values
local function lerpColor(a, b, t)
    return Color3.new(
        a.R + (b.R - a.R) * t,
        a.G + (b.G - a.G) * t,
        a.B + (b.B - a.B) * t
    )
end

-- ============================================================
--  DRAWING HELPER  (thin wrapper so we don't repeat properties)
-- ============================================================
local function newLine(color, thickness)
    local l = Drawing.new("Line")
    l.Color     = color or Color3.new(1,1,1)
    l.Thickness = thickness or 1
    l.Visible   = false
    return l
end

local function newText(color, size, outline)
    local t = Drawing.new("Text")
    t.Color   = color or Color3.new(1,1,1)
    t.Size    = size  or Config.TextSize
    t.Font    = Drawing.Fonts.UI
    t.Outline = outline ~= false
    t.Visible = false
    return t
end

local function newSquare(color, filled)
    local s = Drawing.new("Square")
    s.Color   = color or Color3.new(1,1,1)
    s.Filled  = filled or false
    s.Visible = false
    return s
end

-- ============================================================
--  PER-PLAYER ESP INSTANCE
-- ============================================================
local ESPInstances = {}   -- [Player] = table of Drawing objects + Highlight

local function createESP(player)
    local obj = {}

    -- ── Box (4 lines, thicker) ────────────────────────────
    obj.boxLines = {
        top    = newLine(Config.BoxColorEnemy, Config.BoxThickness),
        bottom = newLine(Config.BoxColorEnemy, Config.BoxThickness),
        left   = newLine(Config.BoxColorEnemy, Config.BoxThickness),
        right  = newLine(Config.BoxColorEnemy, Config.BoxThickness),
    }

    -- ── Labels ─────────────────────────────────────────────
    obj.nameText   = newText(Config.TextColor, Config.NameTextSize)  -- bold large nametag
    obj.teamText   = newText(Config.TextColor, Config.TextSize)       -- team name tag
    obj.distText   = newText(Config.TextColor, Config.TextSize - 1)
    obj.toolText   = newText(Color3.fromRGB(255, 220, 80), Config.TextSize - 1)
    obj.healthText = newText(Config.TextColor, Config.TextSize - 1)

    -- ── Health Bar (background + foreground) ───────────────
    obj.hpBarBG  = newSquare(Config.HealthBarBG, true)
    obj.hpBarFG  = newSquare(Config.HealthColorHigh, true)

    -- ── Chams (Highlight instance) ─────────────────────────
    local hl = Instance.new("Highlight")
    hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillTransparency    = 0.3   -- more opaque fill = more visible
    hl.OutlineTransparency = 0     -- solid outline around the character
    hl.Enabled             = false

    -- Parent to CoreGui so it survives character resets
    local ok, err = pcall(function()
        hl.Parent = game:GetService("CoreGui")
    end)
    if not ok then
        hl.Parent = LocalPlayer.PlayerGui
    end

    obj.highlight = hl

    ESPInstances[player] = obj
end

local function destroyESP(player)
    local obj = ESPInstances[player]
    if not obj then return end

    for _, line in pairs(obj.boxLines) do line:Remove() end
    obj.nameText:Remove()
    obj.teamText:Remove()
    obj.distText:Remove()
    obj.toolText:Remove()
    obj.healthText:Remove()
    obj.hpBarBG:Remove()
    obj.hpBarFG:Remove()
    obj.highlight:Destroy()

    ESPInstances[player] = nil
end

local function hideESP(obj)
    for _, line in pairs(obj.boxLines) do line.Visible = false end
    obj.nameText.Visible   = false
    obj.teamText.Visible   = false
    obj.distText.Visible   = false
    obj.toolText.Visible   = false
    obj.healthText.Visible = false
    obj.hpBarBG.Visible    = false
    obj.hpBarFG.Visible    = false
    obj.highlight.Enabled  = false
end

-- ============================================================
--  MAIN UPDATE  (called every frame)
-- ============================================================
local function updateESP(player)
    local obj = ESPInstances[player]
    if not obj then return end

    local dist = shouldRender(player)
    if not Config.Enabled or not dist then
        hideESP(obj)
        return
    end

    local char      = player.Character
    local humanoid  = char and char:FindFirstChildOfClass("Humanoid")
    local rootPart  = char and char:FindFirstChild("HumanoidRootPart")

    if not humanoid or not rootPart then
        hideESP(obj)
        return
    end

    -- ── Determine colour scheme (uses real team color when available) ─
    local teammate   = isTeammate(player)
    local teamColor  = getTeamColor(player)

    local boxColor, chamsColor
    if Config.UseTeamColor and teamColor then
        -- use the actual Roblox team color for both the box and chams
        boxColor   = teamColor
        chamsColor = teamColor
    else
        boxColor   = teammate and Config.BoxColorTeammate or Config.BoxColorEnemy
        chamsColor = teammate and Config.ChamsColorTeammate or Config.ChamsColorEnemy
    end

    -- ── Chams ────────────────────────────────────────────────
    if Config.Chams then
        obj.highlight.Adornee          = char
        obj.highlight.FillColor        = chamsColor
        obj.highlight.OutlineColor     = chamsColor
        obj.highlight.FillTransparency = 0.3
        obj.highlight.Enabled          = true
    else
        obj.highlight.Enabled = false
    end

    -- ── Bounding box ────────────────────────────────────────
    local bounds = getCharacterBounds(char)
    if not bounds then
        hideESP(obj)
        return
    end

    local bx, by, bw, bh = bounds.x, bounds.y, bounds.w, bounds.h

    -- Box lines
    if Config.BoxESP then
        local tl = Vector2.new(bx,      by     )
        local tr = Vector2.new(bx + bw, by     )
        local bl = Vector2.new(bx,      by + bh)
        local br = Vector2.new(bx + bw, by + bh)

        obj.boxLines.top.From    = tl ; obj.boxLines.top.To    = tr
        obj.boxLines.bottom.From = bl ; obj.boxLines.bottom.To = br
        obj.boxLines.left.From   = tl ; obj.boxLines.left.To   = bl
        obj.boxLines.right.From  = tr ; obj.boxLines.right.To  = br

        for _, line in pairs(obj.boxLines) do
            line.Color     = boxColor
            line.Thickness = Config.BoxThickness
            line.Visible   = true
        end
    else
        for _, line in pairs(obj.boxLines) do line.Visible = false end
    end

    -- Offset tracker for stacking text above the box
    local textY = by - 2

    -- ── Username (large bold nametag) ─────────────────────
    if Config.Username then
        obj.nameText.Text     = player.DisplayName .. " (@" .. player.Name .. ")"
        obj.nameText.Size     = Config.NameTextSize
        obj.nameText.Position = Vector2.new(bx + bw / 2, textY - Config.NameTextSize - 2)
        obj.nameText.Center   = true
        -- color the name with the team color if available, else white
        obj.nameText.Color    = (Config.UseTeamColor and teamColor) and teamColor or Config.TextColor
        obj.nameText.Visible  = true
        textY = textY - Config.NameTextSize - 4
    else
        obj.nameText.Visible = false
    end

    -- ── Team name tag ────────────────────────────────────────
    if Config.ShowTeamName then
        local teamName = (player.Team and player.Team.Name) or "No Team"
        local tagColor = (Config.UseTeamColor and teamColor) and teamColor or Color3.fromRGB(180, 180, 255)
        obj.teamText.Text     = "[" .. teamName .. "]"
        obj.teamText.Size     = Config.TextSize
        obj.teamText.Position = Vector2.new(bx + bw / 2, textY - Config.TextSize - 2)
        obj.teamText.Center   = true
        obj.teamText.Color    = tagColor
        obj.teamText.Visible  = true
        textY = textY - Config.TextSize - 4
    else
        obj.teamText.Visible = false
    end

    -- ── Distance ────────────────────────────────────────────
    if Config.Distance then
        obj.distText.Text     = string.format("%.0f studs", dist)
        obj.distText.Position = Vector2.new(bx + bw / 2, textY - Config.TextSize - 2)
        obj.distText.Center   = true
        obj.distText.Color    = Color3.fromRGB(180, 220, 255)
        obj.distText.Visible  = true
        textY = textY - Config.TextSize - 4
    else
        obj.distText.Visible = false
    end

    -- ── Tool ────────────────────────────────────────────────
    if Config.ToolESP then
        local toolName = getToolName(player)
        obj.toolText.Text     = "Tool: " .. toolName
        obj.toolText.Position = Vector2.new(bx + bw / 2, textY - Config.TextSize - 2)
        obj.toolText.Center   = true
        obj.toolText.Visible  = true
        textY = textY - Config.TextSize - 4
    else
        obj.toolText.Visible = false
    end

    -- ── Health bar (left side of box, 4px wide) ─────────────
    local hp     = humanoid.Health
    local maxHp  = humanoid.MaxHealth
    local hpFrac = maxHp > 0 and math.clamp(hp / maxHp, 0, 1) or 0
    local hpCol  = lerpColor(Config.HealthColorLow, Config.HealthColorHigh, hpFrac)

    if Config.HealthBar then
        local barW = 4
        local barX = bx - barW - 3

        obj.hpBarBG.Position = Vector2.new(barX, by)
        obj.hpBarBG.Size     = Vector2.new(barW, bh)
        obj.hpBarBG.Color    = Config.HealthBarBG
        obj.hpBarBG.Visible  = true

        local fgH = bh * hpFrac
        obj.hpBarFG.Position = Vector2.new(barX, by + bh - fgH)
        obj.hpBarFG.Size     = Vector2.new(barW, fgH)
        obj.hpBarFG.Color    = hpCol
        obj.hpBarFG.Visible  = true
    else
        obj.hpBarBG.Visible = false
        obj.hpBarFG.Visible = false
    end

    -- ── Health text (optional numeric readout) ───────────────
    if Config.HealthText then
        obj.healthText.Text     = string.format("HP: %.0f / %.0f", hp, maxHp)
        obj.healthText.Position = Vector2.new(bx + bw + 5, by + bh - Config.TextSize)
        obj.healthText.Center   = false
        obj.healthText.Color    = hpCol
        obj.healthText.Visible  = true
    else
        obj.healthText.Visible = false
    end
end

-- ============================================================
--  MENU GUI
-- ============================================================
local function buildMenu()
    -- Clean up any existing menu
    local existing = LocalPlayer.PlayerGui:FindFirstChild("ESP_Menu")
    if existing then existing:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name            = "ESP_Menu"
    screenGui.ResetOnSpawn    = false
    screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
    screenGui.IgnoreGuiInset  = true
    screenGui.Parent          = LocalPlayer.PlayerGui

    -- ── Drag Frame ──────────────────────────────────────────
    local mainFrame = Instance.new("Frame")
    mainFrame.Name            = "MainFrame"
    mainFrame.Size            = UDim2.fromOffset(260, 420)
    mainFrame.Position        = UDim2.fromOffset(40, 120)
    mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    mainFrame.BorderSizePixel = 0
    mainFrame.Active          = true
    mainFrame.Draggable       = true
    mainFrame.Parent          = screenGui

    Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

    -- Stroke
    local stroke = Instance.new("UIStroke", mainFrame)
    stroke.Color     = Color3.fromRGB(80, 80, 200)
    stroke.Thickness = 1.5

    -- Title bar
    local titleBar = Instance.new("Frame", mainFrame)
    titleBar.Size            = UDim2.new(1, 0, 0, 32)
    titleBar.BackgroundColor3 = Color3.fromRGB(30, 30, 60)
    titleBar.BorderSizePixel = 0

    local titleCorner = Instance.new("UICorner", titleBar)
    titleCorner.CornerRadius = UDim.new(0, 8)

    local titleLabel = Instance.new("TextLabel", titleBar)
    titleLabel.Size            = UDim2.new(1, -10, 1, 0)
    titleLabel.Position        = UDim2.fromOffset(10, 0)
    titleLabel.BackgroundTransparency = 1
    titleLabel.Text            = "ESP  ·  RightShift to hide"
    titleLabel.TextColor3      = Color3.fromRGB(220, 220, 255)
    titleLabel.TextSize        = 13
    titleLabel.Font            = Enum.Font.GothamBold
    titleLabel.TextXAlignment  = Enum.TextXAlignment.Left

    -- Scroll container for toggles
    local scroll = Instance.new("ScrollingFrame", mainFrame)
    scroll.Size                = UDim2.new(1, -10, 1, -44)
    scroll.Position            = UDim2.fromOffset(5, 38)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel     = 0
    scroll.ScrollBarThickness  = 3
    scroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 200)
    scroll.CanvasSize          = UDim2.fromOffset(0, 0)  -- auto below
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y

    local listLayout = Instance.new("UIListLayout", scroll)
    listLayout.Padding       = UDim.new(0, 5)
    listLayout.SortOrder     = Enum.SortOrder.LayoutOrder

    local padding = Instance.new("UIPadding", scroll)
    padding.PaddingTop = UDim.new(0, 4)

    -- ── Toggle builder ──────────────────────────────────────
    local function addToggle(label, getter, setter, order)
        local row = Instance.new("Frame", scroll)
        row.Size                = UDim2.new(1, -6, 0, 34)
        row.BackgroundColor3    = Color3.fromRGB(28, 28, 36)
        row.BorderSizePixel     = 0
        row.LayoutOrder         = order
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local lbl = Instance.new("TextLabel", row)
        lbl.Size               = UDim2.new(1, -50, 1, 0)
        lbl.Position           = UDim2.fromOffset(10, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text               = label
        lbl.TextColor3         = Color3.fromRGB(210, 210, 220)
        lbl.TextSize           = 13
        lbl.Font               = Enum.Font.Gotham
        lbl.TextXAlignment     = Enum.TextXAlignment.Left

        local btn = Instance.new("TextButton", row)
        btn.Size               = UDim2.fromOffset(40, 22)
        btn.Position           = UDim2.new(1, -46, 0.5, -11)
        btn.Font               = Enum.Font.GothamBold
        btn.TextSize           = 12
        btn.BorderSizePixel    = 0
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

        local function refresh()
            local val = getter()
            btn.Text              = val and "ON" or "OFF"
            btn.BackgroundColor3  = val and Color3.fromRGB(50, 160, 80) or Color3.fromRGB(160, 50, 50)
            btn.TextColor3        = Color3.new(1, 1, 1)
        end
        refresh()

        btn.MouseButton1Click:Connect(function()
            setter(not getter())
            refresh()
        end)
    end

    -- ── Text input builder ──────────────────────────────────
    local function addTextInput(label, placeholder, getter, setter, order)
        local row = Instance.new("Frame", scroll)
        row.Size            = UDim2.new(1, -6, 0, 54)
        row.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
        row.BorderSizePixel = 0
        row.LayoutOrder     = order
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

        local lbl = Instance.new("TextLabel", row)
        lbl.Size               = UDim2.new(1, -10, 0, 22)
        lbl.Position           = UDim2.fromOffset(10, 4)
        lbl.BackgroundTransparency = 1
        lbl.Text               = label
        lbl.TextColor3         = Color3.fromRGB(210, 210, 220)
        lbl.TextSize           = 12
        lbl.Font               = Enum.Font.Gotham
        lbl.TextXAlignment     = Enum.TextXAlignment.Left

        local box = Instance.new("TextBox", row)
        box.Size               = UDim2.new(1, -16, 0, 22)
        box.Position           = UDim2.fromOffset(8, 26)
        box.BackgroundColor3   = Color3.fromRGB(40, 40, 55)
        box.BorderSizePixel    = 0
        box.PlaceholderText    = placeholder
        box.PlaceholderColor3  = Color3.fromRGB(120, 120, 140)
        box.Text               = getter()
        box.TextColor3         = Color3.fromRGB(220, 220, 255)
        box.TextSize           = 12
        box.Font               = Enum.Font.Gotham
        box.ClearTextOnFocus   = false
        Instance.new("UICorner", box).CornerRadius = UDim.new(0, 4)

        box.FocusLost:Connect(function()
            setter(box.Text)
        end)
    end

    -- ── Section label builder ───────────────────────────────
    local sectionOrder = 0
    local function addSection(text)
        sectionOrder += 1
        local lbl = Instance.new("TextLabel", scroll)
        lbl.Size               = UDim2.new(1, -6, 0, 20)
        lbl.BackgroundTransparency = 1
        lbl.Text               = "  " .. string.upper(text)
        lbl.TextColor3         = Color3.fromRGB(100, 100, 220)
        lbl.TextSize           = 11
        lbl.Font               = Enum.Font.GothamBold
        lbl.TextXAlignment     = Enum.TextXAlignment.Left
        lbl.LayoutOrder        = sectionOrder * 100
        return sectionOrder * 100
    end

    -- ── Populate toggles ─────────────────────────────────────
    addSection("General")
    addToggle("Master Enable",  function() return Config.Enabled   end, function(v) Config.Enabled   = v end, 101)
    addToggle("Chams (Highlight)", function() return Config.Chams  end, function(v) Config.Chams     = v end, 102)
    addToggle("Box ESP",        function() return Config.BoxESP    end, function(v) Config.BoxESP    = v end, 103)

    addSection("Info Labels")
    addToggle("Username",       function() return Config.Username    end, function(v) Config.Username    = v end, 201)
    addToggle("Team Name Tag",  function() return Config.ShowTeamName end, function(v) Config.ShowTeamName = v end, 202)
    addToggle("Distance",       function() return Config.Distance    end, function(v) Config.Distance    = v end, 203)
    addToggle("Tool Held",      function() return Config.ToolESP     end, function(v) Config.ToolESP     = v end, 204)
    addToggle("Health Bar",     function() return Config.HealthBar   end, function(v) Config.HealthBar   = v end, 205)
    addToggle("Health Text",    function() return Config.HealthText  end, function(v) Config.HealthText  = v end, 206)

    addSection("Visuals")
    addToggle("Use Team Color",  function() return Config.UseTeamColor    end, function(v) Config.UseTeamColor    = v end, 300)

    -- ── Team Selector ────────────────────────────────────────
    addSection("Team Selector")
    addToggle("Enable Team Filter", function() return Config.TeamFilterEnabled end, function(v) Config.TeamFilterEnabled = v end, 401)

    -- Refresh button — repopulates per-team rows from the live Teams service
    local refreshBtn = Instance.new("TextButton", scroll)
    refreshBtn.Name             = "RefreshTeamsBtn"
    refreshBtn.Size             = UDim2.new(1, -6, 0, 28)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 90)
    refreshBtn.BorderSizePixel  = 0
    refreshBtn.Text             = "↺  Refresh Team List"
    refreshBtn.TextColor3       = Color3.fromRGB(190, 190, 255)
    refreshBtn.TextSize         = 12
    refreshBtn.Font             = Enum.Font.GothamBold
    refreshBtn.LayoutOrder      = 402
    Instance.new("UICorner", refreshBtn).CornerRadius = UDim.new(0, 6)
    local refreshStroke = Instance.new("UIStroke", refreshBtn)
    refreshStroke.Color     = Color3.fromRGB(80, 80, 200)
    refreshStroke.Thickness = 1

    -- Builds / rebuilds one toggle row per team found in Teams service
    local function rebuildTeamRows()
        -- remove stale rows
        for _, child in ipairs(scroll:GetChildren()) do
            if child.Name:sub(1, 8) == "TeamRow_" then
                child:Destroy()
            end
        end

        local allTeams = TeamsService:GetTeams()
        if #allTeams == 0 then
            -- show a hint label if the game has no teams
            local hint = Instance.new("TextLabel", scroll)
            hint.Name               = "TeamRow_hint"
            hint.Size               = UDim2.new(1, -6, 0, 24)
            hint.BackgroundTransparency = 1
            hint.Text               = "  (No teams found in this game)"
            hint.TextColor3         = Color3.fromRGB(150, 150, 160)
            hint.TextSize           = 11
            hint.Font               = Enum.Font.Gotham
            hint.TextXAlignment     = Enum.TextXAlignment.Left
            hint.LayoutOrder        = 410
            return
        end

        for idx, team in ipairs(allTeams) do
            local teamName = team.Name
            local teamCol  = team.TeamColor.Color

            -- default new teams to OFF
            if Config.SelectedTeams[teamName] == nil then
                Config.SelectedTeams[teamName] = false
            end

            local row = Instance.new("Frame", scroll)
            row.Name             = "TeamRow_" .. teamName
            row.Size             = UDim2.new(1, -6, 0, 34)
            row.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
            row.BorderSizePixel  = 0
            row.LayoutOrder      = 410 + idx
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)

            -- team color swatch
            local swatch = Instance.new("Frame", row)
            swatch.Size             = UDim2.fromOffset(12, 12)
            swatch.Position         = UDim2.new(0, 10, 0.5, -6)
            swatch.BackgroundColor3 = teamCol
            swatch.BorderSizePixel  = 0
            Instance.new("UICorner", swatch).CornerRadius = UDim.new(0, 3)

            local lbl = Instance.new("TextLabel", row)
            lbl.Size               = UDim2.new(1, -68, 1, 0)
            lbl.Position           = UDim2.fromOffset(28, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text               = teamName
            lbl.TextColor3         = Color3.fromRGB(210, 210, 220)
            lbl.TextSize           = 13
            lbl.Font               = Enum.Font.Gotham
            lbl.TextXAlignment     = Enum.TextXAlignment.Left

            local btn = Instance.new("TextButton", row)
            btn.Size             = UDim2.fromOffset(40, 22)
            btn.Position         = UDim2.new(1, -46, 0.5, -11)
            btn.Font             = Enum.Font.GothamBold
            btn.TextSize         = 12
            btn.BorderSizePixel  = 0
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

            local function refreshRow()
                local val = Config.SelectedTeams[teamName]
                btn.Text             = val and "ON" or "OFF"
                btn.BackgroundColor3 = val and Color3.fromRGB(50, 160, 80) or Color3.fromRGB(160, 50, 50)
                btn.TextColor3       = Color3.new(1, 1, 1)
                -- highlight swatch border when selected
                local existing = swatch:FindFirstChildOfClass("UIStroke")
                if val then
                    if not existing then
                        local s = Instance.new("UIStroke", swatch)
                        s.Color = Color3.new(1, 1, 1)
                        s.Thickness = 1.5
                    end
                else
                    if existing then existing:Destroy() end
                end
            end
            refreshRow()

            btn.MouseButton1Click:Connect(function()
                Config.SelectedTeams[teamName] = not Config.SelectedTeams[teamName]
                refreshRow()
            end)
        end
    end

    refreshBtn.MouseButton1Click:Connect(rebuildTeamRows)

    -- auto-populate on first open
    task.defer(rebuildTeamRows)

    return screenGui
end

-- ============================================================
--  INITIALISE PLAYERS
-- ============================================================
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LocalPlayer then
        createESP(player)
    end
end

Players.PlayerAdded:Connect(function(player)
    -- Wait for character data
    task.wait(0.5)
    createESP(player)
end)

Players.PlayerRemoving:Connect(function(player)
    destroyESP(player)
end)

-- ============================================================
--  RENDER STEP  (update all ESP every frame)
-- ============================================================
RunService.RenderStepped:Connect(function()
    for player, _ in pairs(ESPInstances) do
        -- Catch and suppress errors for disconnected players
        local ok, err = pcall(updateESP, player)
        if not ok then
            -- player likely left mid-frame; will be cleaned up by PlayerRemoving
        end
    end
end)

-- ============================================================
--  MENU TOGGLE  (RightShift)
-- ============================================================
local menu = buildMenu()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == Config.MenuKeybind then
        Config.MenuOpen = not Config.MenuOpen
        local frame = menu and menu:FindFirstChild("MainFrame")
        if frame then
            frame.Visible = Config.MenuOpen
        end
    end
end)

print("[ESP] Loaded — press RightShift to toggle menu")
