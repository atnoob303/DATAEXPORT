-- ╔══════════════════════════════════════════╗
-- ║     Sols RNG Egg Farm  |  v4.2           ║
-- ║     Chat Detection + Tabbed UI           ║
-- ╚══════════════════════════════════════════╝

do
    pcall(function()
        local cg  = game:GetService("CoreGui")
        local old = cg and cg:FindFirstChild("SolsEggFarmGUI")
        if old then old:Destroy() end
    end)
    pcall(function()
        local pg  = game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")
        local old = pg and pg:FindFirstChild("SolsEggFarmGUI")
        if old then old:Destroy() end
    end)
end

-- ─── Services ────────────────────────────────────────────────
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local TweenService        = game:GetService("TweenService")
local CoreGui             = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService         = game:GetService("HttpService")
local TextChatService     = game:GetService("TextChatService")

-- ─── Player refs ─────────────────────────────────────────────
local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid")
local rootPart  = character:WaitForChild("HumanoidRootPart")

player.CharacterAdded:Connect(function(char)
    character = char
    humanoid  = char:WaitForChild("Humanoid")
    rootPart  = char:WaitForChild("HumanoidRootPart")
end)

-- ─── Settings ────────────────────────────────────────────────
local SETTINGS = {
    SEARCH_INTERVAL    = 1,
    PROMPT_DISTANCE    = 3,
    PATH_RECOMPUTE_MAX = 5,
    WALK_SPEED_BOOST   = 0,
    SPRINT_SPEED       = 0,       -- NEW: manual sprint speed
    AUTO_EQUIP_ABYSSAL = false,
    MAX_EGG_HEIGHT     = 130,
    SHOW_NOTIFICATIONS = true,
    AUTO_RESPAWN       = true,
    WEBHOOK_URL        = "",
    WEBHOOK_ENABLED    = false,
    SHOW_EGG_MARKERS   = true,
    CHAT_DETECT        = true,    -- NEW: watch chat for [Egg Spawned]
    CHAT_WEBHOOK       = true,    -- NEW: also send webhook on chat detect
}

local CONFIG_FILE = "SolsRngSettingsV4.json"
local function saveConfig()
    if writefile then
        pcall(function() writefile(CONFIG_FILE, HttpService:JSONEncode(SETTINGS)) end)
    end
end
local function loadConfig()
    if readfile and isfile and isfile(CONFIG_FILE) then
        pcall(function()
            local d = HttpService:JSONDecode(readfile(CONFIG_FILE))
            if d then for k,v in pairs(d) do if SETTINGS[k] ~= nil then SETTINGS[k] = v end end end
        end)
    end
end
loadConfig()

-- ─── State ───────────────────────────────────────────────────
local STATE = {
    running            = false,
    eggsCollected      = 0,
    currentTarget      = "—",
    currentEggInstance = nil,
    eggsFound          = 0,
    startTime          = 0,
    failedAttempts     = 0,
    chatEggsDetected   = 0,       -- NEW
    sprintActive       = false,   -- NEW
}

local ignoredEggs = setmetatable({}, {__mode="k"})

-- ─── Egg config ──────────────────────────────────────────────
local EGG_PATTERNS   = {"^point_egg_%d+$", "^random_potion_egg_%d+$"}
local EXCLUDED_ZONES = {
    {center = Vector3.new(55.676, 102.85, -594.476), radius = 100},
    {center = Vector3.new(-50.29, 95.5, -102.54),    radius = 80 },
    {center = Vector3.new(16.326, 93.75, -438.988),  radius = 20 },
}

-- ─── Colors ──────────────────────────────────────────────────
local C = {
    bg       = Color3.fromRGB(10,  10,  16),
    card     = Color3.fromRGB(24,  24,  38),
    cardHov  = Color3.fromRGB(32,  32,  50),
    accent   = Color3.fromRGB(108, 58,  255),
    accentHi = Color3.fromRGB(160, 100, 255),
    green    = Color3.fromRGB(48,  210, 100),
    red      = Color3.fromRGB(232, 65,  78),
    orange   = Color3.fromRGB(255, 160, 48),
    cyan     = Color3.fromRGB(48,  200, 220),
    yellow   = Color3.fromRGB(255, 220, 50),
    pink     = Color3.fromRGB(255, 80,  180),
    textMain = Color3.fromRGB(228, 228, 240),
    textDim  = Color3.fromRGB(110, 110, 140),
    logBg    = Color3.fromRGB(8,   8,   14),
    border   = Color3.fromRGB(48,  48,  72),
    tabActive = Color3.fromRGB(108, 58, 255),
    tabInact  = Color3.fromRGB(24,  24,  38),
}

-- ═══════════════════════════════════════════════════════════
--  SHARED UI FACTORY  (gộp chung, tránh lặp code)
-- ═══════════════════════════════════════════════════════════
local UI = {}

function UI.corner(p, r)
    local c = Instance.new("UICorner", p)
    c.CornerRadius = UDim.new(0, r or 8)
    return c
end

function UI.stroke(p, col, th, tr)
    local s = Instance.new("UIStroke", p)
    s.Color = col or C.border; s.Thickness = th or 1; s.Transparency = tr or 0
    return s
end

function UI.tween(obj, t, props)
    TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props):Play()
end

function UI.label(parent, props)
    local l = Instance.new("TextLabel", parent)
    l.BackgroundTransparency = 1
    l.Font        = Enum.Font.GothamBold
    l.TextColor3  = C.textMain
    l.TextSize    = 12
    for k,v in pairs(props) do l[k] = v end
    return l
end

function UI.button(parent, props)
    local b = Instance.new("TextButton", parent)
    b.Font           = Enum.Font.GothamBold
    b.TextSize       = 12
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    for k,v in pairs(props) do b[k] = v end
    return b
end

function UI.hover(btn, base, hi, baseTr, hiTr)
    baseTr = baseTr or 0; hiTr = hiTr or 0
    btn.MouseEnter:Connect(function() UI.tween(btn, .12, {BackgroundColor3=hi,  BackgroundTransparency=hiTr})  end)
    btn.MouseLeave:Connect(function() UI.tween(btn, .15, {BackgroundColor3=base, BackgroundTransparency=baseTr}) end)
end

function UI.pulse(lbl, color)
    UI.tween(lbl, .08, {TextColor3 = Color3.new(1,1,1)})
    task.delay(.12, function() UI.tween(lbl, .2, {TextColor3 = color}) end)
end

-- Card frame helper
function UI.card(parent, size, pos, radius)
    local f = Instance.new("Frame", parent)
    f.Size             = size
    f.Position         = pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3 = C.card
    f.BorderSizePixel  = 0
    UI.corner(f, radius or 8)
    return f
end

-- Slider thay bang TextBox nhap tay + nut - / + (slider khong hoat dong trong executor)
function UI.slider(parent, yPos, labelTxt, minV, maxV, settingKey)
    local f = UI.card(parent, UDim2.new(1,-24,0,30), UDim2.new(0,12,0,yPos), 7)
    -- Label ten setting
    UI.label(f, {
        Size=UDim2.new(0.50,0,1,0), Position=UDim2.new(0,10,0,0),
        Text=labelTxt, TextColor3=C.textMain, TextSize=10, Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left
    })
    -- Nut -
    local btnMinus = UI.button(f, {
        Size=UDim2.new(0,24,0,22), Position=UDim2.new(1,-112,0.5,-11),
        BackgroundColor3=C.card, Text="-", TextColor3=C.textMain, TextSize=14
    })
    UI.corner(btnMinus, 5); UI.hover(btnMinus, C.card, C.cardHov)
    -- TextBox gia tri (nhap tay)
    local inputBox = Instance.new("TextBox", f)
    inputBox.Size=UDim2.new(0,56,0,22); inputBox.Position=UDim2.new(1,-84,0.5,-11)
    inputBox.BackgroundColor3=C.bg; inputBox.BorderSizePixel=0
    inputBox.Font=Enum.Font.GothamBold; inputBox.TextSize=12
    inputBox.TextColor3=C.accent; inputBox.Text=tostring(SETTINGS[settingKey])
    inputBox.ClearTextOnFocus=false
    UI.corner(inputBox, 5); UI.stroke(inputBox, C.border, 1, 0.5)
    -- Nut +
    local btnPlus = UI.button(f, {
        Size=UDim2.new(0,24,0,22), Position=UDim2.new(1,-26,0.5,-11),
        BackgroundColor3=C.card, Text="+", TextColor3=C.textMain, TextSize=14
    })
    UI.corner(btnPlus, 5); UI.hover(btnPlus, C.card, C.cardHov)
    -- Ham cap nhat gia tri
    local function setValue(v)
        v = math.clamp(math.floor(tonumber(v) or SETTINGS[settingKey]), minV, maxV)
        SETTINGS[settingKey] = v; inputBox.Text = tostring(v); saveConfig()
    end
    inputBox.FocusLost:Connect(function()
        setValue(inputBox.Text); UI.stroke(inputBox, C.border, 1, 0.5)
    end)
    inputBox.Focused:Connect(function() UI.stroke(inputBox, C.accent, 1, 0) end)
    btnMinus.MouseButton1Click:Connect(function() setValue(SETTINGS[settingKey] - 1) end)
    btnPlus.MouseButton1Click:Connect(function()  setValue(SETTINGS[settingKey] + 1) end)
    -- Giu nut de tang/giam lien tuc
    local function holdRepeat(btn, delta)
        btn.MouseButton1Down:Connect(function()
            local holding = true
            local conn; conn = btn.MouseButton1Up:Connect(function() holding=false; conn:Disconnect() end)
            task.delay(0.35, function()
                while holding do setValue(SETTINGS[settingKey]+delta); task.wait(0.07) end
            end)
        end)
    end
    holdRepeat(btnMinus, -1); holdRepeat(btnPlus, 1)
    return inputBox
end

-- Toggle helper
function UI.toggle(parent, yPos, labelTxt, settingKey, onChange)
    local f = UI.card(parent, UDim2.new(1,-24,0,30), UDim2.new(0,12,0,yPos), 7)
    UI.label(f, {
        Size=UDim2.new(0.72,0,1,0), Position=UDim2.new(0,10,0,0),
        Text=labelTxt, TextColor3=C.textMain, TextSize=10, Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left
    })
    local sw = UI.button(f, {
        Size=UDim2.new(0,40,0,20), Position=UDim2.new(1,-48,0.5,-10),
        BackgroundColor3=SETTINGS[settingKey] and C.green or C.border, Text=""
    })
    UI.corner(sw, 10)
    local kn = Instance.new("Frame", sw)
    kn.Size=UDim2.new(0,16,0,16)
    kn.BackgroundColor3=Color3.new(1,1,1); kn.BorderSizePixel=0; UI.corner(kn,8)
    kn.Position = SETTINGS[settingKey] and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
    sw.MouseButton1Click:Connect(function()
        SETTINGS[settingKey] = not SETTINGS[settingKey]; saveConfig()
        local on = SETTINGS[settingKey]
        UI.tween(sw, .18, {BackgroundColor3 = on and C.green or C.border})
        UI.tween(kn, .18, {Position = on and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)})
        if onChange then onChange(on) end
    end)
    return sw
end

-- Section header label
function UI.sectionLabel(parent, yPos, txt)
    return UI.label(parent, {
        Size=UDim2.new(1,-24,0,16), Position=UDim2.new(0,12,0,yPos),
        Text=txt, TextColor3=C.textDim, TextSize=9, Font=Enum.Font.GothamBold,
        TextXAlignment=Enum.TextXAlignment.Left
    })
end

-- ═══════════════════════════════════════════════════════════
--  GUI ROOT
-- ═══════════════════════════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name="SolsEggFarmGUI"; gui.ResetOnSpawn=false; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent = CoreGui end)
if not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end

local W, FULL_H, MINI_H = 380, 520, 54

local main = Instance.new("Frame", gui)
main.Name="Main"
main.Size=UDim2.new(0,W,0,FULL_H)
main.Position=UDim2.new(0.5,-190,0.5,-(FULL_H/2))
main.BackgroundColor3=C.bg; main.BorderSizePixel=0; main.ClipsDescendants=true
UI.corner(main, 14); UI.stroke(main, C.border, 1.5, 0.25)

-- glow bar
local gbar = Instance.new("Frame", main)
gbar.Size=UDim2.new(1,0,0,3); gbar.BorderSizePixel=0; gbar.BackgroundColor3=C.accent
local gg = Instance.new("UIGradient", gbar)
gg.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(108,58,255)),
    ColorSequenceKeypoint.new(0.4, Color3.fromRGB(200,80,255)),
    ColorSequenceKeypoint.new(0.8, Color3.fromRGB(48,160,255)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(108,58,255)),
})
task.spawn(function()
    local t = 0
    while gui.Parent do
        t = (t + .004) % 1
        gg.Offset = Vector2.new(t, 0)
        RunService.RenderStepped:Wait()
    end
end)

-- ── Header ───────────────────────────────────────────────────
local header = Instance.new("Frame", main)
header.Name="Header"; header.Size=UDim2.new(1,0,0,50); header.Position=UDim2.new(0,0,0,3)
header.BackgroundTransparency=1

local iconBox = Instance.new("Frame", header)
iconBox.Size=UDim2.new(0,36,0,36); iconBox.Position=UDim2.new(0,12,0.5,-18)
iconBox.BackgroundColor3=C.accent; iconBox.BorderSizePixel=0; UI.corner(iconBox, 10)
UI.label(iconBox, {Size=UDim2.new(1,0,1,0), Text="🥚", TextSize=18})

UI.label(header, {
    Size=UDim2.new(0,200,0,20), Position=UDim2.new(0,56,0,6),
    Text="Sols RNG  •  Egg Farm", TextSize=15, TextXAlignment=Enum.TextXAlignment.Left
})
local subtitleLbl = UI.label(header, {
    Size=UDim2.new(0,240,0,14), Position=UDim2.new(0,56,0,27),
    Text="v4.0  •  drag header to move", TextSize=9,
    Font=Enum.Font.Gotham, TextColor3=C.textDim, TextXAlignment=Enum.TextXAlignment.Left
})

local closeBtn = UI.button(header, {
    Size=UDim2.new(0,28,0,28), Position=UDim2.new(1,-80,0.5,-14),
    BackgroundColor3=C.red, BackgroundTransparency=0.65,
    Text="✕", TextColor3=C.red, TextSize=12
})
UI.corner(closeBtn, 6); UI.hover(closeBtn, C.red, C.red, .65, .3)
closeBtn.MouseButton1Click:Connect(function()
    STATE.running = false; task.wait(.2); gui:Destroy()
end)

local minimized = false
local minBtn = UI.button(header, {
    Size=UDim2.new(0,28,0,28), Position=UDim2.new(1,-46,0.5,-14),
    BackgroundColor3=C.card, BackgroundTransparency=0.3,
    Text="—", TextColor3=C.textDim, TextSize=14
})
UI.corner(minBtn, 6); UI.hover(minBtn, C.card, C.cardHov, .3, 0)
minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    UI.tween(main, .28, {Size=UDim2.new(0,W,0, minimized and MINI_H or FULL_H)})
    minBtn.Text = minimized and "□" or "—"
    subtitleLbl.Text = minimized and "v4.0  •  click □ to expand" or "v4.0  •  drag header to move"
end)

-- ── DRAG (fixed) ──────────────────────────────────────────────
-- Drag only triggers when clicking inside header but NOT on buttons
local dragActive = false
local dragStartMouse, dragStartFrame

local dragHitbox = UI.button(header, {
    Size=UDim2.new(1,-120,1,0), Position=UDim2.new(0,0,0,0),
    BackgroundTransparency=1, Text="", ZIndex=1
})

-- Hàm chung bắt đầu drag từ bất kỳ vùng nào
local function beginDrag(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragActive     = true
        dragStartMouse = inp.Position
        dragStartFrame = main.Position
    end
end

dragHitbox.InputBegan:Connect(beginDrag)

-- Tab bar cũng có thể kéo để di chuyển UI
-- (sẽ gắn sau khi tabBar được tạo — dùng biến toàn cục tabBar)
-- => gắn bên dưới sau khi tabBar khởi tạo xong

UserInputService.InputChanged:Connect(function(inp)
    if dragActive and inp.UserInputType == Enum.UserInputType.MouseMovement and dragStartMouse then
        local delta = inp.Position - dragStartMouse
        main.Position = UDim2.new(
            dragStartFrame.X.Scale, dragStartFrame.X.Offset + delta.X,
            dragStartFrame.Y.Scale, dragStartFrame.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragActive = false
    end
end)

-- ── Stat cards (horizontal row) ───────────────────────────────
local statsRow = Instance.new("Frame", main)
statsRow.Size=UDim2.new(1,-24,0,54); statsRow.Position=UDim2.new(0,12,0,58)
statsRow.BackgroundTransparency=1

local function statCard(parent, xOff, w, label, val, col)
    local f = UI.card(parent, UDim2.new(0,w,1,0), UDim2.new(0,xOff,0,0), 8)
    local v = UI.label(f, {
        Name="Val", Size=UDim2.new(1,0,0,28), Position=UDim2.new(0,0,0,4),
        Text=val, TextColor3=col, TextSize=20, Font=Enum.Font.GothamBold
    })
    UI.label(f, {
        Size=UDim2.new(1,0,0,13), Position=UDim2.new(0,0,1,-16),
        Text=label, TextColor3=C.textDim, TextSize=8, Font=Enum.Font.Gotham
    })
    return v
end

local sw4 = math.floor((W-24-24)/4)
local valCollected = statCard(statsRow, 0,         sw4, "COLLECTED", "0",  C.green)
local valFound     = statCard(statsRow, sw4+8,     sw4, "FOUND",     "0",  C.orange)
local valChat      = statCard(statsRow, (sw4+8)*2, sw4, "CHAT DET.", "0",  C.pink)   -- NEW
local valTime      = statCard(statsRow, (sw4+8)*3, sw4, "TIME",      "0s", C.cyan)

-- ── Target bar ───────────────────────────────────────────────
local tbar = UI.card(main, UDim2.new(1,-24,0,28), UDim2.new(0,12,0,118), 7)
UI.label(tbar, {
    Size=UDim2.new(0,56,1,0), Position=UDim2.new(0,10,0,0),
    Text="TARGET:", TextColor3=C.textDim, TextSize=9, Font=Enum.Font.GothamBold,
    TextXAlignment=Enum.TextXAlignment.Left
})
local targetLbl = UI.label(tbar, {
    Size=UDim2.new(1,-70,1,0), Position=UDim2.new(0,66,0,0),
    Text="—", TextColor3=C.accentHi, TextSize=10, TextXAlignment=Enum.TextXAlignment.Left,
    TextTruncate=Enum.TextTruncate.AtEnd
})

-- ── START / STOP ─────────────────────────────────────────────
local ctrlRow = Instance.new("Frame", main)
ctrlRow.Size=UDim2.new(1,-24,0,34); ctrlRow.Position=UDim2.new(0,12,0,152)
ctrlRow.BackgroundTransparency=1

local bw = math.floor((W-24-8)/2)
local startBtn = UI.button(ctrlRow, {
    Size=UDim2.new(0,bw,1,0), BackgroundColor3=C.green,
    Text="▶  START", TextColor3=Color3.new(1,1,1), TextSize=12
})
UI.corner(startBtn, 8); UI.hover(startBtn, C.green, Color3.fromRGB(60,230,115))

local stopBtn = UI.button(ctrlRow, {
    Size=UDim2.new(0,bw,1,0), Position=UDim2.new(0,bw+8,0,0),
    BackgroundColor3=C.red, BackgroundTransparency=0.55,
    Text="■  STOP", TextColor3=Color3.new(1,1,1), TextSize=12
})
UI.corner(stopBtn, 8); UI.hover(stopBtn, C.red, C.red, .55, .25)

-- ═══════════════════════════════════════════════════════════
--  TAB SYSTEM (horizontal)
-- ═══════════════════════════════════════════════════════════
local TAB_Y     = 194
local TAB_H     = 28
local CONTENT_Y = TAB_Y + TAB_H + 4
local CONTENT_H = FULL_H - CONTENT_Y - 4

-- Tab bar
local tabBar = Instance.new("Frame", main)
tabBar.Size=UDim2.new(1,-24,0,TAB_H); tabBar.Position=UDim2.new(0,12,0,TAB_Y)
tabBar.BackgroundColor3=C.card; tabBar.BorderSizePixel=0; UI.corner(tabBar, 8)

-- Content area (clipped)
local contentArea = Instance.new("Frame", main)
contentArea.Size=UDim2.new(1,-24,0,CONTENT_H); contentArea.Position=UDim2.new(0,12,0,CONTENT_Y)
contentArea.BackgroundTransparency=1; contentArea.ClipsDescendants=true

-- Tab pages (each is a full-size Frame inside contentArea)
local pages = {}
local tabBtns = {}
local activeTab = nil

local TAB_DEFS = {
    {id="farm",    icon="🚜", label="Farm"},
    {id="speed",   icon="⚡", label="Speed"},
    {id="notify",  icon="🔔", label="Notify"},
    {id="log",     icon="📋", label="Log"},
}

local tbw = math.floor((W-24) / #TAB_DEFS)

for i, tdef in ipairs(TAB_DEFS) do
    -- tab button
    local tb = UI.button(tabBar, {
        Size=UDim2.new(0,tbw,1,0),
        Position=UDim2.new(0,(i-1)*tbw,0,0),
        BackgroundColor3=C.tabInact, BackgroundTransparency=1,
        Text=tdef.icon.." "..tdef.label, TextColor3=C.textDim,
        TextSize=10, Font=Enum.Font.GothamBold
    })
    UI.corner(tb, 7)

    -- page frame
    local page = Instance.new("Frame", contentArea)
    page.Size=UDim2.new(1,0,1,0); page.Position=UDim2.new(0,0,0,0)
    page.BackgroundTransparency=1; page.Visible=false

    tabBtns[tdef.id] = tb
    pages[tdef.id]   = page
end

local function switchTab(id)
    if activeTab == id then return end
    activeTab = id
    for tid, btn in pairs(tabBtns) do
        local on = (tid == id)
        UI.tween(btn, .15, {
            BackgroundColor3    = on and C.tabActive or C.tabInact,
            BackgroundTransparency = on and 0 or 1,
            TextColor3          = on and Color3.new(1,1,1) or C.textDim,
        })
        pages[tid].Visible = on
    end
end

for _, tdef in ipairs(TAB_DEFS) do
    tabBtns[tdef.id].MouseButton1Click:Connect(function() switchTab(tdef.id) end)
end

-- Tab bar drag: chỉ kích hoạt khi chuột thực sự di chuyển (> 4px)
-- → click tab bình thường vẫn hoạt động, chỉ kéo dài mới drag UI
do
    local tabDragPending  = false
    local tabDragOrigin   = nil
    local tabDragFrame    = nil

    tabBar.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            tabDragPending = true
            tabDragOrigin  = inp.Position
            tabDragFrame   = main.Position
        end
    end)

    UserInputService.InputChanged:Connect(function(inp)
        if tabDragPending and inp.UserInputType == Enum.UserInputType.MouseMovement and tabDragOrigin then
            local delta = inp.Position - tabDragOrigin
            if delta.Magnitude > 4 then
                -- đủ threshold → chuyển sang drag thật
                dragActive     = true
                dragStartMouse = tabDragOrigin
                dragStartFrame = tabDragFrame
                tabDragPending = false
            end
        end
    end)

    UserInputService.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            tabDragPending = false
        end
    end)
end

-- ════════════════════════════
--  TAB: FARM
-- ════════════════════════════
local pgFarm = pages["farm"]
local farmScroll = Instance.new("ScrollingFrame", pgFarm)
farmScroll.Size=UDim2.new(1,0,1,0); farmScroll.BackgroundTransparency=1
farmScroll.ScrollBarThickness=3; farmScroll.ScrollBarImageColor3=C.accent
farmScroll.CanvasSize=UDim2.new(0,0,0,0); farmScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
farmScroll.BorderSizePixel=0

-- We build inside farmScroll using absolute y positions in a helper container
local fInner = Instance.new("Frame", farmScroll)
fInner.Size=UDim2.new(1,0,0,0); fInner.AutomaticSize=Enum.AutomaticSize.Y
fInner.BackgroundTransparency=1

-- Farm settings (using shared UI helpers, y positions relative to fInner)
UI.sectionLabel(fInner, 4, "⚙  FARM SETTINGS")
UI.slider(fInner,  22, "Collect Distance",  2, 12,  "PROMPT_DISTANCE")
UI.slider(fInner,  56, "Path Retries",      1, 10,  "PATH_RECOMPUTE_MAX")
UI.slider(fInner,  90, "Max Egg Height",    50,300, "MAX_EGG_HEIGHT")
UI.toggle(fInner, 124, "Auto Equip Abyssal",      "AUTO_EQUIP_ABYSSAL")
UI.toggle(fInner, 158, "Show Egg Markers",         "SHOW_EGG_MARKERS")
UI.toggle(fInner, 192, "Auto Respawn on Death",    "AUTO_RESPAWN")
UI.toggle(fInner, 226, "Show Notifications",       "SHOW_NOTIFICATIONS")

-- ════════════════════════════
--  TAB: SPEED
-- ════════════════════════════
local pgSpeed = pages["speed"]
local sInner = Instance.new("Frame", pgSpeed)
sInner.Size=UDim2.new(1,0,1,0); sInner.BackgroundTransparency=1

UI.sectionLabel(sInner, 4, "⚡  SPEED SETTINGS")
UI.slider(sInner,  22, "Walk Boost (farm)",  0, 80, "WALK_SPEED_BOOST")
UI.slider(sInner,  56, "Sprint Speed",       0, 80, "SPRINT_SPEED")

-- Nut Sprint bat/tat (khong can giu Shift)
local sprintCard = UI.card(sInner, UDim2.new(1,-24,0,36), UDim2.new(0,12,0,96), 8)
UI.label(sprintCard, {
    Size=UDim2.new(0.55,0,1,0), Position=UDim2.new(0,10,0,0),
    Text="Chay nhanh (Sprint)",
    TextColor3=C.textMain, TextSize=10, Font=Enum.Font.Gotham,
    TextXAlignment=Enum.TextXAlignment.Left
})
local sprintIndicator = UI.label(sprintCard, {
    Size=UDim2.new(0,40,0,20), Position=UDim2.new(1,-108,0.5,-10),
    Text="OFF", TextColor3=C.red, TextSize=10, Font=Enum.Font.GothamBold
})
local sprintBtn = UI.button(sprintCard, {
    Size=UDim2.new(0,60,0,24), Position=UDim2.new(1,-68,0.5,-12),
    BackgroundColor3=C.card, Text="RUN", TextColor3=C.textMain, TextSize=11
})
UI.corner(sprintBtn, 6); UI.hover(sprintBtn, C.card, C.green)

-- Speed display card
local speedCard = UI.card(sInner, UDim2.new(1,-24,0,36), UDim2.new(0,12,0,140), 8)
UI.label(speedCard, {
    Size=UDim2.new(0.5,0,1,0), Position=UDim2.new(0,10,0,0),
    Text="Current WalkSpeed:", TextColor3=C.textDim, TextSize=10, Font=Enum.Font.Gotham,
    TextXAlignment=Enum.TextXAlignment.Left
})
local speedValLbl = UI.label(speedCard, {
    Size=UDim2.new(0.4,0,1,0), Position=UDim2.new(0.55,0,0,0),
    Text="16", TextColor3=C.cyan, TextSize=16, Font=Enum.Font.GothamBold
})

-- Sprint logic - dung nut bam thay vi giu Shift
local BASE_SPEED = 16
local function applySprintState(on)
    STATE.sprintActive = on
    if humanoid and humanoid.Parent then
        humanoid.WalkSpeed = on and (BASE_SPEED + SETTINGS.SPRINT_SPEED) or BASE_SPEED
    end
    sprintIndicator.Text = on and "ON" or "OFF"
    sprintIndicator.TextColor3 = on and C.green or C.red
    UI.tween(sprintBtn, .15, {BackgroundColor3 = on and C.green or C.card})
    sprintBtn.Text = on and "STOP" or "RUN"
end

sprintBtn.MouseButton1Click:Connect(function()
    if SETTINGS.SPRINT_SPEED <= 0 then
        -- nhac nguoi dung set speed truoc
        sprintIndicator.Text = "Set speed!"
        sprintIndicator.TextColor3 = C.orange
        task.delay(1.5, function()
            sprintIndicator.Text = STATE.sprintActive and "ON" or "OFF"
            sprintIndicator.TextColor3 = STATE.sprintActive and C.green or C.red
        end)
        return
    end
    applySprintState(not STATE.sprintActive)
end)

-- Update speed display
task.spawn(function()
    while gui.Parent do
        if humanoid and humanoid.Parent then
            speedValLbl.Text = tostring(math.floor(humanoid.WalkSpeed))
        end
        task.wait(0.5)
    end
end)

-- Reset sprint khi respawn
player.CharacterAdded:Connect(function(char)
    humanoid = char:WaitForChild("Humanoid")
    rootPart = char:WaitForChild("HumanoidRootPart")
    applySprintState(false)
end)

-- ════════════════════════════
--  TAB: NOTIFY
-- ════════════════════════════
local pgNotify = pages["notify"]
local nScroll = Instance.new("ScrollingFrame", pgNotify)
nScroll.Size=UDim2.new(1,0,1,0); nScroll.BackgroundTransparency=1
nScroll.ScrollBarThickness=3; nScroll.ScrollBarImageColor3=C.accent
nScroll.CanvasSize=UDim2.new(0,0,0,0); nScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
nScroll.BorderSizePixel=0

local nInner = Instance.new("Frame", nScroll)
nInner.Size=UDim2.new(1,0,0,0); nInner.AutomaticSize=Enum.AutomaticSize.Y
nInner.BackgroundTransparency=1

UI.sectionLabel(nInner, 4, "💬  CHAT DETECTION")
UI.toggle(nInner, 22, "Detect from chat [Egg Spawned]", "CHAT_DETECT")
UI.toggle(nInner, 56, "Webhook on chat detect",         "CHAT_WEBHOOK")

-- Chat egg log (mini display inside tab)
local chatCard = UI.card(nInner, UDim2.new(1,-24,0,54), UDim2.new(0,12,0,94), 7)
local chatLogLbl = UI.label(chatCard, {
    Size=UDim2.new(1,-8,1,0), Position=UDim2.new(0,6,0,0),
    Text="Watching chat for [Egg Spawned]…",
    TextColor3=C.textDim, TextSize=9, Font=Enum.Font.Code,
    TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top,
    TextWrapped=true
})

UI.sectionLabel(nInner, 156, "🔔  DISCORD WEBHOOK")

-- Webhook URL input
local wbox = UI.card(nInner, UDim2.new(1,-24,0,30), UDim2.new(0,12,0,174), 7)
local wStroke = UI.stroke(wbox, C.border, 1, 0.4)
local webhookInput = Instance.new("TextBox", wbox)
webhookInput.Size=UDim2.new(1,-12,1,0); webhookInput.Position=UDim2.new(0,8,0,0)
webhookInput.BackgroundTransparency=1; webhookInput.Font=Enum.Font.Code
webhookInput.TextSize=9; webhookInput.TextColor3=C.textMain
webhookInput.PlaceholderText="Paste Discord webhook URL here..."
webhookInput.PlaceholderColor3=C.textDim
webhookInput.TextXAlignment=Enum.TextXAlignment.Left
webhookInput.ClearTextOnFocus=false; webhookInput.Text=SETTINGS.WEBHOOK_URL
webhookInput.FocusLost:Connect(function()
    SETTINGS.WEBHOOK_URL = webhookInput.Text; saveConfig()
end)
webhookInput.Focused:Connect(function()
    wStroke.Color=C.accent; wStroke.Transparency=0
end)
webhookInput.FocusLost:Connect(function()
    wStroke.Color=C.border; wStroke.Transparency=0.4
end)

UI.toggle(nInner, 208, "Auto Webhook on Workspace Detect", "WEBHOOK_ENABLED")

-- ════════════════════════════
--  TAB: LOG
-- ════════════════════════════
local pgLog = pages["log"]

local logHdr = Instance.new("Frame", pgLog)
logHdr.Size=UDim2.new(1,0,0,18); logHdr.BackgroundTransparency=1
UI.label(logHdr, {
    Size=UDim2.new(0.5,0,1,0), Text="📋  LOG",
    TextColor3=C.textDim, TextSize=9, Font=Enum.Font.GothamBold,
    TextXAlignment=Enum.TextXAlignment.Left
})
local clearBtn = UI.button(logHdr, {
    Size=UDim2.new(0,52,0,16), Position=UDim2.new(1,-52,0.5,-8),
    BackgroundColor3=C.card, Text="CLEAR", TextColor3=C.textDim, TextSize=9
})
UI.corner(clearBtn, 4); UI.hover(clearBtn, C.card, C.cardHov)

local logScroll = Instance.new("ScrollingFrame", pgLog)
logScroll.Size=UDim2.new(1,0,1,-22); logScroll.Position=UDim2.new(0,0,0,20)
logScroll.BackgroundColor3=C.logBg; logScroll.BorderSizePixel=0
logScroll.ScrollBarThickness=3; logScroll.ScrollBarImageColor3=C.accent
logScroll.CanvasSize=UDim2.new(0,0,0,0); logScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
UI.corner(logScroll, 6)
Instance.new("UIListLayout", logScroll).SortOrder=Enum.SortOrder.LayoutOrder
local lp = Instance.new("UIPadding", logScroll)
lp.PaddingLeft=UDim.new(0,6); lp.PaddingTop=UDim.new(0,3)

local logOrder=0; local MAX_LINES=60
local lastLogMsg=""; local lastLogCount=1; local lastLogLbl=nil

local function guiLog(msg, color)
    color = color or C.textDim
    if msg==lastLogMsg and lastLogLbl and lastLogLbl.Parent then
        lastLogCount += 1
        lastLogLbl.Text = os.date("%H:%M:%S").."  "..msg.."  ×"..lastLogCount
        task.defer(function() logScroll.CanvasPosition=Vector2.new(0,logScroll.AbsoluteCanvasSize.Y) end)
        return
    end
    lastLogMsg=msg; lastLogCount=1; logOrder+=1
    local lbl = Instance.new("TextLabel", logScroll)
    lbl.Size=UDim2.new(1,0,0,13); lbl.BackgroundTransparency=1
    lbl.Text=os.date("%H:%M:%S").."  "..msg
    lbl.TextColor3=color; lbl.TextSize=9; lbl.Font=Enum.Font.Code
    lbl.TextXAlignment=Enum.TextXAlignment.Left
    lbl.TextTruncate=Enum.TextTruncate.AtEnd
    lbl.LayoutOrder=logOrder; lastLogLbl=lbl
    local kids = {}
    for _,c in ipairs(logScroll:GetChildren()) do
        if c:IsA("TextLabel") then kids[#kids+1]=c end
    end
    table.sort(kids, function(a,b) return a.LayoutOrder<b.LayoutOrder end)
    while #kids>MAX_LINES do table.remove(kids,1):Destroy() end
    task.defer(function() logScroll.CanvasPosition=Vector2.new(0,logScroll.AbsoluteCanvasSize.Y) end)
end

clearBtn.MouseButton1Click:Connect(function()
    lastLogMsg=""; lastLogLbl=nil; lastLogCount=1
    for _,c in ipairs(logScroll:GetChildren()) do
        if c:IsA("TextLabel") then c:Destroy() end
    end
    guiLog("Log cleared.", C.textDim)
end)

-- Set default tab
switchTab("farm")

-- ── GUI updater ───────────────────────────────────────────────
local function updateGUI()
    valCollected.Text = tostring(STATE.eggsCollected)
    valFound.Text     = tostring(STATE.eggsFound)
    valChat.Text      = tostring(STATE.chatEggsDetected)
    if STATE.running then
        local s = math.floor(tick()-STATE.startTime)
        valTime.Text = s<60 and s.."s" or math.floor(s/60).."m"..(s%60).."s"
    else
        valTime.Text = "0s"
    end
    targetLbl.Text = STATE.currentTarget
end

task.spawn(function()
    while gui.Parent do
        if STATE.running then updateGUI() end
        task.wait(1)
    end
end)

-- ═══════════════════════════════════════════════════════════
--  CHAT DETECTION  (NEW)
--  Watches for messages like:  [Egg Spawned]: 'Holy Eggsus.'
-- ═══════════════════════════════════════════════════════════
-- Pattern KHÔNG dùng trực tiếp vì Lua không hỗ trợ case-insensitive flag
-- → dùng hàm detect riêng bên dưới thay vì pattern đơn
local CHAT_EGG_PATTERN = nil -- unused, replaced by detectChatEgg()

-- List of egg names that are considered rare (lowercase match)
local RARE_EGG_KEYWORDS = {
    "holy", "abyssal", "abyss", "divine", "mythic",
    "celestial", "void", "shadow", "storm", "ancient",
    "legendary", "galaxy", "cosmic", "prismatic",
}

-- ─── Chat egg detector linh hoạt ────────────────────────────
-- Bắt được mọi biến thể:
--   [Egg Spawned]: 'Holy Eggsus.'
--   EGG SPAWNED: Holy Eggsus
--   egg spawned - Holy Eggsus
--   Egg Spawned Holy Eggsus       (không có dấu phân cách)
--   [EGG SPAWNED] Holy Eggsus
local function detectChatEgg(msg)
    if not msg or msg == "" then return nil end

    -- Bước 1: lowercase để so sánh
    local lower = msg:lower()

    -- Bước 2: phải chứa cả "egg" lẫn "spawn" (dạng nào cũng được)
    if not lower:match("egg") then return nil end
    if not lower:match("spawn") then return nil end

    -- Bước 3: tìm vị trí kết thúc của từ "spawned" (hoặc "spawn")
    -- rồi lấy phần text phía sau làm tên trứng
    local afterIdx = nil

    -- thử "spawned" trước, sau đó "spawn"
    local _, e1 = lower:find("spawned")
    local _, e2 = lower:find("spawn")
    afterIdx = e1 or e2

    if not afterIdx then return nil end

    -- Bước 4: cắt phần sau, bỏ qua ký tự phân cách [:]-_|>
    local rest = msg:sub(afterIdx + 1)
    -- bỏ dấu ngoặc đóng, dấu phân cách, khoảng trắng ở đầu
    rest = rest:gsub("^[%]%)%}%s:%.%-_|>\"'!]+", "")
    -- trim đầu/cuối
    rest = rest:match("^%s*(.-)%s*$")
    -- bỏ dấu nháy/ngoặc bao quanh nếu có
    rest = rest:gsub("^[\"'%[%(](.+)[\"'%]%)]$", "%1")
    -- bỏ dấu chấm/! cuối
    rest = rest:gsub("[%.!]+$", "")
    -- trim lại
    rest = rest:match("^%s*(.-)%s*$")

    if rest == "" then
        -- không có tên cụ thể, vẫn trigger nhưng tên là "Unknown"
        return "Unknown Egg"
    end

    return rest
end

local function isRareEgg(name)
    local lower = name:lower()
    for _, kw in ipairs(RARE_EGG_KEYWORDS) do
        if lower:find(kw, 1, true) then return true end
    end
    return false
end

local chatCooldown = {}

local function onChatEggDetected(eggName, rawMsg)
    if not SETTINGS.CHAT_DETECT then return end

    local key = eggName
    if chatCooldown[key] and tick()-chatCooldown[key] < 8 then return end
    chatCooldown[key] = tick()

    STATE.chatEggsDetected += 1
    local rare = isRareEgg(eggName)
    local color = rare and C.pink or C.yellow

    -- Update the chat log preview in Notify tab
    chatLogLbl.Text = (rare and "⭐ RARE: " or "🥚 ").."["..os.date("%H:%M:%S").."] "..eggName
    chatLogLbl.TextColor3 = color

    guiLog((rare and "⭐ RARE " or "💬 Chat: ")..eggName, color)
    updateGUI()

    if rare then
        -- notify screen
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title = "⭐ Rare Egg Spotted!",
                Text  = eggName,
                Duration = 6,
            })
        end)
    end

    if SETTINGS.CHAT_WEBHOOK then
        task.spawn(function() sendWebhook(eggName, "chat detect"..(rare and " [RARE]" or "")) end)
    end
end

-- Hook TextChatService (modern Roblox)
local function hookTextChat()
    local success = pcall(function()
        local defaultChannel = TextChatService:FindFirstChild("TextChannels")
        if defaultChannel then
            for _, ch in ipairs(defaultChannel:GetChildren()) do
                ch.MessageReceived:Connect(function(msg)
                    if msg and msg.Text then
                        local eggName = detectChatEgg(msg.Text)
                        if eggName then
                            onChatEggDetected(eggName, msg.Text)
                        end
                    end
                end)
            end
        end
    end)
    if not success then
        -- Fallback: legacy chat
        pcall(function()
            local StarterGui = game:GetService("StarterGui")
            local chatGui = player:WaitForChild("PlayerGui"):WaitForChild("Chat", 5)
            if chatGui then
                local chatFrame = chatGui:FindFirstChildWhichIsA("Frame", true)
                if chatFrame then
                    chatFrame.ChildAdded:Connect(function(child)
                        if child:IsA("TextLabel") or child:IsA("Frame") then
                            local txt = child:FindFirstChildWhichIsA("TextLabel")
                            if txt and detectChatEgg(txt.Text) then
                                local eggName = detectChatEgg(txt.Text)
                                if eggName then
                                    onChatEggDetected(eggName, txt.Text)
                                end
                            end
                        end
                    end)
                end
            end
        end)
    end
end

game:GetService("LogService").MessageOut:Connect(function(msg)
    -- bắt cả log system lẫn chat egg spawn
    if msg:match("Invalid egg") and STATE.currentEggInstance then
        ignoredEggs[STATE.currentEggInstance] = true
    end
    local eggName = detectChatEgg(msg)
    if eggName then
        onChatEggDetected(eggName, msg)
    end
end)

task.spawn(hookTextChat)

-- ═══════════════════════════════════════════════════════════
--  EGG BILLBOARD MARKERS
-- ═══════════════════════════════════════════════════════════
local markerRegistry = {}

local function getMarkerColor(name)
    if name:match("random_potion") then return Color3.fromRGB(200, 80, 255) end
    return Color3.fromRGB(80, 180, 255)
end

local function getEggLabel(name)
    if name:match("random_potion") then return "🧪 Potion Egg" end
    if name:match("point_egg")     then return "✨ Point Egg"  end
    return "🥚 Egg"
end

local function createBillboard(eggInstance, anchorPart)
    if markerRegistry[eggInstance] then return end
    local bb = Instance.new("BillboardGui")
    bb.Name="EggMarker"; bb.Size=UDim2.new(0,110,0,52)
    bb.StudsOffset=Vector3.new(0,5,0); bb.AlwaysOnTop=true
    bb.Adornee=anchorPart; bb.Parent=anchorPart
    bb.Enabled=SETTINGS.SHOW_EGG_MARKERS

    local bg = Instance.new("Frame", bb)
    bg.Size=UDim2.new(1,0,1,0); bg.BackgroundColor3=Color3.fromRGB(10,10,18)
    bg.BackgroundTransparency=0.25; bg.BorderSizePixel=0
    UI.corner(bg, 8); UI.stroke(bg, getMarkerColor(eggInstance.Name), 1.5, 0)

    local nameLbl = Instance.new("TextLabel", bg)
    nameLbl.Size=UDim2.new(1,-6,0,22); nameLbl.Position=UDim2.new(0,3,0,2)
    nameLbl.BackgroundTransparency=1; nameLbl.Text=getEggLabel(eggInstance.Name)
    nameLbl.TextColor3=getMarkerColor(eggInstance.Name); nameLbl.TextSize=12
    nameLbl.Font=Enum.Font.GothamBold; nameLbl.TextXAlignment=Enum.TextXAlignment.Center

    local timerLbl = Instance.new("TextLabel", bg)
    timerLbl.Size=UDim2.new(1,-6,0,16); timerLbl.Position=UDim2.new(0,3,0,26)
    timerLbl.BackgroundTransparency=1; timerLbl.Text="⏱ 0s"
    timerLbl.TextColor3=Color3.fromRGB(180,180,200); timerLbl.TextSize=10
    timerLbl.Font=Enum.Font.Gotham; timerLbl.TextXAlignment=Enum.TextXAlignment.Center

    markerRegistry[eggInstance] = {
        billboard=bb, spawnTick=tick(), timerLbl=timerLbl, anchorPart=anchorPart
    }
end

local function removeMarker(eggInstance)
    local entry = markerRegistry[eggInstance]
    if entry then pcall(function() entry.billboard:Destroy() end); markerRegistry[eggInstance]=nil end
end

task.spawn(function()
    while gui.Parent do
        local now = tick()
        for eggInst, entry in pairs(markerRegistry) do
            if not eggInst or not eggInst.Parent then
                removeMarker(eggInst)
            else
                entry.billboard.Enabled = SETTINGS.SHOW_EGG_MARKERS
                local secs = math.floor(now - entry.spawnTick)
                entry.timerLbl.Text = "⏱ "..(secs<60 and secs.."s" or math.floor(secs/60).."m "..(secs%60).."s")
            end
        end
        task.wait(1)
    end
end)

-- ─── Egg helpers ─────────────────────────────────────────────
local function isEggName(n)
    for _,p in ipairs(EGG_PATTERNS) do if n:match(p) then return true end end
    return false
end
local function getAnchor(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true) end
    return nil
end
local function inExcluded(pos)
    for _,z in ipairs(EXCLUDED_ZONES) do
        if (pos-z.center).Magnitude<=z.radius then return true end
    end
    return false
end

local function onNewEgg(obj)
    if ignoredEggs[obj] then return end
    local anchor = getAnchor(obj)
    if not anchor then return end
    if anchor.Position.Y > SETTINGS.MAX_EGG_HEIGHT then return end
    if inExcluded(anchor.Position) then return end
    createBillboard(obj, anchor)
    guiLog("🥚 Egg appeared: "..obj.Name, C.yellow)
    if SETTINGS.WEBHOOK_ENABLED then
        task.spawn(function() sendWebhook(obj.Name, "workspace detect") end)
    end
end

task.spawn(function()
    task.wait(1)
    for _,obj in ipairs(workspace:GetDescendants()) do
        if isEggName(obj.Name) then onNewEgg(obj) end
    end
end)

workspace.DescendantAdded:Connect(function(obj)
    if isEggName(obj.Name) then task.wait(0.1); onNewEgg(obj) end
end)
workspace.DescendantRemoving:Connect(function(obj)
    if markerRegistry[obj] then removeMarker(obj) end
end)

-- ═══════════════════════════════════════════════════════════
--  WEBHOOK
-- ═══════════════════════════════════════════════════════════
local webhookCooldown = {}

function sendWebhook(eggName, source)
    if not SETTINGS.WEBHOOK_ENABLED and not SETTINGS.CHAT_WEBHOOK then return end
    local url = SETTINGS.WEBHOOK_URL
    if url=="" or not url:match("^https://discord%.com/api/webhooks/") then
        guiLog("⚠ Invalid webhook URL", C.orange); return
    end
    local key = eggName..(source or "")
    if webhookCooldown[key] and tick()-webhookCooldown[key]<10 then return end
    webhookCooldown[key] = tick()

    local isRare = isRareEgg(eggName)
    local body = HttpService:JSONEncode({
        username = "Sols Egg Farm",
        content  = isRare and "@everyone ⭐ **RARE EGG!**" or "@everyone",
        embeds   = {{
            color  = isRare and 0xFF50B4 or 0x6C3AFF,
            title  = isRare and "⭐ Rare Egg Detected!" or "🥚 Egg Detected!",
            fields = {
                {name="Egg",       value="`"..eggName.."`",           inline=true},
                {name="Source",    value=source or "scan",            inline=true},
                {name="Player",    value=player.Name,                 inline=true},
                {name="Collected", value=tostring(STATE.eggsCollected), inline=true},
                {name="Chat Det.", value=tostring(STATE.chatEggsDetected), inline=true},
                {name="Server",    value=game.JobId~="" and game.JobId:sub(1,18).."…" or "private", inline=false},
            },
            footer = {text="Sols RNG Egg Farm v4.0  •  "..os.date("%H:%M:%S")},
        }}
    })

    pcall(function()
        HttpService:RequestAsync({
            Url="https://discord.com/api/webhooks/...", -- filled from SETTINGS
            Method="POST",
            Headers={["Content-Type"]="application/json"},
            Body=body,
        })
    end)

    -- Actually send to the real URL
    pcall(function()
        HttpService:RequestAsync({
            Url=url, Method="POST",
            Headers={["Content-Type"]="application/json"},
            Body=body,
        })
    end)

    guiLog("📨 Webhook: "..eggName..(isRare and " [RARE]" or ""), C.cyan)
end

-- ═══════════════════════════════════════════════════════════
--  FARM LOGIC
-- ═══════════════════════════════════════════════════════════
local function getEggPriority(n)
    if n:match("^random_potion_egg_%d+$") then return 1
    elseif n:match("^point_egg_%d+$") then return 2 end
    return 3
end

local function dist(pos)
    if not rootPart or not rootPart.Parent then return math.huge end
    return (rootPart.Position-pos).Magnitude
end

local function findAllEggs()
    local eggs = {}
    for _,obj in ipairs(workspace:GetDescendants()) do
        if isEggName(obj.Name) and not ignoredEggs[obj] then
            local part = getAnchor(obj)
            if part and part.Position.Y<=SETTINGS.MAX_EGG_HEIGHT and not inExcluded(part.Position) then
                eggs[#eggs+1] = {
                    instance=obj, part=part, position=part.Position,
                    prompt=obj:FindFirstChildWhichIsA("ProximityPrompt",true),
                    name=obj.Name, priority=getEggPriority(obj.Name)
                }
            end
        end
    end
    table.sort(eggs, function(a,b)
        if a.priority~=b.priority then return a.priority<b.priority end
        return dist(a.position)<dist(b.position)
    end)
    STATE.eggsFound = #eggs
    return eggs
end

local function firePrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    if fireproximityprompt then fireproximityprompt(prompt); return true end
    local oh,od = prompt.HoldDuration, prompt.MaxActivationDistance
    prompt.MaxActivationDistance=9999; prompt.HoldDuration=0
    prompt:InputHoldBegin(); task.wait(0.1); prompt:InputHoldEnd()
    prompt.HoldDuration=oh; prompt.MaxActivationDistance=od
    return true
end

local function collectEgg(egg)
    local prompt = egg.prompt or egg.instance:FindFirstChildWhichIsA("ProximityPrompt",true)
    if prompt then
        firePrompt(prompt)
    else
        if VirtualInputManager then
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.15)
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        end
    end
    task.wait(0.35)
    removeMarker(egg.instance)
    STATE.eggsCollected += 1
    guiLog("✓ "..egg.name, C.green)
    UI.pulse(valCollected, C.green)
    updateGUI()
end

-- SimplePath
local SimplePath
pcall(function()
    SimplePath = loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/grayzcale/simplepath/main/src/SimplePath.lua"
    ))()
end)

local pathAgent = nil
local function initPath()
    if pathAgent then pcall(function() pathAgent:Destroy() end) end
    if not SimplePath or not character then return end
    pathAgent = SimplePath.new(character, {
        AgentRadius=3, AgentHeight=5.5, AgentCanJump=true, AgentCanClimb=true,
        AgentJumpHeight=7.2, WaypointSpacing=3, Costs={Water=100,Climb=1},
    })
end
if character then initPath() end
player.CharacterAdded:Connect(function() task.wait(1); initPath() end)

local function walkToEgg(egg)
    STATE.currentEggInstance = egg.instance
    if not rootPart or not egg.part or not egg.part.Parent then return false end
    if not pathAgent then guiLog("❌ SimplePath missing!", C.red); return false end

    guiLog("→ "..egg.name, C.accentHi)
    local baseSpeed = 16
    if SETTINGS.WALK_SPEED_BOOST > 0 and humanoid then
        humanoid.WalkSpeed = baseSpeed + SETTINGS.WALK_SPEED_BOOST
    end

    local done, errors = false, 0
    local maxErr = SETTINGS.PATH_RECOMPUTE_MAX * 3
    local conR,conB,conE,conW

    local function cleanup()
        for _,c in ipairs({conR,conB,conE,conW}) do if c then c:Disconnect() end end
        pcall(function() pathAgent:Stop() end)
        if humanoid and not STATE.sprintActive then humanoid.WalkSpeed = baseSpeed end
    end

    conR = pathAgent.Reached:Connect(function() done=true end)
    conB = pathAgent.Blocked:Connect(function() pcall(function() pathAgent:Run(egg.part.Position) end) end)
    conE = pathAgent.Error:Connect(function()
        errors+=1; if humanoid then humanoid.Jump=true end; task.wait(0.2)
        pcall(function() pathAgent:Run(egg.part.Position) end)
    end)
    conW = pathAgent.WaypointReached:Connect(function()
        local d = dist(egg.part.Position)
        if d<=SETTINGS.PROMPT_DISTANCE then done=true end
        STATE.currentTarget = egg.name..string.format(" (%.0fm)",d)
        targetLbl.Text = STATE.currentTarget
    end)

    pcall(function() pathAgent:Run(egg.part.Position) end)
    local lastP = rootPart.Position; local stuck = 0

    while STATE.running and not done do
        if not egg.part or not egg.part.Parent then guiLog("⚠ Gone: "..egg.name, C.orange); break end
        if dist(egg.part.Position)<=SETTINGS.PROMPT_DISTANCE then done=true; break end
        if errors>maxErr then guiLog("⚠ Too many errors", C.orange); break end
        local cur = rootPart.Position
        if (cur-lastP).Magnitude<0.2 then
            stuck+=0.1
            if stuck>1.5 then
                if humanoid then
                    humanoid.Jump=true
                    humanoid:MoveTo(cur+rootPart.CFrame.RightVector*math.random(-5,5))
                end
                errors+=1; task.wait(0.4)
                pcall(function() pathAgent:Run(egg.part.Position) end)
                stuck=0
            end
        else stuck=0 end
        lastP=cur; task.wait(0.1)
    end

    cleanup()
    if not STATE.running then return false end
    if done or (egg.part and egg.part.Parent and dist(egg.part.Position)<=SETTINGS.PROMPT_DISTANCE) then
        collectEgg(egg); return true
    end
    guiLog("✗ Failed: "..egg.name, C.red)
    STATE.failedAttempts+=1
    return false
end

-- Map fix
local mapFixed = false
local function fixMap()
    if mapFixed then return end; mapFixed=true
    local lg = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("leafygrass")
    if not lg then return end
    guiLog("🛠 Patching geometry...", C.textDim)
    for _,obj in ipairs(lg:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name~="PathBlocker" then
            local b=Instance.new("Part")
            b.Name="PathBlocker"; b.Size=Vector3.new(obj.Size.X,25,obj.Size.Z)
            b.CFrame=obj.CFrame*CFrame.new(0,-(obj.Size.Y/2+12.5),0)
            b.Anchored=true; b.CanCollide=true; b.Transparency=1; b.Parent=obj
        end
    end
end

-- Auto Equip Abyssal
local function autoEquipAbyssal()
    local PG=player:WaitForChild("PlayerGui"); local GS=game:GetService("GuiService")
    local function click(t) pcall(function()
        GS.SelectedObject=t; task.wait()
        VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.Return,false,game); task.wait()
        VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Return,false,game); GS.SelectedObject=nil
    end) end
    local function openBag()
        local sb=PG:FindFirstChild("MainInterface") and PG.MainInterface:FindFirstChild("SideButtons")
        if not sb then return end
        local btns={}
        for _,b in ipairs(sb:GetChildren()) do if b:IsA("TextButton") then btns[#btns+1]=b end end
        table.sort(btns,function(a,b) return a.AbsolutePosition.Y<b.AbsolutePosition.Y end)
        if btns[1] then click(btns[1]); task.wait(0.1) end
    end
    guiLog("🎒 Equipping Abyssal...", C.accent); openBag()
    local hit=false
    for _,o in ipairs(PG:GetDescendants()) do
        if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Text:lower():match("abyssal") then
            if o.AbsoluteSize.X>0 then
                local btn=o:FindFirstAncestorWhichIsA("GuiButton")
                if btn then click(btn); hit=true; break end
            end
        end
    end
    if not hit then guiLog("⚠ Abyssal not found", C.orange); openBag(); return end
    task.wait(0.1)
    for _,o in ipairs(PG:GetDescendants()) do
        if o:IsA("ImageButton") and o:GetFullName():match("MainInterface%.Frame%.Frame%.Frame%.Frame%.ImageButton%.ImageButton$") then
            click(o); guiLog("✅ Aura equipped", C.green); break
        end
    end
    openBag()
end

-- Auto Respawn
local function watchDeath()
    if not humanoid then return end
    humanoid.Died:Connect(function()
        if not STATE.running or not SETTINGS.AUTO_RESPAWN then return end
        guiLog("💀 Died — respawning...", C.orange); task.wait(3); player:LoadCharacter()
    end)
end
watchDeath()
player.CharacterAdded:Connect(function() task.wait(1); watchDeath() end)

local function notify(title, body, dur)
    if not SETTINGS.SHOW_NOTIFICATIONS then return end
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",{Title=title,Text=body,Duration=dur or 4})
    end)
end

-- ── Main loop ─────────────────────────────────────────────────
local function mainLoop()
    fixMap()
    STATE.startTime=tick(); STATE.eggsCollected=0; STATE.failedAttempts=0
    guiLog("▶ Farming started!", C.green)
    notify("Egg Farm","Farming started!",3)
    updateGUI()

    while STATE.running do
        if SETTINGS.AUTO_EQUIP_ABYSSAL then
            if rootPart and rootPart.Parent then autoEquipAbyssal() end
            task.wait(0.5)
        end
        local eggs=findAllEggs(); updateGUI()
        if #eggs==0 then
            STATE.currentTarget="Scanning..."; targetLbl.Text=STATE.currentTarget
            guiLog("No eggs — scanning...", C.textDim)
            task.wait(SETTINGS.SEARCH_INTERVAL)
        else
            guiLog("Found "..(#eggs).." egg(s)", C.accent)
            for _,egg in ipairs(eggs) do
                if not STATE.running then break end
                if egg.part and egg.part.Parent then
                    walkToEgg(egg); task.wait(0.3)
                end
            end
            task.wait(SETTINGS.SEARCH_INTERVAL)
        end
    end

    STATE.currentTarget="—"; targetLbl.Text="—"
    updateGUI()
    guiLog("⏸ Stopped. Collected: "..STATE.eggsCollected, C.orange)
    notify("Egg Farm","Stopped. Collected: "..STATE.eggsCollected, 5)
end

-- Buttons
startBtn.MouseButton1Click:Connect(function()
    if STATE.running then return end
    STATE.running=true
    UI.tween(startBtn,.1,{BackgroundTransparency=0.5})
    task.delay(.15,function() UI.tween(startBtn,.1,{BackgroundTransparency=0}) end)
    task.spawn(mainLoop)
end)

stopBtn.MouseButton1Click:Connect(function()
    if not STATE.running then return end
    STATE.running=false
    UI.tween(stopBtn,.1,{BackgroundTransparency=0})
    task.delay(.15,function() UI.tween(stopBtn,.1,{BackgroundTransparency=0.55}) end)
    updateGUI()
end)

-- Ready
guiLog("Ready — press START.", C.accent)
guiLog("Chat detection active for [Egg Spawned].", C.pink)
updateGUI()
