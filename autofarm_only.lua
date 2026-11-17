-- ============================================================
-- EAZY AUTO FARM (stripped down)
-- Auto-buy farm + nearest-buyable readout, plus: trait scanner (all traits on the
-- carpet), per-brainrot traits, heading/trajectory (which base it is moving toward),
-- a walk-to-farmed-brainrot mode, your money, a detector for brainrots being added to
-- your base, lock position, and anti-fling (collision stripped from other players).
-- Removed: intro, hub, redeemer/sniper, trader, riddler, anti-ragdoll,
--          carpet ESP, themes, saved settings.
-- v5: collapsible sections, scrollable brainrot list (click = farm list), FPS/ping strip,
--     walk radius ring, fixed cash reading (parses the "$17.22T" HUD label).
-- v4: walk mode only chases brainrots from your BOUGHT LIST (kinds you bought / own),
--     inside the WALK RADIUS, still purchasable and affordable. New OPTIMIZER toggle
--     strips particles/lights/post effects/shadows/animations (fully reversible).
--     FARM LIST: names typed in are walked to + bought whenever they show up, at any
--     distance, ahead of the bought list (type a name again to remove it).
-- ============================================================

-- re-run safe: tear down a previous copy
if getgenv and getgenv().EAZYFarmStop then
    pcall(getgenv().EAZYFarmStop)
end

local cloneref_ = cloneref or function(o) return o end
local Players = cloneref_(game:GetService("Players"))
local ReplicatedStorage = cloneref_(game:GetService("ReplicatedStorage"))
local RunService = cloneref_(game:GetService("RunService"))
local UserInputService = cloneref_(game:GetService("UserInputService"))
local TweenService = cloneref_(game:GetService("TweenService"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local getupvalue_ = (debug and debug.getupvalue) or getupvalue

-- ── theme ────────────────────────────────────────────────────
local T = {
    bg    = Color3.fromRGB(8, 8, 8),
    panel = Color3.fromRGB(18, 18, 19),
    panel2 = Color3.fromRGB(32, 32, 34),
    line  = Color3.fromRGB(54, 54, 58),
    acc   = Color3.fromRGB(205, 205, 210),
    txt   = Color3.fromRGB(240, 240, 240),
    sub   = Color3.fromRGB(150, 150, 155),
    ok    = Color3.fromRGB(55, 195, 105),
    err   = Color3.fromRGB(205, 50, 50),
    warn  = Color3.fromRGB(255, 215, 0),
}
local FONT_BOLD = Enum.Font.GothamBold
local FONT_BLACK = Enum.Font.GothamBlack

-- ── price / brainrot data (read from the game's Animals module) ──
local data = { animals = nil, game = nil, mutations = nil, traits = nil, tried = false }

local function upv(fn, i)
    if not getupvalue_ then return nil end
    local a, b = getupvalue_(fn, i)
    return b ~= nil and b or a
end

local function hasNumField(tbl, field)
    for _, v in pairs(tbl) do
        if type(v) == "table" and tonumber(rawget(v, field)) ~= nil then
            return true
        end
    end
    return false
end

local function loadData()
    if data.tried then return end
    data.tried = true
    local shared = ReplicatedStorage:FindFirstChild("Shared")
    local mod = shared and shared:FindFirstChild("Animals")
    if not mod then return end
    local ok, result = pcall(require, mod)
    if not ok or type(result) ~= "table" then return end
    local gen = rawget(result, "GetGeneration")
    if type(gen) ~= "function" then return end
    for i = 1, 20 do
        local ok2, t = pcall(upv, gen, i)
        if ok2 and type(t) == "table" then
            local g = rawget(t, "Game")
            if not data.game and type(g) == "table" and tonumber(rawget(g, "AnimalGanerationModifier")) then
                data.game = t
            elseif not data.traits and hasNumField(t, "MultiplierModifier") then
                data.traits = t
            elseif not data.mutations and hasNumField(t, "Modifier") then
                data.mutations = t
            elseif not data.animals and (hasNumField(t, "Generation") or hasNumField(t, "Price")) then
                data.animals = t
            end
        end
    end
end

-- returns income/sec, definition
local function lookup(index, mutation, traits)
    local def = data.animals and rawget(data.animals, index)
    if type(def) ~= "table" then return nil, nil end
    local income = tonumber(rawget(def, "Generation"))
    if not income then
        local mod = 0
        if data.game then
            mod = tonumber(rawget(rawget(data.game, "Game") or {}, "AnimalGanerationModifier")) or 0
        end
        income = (tonumber(rawget(def, "Price")) or 0) * mod
    end
    local mult = 1
    if mutation and data.mutations then
        local m = rawget(data.mutations, mutation)
        if type(m) == "table" then mult = 1 + (tonumber(rawget(m, "Modifier")) or 0) end
    end
    local sleepy = false
    if type(traits) == "table" and data.traits then
        for _, tr in ipairs(traits) do
            if tr == "Sleepy" then
                sleepy = true
            else
                local t = rawget(data.traits, tr)
                if type(t) == "table" then mult += tonumber(rawget(t, "MultiplierModifier")) or 0 end
            end
        end
    end
    income = income * mult
    if sleepy then income = income * 0.5 end
    return math.round(income), def
end

local function fmt(n)
    local num = tonumber(n)
    if not num then return tostring(n or "---") end
    local a = math.abs(num)
    for _, u in ipairs({ { 1e33, "Dc" }, { 1e30, "No" }, { 1e27, "Oc" }, { 1e24, "Sp" }, { 1e21, "Sx" }, { 1e18, "Qi" }, { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
        if a >= u[1] then
            local v = num / u[1]
            return string.format(v >= 100 and "%.0f%s" or "%.1f%s", v, u[2])
        end
    end
    if num % 1 == 0 then return tostring(math.floor(num)) end
    return string.format("%.1f", num)
end

-- ── UI ───────────────────────────────────────────────────────
local function make(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function round(o, r) return make("UICorner", { CornerRadius = UDim.new(0, r) }, o) end
local function stroke(o, c, th, tr) return make("UIStroke", { Color = c, Thickness = th, Transparency = tr or 0 }, o) end

local function tween(obj, dur, goal, style)
    TweenService:Create(obj, TweenInfo.new(dur, style or Enum.EasingStyle.Quad), goal):Play()
end

local function label(text, size, color, font, parent)
    return make("TextLabel", {
        BackgroundTransparency = 1, Text = text, TextSize = size, TextColor3 = color,
        Font = font or FONT_BOLD, TextXAlignment = Enum.TextXAlignment.Left,
        Size = UDim2.new(1, 0, 0, 16),
    }, parent)
end

local hui = (gethui and gethui()) or playerGui
local old = hui:FindFirstChild("EazyAutoFarm")
if old then old:Destroy() end

local gui = make("ScreenGui", {
    Name = "EazyAutoFarm", ResetOnSpawn = false, DisplayOrder = 250,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, hui)

-- window: same chrome as the sniper panel (gradient body, soft accent outline, rounded)
local panel = make("Frame", {
    Name = "Panel", Size = UDim2.fromOffset(300, 700),
    Position = UDim2.new(0, 24, 0, 10),
    BackgroundColor3 = T.bg, BorderSizePixel = 0, Active = true, ClipsDescendants = true,
}, gui)
round(panel, 14)
make("UIGradient", {
    Color = ColorSequence.new(Color3.fromRGB(22, 22, 23), Color3.fromRGB(8, 8, 8)), Rotation = 90,
}, panel)
stroke(panel, T.acc, 1.5, 0.45)
do   -- shrink the panel to fit short screens
    local cam = workspace.CurrentCamera
    local vy = cam and cam.ViewportSize.Y or 700
    make("UIScale", { Name = "WinScale", Scale = math.clamp((vy - 20) / 700, 0.45, 1) }, panel)
end

-- title bar
local header = make("Frame", {
    Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = T.panel, BorderSizePixel = 0, Active = true,
}, panel)
round(header, 14)
make("Frame", {   -- square off the title bar's bottom corners
    Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14),
    BackgroundColor3 = T.panel, BorderSizePixel = 0,
}, header)
do
local icon = make("ImageLabel", {
    Size = UDim2.fromOffset(24, 24), Position = UDim2.new(0, 12, 0.5, -12),
    BackgroundColor3 = T.panel2, BorderSizePixel = 0,
    Image = "rbxthumb://type=Asset&id=92405934506374&w=150&h=150",
}, header)
round(icon, 12)
stroke(icon, T.acc, 1.5, 0.2)
local title = label("AUTO FARM", 14, T.txt, FONT_BLACK, header)
title.Size = UDim2.new(1, -180, 1, 0)
title.Position = UDim2.fromOffset(44, 0)

end
local lMoney = label("$ ---", 12, T.ok, FONT_BOLD, header)
lMoney.Size = UDim2.new(0, 110, 1, 0)
lMoney.Position = UDim2.new(1, -150, 0, 0)
lMoney.TextXAlignment = Enum.TextXAlignment.Right

local closeBtn = make("TextButton", {
    Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -28, 0.5, -11),
    BackgroundColor3 = T.panel2, BorderSizePixel = 0, Text = "X", TextSize = 12,
    Font = FONT_BOLD, TextColor3 = T.txt, AutoButtonColor = false,
}, header)
round(closeBtn, 8)
do
    local st = stroke(closeBtn, T.line, 1, 0.2)
    closeBtn.MouseEnter:Connect(function()
        tween(closeBtn, 0.12, { BackgroundColor3 = T.panel })
        tween(st, 0.12, { Color = T.acc, Transparency = 0 })
    end)
    closeBtn.MouseLeave:Connect(function()
        tween(closeBtn, 0.12, { BackgroundColor3 = T.panel2 })
        tween(st, 0.12, { Color = T.line, Transparency = 0.2 })
    end)
end

-- dragging: reads the pointer every frame and lets go by itself when the button is up,
-- so a drag can never get stuck (same controller as the original panel)
do
    local D = { target = nil, input = nil, mouse = false, sx = 0, sy = 0, base = nil, conn = nil }
    local function ptr()
        if D.mouse then
            local m = UserInputService:GetMouseLocation()
            return m.X, m.Y
        end
        local p = D.input.Position
        return p.X, p.Y
    end
    local function stopDrag()
        D.target, D.input = nil, nil
        if D.conn then D.conn:Disconnect() D.conn = nil end
    end
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            stopDrag()
            D.target, D.input = panel, input
            D.mouse = input.UserInputType == Enum.UserInputType.MouseButton1
            D.sx, D.sy = ptr()
            D.base = panel.Position
            D.conn = RunService.RenderStepped:Connect(function()
                local t = D.target
                if not t or not t.Parent then stopDrag() return end
                local released
                if D.mouse then
                    released = not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
                else
                    local st = D.input.UserInputState
                    released = st == Enum.UserInputState.End or st == Enum.UserInputState.Cancel
                end
                if released then stopDrag() return end
                local x, y = ptr()
                t.Position = UDim2.new(D.base.X.Scale, D.base.X.Offset + (x - D.sx),
                    D.base.Y.Scale, D.base.Y.Offset + (y - D.sy))
            end)
        end
    end)
end

-- stats strip: FPS + ping with small icons (colour = how healthy the number is)
local statsBar = make("Frame", {
    Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 48), BackgroundTransparency = 1,
}, panel)
local fpsScreen = make("Frame", {
    Size = UDim2.fromOffset(14, 10), Position = UDim2.fromOffset(0, 3), BackgroundTransparency = 1,
}, statsBar)
round(fpsScreen, 2)
local fpsStroke = stroke(fpsScreen, T.sub, 1.5, 0)
local fpsStand = make("Frame", {
    Size = UDim2.fromOffset(6, 2), Position = UDim2.fromOffset(4, 15),
    BackgroundColor3 = T.sub, BorderSizePixel = 0,
}, statsBar)
local fpsLabel = label("-- FPS", 11, T.sub, FONT_BOLD, statsBar)
fpsLabel.Size = UDim2.fromOffset(64, 20)
fpsLabel.Position = UDim2.fromOffset(20, 0)
local pingBars = {}
for i = 1, 3 do
    local h = 3 + i * 3
    pingBars[i] = make("Frame", {
        Size = UDim2.fromOffset(3, h), Position = UDim2.fromOffset(104 + (i - 1) * 5, 15 - h),
        BackgroundColor3 = T.line, BorderSizePixel = 0,
    }, statsBar)
    round(pingBars[i], 1)
end
local pingLabel = label("-- ms", 11, T.sub, FONT_BOLD, statsBar)
pingLabel.Size = UDim2.fromOffset(70, 20)
pingLabel.Position = UDim2.fromOffset(124, 0)

-- status bar (fixed under the header)
local statusBar = make("Frame", {
    Size = UDim2.new(1, -24, 0, 32), Position = UDim2.fromOffset(12, 72),
    BackgroundColor3 = T.panel, BorderSizePixel = 0,
}, panel)

-- everything else lives in a scrolling body made of collapsible sections
local body = make("ScrollingFrame", {
    Size = UDim2.new(1, -24, 1, -118), Position = UDim2.fromOffset(12, 110), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = T.line,
    CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    ScrollingDirection = Enum.ScrollingDirection.Y,
}, panel)
make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)
make("UIPadding", { PaddingRight = UDim.new(0, 6) }, body)

-- section(title, open): header button that collapses its content. Rows created afterwards
-- (they all parent to `body`) land inside the newest section.
local scrollRoot, sectionCount = body, 0
local function section(title, open)
    sectionCount += 1
    local wrap = make("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, LayoutOrder = sectionCount,
    }, scrollRoot)
    make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, wrap)
    local head = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = T.panel, BorderSizePixel = 0,
        Text = "", AutoButtonColor = false, LayoutOrder = 0,
    }, wrap)
    round(head, 7)
    stroke(head, T.line, 1, 0.3)
    local t = label((open and "v   " or ">   ") .. title, 10, T.acc, FONT_BLACK, head)
    t.Size = UDim2.new(1, -16, 1, 0)
    t.Position = UDim2.fromOffset(10, 0)
    local content = make("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, LayoutOrder = 1, Visible = open and true or false,
    }, wrap)
    make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, content)
    head.MouseButton1Click:Connect(function()
        content.Visible = not content.Visible
        t.Text = (content.Visible and "v   " or ">   ") .. title
    end)
    body = content
    return content
end
round(statusBar, 9)
stroke(statusBar, T.line, 1, 0.3)
local dot = make("Frame", {
    Size = UDim2.fromOffset(8, 8), Position = UDim2.new(0, 12, 0.5, -4),
    BackgroundColor3 = T.line, BorderSizePixel = 0,
}, statusBar)
round(dot, 4)
local statusText = label("idle", 12, T.sub, FONT_BOLD, statusBar)
statusText.Size = UDim2.new(1, -32, 1, 0)
statusText.Position = UDim2.fromOffset(28, 0)
statusText.TextTruncate = Enum.TextTruncate.AtEnd

local function setStatus(text, kind)
    statusText.Text = text
    local c = kind == "ok" and T.ok or kind == "err" and T.err or kind == "busy" and T.acc
        or kind == "wait" and T.warn or T.sub
    statusText.TextColor3 = c
    dot.BackgroundColor3 = c
end

-- toggles
local Enabled, WalkEnabled = false, false
local onFarmChanged, onWalkChanged, onLockChanged, onFlingChanged, onOptChanged, onRingChanged

-- toggle row: same look as the original panel (label dims when off, pill switch slides)
local function makeToggle(order, text, onChange)
    local rowF = make("Frame", {
        Size = UDim2.new(1, 0, 0, 31), BackgroundColor3 = T.panel, BorderSizePixel = 0, LayoutOrder = order,
    }, body)
    round(rowF, 8)
    stroke(rowF, T.line, 1, 0.3)
    local name = label(text, 11, T.sub, FONT_BOLD, rowF)
    name.Size = UDim2.new(1, -56, 1, 0)
    name.Position = UDim2.fromOffset(12, 0)
    name.TextTruncate = Enum.TextTruncate.AtEnd
    local track = make("Frame", {
        Size = UDim2.fromOffset(36, 18), Position = UDim2.new(1, -44, 0.5, -9),
        BackgroundColor3 = T.line, BorderSizePixel = 0,
    }, rowF)
    round(track, 9)
    local knob = make("Frame", {
        Size = UDim2.fromOffset(14, 14), Position = UDim2.new(0, 2, 0.5, -7),
        BackgroundColor3 = T.txt, BorderSizePixel = 0,
    }, track)
    round(knob, 7)
    local hit = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, rowF)
    local state = false
    local function paint(v)
        state = v and true or false
        tween(track, 0.16, { BackgroundColor3 = state and T.acc or T.line })
        tween(knob, 0.16, { Position = UDim2.new(0, state and 20 or 2, 0.5, -7) }, Enum.EasingStyle.Back)
        tween(name, 0.16, { TextColor3 = state and T.txt or T.sub })
    end
    hit.MouseButton1Click:Connect(function()
        paint(not state)
        onChange(state)
    end)
    return paint
end

section("CONTROLS", true)
local paintFarm = makeToggle(2, "AUTO FARM", function(on) if onFarmChanged then onFarmChanged(on) end end)
local paintWalk = makeToggle(3, "WALK TO BOUGHT BRAINROTS", function(on) if onWalkChanged then onWalkChanged(on) end end)
local paintLock = makeToggle(4, "LOCK POSITION", function(on) if onLockChanged then onLockChanged(on) end end)
local paintFling = makeToggle(5, "ANTI FLING", function(on) if onFlingChanged then onFlingChanged(on) end end)
local paintOpt = makeToggle(6, "OPTIMIZER (STRIP FX / ANIMS)", function(on) if onOptChanged then onOptChanged(on) end end)

-- walk radius stepper
local walkRadius = 60
local showRadius = false
local smallBtn
do
local radiusRow = make("Frame", {
    Size = UDim2.new(1, 0, 0, 31), BackgroundColor3 = T.panel, BorderSizePixel = 0, LayoutOrder = 7,
}, body)
round(radiusRow, 8)
stroke(radiusRow, T.line, 1, 0.3)
local radiusLabel = label("WALK RADIUS: 60 studs", 11, T.txt, FONT_BOLD, radiusRow)
radiusLabel.Size = UDim2.new(1, -90, 1, 0)
radiusLabel.Position = UDim2.fromOffset(12, 0)
function smallBtn(parent, text, w, xOff)
    local b = make("TextButton", {
        Size = UDim2.fromOffset(w, 22), Position = UDim2.new(1, xOff, 0.5, -11),
        BackgroundColor3 = T.panel2, BorderSizePixel = 0, Text = text, TextSize = 12,
        Font = FONT_BOLD, TextColor3 = T.txt, AutoButtonColor = false,
    }, parent)
    round(b, 7)
    stroke(b, T.line, 1, 0.2)
    return b
end
local function setRadius(v)
    walkRadius = math.clamp(v, 10, 300)
    radiusLabel.Text = "WALK RADIUS: " .. walkRadius .. " studs"
end
smallBtn(radiusRow, "-", 24, -64).MouseButton1Click:Connect(function() setRadius(walkRadius - 10) end)
smallBtn(radiusRow, "+", 24, -34).MouseButton1Click:Connect(function() setRadius(walkRadius + 10) end)
end

local paintShowRadius = makeToggle(8, "SHOW WALK RADIUS (RING)", function(on)
    if onRingChanged then onRingChanged(on) end
end)

section("LISTS", true)
-- bought list readout (+ clear button)
local boughtRow = make("Frame", {
    Size = UDim2.new(1, 0, 0, 31), BackgroundColor3 = T.panel, BorderSizePixel = 0, LayoutOrder = 8,
}, body)
round(boughtRow, 8)
stroke(boughtRow, T.line, 1, 0.3)
local lBought = label("BOUGHT LIST: 0 kinds", 11, T.sub, FONT_BOLD, boughtRow)
lBought.Size = UDim2.new(1, -74, 1, 0)
lBought.Position = UDim2.fromOffset(12, 0)
lBought.TextTruncate = Enum.TextTruncate.AtEnd
local boughtClear = smallBtn(boughtRow, "CLEAR", 52, -60)
boughtClear.TextSize = 10

-- farm list: names that are always farmed / walked to when detected
local listDirty = true   -- the brainrot list needs a redraw
local farmList = {}   -- lowercase name fragment -> true
local farmRow = make("Frame", {
    Size = UDim2.new(1, 0, 0, 31), BackgroundColor3 = T.panel, BorderSizePixel = 0, LayoutOrder = 9,
}, body)
round(farmRow, 8)
stroke(farmRow, T.line, 1, 0.3)
local farmBox = make("TextBox", {
    Size = UDim2.new(1, -82, 0, 22), Position = UDim2.fromOffset(8, 4),
    BackgroundColor3 = T.panel2, BorderSizePixel = 0, Text = "", PlaceholderText = "name: filters list / ADD to farm list",
    PlaceholderColor3 = T.sub, TextColor3 = T.txt, TextSize = 11, Font = FONT_BOLD,
    TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false,
}, farmRow)
round(farmBox, 7)
make("UIPadding", { PaddingLeft = UDim.new(0, 6) }, farmBox)
local farmAdd = smallBtn(farmRow, "ADD", 52, -60)
farmAdd.TextSize = 10

local farmListRow = make("Frame", {
    Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = T.panel, BorderSizePixel = 0, LayoutOrder = 10,
}, body)
round(farmListRow, 8)
stroke(farmListRow, T.line, 1, 0.3)
local lFarm = label("FARM LIST: empty", 10, T.sub, FONT_BOLD, farmListRow)
lFarm.Size = UDim2.new(1, -74, 1, -6)
lFarm.Position = UDim2.fromOffset(12, 3)
lFarm.TextWrapped = true
lFarm.TextTruncate = Enum.TextTruncate.AtEnd
lFarm.TextYAlignment = Enum.TextYAlignment.Top
local farmClear = smallBtn(farmListRow, "CLEAR", 52, -60)
farmClear.TextSize = 10

local function refreshFarmLabel()
    local names = {}
    for n in pairs(farmList) do names[#names + 1] = n end
    table.sort(names)
    lFarm.Text = #names > 0 and ("FARM LIST: " .. table.concat(names, ", ")) or "FARM LIST: empty (type a name, ADD; again = remove)"
    lFarm.TextColor3 = #names > 0 and T.txt or T.sub
    listDirty = true
end
local function toggleFarmKey(name)
    name = (name or ""):lower()
    if name == "" then return end
    if farmList[name] then farmList[name] = nil else farmList[name] = true end
    refreshFarmLabel()
end
local function toggleFarmName()
    local name = farmBox.Text:match("^%s*(.-)%s*$") or ""
    if name == "" then return end
    toggleFarmKey(name)
    farmBox.Text = ""
end
farmBox:GetPropertyChangedSignal("Text"):Connect(function() listDirty = true end)
farmAdd.MouseButton1Click:Connect(toggleFarmName)
farmBox.FocusLost:Connect(function(enter) if enter then toggleFarmName() end end)
farmClear.MouseButton1Click:Connect(function()
    farmList = {}
    refreshFarmLabel()
end)

-- nearest buyable readout
section("BRAINROTS  (click a row = farm list)", true)
local listMode = "track"
local tabFarm
do
local tabRow = make("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, body)
local function tabButton(text, xScale, xOff)
    local b = make("TextButton", {
        Size = UDim2.new(1 / 3, -4, 1, 0), Position = UDim2.new(xScale, xOff, 0, 0),
        BackgroundColor3 = T.panel2, BorderSizePixel = 0, Text = text, TextSize = 10,
        Font = FONT_BOLD, TextColor3 = T.sub, AutoButtonColor = false,
    }, tabRow)
    round(b, 7)
    return b
end
local tabTrack = tabButton("ON TRACK", 0, 0)
tabFarm = tabButton("FARMING", 1 / 3, 2)
local tabAll = tabButton("ALL KINDS", 2 / 3, 4)
local function paintTabs()
    tabTrack.TextColor3 = listMode == "track" and T.txt or T.sub
    tabTrack.BackgroundColor3 = listMode == "track" and T.line or T.panel2
    tabFarm.TextColor3 = listMode == "farming" and T.txt or T.sub
    tabFarm.BackgroundColor3 = listMode == "farming" and T.line or T.panel2
    tabAll.TextColor3 = listMode == "all" and T.txt or T.sub
    tabAll.BackgroundColor3 = listMode == "all" and T.line or T.panel2
end
paintTabs()
tabTrack.MouseButton1Click:Connect(function() listMode = "track" listDirty = true paintTabs() end)
tabFarm.MouseButton1Click:Connect(function() listMode = "farming" listDirty = true paintTabs() end)
tabAll.MouseButton1Click:Connect(function() listMode = "all" listDirty = true paintTabs() end)
end

local listFrame = make("ScrollingFrame", {
    Size = UDim2.new(1, 0, 0, 170), BackgroundColor3 = T.panel, BorderSizePixel = 0, LayoutOrder = 2,
    ScrollBarThickness = 4, ScrollBarImageColor3 = T.line, CanvasSize = UDim2.new(),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
}, body)
round(listFrame, 8)
stroke(listFrame, T.line, 1, 0.3)
make("UIListLayout", { Padding = UDim.new(0, 1), SortOrder = Enum.SortOrder.LayoutOrder }, listFrame)
make("UIPadding", {
    PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3),
}, listFrame)
local listRows, listKeys = {}, {}
local function getListRow(i)
    local r = listRows[i]
    if r then return r end
    r = make("TextButton", {
        Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
        TextSize = 10, Font = FONT_BOLD, TextColor3 = T.txt, TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, AutoButtonColor = false, LayoutOrder = i,
    }, listFrame)
    r.MouseButton1Click:Connect(function()
        local key = listKeys[i]
        if key then toggleFarmKey(key) end
    end)
    listRows[i] = r
    return r
end

section("NEAREST BUYABLE", true)

local function row(order, text, color, h)
    local l = label(text, 11, color or T.sub, FONT_BOLD, body)
    l.Size = UDim2.new(1, 0, 0, h or 16)
    l.LayoutOrder = order
    l.TextTruncate = Enum.TextTruncate.AtEnd
    return l
end
local lName     = row(12, "Name: ---", T.txt)
local lIncome   = row(13, "Income: --- /sec", T.acc)
local lRarity   = row(14, "Rarity: ---")
local lMutation = row(15, "Mutation: ---")
local lTraits   = row(16, "Traits: ---", T.sub, 30)
lTraits.TextWrapped = true
lTraits.TextYAlignment = Enum.TextYAlignment.Top
local lDist     = row(17, "Distance: ---", T.sub, 14)
lDist.TextSize = 9
local lHeading = row(18, "Heading: ---", T.warn, 30)
lHeading.TextWrapped = true
lHeading.TextYAlignment = Enum.TextYAlignment.Top

section("TRAITS ON CARPET", true)
local lCarpet = row(20, "---", T.sub, 64)
lCarpet.TextWrapped = true
lCarpet.TextSize = 10
lCarpet.TextTruncate = Enum.TextTruncate.None
lCarpet.TextYAlignment = Enum.TextYAlignment.Top

section("YOUR BASE", true)
local lBase = row(22, "scanning...", T.sub, 66)
section("DEBUG", false)
local lDebug = row(23, "debug: ---", T.sub, 44)
lDebug.TextSize = 9
lDebug.TextWrapped = true
lDebug.TextTruncate = Enum.TextTruncate.None
lDebug.TextYAlignment = Enum.TextYAlignment.Top
lBase.TextWrapped = true
lBase.TextSize = 10
lBase.TextTruncate = Enum.TextTruncate.None
lBase.TextYAlignment = Enum.TextYAlignment.Top

local function clearReadout()
    lName.Text = "Name: ---"
    lIncome.Text = "Income: --- /sec"
    lRarity.Text = "Rarity: ---"
    lMutation.Text = "Mutation: ---"
    lTraits.Text = "Traits: ---"
    lDist.Text = "Distance: ---"
    lHeading.Text = "Heading: ---"
end

-- ── farm logic ───────────────────────────────────────────────
local models = {}   -- carpet brainrots: model -> its Purchase prompt (rebuilt every scan)
local entries = {}  -- every ProximityPrompt found in workspace -> the model it belongs to
local motion = {}   -- model -> { pos, t, vel }  (for trajectory)
local conns = {}
local ALIVE = true
local debugPrinted = 0
local dbgSeen = {}

local function modelPart(model)
    if model:IsA("BasePart") then return model end
    if model:IsA("Model") then
        return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    end
    return model:FindFirstChildWhichIsA("BasePart", true)
end

local function traitList(model)
    local traits = model:GetAttribute("Traits")
    if type(traits) == "string" then
        return traits ~= "" and { traits } or {}
    end
    return type(traits) == "table" and traits or {}
end

local function inPlots(inst)
    local plots = workspace:FindFirstChild("Plots")
    return plots ~= nil and inst:IsDescendantOf(plots)
end

-- ── bought list ──────────────────────────────────────────────
-- Kinds of brainrot (by their "Index" attribute) that are yours: ones the farm bought
-- (confirmed by the buy prompt going away + your money dropping) and ones that show up
-- in your base. Walk mode only chases carpet brainrots whose kind is in here.
local bought = {}            -- index -> { name = string, t = os.clock() }
local boughtSeeded = false   -- first base snapshot seeds the list with what you already own
local boughtLast = nil

local function boughtCount()
    local n = 0
    for _ in pairs(bought) do n += 1 end
    return n
end

local function refreshBoughtLabel()
    local n = boughtCount()
    lBought.Text = "BOUGHT LIST: " .. n .. (n == 1 and " kind" or " kinds")
        .. (boughtLast and (" (last: " .. boughtLast .. ")") or "")
    lBought.TextColor3 = n > 0 and T.txt or T.sub
end

local function addBought(index)
    if index == nil then return end
    local _, def = lookup(index)
    local name = tostring(def and rawget(def, "DisplayName") or index)
    local new = bought[index] == nil
    bought[index] = { name = name, t = os.clock() }
    listDirty = true
    if new then boughtLast = name end
    refreshBoughtLabel()
end

boughtClear.MouseButton1Click:Connect(function()
    bought, boughtLast = {}, nil
    listDirty = true
    refreshBoughtLabel()
end)

-- the brainrot a prompt belongs to: the nearest ancestor Model carrying an "Index"
-- attribute, else the first Model above it, else the part it sits on
local function modelOf(prompt)
    local cur, firstModel = prompt.Parent, nil
    for _ = 1, 8 do
        if not cur or cur == workspace then break end
        if cur:IsA("Model") then
            firstModel = firstModel or cur
            if cur:GetAttribute("Index") ~= nil then return cur end
        end
        cur = cur.Parent
    end
    if firstModel then return firstModel end
    local par = prompt.Parent
    if par and par:IsA("Attachment") then par = par.Parent end
    return par
end

local function track(inst)
    if inst:IsA("ProximityPrompt") and not inPlots(inst) then
        local m = modelOf(inst)
        if m then entries[inst] = m end
    end
end

local function promptPos(prompt, model)
    local par = prompt.Parent
    if par and par:IsA("Attachment") then return par.WorldPosition end
    if par and par:IsA("BasePart") then return par.Position end
    local part = model and modelPart(model)
    return part and part.Position or nil
end

-- rebuild `models` from the prompts that currently say "Purchase"
local function refreshModels()
    local fresh = {}
    for prompt, m in pairs(entries) do
        if not prompt.Parent or not m.Parent then
            entries[prompt] = nil
        elseif prompt.ActionText == "Purchase" then
            fresh[m] = prompt
        end
    end
    for m in pairs(motion) do
        if not fresh[m] then motion[m] = nil end
    end
    models = fresh
end

local function nearest(filter)
    local char = localPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return nil, nil, math.huge end
    local best, bestPrompt, bestDist = nil, nil, math.huge
    for m, prompt in pairs(models) do
        if prompt.Enabled then
            local pos = promptPos(prompt, m)
            if pos then
                local d = (root.Position - pos).Magnitude
                if d < bestDist and (not filter or filter(m, prompt, d)) then
                    best, bestPrompt, bestDist = m, prompt, d
                end
            end
        end
    end
    return best, bestPrompt, bestDist
end

local function fullPath(inst)
    local ok, r = pcall(function() return inst:GetFullName() end)
    return ok and r or tostring(inst)
end

local function press(prompt)
    if not prompt or not prompt.Parent or not prompt.Enabled then
        return false, "prompt gone"
    end
    if type(fireproximityprompt) == "function" then
        local ok = pcall(fireproximityprompt, prompt)
        return ok, (not ok) and "fire failed" or nil
    end
    local ok = pcall(function()
        prompt:InputHoldBegin()
        task.wait(math.max(prompt.HoldDuration, 0.05) + 0.05)
        prompt:InputHoldEnd()
    end)
    return ok, (not ok) and "hold failed" or nil
end

-- ── bases / trajectory ───────────────────────────────────────
-- Plot owners come from each plot's PlotSign. The heading is inferred from the
-- brainrot's own movement (position change between scans): the base whose centre
-- lies closest to the line the brainrot is travelling along, ahead of it.
local function plotOwner(plot)
    local sign = plot:FindFirstChild("PlotSign")
    if not sign then return nil end
    local marker = sign:FindFirstChild("YourBase")
    if marker and marker:IsA("BillboardGui") and marker.Enabled then return "YOUR BASE" end
    local sg = sign:FindFirstChildWhichIsA("SurfaceGui", true)
    local l = sg and sg:FindFirstChildWhichIsA("TextLabel", true)
    local text = l and l.Text or ""
    return text ~= "" and text or "empty plot"
end

local function flat(v) return Vector3.new(v.X, 0, v.Z) end

local MIN_SPEED = 0.5      -- studs/sec below this counts as standing still
local MAX_OFFSET = 60      -- studs: how far a base may sit from the travel line

local function headingOf(model)
    local m = motion[model]
    if not m or not m.vel then return "Heading: measuring..." end
    local v = flat(m.vel)
    if v.Magnitude < MIN_SPEED then return "Heading: standing still" end
    local dir = v.Unit
    local plots = workspace:FindFirstChild("Plots")
    if not plots then
        return string.format("Heading: %.1f studs/s (no Plots folder)", v.Magnitude)
    end
    local best, bestOff, bestAlong
    for _, plot in ipairs(plots:GetChildren()) do
        local ok, pivot = pcall(function() return plot:GetPivot().Position end)
        if ok then
            local to = flat(pivot - m.pos)
            local along = to:Dot(dir)
            if along > 0 then
                local off = (to - dir * along).Magnitude
                if not bestOff or off < bestOff then
                    best, bestOff, bestAlong = plot, off, along
                end
            end
        end
    end
    if best and bestOff <= MAX_OFFSET then
        return string.format("Heading: %s's base\n%.1f studs/s, ~%d studs away",
            tostring(plotOwner(best) or best.Name), v.Magnitude, math.floor(bestAlong))
    end
    return string.format("Heading: no base in line\n%.1f studs/s", v.Magnitude)
end

local function updateMotion()
    local now = os.clock()
    for m in pairs(models) do
        if m.Parent then
            local part = modelPart(m)
            if part then
                local rec = motion[m]
                if rec and now > rec.t then
                    local dt = now - rec.t
                    if dt >= 0.15 then
                        rec.vel = (part.Position - rec.pos) / dt
                        rec.pos, rec.t = part.Position, now
                    end
                elseif not rec then
                    motion[m] = { pos = part.Position, t = now }
                end
            end
        end
    end
end

-- ── carpet trait scanner ─────────────────────────────────────
local function scanCarpet()
    local counts, total, withTraits = {}, 0, 0
    for m in pairs(models) do
        if m.Parent then
            total += 1
            local list = traitList(m)
            if #list > 0 then withTraits += 1 end
            for _, t in ipairs(list) do counts[t] = (counts[t] or 0) + 1 end
        end
    end
    local names = {}
    for t in pairs(counts) do names[#names + 1] = t end
    table.sort(names, function(a, b)
        if counts[a] ~= counts[b] then return counts[a] > counts[b] end
        return a < b
    end)
    if total == 0 then
        lCarpet.Text = "no brainrots on the carpet"
        return
    end
    local parts = {}
    for _, t in ipairs(names) do
        parts[#parts + 1] = (counts[t] > 1) and (t .. " x" .. counts[t]) or t
    end
    lCarpet.Text = string.format("%d brainrots, %d with traits\n%s", total, withTraits,
        #parts > 0 and table.concat(parts, ", ") or "no traits running")
end

-- ── money ────────────────────────────────────────────────────
-- Source order: player attribute Cash/Money, leaderstats cash/money, then the HUD label
-- that shows your cash as "$17.22T": the largest visible label whose whole text is a
-- "$" amount (digits plus a K/M/B/T/Qa/... suffix). Labels without a "$" (bunny coins,
-- gems) and things like "$15/s" never match.
local myMoney, moneyDesc = nil, "none"
local updateMoney
do
local moneySrc, moneyHud, lastMoneyScan = nil, false, 0
local SUFFIX = {
    K = 1e3, M = 1e6, B = 1e9, T = 1e12, Qa = 1e15, Qi = 1e18,
    Sx = 1e21, Sp = 1e24, Oc = 1e27, No = 1e30, Dc = 1e33,
}

local function parseMoney(text)
    if type(text) ~= "string" then return nil end
    text = text:gsub("<[^>]+>", "")
    local num, suf = text:match("^%s*%$?%s*([%d,]*%.?%d+)%s*(%a*)%s*$")
    if not num then return nil end
    num = tonumber((num:gsub(",", "")))
    if not num then return nil end
    if suf == "" then return num end
    local mult = SUFFIX[suf] or SUFFIX[suf:sub(1, 1):upper() .. suf:sub(2):lower()]
    return mult and num * mult or nil
end

local function findHudMoney()
    local best, bestScore
    for _, d in ipairs(playerGui:GetDescendants()) do
        if d:IsA("TextLabel") and d.Visible and not d:IsDescendantOf(gui) and d.AbsoluteSize.Y > 0 then
            local text = d.Text
            if text:find("^%s*%$") and parseMoney(text) then
                local score = d.AbsoluteSize.Y
                local n = d.Name:lower()
                if n:find("cash", 1, true) or n:find("money", 1, true) then score += 10000 end
                if not bestScore or score > bestScore then best, bestScore = d, score end
            end
        end
    end
    return best
end

local function findMoneySource()
    moneyHud = false
    for _, n in ipairs({ "Cash", "Money" }) do
        if tonumber(localPlayer:GetAttribute(n)) then
            moneyDesc = "player attribute " .. n
            return function() return tonumber(localPlayer:GetAttribute(n)) end
        end
    end
    local ls = localPlayer:FindFirstChild("leaderstats")
    if ls then
        for _, c in ipairs(ls:GetChildren()) do
            local nm = c.Name:lower()
            if c:IsA("ValueBase") and (nm:find("cash", 1, true) or nm:find("money", 1, true))
                and tonumber(c.Value) then
                moneyDesc = "leaderstats." .. c.Name
                return function() return tonumber(c.Value) end
            end
        end
    end
    local d = findHudMoney()
    if d then
        moneyHud = true
        moneyDesc = "HUD label " .. fullPath(d)
        return function()
            if not d.Parent then return nil end
            return parseMoney(d.Text)
        end
    end
    return nil
end

local function fmtMoney(n)
    local a = math.abs(n)
    for _, u in ipairs({ { 1e33, "Dc" }, { 1e30, "No" }, { 1e27, "Oc" }, { 1e24, "Sp" }, { 1e21, "Sx" },
        { 1e18, "Qi" }, { 1e15, "Qa" }, { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
        if a >= u[1] then
            local v = n / u[1]
            return string.format(v >= 100 and "%.1f%s" or "%.2f%s", v, u[2])
        end
    end
    return tostring(math.floor(n))
end

function updateMoney()
    local now = os.clock()
    if (not moneySrc and now - lastMoneyScan > 3) or (moneyHud and now - lastMoneyScan > 5) then
        lastMoneyScan = now
        moneySrc = findMoneySource()   -- HUD sources are re-picked now and then
    end
    if not moneySrc then
        myMoney = nil
        lMoney.Text = "$ not found"
        return
    end
    local ok, v = pcall(moneySrc)
    if not ok or type(v) ~= "number" then moneySrc = nil return end
    myMoney = v
    lMoney.Text = "$" .. fmtMoney(v)
end
end -- money scope

-- ── your base: detect brainrots being added ──────────────────
-- Two signals: (1) a Model carrying an "Index" attribute appearing inside your plot,
-- (2) a slow check of the plot's server-side animal list for new entries.
local myPlot, baseCount, serverCount = nil, 0, nil
local baseSeen, baseConns, baseLog = {}, {}, {}
local recentAdds = {}          -- index -> os.clock() (so both signals don't double-report)
local snapshot = nil           -- sig -> { n, index, mutation, traits }
local baseDirty = true
local baseLoopId = 0
local requestData = nil

local function isMine(plot)
    local sign = plot:FindFirstChild("PlotSign")
    if not sign then return false end
    local marker = sign:FindFirstChild("YourBase")
    if marker and marker:IsA("BillboardGui") and marker.Enabled then return true end
    local sg = sign:FindFirstChildWhichIsA("SurfaceGui", true)
    local l = sg and sg:FindFirstChildWhichIsA("TextLabel", true)
    if l then
        local text = l.Text:lower()
        return text:find(localPlayer.Name:lower(), 1, true) ~= nil
            or text:find(localPlayer.DisplayName:lower(), 1, true) ~= nil
    end
    return false
end

local function findMyPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        if isMine(plot) then return plot end
    end
    return nil
end

local function describe(index, mutation, traits)
    local list = {}
    for _, t in pairs(traits or {}) do
        if type(t) == "string" then list[#list + 1] = t end
    end
    table.sort(list)
    local income, def = lookup(index, mutation, #list > 0 and list or nil)
    local extra = {}
    if mutation and mutation ~= "" then extra[#extra + 1] = tostring(mutation) end
    if #list > 0 then extra[#extra + 1] = table.concat(list, "/") end
    return tostring(def and rawget(def, "DisplayName") or index)
        .. (#extra > 0 and (" [" .. table.concat(extra, ", ") .. "]") or "")
        .. (income and (" " .. fmt(income) .. "/s") or ""), table.concat(list, ",")
end

local function announce(text)
    table.insert(baseLog, 1, text)
    while #baseLog > 3 do table.remove(baseLog) end
    baseDirty = true
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Added to your base", Text = text, Duration = 4,
        })
    end)
end

local function considerBase(inst, notify)
    if baseSeen[inst] or not inst:IsA("Model") then return end
    local index = inst:GetAttribute("Index")
    if index == nil then return end
    baseSeen[inst] = true
    baseCount += 1
    baseDirty = true
    if notify then
        recentAdds[index] = os.clock()
        addBought(index)
        announce("+ " .. (describe(index, inst:GetAttribute("Mutation"), traitList(inst))))
    end
end

local function detachPlot()
    for _, c in ipairs(baseConns) do pcall(function() c:Disconnect() end) end
    baseConns, baseSeen, baseCount, snapshot, serverCount = {}, {}, 0, nil, nil
    baseDirty = true
end

local function attachPlot(plot)
    detachPlot()
    myPlot = plot
    if not plot then return end
    for _, d in ipairs(plot:GetDescendants()) do considerBase(d, false) end
    baseConns[#baseConns + 1] = plot.DescendantAdded:Connect(function(d)
        if not d:IsA("Model") then return end
        considerBase(d, true)
        if not baseSeen[d] then   -- the Index attribute can arrive a moment after the model
            task.delay(0.4, function()
                if d.Parent and myPlot == plot then considerBase(d, true) end
            end)
        end
    end)
    baseConns[#baseConns + 1] = plot.DescendantRemoving:Connect(function(d)
        if baseSeen[d] then
            baseSeen[d] = nil
            baseCount -= 1
            baseDirty = true
        end
    end)
end

local function pollServerList()
    if not myPlot then return end
    if not requestData then
        local pk = ReplicatedStorage:FindFirstChild("Packages")
        local sy = pk and pk:FindFirstChild("Synchronizer")
        local rd = sy and sy:FindFirstChild("RequestData")
        if rd and rd:IsA("RemoteFunction") then requestData = rd end
    end
    if not requestData then return end
    local plot = myPlot
    local ok, cache = pcall(function() return requestData:InvokeServer(plot.Name) end)
    if not ok or type(cache) ~= "table" or plot ~= myPlot then return end
    local list = cache.AnimalList or cache.Animals
    if type(list) ~= "table" then return end

    local snap, total = {}, 0
    for _, a in pairs(list) do
        if type(a) == "table" and a.Index then
            total += 1
            local text, traitSig = describe(a.Index, a.Mutation, type(a.Traits) == "table" and a.Traits
                or (type(a.Traits) == "string" and a.Traits ~= "" and { a.Traits }) or nil)
            local sig = tostring(a.Index) .. "|" .. tostring(a.Mutation or "") .. "|" .. traitSig
            local e = snap[sig]
            if e then
                e.n += 1
            else
                snap[sig] = { n = 1, index = a.Index, text = text }
            end
        end
    end
    if snapshot then   -- compare counts per kind, so moving a brainrot between slots isn't an "add"
        for sig, e in pairs(snap) do
            local before = snapshot[sig] and snapshot[sig].n or 0
            if e.n > before then
                local now = os.clock()
                addBought(e.index)
                if not (recentAdds[e.index] and now - recentAdds[e.index] < 6) then
                    recentAdds[e.index] = now
                    announce("+ " .. e.text)
                end
            end
        end
    end
    if not boughtSeeded then   -- first look at your base: everything you own counts as yours
        boughtSeeded = true
        for _, e in pairs(snap) do addBought(e.index) end
    end
    snapshot = snap
    if serverCount ~= total then serverCount = total baseDirty = true end
end

local function refreshBaseText()
    if not baseDirty then return end
    baseDirty = false
    if not myPlot then
        lBase.Text = "base not found yet"
        return
    end
    local lines = { string.format("In base: %d", serverCount or baseCount) }
    if #baseLog == 0 then
        lines[#lines + 1] = "no additions yet"
    else
        for _, l in ipairs(baseLog) do lines[#lines + 1] = l end
    end
    lBase.Text = table.concat(lines, "\n")
end

local function startBaseWatch()
    baseLoopId += 1
    local id = baseLoopId
    task.spawn(function()
        local lastPoll = 0
        while ALIVE and id == baseLoopId do
            local plot = findMyPlot()
            if plot ~= myPlot then attachPlot(plot) end
            if os.clock() - lastPoll >= 5 then
                lastPoll = os.clock()
                pcall(pollServerList)
            end
            refreshBaseText()
            task.wait(2)
        end
    end)
end

local function stopBaseWatch()
    baseLoopId += 1
    detachPlot()
    myPlot = nil
end

-- ── debug: what the scanner actually sees ────────────────────
local function updateDebug()
    local total, purchase, enabled = 0, 0, 0
    for prompt in pairs(entries) do
        total += 1
        if prompt.ActionText == "Purchase" then
            purchase += 1
            if prompt.Enabled then enabled += 1 end
        end
    end
    local sample = ""
    for m, prompt in pairs(models) do
        sample = "\n" .. fullPath(m)
        -- print each new kind of brainrot's attributes once, so a wrong guess is easy to fix
        if debugPrinted < 3 and not dbgSeen[m] then
            dbgSeen[m] = true
            debugPrinted += 1
            local attrs = {}
            for k, v in pairs(m:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. tostring(v) end
            warn(string.format("[EAZY] purchase prompt on %s | attributes: %s | ObjectText: %s",
                fullPath(m), #attrs > 0 and table.concat(attrs, ", ") or "(none)", tostring(prompt.ObjectText)))
        end
        break
    end
    lDebug.Text = string.format("prompts %d | purchase %d (enabled %d)\nmoney: %s%s",
        total, purchase, enabled, moneyDesc, sample)
end

-- ── readout for the targeted brainrot ───────────────────────
local function showReadout(model, prompt, dist)
    if not (model and prompt) then clearReadout() return end
    local index = model:GetAttribute("Index")
    local mutation = model:GetAttribute("Mutation")
    local traits = traitList(model)
    local income, def = lookup(index, mutation, #traits > 0 and traits or nil)
    local price = def and rawget(def, "Price")
    lName.Text = "Name: " .. tostring(def and rawget(def, "DisplayName") or index or prompt.ObjectText or "---")
        .. (price and (" ($" .. fmt(price) .. ")") or "")
        .. ((price and myMoney and myMoney < tonumber(price)) and " - can't afford" or "")
    lIncome.Text = "Income: " .. fmt(income) .. " /sec"
    lRarity.Text = "Rarity: " .. tostring(def and rawget(def, "Rarity") or "---")
    lMutation.Text = "Mutation: " .. tostring(mutation or "---")
    lTraits.Text = "Traits: " .. (#traits > 0 and table.concat(traits, ", ") or "---")
    lDist.Text = string.format("Distance: %.1f studs", dist)
    lHeading.Text = headingOf(model)
end

-- ── walking ──────────────────────────────────────────────────
local function stopWalking()
    local char = localPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if hum and root then pcall(function() hum:MoveTo(root.Position) end) end
end

-- ── lock position ────────────────────────────────────────────
-- Switches the movement controls off while you stand on the ground and welds your limbs
-- to the root, with a ragdoll guard. Everything it changes is remembered and put back on
-- toggle-off, death, respawn and teardown. It only engages after you have stood on the
-- ground for a moment, never while seated/dead/airborne, and switches itself off if it
-- keeps erroring. (Movement via the walk option still works: it uses Humanoid:MoveTo.)
local lockWanted = false
local updateLock, lockControlsRaw
do
local lock = {
    engaged = false, controlsOff = false, char = nil, hum = nil,
    welds = {}, cons = {}, states = {}, groundSince = nil,
    lastKeep = 0, lastScan = 0, lastFix = 0, errors = 0,
    conn = nil, removingConn = nil, controls = nil,
}
local LOCK_STATES = {
    Enum.HumanoidStateType.Ragdoll, Enum.HumanoidStateType.Physics,
    Enum.HumanoidStateType.FallingDown, Enum.HumanoidStateType.PlatformStanding,
}

local function lockParts()
    local c = localPlayer.Character
    return c, c and c:FindFirstChildOfClass("Humanoid"), c and c:FindFirstChild("HumanoidRootPart")
end

local function lockGrounded()
    local _, hum = lockParts()
    if not hum or hum.Health <= 0 or hum.SeatPart ~= nil then return false end
    if hum.FloorMaterial == Enum.Material.Air then return false end
    local st = hum:GetState()
    return st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics
        or st == Enum.HumanoidStateType.Landed
end

local function lockGetControls()
    if lock.controls then return lock.controls end
    pcall(function()
        local scripts = localPlayer:FindFirstChild("PlayerScripts")
        local pm = scripts and scripts:FindFirstChild("PlayerModule")
        if pm then lock.controls = require(pm):GetControls() end
    end)
    return lock.controls
end

function lockControlsRaw(disable)
    local cas = game:GetService("ContextActionService")
    local controls = lockGetControls()
    if controls then
        if disable then controls:Disable() else controls:Enable() end
        if not disable then pcall(function() cas:UnbindAction("EazyLockPosition") end) end
        return
    end
    -- fallback when the control module can't be reached: swallow the movement keys
    if disable then
        cas:BindActionAtPriority("EazyLockPosition", function()
            return Enum.ContextActionResult.Sink
        end, false, Enum.ContextActionPriority.High.Value,
            Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
            Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right, Enum.KeyCode.Space)
    else
        cas:UnbindAction("EazyLockPosition")
    end
end

local function lockSetControls(disable)
    if disable then
        lock.controlsOff = true
        pcall(lockControlsRaw, true)
    elseif lock.controlsOff then   -- only re-enable what WE disabled
        lock.controlsOff = false
        pcall(lockControlsRaw, false)
    end
end

local function lockUnweld()
    for _, w in ipairs(lock.welds) do pcall(function() w:Destroy() end) end
    lock.welds = {}
    local c = localPlayer.Character
    if c then
        pcall(function()
            for _, d in ipairs(c:GetDescendants()) do
                if d.Name == "EazyLockWeld" then d:Destroy() end
            end
        end)
    end
end

local function lockWeld(c, root)
    lockUnweld()
    for _, part in ipairs(c:GetChildren()) do
        if part:IsA("BasePart") and part ~= root then
            local ok, weld = pcall(function()
                local w = Instance.new("WeldConstraint")
                w.Name = "EazyLockWeld"
                w.Part0, w.Part1, w.Parent = root, part, root
                return w
            end)
            if ok and weld then lock.welds[#lock.welds + 1] = weld end
        end
    end
end

local function lockGuard(hum)
    if lock.hum ~= hum then lock.states, lock.hum = {}, hum end
    for _, st in ipairs(LOCK_STATES) do
        if lock.states[st] == nil then
            local ok, was = pcall(function() return hum:GetStateEnabled(st) end)
            if ok then lock.states[st] = was end
        end
        pcall(function() hum:SetStateEnabled(st, false) end)
    end
end

local function lockUnguard()
    local hum = lock.hum
    if hum and hum.Parent then
        for st, was in pairs(lock.states) do
            pcall(function() hum:SetStateEnabled(st, was) end)
        end
    end
    lock.states, lock.hum = {}, nil
    for con, was in pairs(lock.cons) do
        if con.Parent then pcall(function() con.Enabled = was end) end
    end
    lock.cons = {}
end

local function lockDisengage()   -- hand movement back, keep the ragdoll guard
    lock.engaged, lock.groundSince = false, nil
    lockSetControls(false)
    lockUnweld()
end

local function lockRelease()     -- hand EVERYTHING back; safe to call any number of times
    lockDisengage()
    lockUnguard()
    lock.char = nil
end

local function lockTick()
    local c, hum, root = lockParts()
    if not (c and hum and root) then return end
    if hum.Health <= 0 or hum.SeatPart ~= nil then
        if lock.engaged or lock.controlsOff then lockDisengage() end
        return
    end
    if lock.char ~= c then       -- new character after a respawn
        lockRelease()
        lock.char = c
        lockGuard(hum)
    end
    local now = os.clock()
    if now - lock.lastScan > 0.15 then   -- ragdoll guard: undo what the game applies
        lock.lastScan = now
        for _, d in ipairs(c:GetDescendants()) do
            if d:IsA("BallSocketConstraint") or d:IsA("HingeConstraint")
                or d:IsA("RopeConstraint") or d:IsA("RodConstraint") then
                if d.Enabled then
                    if lock.cons[d] == nil then lock.cons[d] = true end
                    d.Enabled = false
                end
            elseif d:IsA("Motor6D") and not d.Enabled then
                d.Enabled = true
            end
        end
    end
    local st = hum:GetState()
    if (hum.PlatformStand or st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll
        or st == Enum.HumanoidStateType.FallingDown or st == Enum.HumanoidStateType.PlatformStanding)
        and now - lock.lastFix > 0.1 then
        lock.lastFix = now
        hum.PlatformStand = false
        pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
    if lockGrounded() then
        lock.groundSince = lock.groundSince or now
        if not lock.engaged then
            if now - lock.groundSince >= 0.15 then   -- must be standing for a moment first
                lock.engaged, lock.lastKeep = true, now
                lockSetControls(true)
                lockWeld(c, root)
                pcall(function() hum:Move(Vector3.zero, false) end)
            end
        elseif now - lock.lastKeep > 0.5 then
            lock.lastKeep = now
            pcall(lockControlsRaw, true)   -- re-assert if something turned the controls back on
        end
    else
        lock.groundSince = nil
        if lock.engaged then lockDisengage() end   -- airborne: give control back until you land
    end
end

function updateLock()
    if lock.conn then lock.conn:Disconnect() lock.conn = nil end
    if lock.removingConn then lock.removingConn:Disconnect() lock.removingConn = nil end
    lockRelease()
    lock.errors = 0
    if not lockWanted then return end
    lock.removingConn = localPlayer.CharacterRemoving:Connect(lockRelease)
    lock.conn = RunService.Heartbeat:Connect(function()
        local ok, err = pcall(lockTick)
        if ok then
            lock.errors = 0
        else
            lock.errors += 1
            if lock.errors >= 10 then   -- keeps failing: give everything back and switch off
                warn("[EAZY] lock position turned itself off: " .. tostring(err))
                lockWanted = false
                paintLock(false)
                pcall(updateLock)
            end
        end
    end)
end

end -- lock scope

onLockChanged = function(on)
    lockWanted = on
    updateLock()
end

if getgenv then
    getgenv().EAZYUnlock = function()   -- emergency release, runnable from the executor
        lockWanted = false
        paintLock(false)
        pcall(updateLock)
        pcall(lockControlsRaw, false)
    end
end

-- ── anti fling ───────────────────────────────────────────────
-- Other players' character parts get CanCollide = false (only on your screen), so
-- someone spinning or launching into you has nothing to hit you with. The map and
-- your own character keep their collision, so this is NOT noclip. The Humanoid
-- resets those flags every physics step, which is why it runs on Stepped; when you
-- switch it off they simply go back to normal by themselves. It also zeroes
-- extreme spin/speed on your own root (above what normal play produces).
local stopAntiFling
do
local flingConn = nil
local FLING_SPIN = 60       -- rad/s
local FLING_SPEED = 150     -- studs/s horizontal

local function startAntiFling()
    if flingConn then return end
    flingConn = RunService.Stepped:Connect(function()
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= localPlayer then
                local ch = plr.Character
                if ch then
                    for _, part in ipairs(ch:GetChildren()) do
                        if part:IsA("BasePart") and part.CanCollide then
                            part.CanCollide = false
                        end
                    end
                end
            end
        end
        local char = localPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            if root.AssemblyAngularVelocity.Magnitude > FLING_SPIN then
                root.AssemblyAngularVelocity = Vector3.zero
            end
            local v = root.AssemblyLinearVelocity
            if Vector3.new(v.X, 0, v.Z).Magnitude > FLING_SPEED then
                root.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
            end
        end
    end)
end

function stopAntiFling()
    if flingConn then flingConn:Disconnect() flingConn = nil end
end
end -- fling scope

onFlingChanged = function(on)
    if on then startAntiFling() else stopAntiFling() end
end

-- ── optimizer ────────────────────────────────────────────────
-- Strips what you don't need to farm: particles/trails/beams, lights, post effects,
-- shadows, and animations on brainrots / NPCs / other players (your own character keeps
-- its animations). Every property it changes is remembered and put back when you switch
-- it off. New brainrots that spawn on the carpet get stripped as they appear.
-- Animations that were stopped simply start again by themselves when it is off.
local startOptimizer, stopOptimizer
do
local Lighting = cloneref_(game:GetService("Lighting"))
local OPT = {
    particles   = true,    -- ParticleEmitter, Trail, Beam, Fire, Smoke, Sparkles
    lights      = true,    -- Point/Spot/Surface lights
    post        = true,    -- Bloom, Blur, ColorCorrection, DepthOfField, SunRays, Clouds
    shadows     = true,    -- global shadows + part shadows, part reflectance
    animations  = true,    -- stop animation tracks (not on your own character)
    accessories = true,    -- hide other players' hats/hair (visual only, local)
    terrain     = true,    -- grass decoration + water waves
    quality     = true,    -- lowest graphics quality level
    materials   = false,   -- flat SmoothPlastic everywhere (big gain, changes the look)
}
local OPT_PARTICLE = { ParticleEmitter = true, Trail = true, Beam = true, Fire = true, Smoke = true, Sparkles = true }
local OPT_LIGHT = { PointLight = true, SpotLight = true, SurfaceLight = true }
local OPT_POST = {
    BloomEffect = true, BlurEffect = true, ColorCorrectionEffect = true,
    DepthOfFieldEffect = true, SunRaysEffect = true, Clouds = true,
}
local function weak() return setmetatable({}, { __mode = "k" }) end
local opt = { on = false, id = 0, saved = weak(), anims = weak(), conns = {}, quality = nil }

local function optSet(inst, prop, val)   -- change a property, remembering the original
    local rec = opt.saved[inst]
    if not rec then rec = {} opt.saved[inst] = rec end
    if rec[prop] == nil then
        local ok, cur = pcall(function() return inst[prop] end)
        if not ok then return end
        rec[prop] = cur
    end
    pcall(function() inst[prop] = val end)
end

local function stopAnimator(an)
    if opt.anims[an] then return end
    local mine = localPlayer.Character
    if mine and an:IsDescendantOf(mine) then return end
    pcall(function()
        for _, tr in ipairs(an:GetPlayingAnimationTracks()) do pcall(function() tr:Stop(0) end) end
    end)
    opt.anims[an] = an.AnimationPlayed:Connect(function(tr)
        pcall(function() tr:Stop(0) end)
    end)
end

local function strip(inst)
    local cls = inst.ClassName
    if OPT_PARTICLE[cls] then
        if OPT.particles then optSet(inst, "Enabled", false) end
    elseif OPT_LIGHT[cls] then
        if OPT.lights then optSet(inst, "Enabled", false) end
    elseif OPT_POST[cls] then
        if OPT.post then optSet(inst, "Enabled", false) end
    elseif cls == "Animator" then
        if OPT.animations then stopAnimator(inst) end
    elseif cls == "Accessory" then
        if OPT.accessories then
            local plr = inst.Parent and Players:GetPlayerFromCharacter(inst.Parent)
            if plr and plr ~= localPlayer then
                task.spawn(function()
                    local h = inst:FindFirstChild("Handle") or inst:WaitForChild("Handle", 3)
                    if h and h:IsA("BasePart") then optSet(h, "LocalTransparencyModifier", 1) end
                end)
            end
        end
    elseif inst:IsA("BasePart") and not inst:IsA("Terrain") then
        if OPT.shadows then
            if inst.CastShadow then optSet(inst, "CastShadow", false) end
            if inst.Reflectance ~= 0 then optSet(inst, "Reflectance", 0) end
        end
        if OPT.materials and inst.Material ~= Enum.Material.SmoothPlastic then
            optSet(inst, "Material", Enum.Material.SmoothPlastic)
        end
    end
end

function stopOptimizer()
    if not opt.on then return end
    opt.on = false
    opt.id += 1
    for _, c in ipairs(opt.conns) do pcall(function() c:Disconnect() end) end
    opt.conns = {}
    for an, c in pairs(opt.anims) do pcall(function() c:Disconnect() end) end
    opt.anims = weak()
    for inst, rec in pairs(opt.saved) do
        for prop, val in pairs(rec) do
            pcall(function() inst[prop] = val end)
        end
    end
    opt.saved = weak()
    if opt.quality ~= nil then
        pcall(function() settings().Rendering.QualityLevel = opt.quality end)
        opt.quality = nil
    end
end

function startOptimizer()
    if opt.on then return end
    opt.on = true
    opt.id += 1
    local id = opt.id

    if OPT.shadows then optSet(Lighting, "GlobalShadows", false) end
    if OPT.terrain then
        local terrain = workspace:FindFirstChildOfClass("Terrain")
        if terrain then
            optSet(terrain, "Decoration", false)
            optSet(terrain, "WaterWaveSize", 0)
            optSet(terrain, "WaterWaveSpeed", 0)
            optSet(terrain, "WaterReflectance", 0)
        end
    end
    if OPT.quality then
        pcall(function()
            local r = settings().Rendering
            opt.quality = r.QualityLevel
            r.QualityLevel = Enum.QualityLevel.Level01
        end)
    end

    local function onAdded(d) if opt.on then pcall(strip, d) end end
    opt.conns[1] = workspace.DescendantAdded:Connect(onAdded)
    opt.conns[2] = Lighting.DescendantAdded:Connect(onAdded)

    task.spawn(function()   -- existing instances, in batches so the game doesn't hitch
        for _, d in ipairs(Lighting:GetDescendants()) do pcall(strip, d) end
        local list = workspace:GetDescendants()
        for i, d in ipairs(list) do
            if not (ALIVE and opt.on and opt.id == id) then return end
            pcall(strip, d)
            if i % 300 == 0 then task.wait() end
        end
    end)
end

onOptChanged = function(on)
    if on then startOptimizer() else stopOptimizer() end
end
end -- optimizer scope

-- ── farm target (sticky) ─────────────────────────────────────
-- The farm keeps working on the same brainrot until it is bought or gone, and only
-- switches if another one is clearly closer. Walking follows this target.
local target = { model = nil, prompt = nil }
local function selectTarget()
    local m, p, d = nearest()
    local cur = target.prompt
    if cur and target.model and models[target.model] == cur and cur.Parent
        and cur.Enabled and cur.ActionText == "Purchase" then
        local char = localPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local pos = promptPos(cur, target.model)
        if root and pos then
            local cd = (root.Position - pos).Magnitude
            if not p or cd <= d + 6 then
                return target.model, cur, cd
            end
        end
    end
    target.model, target.prompt = m, p
    return m, p, d
end

-- ── walk target: only brainrots from the bought list ─────────
-- A carpet brainrot qualifies when its kind is in the bought list, it is within the walk
-- radius, its prompt still says Purchase (and is enabled), and you can afford it. Sticky
-- like the farm target, so it doesn't dither between two close ones.
local function affordable(m)
    if not myMoney then return true end
    local _, def = lookup(m:GetAttribute("Index"))
    local price = def and tonumber(rawget(def, "Price"))
    return not (price and myMoney < price)
end

-- on the farm list: the name typed in matches the brainrot's Index or display name
local function farmMatches(index, displayName)
    if next(farmList) == nil then return false end
    local a = tostring(index or ""):lower()
    local b = tostring(displayName or ""):lower()
    for name in pairs(farmList) do
        if a:find(name, 1, true) or b:find(name, 1, true) then return true end
    end
    return false
end
local function onFarmList(m)
    if next(farmList) == nil then return false end
    local index = m:GetAttribute("Index")
    local _, def = lookup(index)
    return farmMatches(index, def and rawget(def, "DisplayName"))
end

-- farm-list brainrots count at ANY distance
local function farmOk(m, prompt, d)
    return onFarmList(m) and affordable(m)
end

-- bought-list brainrots count only inside the walk radius
local function walkOk(m, prompt, d)
    if farmOk(m, prompt, d) then return true end
    if d > walkRadius then return false end
    local index = m:GetAttribute("Index")
    if index == nil or not bought[index] then return false end
    return affordable(m)
end

local wTarget = { model = nil, prompt = nil }
local function selectWalkTarget()
    local m, p, d = nearest(farmOk)   -- farm list first, any distance
    local isFarm = p ~= nil
    if not p then m, p, d = nearest(walkOk) end
    local cur = wTarget.prompt
    if cur and wTarget.model and models[wTarget.model] == cur and cur.Parent
        and cur.Enabled and cur.ActionText == "Purchase" then
        local char = localPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local pos = promptPos(cur, wTarget.model)
        if root and pos then
            local cd = (root.Position - pos).Magnitude
            local curFarm = farmOk(wTarget.model, cur, cd)
            if walkOk(wTarget.model, cur, cd) and (curFarm or not isFarm) and (not p or cd <= d + 6) then
                return wTarget.model, cur, cd
            end
        end
    end
    wTarget.model, wTarget.prompt = m, p
    return m, p, d
end

-- A press only counts as a purchase when the prompt goes away AND your money dropped
-- (when money can be read), so a brainrot someone else grabbed isn't added to the list.
local pendingBuys = {}
local function queueBuy(model)
    for _, pb in ipairs(pendingBuys) do
        if pb.model == model then return end
    end
    local index = model:GetAttribute("Index")
    if index == nil then return end
    local _, def = lookup(index)
    pendingBuys[#pendingBuys + 1] = {
        model = model, index = index, t = os.clock(), money = myMoney,
        price = def and tonumber(rawget(def, "Price")),
    }
end

local function checkPendingBuys()
    local now = os.clock()
    for i = #pendingBuys, 1, -1 do
        local pb = pendingBuys[i]
        local stillBuyable = pb.model.Parent ~= nil and models[pb.model] ~= nil
        if not stillBuyable then
            local paid = true
            if pb.money and myMoney and pb.price then
                paid = myMoney < pb.money - pb.price * 0.5
            end
            if paid then addBought(pb.index) end
            table.remove(pendingBuys, i)
        elseif now - pb.t > 6 then
            table.remove(pendingBuys, i)
        end
    end
end

-- ── brainrot list (scrollable) ───────────────────────────────
-- FARMING: the brainrots on the track the farm is going for right now (farm-list names at
-- any distance, bought-list kinds inside the walk radius, affordable), farm list first then
-- nearest, with ">" on the one it is currently walking to / buying.
-- ON TRACK: every purchasable brainrot on the carpet, nearest first. ALL KINDS: every
-- brainrot the game defines, cheapest first. The name box filters both. Click a row to
-- add/remove that brainrot from the farm list. [F] = on farm list, [B] = bought list.
local updateList
do
local allKinds = nil
local function buildAllKinds()
    local t = {}
    if data.animals then
        for index, def in pairs(data.animals) do
            if type(def) == "table" then
                local income = lookup(index)
                t[#t + 1] = {
                    index = index, name = tostring(rawget(def, "DisplayName") or index),
                    price = tonumber(rawget(def, "Price")), income = income, rarity = rawget(def, "Rarity"),
                }
            end
        end
        table.sort(t, function(a, b)
            local pa, pb = a.price or 0, b.price or 0
            if pa ~= pb then return pa < pb end
            return a.name < b.name
        end)
    end
    return t
end

local function setListRow(i, text, color, key)
    local r = getListRow(i)
    if r.Text ~= text then r.Text = text end
    r.TextColor3 = color
    r.Visible = true
    listKeys[i] = key
end

function updateList()
    local filter = (farmBox.Text:match("^%s*(.-)%s*$") or ""):lower()
    local n = 0
    if listMode ~= "all" then
        local ch = localPlayer.Character
        local root = ch and ch:FindFirstChild("HumanoidRootPart")
        local items = {}
        for m, prompt in pairs(models) do
            if m.Parent then
                local index = m:GetAttribute("Index")
                local mut = m:GetAttribute("Mutation")
                local traits = traitList(m)
                local income, def = lookup(index, mut, #traits > 0 and traits or nil)
                local name = tostring(def and rawget(def, "DisplayName") or index or prompt.ObjectText or m.Name)
                if filter == "" or name:lower():find(filter, 1, true) then
                    local pos = promptPos(prompt, m)
                    local d = (root and pos) and (root.Position - pos).Magnitude or math.huge
                    if listMode == "track" or walkOk(m, prompt, d) then
                        items[#items + 1] = {
                            m = m, name = name, index = index, mut = mut, income = income,
                            price = def and tonumber(rawget(def, "Price")), d = d, farm = onFarmList(m),
                        }
                    end
                end
            end
        end
        table.sort(items, function(a, b)
            if listMode == "farming" and a.farm ~= b.farm then return a.farm end
            return a.d < b.d
        end)
        tabFarm.Text = listMode == "farming" and ("FARMING (" .. #items .. ")") or "FARMING"
        for _, it in ipairs(items) do
            if n >= 300 then break end
            n += 1
            local isFarm = onFarmList(it.m)
            local isBought = it.index ~= nil and bought[it.index] ~= nil
            local color = isFarm and T.ok or isBought and T.acc or T.txt
            if myMoney and it.price and myMoney < it.price then color = T.sub end
            local current = wTarget.model == it.m and "> " or ""
            setListRow(n, string.format("%s%s%s%s  $%s  %s/s  %s",
                current, isFarm and "[F] " or isBought and "[B] " or "", it.name,
                it.mut and (" [" .. tostring(it.mut) .. "]") or "",
                fmt(it.price), fmt(it.income),
                it.d < math.huge and (math.floor(it.d) .. "st") or ""), color, it.name:lower())
        end
        if n == 0 then
            n = 1
            setListRow(1, listMode == "farming" and "nothing being farmed right now"
                or (filter ~= "" and "no match on the track" or "no brainrots on the track"), T.sub, nil)
        end
    else
        if not listDirty and allKinds then return end
        allKinds = buildAllKinds()
        for _, k in ipairs(allKinds) do
            if n >= 400 then break end
            if filter == "" or k.name:lower():find(filter, 1, true) or tostring(k.index):lower():find(filter, 1, true) then
                n += 1
                local isFarm = farmMatches(k.index, k.name)
                local isBought = bought[k.index] ~= nil
                setListRow(n, string.format("%s%s  $%s  %s/s  %s",
                    isFarm and "[F] " or isBought and "[B] " or "", k.name,
                    fmt(k.price), fmt(k.income), tostring(k.rarity or "")),
                    isFarm and T.ok or isBought and T.acc or T.txt, k.name:lower())
            end
        end
        if n == 0 then
            n = 1
            setListRow(1, #allKinds == 0 and "brainrot data not loaded" or "no match", T.sub, nil)
        end
    end
    for i = n + 1, #listRows do listRows[i].Visible = false end
    listDirty = false
end
end -- list scope

-- ── fps / ping strip + walk radius ring ──────────────────────
local stopStats
do
local Stats = cloneref_(game:GetService("Stats"))
local statAcc, statFrames = 0, 0
local ringPart, ringR = nil, nil

local function pingMs()
    local ok, v = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
    if ok and type(v) == "number" then return v end
    local ok2, p = pcall(function() return localPlayer:GetNetworkPing() end)
    if ok2 and type(p) == "number" then return p * 1000 end
    return nil
end

local function updateRing()
    if not showRadius then
        if ringPart and ringPart.Parent then ringPart.Parent = nil end
        return
    end
    local char = localPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not root then return end
    if not ringPart then
        ringPart = Instance.new("Part")
        ringPart.Name = "EazyWalkRadius"
        ringPart.Shape = Enum.PartType.Cylinder
        ringPart.Anchored = true
        ringPart.CanCollide = false
        ringPart.CanQuery = false
        ringPart.CanTouch = false
        ringPart.CastShadow = false
        ringPart.Material = Enum.Material.Neon
        ringPart.Color = T.warn
        ringPart.Transparency = 0.9
        pcall(function()
            local hl = Instance.new("Highlight")   -- outline of the flat disc = a ring
            hl.FillTransparency = 1
            hl.OutlineColor = T.warn
            hl.OutlineTransparency = 0
            hl.DepthMode = Enum.HighlightDepthMode.Occluded
            hl.Parent = ringPart
        end)
    end
    if ringR ~= walkRadius then
        ringR = walkRadius
        ringPart.Size = Vector3.new(0.2, walkRadius * 2, walkRadius * 2)
    end
    local feetY = root.Position.Y - root.Size.Y / 2 - (hum and hum.HipHeight or 2) + 0.2
    ringPart.CFrame = CFrame.new(root.Position.X, feetY, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
    local cam = workspace.CurrentCamera
    if cam and ringPart.Parent ~= cam then ringPart.Parent = cam end
end

onRingChanged = function(on)
    showRadius = on
    if not on and ringPart and ringPart.Parent then ringPart.Parent = nil end
end

local statConn = RunService.Heartbeat:Connect(function(dt)
    statAcc += dt
    statFrames += 1
    if statAcc >= 0.5 then
        local fps = statFrames / statAcc
        statAcc, statFrames = 0, 0
        local c = fps >= 50 and T.ok or fps >= 30 and T.warn or T.err
        fpsLabel.Text = string.format("%d FPS", math.floor(fps + 0.5))
        fpsLabel.TextColor3, fpsStroke.Color, fpsStand.BackgroundColor3 = c, c, c
        local ms = pingMs()
        if ms then
            local pc = ms < 100 and T.ok or ms < 200 and T.warn or T.err
            local lit = ms < 100 and 3 or ms < 200 and 2 or 1
            pingLabel.Text = string.format("%d ms", math.floor(ms + 0.5))
            pingLabel.TextColor3 = pc
            for i, bar in ipairs(pingBars) do bar.BackgroundColor3 = i <= lit and pc or T.line end
        else
            pingLabel.Text = "-- ms"
        end
    end
    pcall(updateRing)
end)

function stopStats()
    if statConn then statConn:Disconnect() statConn = nil end
    if ringPart then pcall(function() ringPart:Destroy() end) ringPart = nil end
end
end -- stats scope

-- ── main loop ────────────────────────────────────────────────
local lastPrompt, lastPress, acc = nil, 0, 0
local walkActive = false
local function tick(dt)
    acc += dt
    if acc < 0.2 then return end
    acc = 0

    refreshModels()
    pcall(checkPendingBuys)
    pcall(updateList)
    updateMotion()
    pcall(scanCarpet)
    pcall(updateMoney)
    pcall(updateDebug)

    local model, prompt, dist = selectTarget()
    local walkMode = WalkEnabled and Enabled
    local wPrompt = nil
    if walkMode then
        -- walk mode works on a bought-list brainrot inside the radius instead of the nearest one
        local wm, wp, wd = selectWalkTarget()
        if wp then model, prompt, dist, wPrompt = wm, wp, wd, wp end
    end
    showReadout(model, prompt, dist)

    local range = prompt and ((prompt.MaxActivationDistance or 10) - 2) or 0
    local inRange = prompt ~= nil and dist <= range + 4

    if walkMode then
        if wPrompt and not inRange then
            local pos = promptPos(prompt, model)
            local char = localPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if pos and hum and hum.Health > 0 then
                walkActive = true
                pcall(function() hum:MoveTo(pos) end)
            end
        elseif walkActive then   -- arrived, or nothing from the list is left in the radius
            walkActive = false
            stopWalking()
        end
    elseif walkActive then
        walkActive = false
        stopWalking()
    end

    if not Enabled then
        if WalkEnabled then setStatus("walking follows AUTO FARM - turn it on", "wait") end
        return
    end

    if not prompt then
        setStatus("no buy prompt in range", "wait")
        return
    end
    if not inRange then
        if walkMode and wPrompt then
            local _, def = lookup(model:GetAttribute("Index"))
            setStatus("walking to " .. tostring(def and rawget(def, "DisplayName") or model.Name)
                .. (onFarmList(model) and " (farm list)..." or "..."), "busy")
        elseif walkMode then
            setStatus(string.format("no farm-list brainrot, none bought within %d studs", walkRadius), "wait")
        else
            setStatus("move closer to buy", "wait")
        end
        return
    end
    if prompt ~= lastPrompt or os.clock() - lastPress >= 1.2 then
        lastPrompt, lastPress = prompt, os.clock()
        setStatus("buying...", "busy")
        local pressedModel = model
        task.spawn(function()
            local ok, why = press(prompt)
            if ok then
                pcall(queueBuy, pressedModel)
                setStatus("bought!", "ok")
            elseif Enabled then
                setStatus(why or "buy failed", "err")
            end
        end)
    end
end

local function startTracking()
    if #conns > 0 then return end
    pcall(loadData)
    for _, d in ipairs(workspace:GetDescendants()) do track(d) end
    conns[#conns + 1] = workspace.DescendantAdded:Connect(track)
    conns[#conns + 1] = workspace.DescendantRemoving:Connect(function(d)
        entries[d] = nil
    end)
    conns[#conns + 1] = RunService.Heartbeat:Connect(tick)
    startBaseWatch()
end

local function stopTracking()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    conns = {}
    models, entries, motion = {}, {}, {}
    lastPrompt = nil
    pendingBuys = {}
    stopBaseWatch()
end

onFarmChanged = function(on)
    Enabled = on
    if on then
        setStatus("armed - looking for a buy...", "wait")
    else
        lastPrompt = nil
        setStatus("idle", nil)
    end
end

onWalkChanged = function(on)
    WalkEnabled = on
    if not on then stopWalking() end
end

-- ── teardown ─────────────────────────────────────────────────
local function teardown()
    if not ALIVE then return end
    ALIVE = false
    Enabled, WalkEnabled = false, false
    lockWanted = false
    pcall(updateLock)
    stopAntiFling()
    pcall(stopOptimizer)
    pcall(stopStats)
    stopWalking()
    stopTracking()
    pcall(function() gui:Destroy() end)
end
closeBtn.MouseButton1Click:Connect(teardown)
if getgenv then getgenv().EAZYFarmStop = teardown end

paintFarm(false)
paintWalk(false)
paintLock(false)
paintFling(false)
paintOpt(false)
paintShowRadius(false)
refreshBoughtLabel()
refreshFarmLabel()
setStatus("idle", nil)
startTracking()   -- scanning (traits, heading) runs even while the farm is off
