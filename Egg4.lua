-- ╔══════════════════════════════════════════╗
-- ║     Sols RNG Egg Farm  |  v4.3           ║
-- ║     Chat Detection + Tabbed UI           ║
-- ║     Fixed: Drag, Timer, Webhook UI       ║
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
    SPRINT_SPEED       = 0,
    AUTO_EQUIP_ABYSSAL = false,
    MAX_EGG_HEIGHT     = 130,
    SHOW_NOTIFICATIONS = true,
    AUTO_RESPAWN       = true,
    WEBHOOK_URL        = "",
    WEBHOOK_ENABLED    = false,
    SHOW_EGG_MARKERS   = true,
    CHAT_DETECT        = true,
    CHAT_WEBHOOK       = true,
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
    chatEggsDetected   = 0,
    sprintActive       = false,
}

local ignoredEggs = setmetatable({}, {__mode="k"})

-- ─── Egg config ──────────────────────────────────────────────
local EGG_PATTERNS   = {"^point_egg_%d+$", "^random_potion_egg_%d+$"}

-- ─── Easter Event 2026 — Template Similarity Engine ─────────
-- Load templates từ ReplicatedStorage, rồi dùng Jaccard similarity
-- để nhận diện trứng trong workspace (ngưỡng >= 20%)
local easterTemplates  = {}  -- [templateName] = {childNames, childClasses, totalFeatures}
local easterMatchCache = setmetatable({}, {__mode="k"})  -- cache kết quả match
local SIMILARITY_THRESHOLD = 0.20

local function extractFeatures(obj)
    local names, classes = {}, {}
    names[obj.Name:lower()] = true
    for _, child in ipairs(obj:GetChildren()) do
        names[child.Name:lower()]        = true
        classes[child.ClassName:lower()] = true
        for _, gc in ipairs(child:GetChildren()) do
            names[gc.Name:lower()]        = true
            classes[gc.ClassName:lower()] = true
        end
    end
    local total = 0
    for _ in pairs(names)   do total += 1 end
    for _ in pairs(classes) do total += 1 end
    return names, classes, total
end

local function similarityScore(nA, cA, tA, nB, cB, tB)
    if tA == 0 or tB == 0 then return 0 end
    local inter = 0
    for k in pairs(nA) do if nB[k] then inter += 1 end end
    for k in pairs(cA) do if cB[k] then inter += 1 end end
    local union = tA + tB - inter
    return union > 0 and (inter / union) or 0
end

local function matchEasterTemplate(obj)
    local cached = easterMatchCache[obj]
    if cached ~= nil then return cached or nil end
    if obj.Name:match("^point_egg_%d+$") or obj.Name:match("^random_potion_egg_%d+$") then
        easterMatchCache[obj] = false; return nil
    end
    -- Tên khớp trực tiếp → điểm tuyệt đối
    local direct = obj.Name:lower()
    if easterTemplates[direct] then
        easterMatchCache[obj] = direct; return direct
    end
    if not next(easterTemplates) then
        easterMatchCache[obj] = false; return nil
    end
    local nO, cO, tO = extractFeatures(obj)
    local best, bestName = 0, nil
    for tName, tData in pairs(easterTemplates) do
        local s = similarityScore(nO, cO, tO, tData.childNames, tData.childClasses, tData.totalFeatures)
        if s > best then best = s; bestName = tName end
    end
    if best >= SIMILARITY_THRESHOLD then
        easterMatchCache[obj] = bestName; return bestName
    end
    easterMatchCache[obj] = false; return nil
end

-- ─── Easter Egg Rarity Table (EasterEvent2026) ───────────────
-- Dữ liệu đầy đủ từ bảng chính thức
-- Rarity phân theo spawn chance:
--   Common    >= 0.1%
--   Uncommon  >= 0.05%
--   Rare      >= 0.013%
--   Epic      >= 0.004%
--   Legendary >= 0.002%
local RARITY_COLORS = {
    ["Common"]    = Color3.fromRGB(200, 200, 210),
    ["Uncommon"]  = Color3.fromRGB(80,  220, 110),
    ["Rare"]      = Color3.fromRGB(80,  160, 255),
    ["Epic"]      = Color3.fromRGB(180, 80,  255),
    ["Legendary"] = Color3.fromRGB(255, 200, 50),
    ["Unknown"]   = Color3.fromRGB(140, 140, 160),
}

-- Format: chance = spawn % (để hiển thị), rarity, aura, spawnMsg, despawn = phút
local EASTER_RARITY = {
    ["hatch_egg"] = {
        label      = "Hatch Egg",
        rarity     = "Common",
        chance     = "0.1%",
        oneIn      = "1/1,000",
        aura       = "Hatchwarden",
        despawn    = 30,
        spawnMsg   = "A special egg has spawned.",
        color      = RARITY_COLORS["Common"],
    },
    ["royal_egg"] = {
        label      = "Royal Egg",
        rarity     = "Uncommon",
        chance     = "0.05%",
        oneIn      = "1/2,000",
        aura       = "EMPEROR",
        despawn    = 30,
        spawnMsg   = "A special egg has spawned.",
        color      = RARITY_COLORS["Uncommon"],
    },
    ["andromeda_egg"] = {
        label      = "Andromeda Egg",
        rarity     = "Rare",
        chance     = "0.013%",
        oneIn      = "1/7,692",
        aura       = "Eggsistence",
        despawn    = 60,
        spawnMsg   = "'Am I in spaaaace right now?!'",
        color      = RARITY_COLORS["Rare"],
    },
    ["angelic_egg"] = {
        label      = "Angelic Egg",
        rarity     = "Epic",
        chance     = "0.0062%",
        oneIn      = "1/16,129",
        aura       = "Revive",
        despawn    = 60,
        spawnMsg   = "'Holy Eggsus.'",
        color      = RARITY_COLORS["Epic"],
    },
    ["blooming_egg"] = {
        label      = "Blooming Egg",
        rarity     = "Epic",
        chance     = "0.0057%",
        oneIn      = "1/17,543",
        aura       = "EGGORE",
        despawn    = 60,
        spawnMsg   = "Don't forget to water the 'small plant'.",
        color      = RARITY_COLORS["Epic"],
    },
    ["forest_egg"] = {
        label      = "Forest Egg",
        rarity     = "Epic",
        chance     = "0.004%",
        oneIn      = "1/25,000",
        aura       = "Eostre",
        despawn    = 120,
        spawnMsg   = "'Let's have an egg hunt here!'",
        color      = RARITY_COLORS["Epic"],
    },
    ["the_egg_of_the_sky"] = {
        label      = "Egg of the Sky",
        rarity     = "Legendary",
        chance     = "0.0035%",
        oneIn      = "1/28,571",
        aura       = "EGGIS",
        despawn    = 120,
        spawnMsg   = "Scanning. Egg cannon charging 2000%.",
        color      = RARITY_COLORS["Legendary"],
    },
    ["egg_v2.0"] = {
        label      = "Egg V2.0",
        rarity     = "Legendary",
        chance     = "0.0023%",
        oneIn      = "1/43,478",
        aura       = "Y.O.L.K.E.G.G.",
        despawn    = 120,
        spawnMsg   = "Preparing Protocol. 'Do you want to be my friend?'",
        color      = RARITY_COLORS["Legendary"],
    },
    ["dreamer_egg"] = {
        label      = "Dreamer Egg",
        rarity     = "Legendary",
        chance     = "0.002%",
        oneIn      = "1/50,000",
        aura       = "[Sky Festival]",
        despawn    = 120,
        spawnMsg   = "'Wait, am I still dreaming?'",
        color      = RARITY_COLORS["Legendary"],
    },
}

local function getEasterInfo(name)
    -- Thử tìm trực tiếp
    local info = EASTER_RARITY[name]
    if info then return info end
    -- Thử normalize tên (thêm _egg nếu chưa có, thay space bằng _)
    local normalized = name:lower():gsub(" ", "_")
    info = EASTER_RARITY[normalized]
    if info then return info end
    -- Fallback: tự tạo từ tên
    local displayName = name:gsub("_egg$",""):gsub("_"," ")
    displayName = displayName:gsub("(%a)([%w_']*)", function(a,b) return a:upper()..b end).." Egg"
    return {
        label   = displayName,
        rarity  = "Unknown",
        chance  = "?",
        oneIn   = "?",
        aura    = "?",
        despawn = 60,
        spawnMsg = "",
        color   = RARITY_COLORS["Unknown"],
    }
end

-- Auto-farm toggle per egg type (lưu trong SETTINGS)
-- Key: "EASTER_FARM_<tên_egg>" = true/false
local EASTER_EGG_ORDER = {
    "hatch_egg", "royal_egg", "andromeda_egg", "angelic_egg",
    "blooming_egg", "forest_egg", "the_egg_of_the_sky", "egg_v2.0", "dreamer_egg",
}
local function isEasterAutoFarm(objOrName)
    local key
    if typeof(objOrName) == "Instance" then
        local tName = matchEasterTemplate(objOrName)
        if not tName then return false end
        key = "EASTER_FARM_"..tName
    else
        key = "EASTER_FARM_"..tostring(objOrName):lower()
    end
    return SETTINGS[key] == true
end

-- isEasterEgg dùng cho scan nhanh (chỉ check tên) — dùng trước khi gọi matchEasterTemplate
local function isEasterEgg(obj)
    if typeof(obj) == "string" then
        -- Gọi bằng tên thuần — chỉ check bảng cứng
        local n = obj:lower()
        if n:match("^point_egg_%d+$") or n:match("^random_potion_egg_%d+$") then return false end
        if easterTemplates[n] then return true end
        return false
    end
    -- Gọi bằng Instance — dùng similarity engine đầy đủ
    return matchEasterTemplate(obj) ~= nil
end

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
--  SHARED UI FACTORY
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

function UI.card(parent, size, pos, radius)
    local f = Instance.new("Frame", parent)
    f.Size             = size
    f.Position         = pos or UDim2.new(0,0,0,0)
    f.BackgroundColor3 = C.card
    f.BorderSizePixel  = 0
    UI.corner(f, radius or 8)
    return f
end

function UI.slider(parent, yPos, labelTxt, minV, maxV, settingKey)
    local f = UI.card(parent, UDim2.new(1,-24,0,30), UDim2.new(0,12,0,yPos), 7)
    UI.label(f, {
        Size=UDim2.new(0.50,0,1,0), Position=UDim2.new(0,10,0,0),
        Text=labelTxt, TextColor3=C.textMain, TextSize=10, Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left
    })
    local btnMinus = UI.button(f, {
        Size=UDim2.new(0,24,0,22), Position=UDim2.new(1,-112,0.5,-11),
        BackgroundColor3=C.card, Text="-", TextColor3=C.textMain, TextSize=14
    })
    UI.corner(btnMinus, 5); UI.hover(btnMinus, C.card, C.cardHov)
    local inputBox = Instance.new("TextBox", f)
    inputBox.Size=UDim2.new(0,56,0,22); inputBox.Position=UDim2.new(1,-84,0.5,-11)
    inputBox.BackgroundColor3=C.bg; inputBox.BorderSizePixel=0
    inputBox.Font=Enum.Font.GothamBold; inputBox.TextSize=12
    inputBox.TextColor3=C.accent; inputBox.Text=tostring(SETTINGS[settingKey])
    inputBox.ClearTextOnFocus=false
    UI.corner(inputBox, 5); UI.stroke(inputBox, C.border, 1, 0.5)
    local btnPlus = UI.button(f, {
        Size=UDim2.new(0,24,0,22), Position=UDim2.new(1,-26,0.5,-11),
        BackgroundColor3=C.card, Text="+", TextColor3=C.textMain, TextSize=14
    })
    UI.corner(btnPlus, 5); UI.hover(btnPlus, C.card, C.cardHov)
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

-- ════════════════════════════════════════════════════════════
--  HEADER — FIX: drag toàn bộ header, double-click thu nhỏ
--  Nút — đã tích hợp vào header (double-click), chỉ còn nút ✕
-- ════════════════════════════════════════════════════════════
local header = Instance.new("Frame", main)
header.Name="Header"
header.Size=UDim2.new(1,0,0,50)
header.Position=UDim2.new(0,0,0,3)
header.BackgroundTransparency=1

-- Icon
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
    Text="v4.3  •  double-click header to minimize",
    TextSize=9, Font=Enum.Font.Gotham, TextColor3=C.textDim,
    TextXAlignment=Enum.TextXAlignment.Left
})

-- Nút ✕ (đóng) — giữ nguyên
local closeBtn = UI.button(header, {
    Size=UDim2.new(0,28,0,28), Position=UDim2.new(1,-42,0.5,-14),
    BackgroundColor3=C.red, BackgroundTransparency=0.65,
    Text="✕", TextColor3=C.red, TextSize=12, ZIndex=10
})
UI.corner(closeBtn, 6); UI.hover(closeBtn, C.red, C.red, .65, .3)
closeBtn.MouseButton1Click:Connect(function()
    STATE.running = false; task.wait(.2); gui:Destroy()
end)

-- ── FIX DRAG: dùng TextButton trong suốt phủ toàn header, ZIndex cao ──
-- Nhưng KHÔNG phủ lên nút ✕ (chừa 44px bên phải)
local minimized = false

local dragBtn = UI.button(header, {
    Size       = UDim2.new(1, -50, 1, 0),   -- chừa nút ✕ bên phải
    Position   = UDim2.new(0, 0, 0, 0),
    BackgroundTransparency = 1,
    Text       = "",
    ZIndex     = 5,                          -- cao hơn label nhưng thấp hơn closeBtn
})

-- Drag state
local dragActive      = false
local dragStartMouse  = nil
local dragStartFrame  = nil

-- Double-click để thu nhỏ
local lastClickTime   = 0
local DBL_CLICK_TIME  = 0.35

dragBtn.MouseButton1Click:Connect(function()
    local now = tick()
    if now - lastClickTime < DBL_CLICK_TIME then
        -- Double-click → toggle minimize
        minimized = not minimized
        UI.tween(main, .28, {Size=UDim2.new(0,W,0, minimized and MINI_H or FULL_H)})
        subtitleLbl.Text = minimized
            and "v4.3  •  double-click to expand"
            or  "v4.3  •  double-click header to minimize"
        lastClickTime = 0
    else
        lastClickTime = now
    end
end)

dragBtn.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragActive     = true
        dragStartMouse = inp.Position
        dragStartFrame = main.Position
    end
end)

UserInputService.InputChanged:Connect(function(inp)
    if dragActive and inp.UserInputType == Enum.UserInputType.MouseMovement and dragStartMouse then
        local delta = inp.Position - dragStartMouse
        -- chỉ drag nếu di chuyển > 4px (tránh xung đột double-click)
        if delta.Magnitude > 4 then
            main.Position = UDim2.new(
                dragStartFrame.X.Scale, dragStartFrame.X.Offset + delta.X,
                dragStartFrame.Y.Scale, dragStartFrame.Y.Offset + delta.Y
            )
        end
    end
end)

UserInputService.InputEnded:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 then
        dragActive = false
    end
end)

-- ── Stat cards ───────────────────────────────────────────────
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
local valChat      = statCard(statsRow, (sw4+8)*2, sw4, "CHAT DET.", "0",  C.pink)
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
--  TAB SYSTEM
-- ═══════════════════════════════════════════════════════════
local TAB_Y     = 194
local TAB_H     = 28
local CONTENT_Y = TAB_Y + TAB_H + 4
local CONTENT_H = FULL_H - CONTENT_Y - 4

local tabBar = Instance.new("Frame", main)
tabBar.Size=UDim2.new(1,-24,0,TAB_H); tabBar.Position=UDim2.new(0,12,0,TAB_Y)
tabBar.BackgroundColor3=C.card; tabBar.BorderSizePixel=0; UI.corner(tabBar, 8)

local contentArea = Instance.new("Frame", main)
contentArea.Size=UDim2.new(1,-24,0,CONTENT_H); contentArea.Position=UDim2.new(0,12,0,CONTENT_Y)
contentArea.BackgroundTransparency=1; contentArea.ClipsDescendants=true

local pages   = {}
local tabBtns = {}
local activeTab = nil

local TAB_DEFS = {
    {id="farm",   icon="🚜", label="Farm"},
    {id="speed",  icon="⚡", label="Speed"},
    {id="notify", icon="🔔", label="Notify"},
    {id="log",    icon="📋", label="Log"},
}

local tbw = math.floor((W-24) / #TAB_DEFS)

for i, tdef in ipairs(TAB_DEFS) do
    local tb = UI.button(tabBar, {
        Size=UDim2.new(0,tbw,1,0),
        Position=UDim2.new(0,(i-1)*tbw,0,0),
        BackgroundColor3=C.tabInact, BackgroundTransparency=1,
        Text=tdef.icon.." "..tdef.label, TextColor3=C.textDim,
        TextSize=10, Font=Enum.Font.GothamBold
    })
    UI.corner(tb, 7)
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
            BackgroundColor3       = on and C.tabActive or C.tabInact,
            BackgroundTransparency = on and 0 or 1,
            TextColor3             = on and Color3.new(1,1,1) or C.textDim,
        })
        pages[tid].Visible = on
    end
end

for _, tdef in ipairs(TAB_DEFS) do
    tabBtns[tdef.id].MouseButton1Click:Connect(function() switchTab(tdef.id) end)
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

local fInner = Instance.new("Frame", farmScroll)
fInner.Size=UDim2.new(1,0,0,0); fInner.AutomaticSize=Enum.AutomaticSize.Y
fInner.BackgroundTransparency=1

UI.sectionLabel(fInner, 4, "⚙  FARM SETTINGS")
UI.slider(fInner,  22, "Collect Distance",  2, 12,  "PROMPT_DISTANCE")
UI.slider(fInner,  56, "Path Retries",      1, 10,  "PATH_RECOMPUTE_MAX")
UI.slider(fInner,  90, "Max Egg Height",    50,300, "MAX_EGG_HEIGHT")
UI.toggle(fInner, 124, "Auto Equip Abyssal",      "AUTO_EQUIP_ABYSSAL")
UI.toggle(fInner, 158, "Show Egg Markers",         "SHOW_EGG_MARKERS")
UI.toggle(fInner, 192, "Auto Respawn on Death",    "AUTO_RESPAWN")
UI.toggle(fInner, 226, "Show Notifications",       "SHOW_NOTIFICATIONS")

-- ── EASTER EGG AUTO-FARM SECTION ─────────────────────────────
local easterSectionY = 266

-- Header
local easterHeader = UI.card(fInner, UDim2.new(1,-24,0,28), UDim2.new(0,12,0,easterSectionY), 7)
easterHeader.BackgroundColor3 = Color3.fromRGB(30, 20, 50)
UI.stroke(easterHeader, Color3.fromRGB(108,58,255), 1, 0.3)

UI.label(easterHeader, {
    Size=UDim2.new(0.55,0,1,0), Position=UDim2.new(0,10,0,0),
    Text="🐣  EASTER AUTO-FARM",
    TextColor3=Color3.fromRGB(180,120,255), TextSize=10,
    Font=Enum.Font.GothamBold, TextXAlignment=Enum.TextXAlignment.Left,
})

-- Nút "Bật hết" và "Tắt hết"
local easterBtnW = math.floor(((W-24-24) - 8) / 2)
local easterBtnRow = Instance.new("Frame", fInner)
easterBtnRow.Size=UDim2.new(1,-24,0,26); easterBtnRow.Position=UDim2.new(0,12,0,easterSectionY+34)
easterBtnRow.BackgroundTransparency=1

local btnEnableAll = UI.button(easterBtnRow, {
    Size=UDim2.new(0,easterBtnW,1,0), Position=UDim2.new(0,0,0,0),
    BackgroundColor3=C.green, Text="✅ Nhặt hết",
    TextColor3=Color3.new(1,1,1), TextSize=10,
})
UI.corner(btnEnableAll, 6); UI.hover(btnEnableAll, C.green, Color3.fromRGB(60,230,115))

local btnDisableAll = UI.button(easterBtnRow, {
    Size=UDim2.new(0,easterBtnW,1,0), Position=UDim2.new(0,easterBtnW+8,0,0),
    BackgroundColor3=C.card, Text="🚫 Tắt hết",
    TextColor3=C.textDim, TextSize=10,
})
UI.corner(btnDisableAll, 6); UI.hover(btnDisableAll, C.card, C.cardHov)
UI.stroke(btnDisableAll, C.border, 1, 0.4)

-- Danh sách checkbox từng trứng Easter
local easterCheckboxes = {}  -- [eggKey] = switchFrame
local easterListY = easterSectionY + 66

for i, eggKey in ipairs(EASTER_EGG_ORDER) do
    local info = EASTER_RARITY[eggKey]
    if not info then
        -- fallback nếu key chưa có trong bảng
        info = { label = eggKey, rarity = "Unknown", color = RARITY_COLORS["Unknown"] }
    end

    -- Init setting nếu chưa có
    local settingKey = "EASTER_FARM_"..eggKey
    if SETTINGS[settingKey] == nil then SETTINGS[settingKey] = false end

    local rowY = easterListY + (i-1) * 34
    local rowCard = UI.card(fInner, UDim2.new(1,-24,0,28), UDim2.new(0,12,0,rowY), 7)
    rowCard.BackgroundColor3 = Color3.fromRGB(18,14,30)

    -- Dot màu rarity bên trái
    local dot = Instance.new("Frame", rowCard)
    dot.Size=UDim2.new(0,6,0,6); dot.Position=UDim2.new(0,8,0.5,-3)
    dot.BackgroundColor3=info.color; dot.BorderSizePixel=0; UI.corner(dot,3)

    -- Tên trứng
    UI.label(rowCard, {
        Size=UDim2.new(0.42,0,1,0), Position=UDim2.new(0,20,0,0),
        Text=info.label, TextColor3=info.color,
        TextSize=9, Font=Enum.Font.GothamBold,
        TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,
    })

    -- Badge rarity
    local rarBadge = Instance.new("TextLabel", rowCard)
    rarBadge.Size=UDim2.new(0,60,0,16); rarBadge.Position=UDim2.new(0.43,0,0.5,-8)
    rarBadge.BackgroundColor3=info.color; rarBadge.BackgroundTransparency=0.78
    rarBadge.BorderSizePixel=0; rarBadge.Text=info.rarity
    rarBadge.TextColor3=info.color; rarBadge.TextSize=8; rarBadge.Font=Enum.Font.GothamBold
    UI.corner(rarBadge, 4)

    -- Chance label
    UI.label(rowCard, {
        Size=UDim2.new(0,52,1,0), Position=UDim2.new(1,-106,0,0),
        Text=info.chance or "?", TextColor3=C.textDim,
        TextSize=8, Font=Enum.Font.Code,
        TextXAlignment=Enum.TextXAlignment.Right,
    })

    -- Toggle switch
    local sw = UI.button(rowCard, {
        Size=UDim2.new(0,40,0,20), Position=UDim2.new(1,-48,0.5,-10),
        BackgroundColor3=SETTINGS[settingKey] and C.green or C.border, Text=""
    })
    UI.corner(sw, 10)
    local kn = Instance.new("Frame", sw)
    kn.Size=UDim2.new(0,16,0,16); kn.BackgroundColor3=Color3.new(1,1,1)
    kn.BorderSizePixel=0; UI.corner(kn,8)
    kn.Position = SETTINGS[settingKey] and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)

    sw.MouseButton1Click:Connect(function()
        SETTINGS[settingKey] = not SETTINGS[settingKey]; saveConfig()
        local on = SETTINGS[settingKey]
        UI.tween(sw, .18, {BackgroundColor3 = on and C.green or C.border})
        UI.tween(kn, .18, {Position = on and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)})
    end)

    easterCheckboxes[eggKey] = {sw=sw, kn=kn, settingKey=settingKey}
end

-- Logic Bật/Tắt hết
btnEnableAll.MouseButton1Click:Connect(function()
    for eggKey, cb in pairs(easterCheckboxes) do
        SETTINGS[cb.settingKey] = true
        UI.tween(cb.sw, .15, {BackgroundColor3=C.green})
        UI.tween(cb.kn, .15, {Position=UDim2.new(1,-18,0.5,-8)})
    end
    saveConfig()
    guiLog("✅ Đã bật auto-farm tất cả Easter egg", C.green)
end)
btnDisableAll.MouseButton1Click:Connect(function()
    for eggKey, cb in pairs(easterCheckboxes) do
        SETTINGS[cb.settingKey] = false
        UI.tween(cb.sw, .15, {BackgroundColor3=C.border})
        UI.tween(cb.kn, .15, {Position=UDim2.new(0,2,0.5,-8)})
    end
    saveConfig()
    guiLog("🚫 Đã tắt auto-farm tất cả Easter egg", C.orange)
end)

-- ════════════════════════════
--  TAB: SPEED
-- ════════════════════════════
local pgSpeed = pages["speed"]
local sInner = Instance.new("Frame", pgSpeed)
sInner.Size=UDim2.new(1,0,1,0); sInner.BackgroundTransparency=1

UI.sectionLabel(sInner, 4, "⚡  SPEED SETTINGS")
UI.slider(sInner,  22, "Walk Boost (farm)",  0, 80, "WALK_SPEED_BOOST")
UI.slider(sInner,  56, "Sprint Speed",       0, 80, "SPRINT_SPEED")

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

task.spawn(function()
    while gui.Parent do
        if humanoid and humanoid.Parent then
            speedValLbl.Text = tostring(math.floor(humanoid.WalkSpeed))
        end
        task.wait(0.5)
    end
end)

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

-- Chat Detection
UI.sectionLabel(nInner, 4, "💬  CHAT DETECTION")
UI.toggle(nInner, 22, "Detect from chat [Egg Spawned]", "CHAT_DETECT")
UI.toggle(nInner, 56, "Webhook on chat detect",         "CHAT_WEBHOOK")

local chatCard = UI.card(nInner, UDim2.new(1,-24,0,54), UDim2.new(0,12,0,94), 7)
local chatLogLbl = UI.label(chatCard, {
    Size=UDim2.new(1,-8,1,0), Position=UDim2.new(0,6,0,0),
    Text="Watching chat for [Egg Spawned]…",
    TextColor3=C.textDim, TextSize=9, Font=Enum.Font.Code,
    TextXAlignment=Enum.TextXAlignment.Left,
    TextYAlignment=Enum.TextYAlignment.Top,
    TextWrapped=true
})

-- ── WEBHOOK SECTION ──────────────────────────────────────────
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

-- ── STATUS BAR (hiển thị kết quả gửi webhook) ────────────────
local wStatusCard = UI.card(nInner, UDim2.new(1,-24,0,26), UDim2.new(0,12,0,242), 7)
local wStatusLbl = UI.label(wStatusCard, {
    Size=UDim2.new(1,-10,1,0), Position=UDim2.new(0,8,0,0),
    Text="⏸ Webhook chưa được test",
    TextColor3=C.textDim, TextSize=9, Font=Enum.Font.Gotham,
    TextXAlignment=Enum.TextXAlignment.Left
})

-- ── NÚT WEBHOOK: hàng ngang 3 nút ───────────────────────────
local webhookBtnRow = Instance.new("Frame", nInner)
webhookBtnRow.Size=UDim2.new(1,-24,0,30)
webhookBtnRow.Position=UDim2.new(0,12,0,272)
webhookBtnRow.BackgroundTransparency=1

-- Tính chiều rộng mỗi nút (3 nút, cách nhau 6px)
local wbw = math.floor(((W-24-24) - 12) / 3)

-- [1] Nút TEST WEBHOOK
local testWebhookBtn = UI.button(webhookBtnRow, {
    Size=UDim2.new(0,wbw,1,0), Position=UDim2.new(0,0,0,0),
    BackgroundColor3=C.accent,
    Text="🧪 Test", TextColor3=Color3.new(1,1,1), TextSize=10
})
UI.corner(testWebhookBtn, 7)
UI.hover(testWebhookBtn, C.accent, C.accentHi)

-- [2] Nút COPY URL
local copyUrlBtn = UI.button(webhookBtnRow, {
    Size=UDim2.new(0,wbw,1,0), Position=UDim2.new(0,wbw+6,0,0),
    BackgroundColor3=C.card,
    Text="📋 Copy URL", TextColor3=C.textMain, TextSize=10
})
UI.corner(copyUrlBtn, 7)
UI.hover(copyUrlBtn, C.card, C.cardHov)
UI.stroke(copyUrlBtn, C.border, 1, 0.4)

-- [3] Nút CLEAR URL
local clearUrlBtn = UI.button(webhookBtnRow, {
    Size=UDim2.new(0,wbw,1,0), Position=UDim2.new(0,(wbw+6)*2,0,0),
    BackgroundColor3=C.card,
    Text="🗑 Clear", TextColor3=C.red, TextSize=10
})
UI.corner(clearUrlBtn, 7)
UI.hover(clearUrlBtn, C.card, Color3.fromRGB(50,20,28))
UI.stroke(clearUrlBtn, C.red, 1, 0.6)

-- Logic các nút
local function setWebhookStatus(msg, color, duration)
    wStatusLbl.Text      = msg
    wStatusLbl.TextColor3 = color or C.textDim
    if duration then
        task.delay(duration, function()
            if wStatusLbl and wStatusLbl.Parent then
                wStatusLbl.Text       = "⏸ Webhook chưa được test"
                wStatusLbl.TextColor3 = C.textDim
            end
        end)
    end
end

-- Copy URL
copyUrlBtn.MouseButton1Click:Connect(function()
    local url = SETTINGS.WEBHOOK_URL
    if url == "" then
        setWebhookStatus("⚠ Chưa có URL để copy!", C.orange, 2.5)
        return
    end
    pcall(function() setclipboard(url) end)
    copyUrlBtn.Text = "✓ Copied!"
    UI.tween(copyUrlBtn, .1, {BackgroundColor3 = C.green})
    task.delay(1.5, function()
        if copyUrlBtn and copyUrlBtn.Parent then
            copyUrlBtn.Text = "📋 Copy URL"
            UI.tween(copyUrlBtn, .2, {BackgroundColor3 = C.card})
        end
    end)
end)

-- Clear URL
clearUrlBtn.MouseButton1Click:Connect(function()
    SETTINGS.WEBHOOK_URL = ""
    webhookInput.Text    = ""
    saveConfig()
    setWebhookStatus("🗑 URL đã được xóa", C.orange, 2.5)
end)

-- Test Webhook (gửi thử tin nhắn thật)
testWebhookBtn.MouseButton1Click:Connect(function()
    local url = SETTINGS.WEBHOOK_URL
    if url == "" or not url:match("^https://discord%.com/api/webhooks/") then
        setWebhookStatus("❌ URL không hợp lệ!", C.red, 3)
        return
    end
    testWebhookBtn.Text = "Đang gửi..."
    UI.tween(testWebhookBtn, .1, {BackgroundColor3 = C.orange})
    setWebhookStatus("📡 Đang gửi test webhook…", C.yellow)

    task.spawn(function()
        local ok, err = pcall(function()
            local body = HttpService:JSONEncode({
                username = "Sols Egg Farm",
                embeds   = {{
                    color  = 0x6C3AFF,
                    title  = "🧪 Test Webhook",
                    description = "Webhook đang hoạt động bình thường!",
                    fields = {
                        {name="Player", value=player.Name, inline=true},
                        {name="Server", value=game.JobId~="" and game.JobId:sub(1,18).."…" or "private", inline=true},
                    },
                    footer = {text="Sols RNG Egg Farm v4.3  •  "..os.date("%H:%M:%S")},
                }}
            })
            HttpService:RequestAsync({
                Url     = url,
                Method  = "POST",
                Headers = {["Content-Type"]="application/json"},
                Body    = body,
            })
        end)

        if ok then
            setWebhookStatus("✅ Test thành công! Kiểm tra Discord nhé", C.green, 5)
            UI.tween(testWebhookBtn, .15, {BackgroundColor3 = C.green})
        else
            setWebhookStatus("❌ Gửi thất bại: "..tostring(err):sub(1,40), C.red, 5)
            UI.tween(testWebhookBtn, .15, {BackgroundColor3 = C.red})
        end

        task.delay(2, function()
            if testWebhookBtn and testWebhookBtn.Parent then
                testWebhookBtn.Text = "🧪 Test"
                UI.tween(testWebhookBtn, .2, {BackgroundColor3 = C.accent})
            end
        end)
    end)
end)

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

switchTab("farm")

-- ═══════════════════════════════════════════════════════════
--  EASTER EGG NOTIFICATION PANEL (góc trái dưới)
-- ═══════════════════════════════════════════════════════════
local NOTIF_W       = 290
local NOTIF_CARD_H  = 112
local NOTIF_GAP     = 8
local NOTIF_PAD_B   = 16  -- khoảng cách từ đáy màn hình
local NOTIF_PAD_L   = 16  -- khoảng cách từ trái màn hình
local MAX_NOTIFS    = 10

local notifGui = Instance.new("ScreenGui")
notifGui.Name = "EasterEggNotifGUI"
notifGui.ResetOnSpawn = false
notifGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
notifGui.DisplayOrder = 10
pcall(function() notifGui.Parent = CoreGui end)
if not notifGui.Parent then notifGui.Parent = player:WaitForChild("PlayerGui") end

-- Container cuộn được ở góc trái dưới
local notifContainer = Instance.new("ScrollingFrame", notifGui)
notifContainer.Name = "NotifContainer"
notifContainer.AnchorPoint = Vector2.new(0, 1)
notifContainer.Position = UDim2.new(0, NOTIF_PAD_L, 1, -NOTIF_PAD_B)
notifContainer.Size = UDim2.new(0, NOTIF_W, 0, 0)  -- chiều cao tự tính
notifContainer.BackgroundTransparency = 1
notifContainer.ScrollBarThickness = 3
notifContainer.ScrollBarImageColor3 = C.accent
notifContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
notifContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
notifContainer.ScrollingDirection = Enum.ScrollingDirection.Y
notifContainer.BorderSizePixel = 0
notifContainer.ClipsDescendants = true
notifContainer.VerticalScrollBarPosition = Enum.VerticalScrollBarPosition.Right

local notifLayout = Instance.new("UIListLayout", notifContainer)
notifLayout.SortOrder = Enum.SortOrder.LayoutOrder
notifLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
notifLayout.Padding = UDim.new(0, NOTIF_GAP)
notifLayout.FillDirection = Enum.FillDirection.Vertical

-- Tự cập nhật kích thước container theo số card
local function updateNotifContainerSize()
    local kids = 0
    for _, c in ipairs(notifContainer:GetChildren()) do
        if c:IsA("Frame") then kids = kids + 1 end
    end
    local maxH = math.min(kids, 4) * (NOTIF_CARD_H + NOTIF_GAP)
    TweenService:Create(notifContainer,
        TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
        {Size = UDim2.new(0, NOTIF_W, 0, maxH)}
    ):Play()
end

-- Registry thông báo Easter egg
local easterNotifRegistry = {}  -- [eggInstance] = {card, connections, ...}
local easterNotifOrder = 0

-- Dialog xác nhận tele
local confirmDialog = nil
local function showTeleConfirm(eggInstance, eggName, onConfirm)
    if confirmDialog then confirmDialog:Destroy(); confirmDialog = nil end

    local dlg = Instance.new("Frame", notifGui)
    dlg.Name = "TeleConfirm"
    dlg.AnchorPoint = Vector2.new(0.5, 0.5)
    dlg.Position = UDim2.new(0.5, 0, 0.5, 0)
    dlg.Size = UDim2.new(0, 260, 0, 110)
    dlg.BackgroundColor3 = C.bg
    dlg.BorderSizePixel = 0
    dlg.ZIndex = 20
    UI.corner(dlg, 12)
    UI.stroke(dlg, C.accent, 1.5, 0)
    confirmDialog = dlg

    -- Glow bar
    local gb = Instance.new("Frame", dlg)
    gb.Size = UDim2.new(1,0,0,3); gb.BackgroundColor3 = C.accent; gb.ZIndex = 21
    local ggu = Instance.new("UIGradient", gb)
    ggu.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(108,58,255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200,80,255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(108,58,255)),
    })

    local title = Instance.new("TextLabel", dlg)
    title.Size = UDim2.new(1,-16,0,22); title.Position = UDim2.new(0,8,0,10)
    title.BackgroundTransparency = 1; title.ZIndex = 21
    title.Text = "⚡ Teleport đến trứng?"
    title.TextColor3 = Color3.new(1,1,1); title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left

    local sub = Instance.new("TextLabel", dlg)
    sub.Size = UDim2.new(1,-16,0,16); sub.Position = UDim2.new(0,8,0,32)
    sub.BackgroundTransparency = 1; sub.ZIndex = 21
    sub.Text = eggName; sub.TextColor3 = C.textDim; sub.TextSize = 10
    sub.Font = Enum.Font.Gotham; sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.TextTruncate = Enum.TextTruncate.AtEnd

    local btnRow = Instance.new("Frame", dlg)
    btnRow.Size = UDim2.new(1,-16,0,32); btnRow.Position = UDim2.new(0,8,1,-40)
    btnRow.BackgroundTransparency = 1; btnRow.ZIndex = 21

    local confirmBtn = UI.button(btnRow, {
        Size = UDim2.new(0.48,0,1,0), Position = UDim2.new(0,0,0,0),
        BackgroundColor3 = C.accent, Text = "✈ Tele ngay",
        TextColor3 = Color3.new(1,1,1), TextSize = 11, ZIndex = 22
    })
    UI.corner(confirmBtn, 7)
    UI.hover(confirmBtn, C.accent, C.accentHi)

    local cancelBtn = UI.button(btnRow, {
        Size = UDim2.new(0.48,0,1,0), Position = UDim2.new(0.52,0,0,0),
        BackgroundColor3 = C.card, Text = "✕ Hủy",
        TextColor3 = C.textDim, TextSize = 11, ZIndex = 22
    })
    UI.corner(cancelBtn, 7)
    UI.hover(cancelBtn, C.card, C.cardHov)
    UI.stroke(cancelBtn, C.border, 1, 0.4)

    confirmBtn.MouseButton1Click:Connect(function()
        dlg:Destroy(); confirmDialog = nil
        onConfirm()
    end)
    cancelBtn.MouseButton1Click:Connect(function()
        dlg:Destroy(); confirmDialog = nil
    end)

    -- Tự đóng nếu trứng biến mất
    task.spawn(function()
        while dlg.Parent do
            if not eggInstance or not eggInstance.Parent then
                dlg:Destroy(); confirmDialog = nil; break
            end
            task.wait(0.5)
        end
    end)
end

local function createEasterNotif(eggInstance, anchorPart, info)
    if easterNotifRegistry[eggInstance] then return end

    -- Giới hạn số thông báo
    local kids = {}
    for _, c in ipairs(notifContainer:GetChildren()) do
        if c:IsA("Frame") then kids[#kids+1] = c end
    end
    if #kids >= MAX_NOTIFS then
        -- Xóa cái cũ nhất (LayoutOrder nhỏ nhất)
        table.sort(kids, function(a,b) return a.LayoutOrder < b.LayoutOrder end)
        kids[1]:Destroy()
    end

    easterNotifOrder += 1
    local spawnTick = tick()
    local rarityColor = RARITY_COLORS[info.rarity] or RARITY_COLORS["Unknown"]

    -- ── Card chính ──────────────────────────────────────────
    local card = Instance.new("Frame", notifContainer)
    card.Name = "EasterNotif_"..easterNotifOrder
    card.Size = UDim2.new(1, 0, 0, NOTIF_CARD_H)
    card.BackgroundColor3 = C.card
    card.BorderSizePixel = 0
    card.LayoutOrder = easterNotifOrder
    card.BackgroundTransparency = 1  -- sẽ tween vào
    UI.corner(card, 10)
    UI.stroke(card, rarityColor, 1.5, 0.2)

    -- Thanh màu bên trái
    local sideBar = Instance.new("Frame", card)
    sideBar.Size = UDim2.new(0, 4, 1, -16)
    sideBar.Position = UDim2.new(0, 0, 0, 8)
    sideBar.BackgroundColor3 = rarityColor
    sideBar.BorderSizePixel = 0
    UI.corner(sideBar, 3)

    -- Số thứ tự
    local numLbl = Instance.new("TextLabel", card)
    numLbl.Size = UDim2.new(0, 22, 0, 22)
    numLbl.Position = UDim2.new(0, 10, 0, 8)
    numLbl.BackgroundColor3 = rarityColor
    numLbl.BackgroundTransparency = 0.7
    numLbl.BorderSizePixel = 0
    numLbl.Text = tostring(easterNotifOrder)
    numLbl.TextColor3 = rarityColor
    numLbl.TextSize = 10
    numLbl.Font = Enum.Font.GothamBold
    UI.corner(numLbl, 5)

    -- Tên trứng
    local nameLbl = Instance.new("TextLabel", card)
    nameLbl.Size = UDim2.new(1, -70, 0, 20)
    nameLbl.Position = UDim2.new(0, 38, 0, 7)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text = info.label
    nameLbl.TextColor3 = rarityColor
    nameLbl.TextSize = 12
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd

    -- Badge độ hiếm
    local rarityBadge = Instance.new("TextLabel", card)
    rarityBadge.Size = UDim2.new(0, 62, 0, 16)
    rarityBadge.Position = UDim2.new(1, -68, 0, 9)
    rarityBadge.BackgroundColor3 = rarityColor
    rarityBadge.BackgroundTransparency = 0.75
    rarityBadge.BorderSizePixel = 0
    rarityBadge.Text = info.rarity
    rarityBadge.TextColor3 = rarityColor
    rarityBadge.TextSize = 9
    rarityBadge.Font = Enum.Font.GothamBold
    UI.corner(rarityBadge, 4)

    -- Vị trí
    local pos = anchorPart.Position
    local posLbl = Instance.new("TextLabel", card)
    posLbl.Size = UDim2.new(1, -12, 0, 13)
    posLbl.Position = UDim2.new(0, 10, 0, 30)
    posLbl.BackgroundTransparency = 1
    posLbl.Text = string.format("📍 %.0f, %.0f, %.0f", pos.X, pos.Y, pos.Z)
    posLbl.TextColor3 = C.textDim
    posLbl.TextSize = 9
    posLbl.Font = Enum.Font.Code
    posLbl.TextXAlignment = Enum.TextXAlignment.Left

    -- Aura + Chance
    local auraLbl = Instance.new("TextLabel", card)
    auraLbl.Size = UDim2.new(1, -12, 0, 13)
    auraLbl.Position = UDim2.new(0, 10, 0, 44)
    auraLbl.BackgroundTransparency = 1
    auraLbl.Text = "✨ "..(info.aura or "?").."   🎲 "..(info.chance or "?").." ("..(info.oneIn or "?")..")"
    auraLbl.TextColor3 = rarityColor
    auraLbl.TextSize = 9
    auraLbl.Font = Enum.Font.Gotham
    auraLbl.TextXAlignment = Enum.TextXAlignment.Left
    auraLbl.TextTruncate = Enum.TextTruncate.AtEnd

    -- Giờ spawn + đếm thời gian đã spam
    local spawnLbl = Instance.new("TextLabel", card)
    spawnLbl.Size = UDim2.new(0.5, -6, 0, 13)
    spawnLbl.Position = UDim2.new(0, 10, 0, 58)
    spawnLbl.BackgroundTransparency = 1
    spawnLbl.Text = "🕐 "..os.date("%H:%M:%S", math.floor(spawnTick))
    spawnLbl.TextColor3 = C.textDim
    spawnLbl.TextSize = 9
    spawnLbl.Font = Enum.Font.Code
    spawnLbl.TextXAlignment = Enum.TextXAlignment.Left

    local aliveLbl = Instance.new("TextLabel", card)
    aliveLbl.Size = UDim2.new(0.5, -6, 0, 13)
    aliveLbl.Position = UDim2.new(0.5, 2, 0, 58)
    aliveLbl.BackgroundTransparency = 1
    aliveLbl.Text = "⏱ 0s"
    aliveLbl.TextColor3 = C.cyan
    aliveLbl.TextSize = 9
    aliveLbl.Font = Enum.Font.Code
    aliveLbl.TextXAlignment = Enum.TextXAlignment.Left

    -- Đếm ngược đến despawn
    local despawnSecs = (info.despawn or 60) * 60
    local despawnLbl = Instance.new("TextLabel", card)
    despawnLbl.Size = UDim2.new(1, -12, 0, 13)
    despawnLbl.Position = UDim2.new(0, 10, 0, 72)
    despawnLbl.BackgroundTransparency = 1
    despawnLbl.Text = "💀 Despawn: "..(info.despawn or "?").."m"
    despawnLbl.TextColor3 = C.orange
    despawnLbl.TextSize = 9
    despawnLbl.Font = Enum.Font.GothamBold
    despawnLbl.TextXAlignment = Enum.TextXAlignment.Left

    -- Nút TELE
    local teleBtn = UI.button(card, {
        Size = UDim2.new(0, 78, 0, 24),
        Position = UDim2.new(0, 10, 1, -30),
        BackgroundColor3 = C.accent,
        Text = "✈ TELE",
        TextColor3 = Color3.new(1,1,1),
        TextSize = 10,
    })
    UI.corner(teleBtn, 6)
    UI.hover(teleBtn, C.accent, C.accentHi)

    -- Nút DISMISS
    local dismissBtn = UI.button(card, {
        Size = UDim2.new(0, 78, 0, 24),
        Position = UDim2.new(0, 94, 1, -30),
        BackgroundColor3 = C.card,
        Text = "✕ Ẩn",
        TextColor3 = C.textDim,
        TextSize = 10,
    })
    UI.corner(dismissBtn, 6)
    UI.hover(dismissBtn, C.card, C.cardHov)
    UI.stroke(dismissBtn, C.border, 1, 0.4)

    -- Khoảng cách tới trứng
    local distLbl = Instance.new("TextLabel", card)
    distLbl.Size = UDim2.new(0, 80, 0, 24)
    distLbl.Position = UDim2.new(1, -86, 1, -30)
    distLbl.BackgroundTransparency = 1
    distLbl.Text = "📏 —"
    distLbl.TextColor3 = C.yellow
    distLbl.TextSize = 9
    distLbl.Font = Enum.Font.GothamBold
    distLbl.TextXAlignment = Enum.TextXAlignment.Right

    -- Tween slide-in từ trái
    card.Size = UDim2.new(1, 0, 0, NOTIF_CARD_H + 18)  -- tăng chiều cao vì thêm row
    card.Position = UDim2.new(-0.2, 0, 0, 0)
    task.defer(function()
        UI.tween(card, 0.25, {BackgroundTransparency = 0, Position = UDim2.new(0,0,0,0)})
    end)

    -- ── Timer loop ──────────────────────────────────────────
    local timerActive = true
    task.spawn(function()
        while timerActive and notifGui.Parent do
            if not eggInstance or not eggInstance.Parent then
                timerActive = false; break
            end
            local elapsed = math.floor(tick() - spawnTick)
            -- Đếm thời gian đã tồn tại
            local ts = elapsed < 60 and elapsed.."s" or math.floor(elapsed/60).."m "..(elapsed%60).."s"
            pcall(function() aliveLbl.Text = "⏱ "..ts end)

            -- Đếm ngược despawn
            local remaining = despawnSecs - elapsed
            if remaining > 0 then
                local rm = math.floor(remaining/60)
                local rs = remaining % 60
                local despawnStr = rm > 0 and (rm.."m "..rs.."s") or (rs.."s")
                local col = remaining < 30 and C.red or (remaining < 120 and C.orange or C.orange)
                pcall(function()
                    despawnLbl.Text      = "💀 Despawn: "..despawnStr
                    despawnLbl.TextColor3 = col
                end)
            else
                pcall(function()
                    despawnLbl.Text       = "💀 Đã hết thời gian!"
                    despawnLbl.TextColor3 = C.red
                end)
            end

            -- Khoảng cách
            if rootPart and rootPart.Parent and anchorPart and anchorPart.Parent then
                local d = math.floor((rootPart.Position - anchorPart.Position).Magnitude)
                pcall(function() distLbl.Text = "📏 "..d.."m" end)
            end
            task.wait(1)
        end
    end)

    -- ── Xóa card khi trứng biến mất ────────────────────────
    local function removeNotif(animate)
        if not easterNotifRegistry[eggInstance] then return end
        timerActive = false
        easterNotifRegistry[eggInstance] = nil
        if animate then
            UI.tween(card, 0.2, {BackgroundTransparency = 1, Size = UDim2.new(1,0,0,0)})
            task.delay(0.22, function()
                pcall(function() card:Destroy() end)
                updateNotifContainerSize()
            end)
        else
            pcall(function() card:Destroy() end)
            updateNotifContainerSize()
        end
    end

    dismissBtn.MouseButton1Click:Connect(function() removeNotif(true) end)

    teleBtn.MouseButton1Click:Connect(function()
        if not eggInstance or not eggInstance.Parent then
            guiLog("⚠ Trứng đã biến mất!", C.orange); return
        end
        local displayName = info.label
        showTeleConfirm(eggInstance, displayName, function()
            if eggInstance and eggInstance.Parent and anchorPart and anchorPart.Parent then
                if rootPart then
                    rootPart.CFrame = CFrame.new(anchorPart.Position + Vector3.new(0, 3, 0))
                end
                guiLog("✈ Tele → "..displayName, C.accentHi)
            else
                guiLog("⚠ Trứng đã biến mất trước khi tele!", C.orange)
            end
        end)
    end)

    -- Theo dõi trứng biến mất
    local conn = eggInstance.AncestryChanged:Connect(function(_, parent)
        if not parent then removeNotif(true) end
    end)

    easterNotifRegistry[eggInstance] = {
        card      = card,
        conn      = conn,
        stopTimer = function() timerActive = false end,
    }

    updateNotifContainerSize()
    guiLog("🐣 Easter Egg: "..info.label.." ["..info.rarity.."]", rarityColor)
end

local function onNewEasterEgg(obj)
    if easterNotifRegistry[obj] then return end
    local tName = matchEasterTemplate(obj)
    if not tName then return end
    local anchor = getAnchor(obj)
    if not anchor then return end
    if inExcluded(anchor.Position) then return end
    local info = getEasterInfo(tName)
    createEasterNotif(obj, anchor, info)
    if SETTINGS.WEBHOOK_ENABLED then
        task.spawn(function() sendWebhook(info.label.." ["..info.rarity.."]", "easter egg") end)
    end
end

-- ── Load templates từ ReplicatedStorage + quét workspace ─────
task.spawn(function()
    local loaded = 0
    local ok = pcall(function()
        local eggsFolder = game:GetService("ReplicatedStorage")
            :WaitForChild("Assets", 8)
            :WaitForChild("EasterEvent2026", 8)
            :WaitForChild("Eggs", 8)

        for _, template in ipairs(eggsFolder:GetChildren()) do
            local tKey = template.Name:lower()
            local names, classes, total = extractFeatures(template)
            easterTemplates[tKey] = {
                childNames   = names,
                childClasses = classes,
                totalFeatures = total,
                originalName  = template.Name,
            }
            loaded += 1
        end
    end)

    if ok and loaded > 0 then
        guiLog("🐣 Loaded "..loaded.." Easter templates từ ReplicatedStorage", C.pink)
    else
        -- Fallback: tự tạo template giả từ EASTER_RARITY nếu không có ReplicatedStorage
        guiLog("⚠ EasterEvent2026 folder not found — dùng name-only matching", C.orange)
        for key, info in pairs(EASTER_RARITY) do
            easterTemplates[key] = {
                childNames   = {[key] = true},
                childClasses = {},
                totalFeatures = 1,
                originalName  = key,
            }
        end
    end

    -- Quét workspace lần đầu sau khi templates đã load
    task.wait(0.3)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if not obj.Name:match("^point_egg_%d+$") and not obj.Name:match("^random_potion_egg_%d+$") then
            if matchEasterTemplate(obj) then
                task.spawn(function() onNewEasterEgg(obj) end)
            end
        end
    end
end)

-- Theo dõi trứng Easter spawn mới trong workspace
workspace.DescendantAdded:Connect(function(obj)
    -- Lọc nhanh: bỏ qua nếu không phải Model hoặc BasePart
    if not (obj:IsA("Model") or obj:IsA("BasePart")) then return end
    -- Bỏ qua point_egg và random_potion_egg
    if obj.Name:match("^point_egg_%d+$") or obj.Name:match("^random_potion_egg_%d+$") then return end
    task.wait(0.15)  -- đợi children load xong
    if matchEasterTemplate(obj) then
        onNewEasterEgg(obj)
    end
end)



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
--  CHAT DETECTION
-- ═══════════════════════════════════════════════════════════
local RARE_EGG_KEYWORDS = {
    "holy", "abyssal", "abyss", "divine", "mythic",
    "celestial", "void", "shadow", "storm", "ancient",
    "legendary", "galaxy", "cosmic", "prismatic",
}

local function detectChatEgg(msg)
    if not msg or msg == "" then return nil end
    local lower = msg:lower()
    if not lower:match("egg")   then return nil end
    if not lower:match("spawn") then return nil end
    local _, e1 = lower:find("spawned")
    local _, e2 = lower:find("spawn")
    local afterIdx = e1 or e2
    if not afterIdx then return nil end
    local rest = msg:sub(afterIdx + 1)
    rest = rest:gsub("^[%]%)%}%s:%.%-_|>\"'!]+", "")
    rest = rest:match("^%s*(.-)%s*$")
    rest = rest:gsub("^[\"'%[%(](.+)[\"'%]%)]$", "%1")
    rest = rest:gsub("[%.!]+$", "")
    rest = rest:match("^%s*(.-)%s*$")
    if rest == "" then return "Unknown Egg" end
    return rest
end

local function isRareEgg(name)
    local lower = name:lower()
    for _, kw in ipairs(RARE_EGG_KEYWORDS) do
        if lower:find(kw, 1, true) then return true end
    end
    return false
end

-- ═══════════════════════════════════════════════════════════
--  WEBHOOK (khai báo trước onChatEggDetected để tránh nil)
-- ═══════════════════════════════════════════════════════════
local webhookCooldown = {}

local function sendWebhook(eggName, source)
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
                {name="Egg",       value="`"..eggName.."`",              inline=true},
                {name="Source",    value=source or "scan",               inline=true},
                {name="Player",    value=player.Name,                    inline=true},
                {name="Collected", value=tostring(STATE.eggsCollected),  inline=true},
                {name="Chat Det.", value=tostring(STATE.chatEggsDetected), inline=true},
                {name="Server",    value=game.JobId~="" and game.JobId:sub(1,18).."…" or "private", inline=false},
            },
            footer = {text="Sols RNG Egg Farm v4.3  •  "..os.date("%H:%M:%S")},
        }}
    })

    -- Chỉ gửi 1 lần duy nhất đến URL thật
    pcall(function()
        HttpService:RequestAsync({
            Url     = url,
            Method  = "POST",
            Headers = {["Content-Type"]="application/json"},
            Body    = body,
        })
    end)

    guiLog("📨 Webhook: "..eggName..(isRare and " [RARE]" or ""), C.cyan)
end

-- Chat egg handler
local chatCooldown = {}

local function onChatEggDetected(eggName, rawMsg)
    if not SETTINGS.CHAT_DETECT then return end
    local key = eggName
    if chatCooldown[key] and tick()-chatCooldown[key] < 8 then return end
    chatCooldown[key] = tick()

    STATE.chatEggsDetected += 1
    local rare  = isRareEgg(eggName)
    local color = rare and C.pink or C.yellow

    chatLogLbl.Text      = (rare and "⭐ RARE: " or "🥚 ").."["..os.date("%H:%M:%S").."] "..eggName
    chatLogLbl.TextColor3 = color

    guiLog((rare and "⭐ RARE " or "💬 Chat: ")..eggName, color)
    updateGUI()

    if rare then
        pcall(function()
            game:GetService("StarterGui"):SetCore("SendNotification", {
                Title    = "⭐ Rare Egg Spotted!",
                Text     = eggName,
                Duration = 6,
            })
        end)
    end

    if SETTINGS.CHAT_WEBHOOK then
        task.spawn(function() sendWebhook(eggName, "chat detect"..(rare and " [RARE]" or "")) end)
    end
end

local function hookTextChat()
    local success = pcall(function()
        local defaultChannel = TextChatService:FindFirstChild("TextChannels")
        if defaultChannel then
            for _, ch in ipairs(defaultChannel:GetChildren()) do
                ch.MessageReceived:Connect(function(msg)
                    if msg and msg.Text then
                        local eggName = detectChatEgg(msg.Text)
                        if eggName then onChatEggDetected(eggName, msg.Text) end
                    end
                end)
            end
        end
    end)
    if not success then
        pcall(function()
            local chatGui = player:WaitForChild("PlayerGui"):WaitForChild("Chat", 5)
            if chatGui then
                local chatFrame = chatGui:FindFirstChildWhichIsA("Frame", true)
                if chatFrame then
                    chatFrame.ChildAdded:Connect(function(child)
                        local txt = child:FindFirstChildWhichIsA("TextLabel")
                        if txt then
                            local eggName = detectChatEgg(txt.Text)
                            if eggName then onChatEggDetected(eggName, txt.Text) end
                        end
                    end)
                end
            end
        end)
    end
end

game:GetService("LogService").MessageOut:Connect(function(msg)
    if msg:match("Invalid egg") and STATE.currentEggInstance then
        ignoredEggs[STATE.currentEggInstance] = true
    end
    local eggName = detectChatEgg(msg)
    if eggName then onChatEggDetected(eggName, msg) end
end)

task.spawn(hookTextChat)

-- ═══════════════════════════════════════════════════════════
--  EGG BILLBOARD MARKERS — FIX: timer hoạt động ổn định
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

    local spawnTick = tick()

    -- FIX: Dùng vòng lặp riêng cho MỖI billboard thay vì 1 vòng lặp chung
    -- Đảm bảo timer luôn chạy ngay cả khi markerRegistry bị thay đổi
    local timerRunning = true
    task.spawn(function()
        while timerRunning and gui.Parent do
            -- Kiểm tra cả billboard lẫn anchorPart còn tồn tại không
            if not bb or not bb.Parent or not anchorPart or not anchorPart.Parent then
                timerRunning = false
                break
            end
            bb.Enabled = SETTINGS.SHOW_EGG_MARKERS
            local secs = math.floor(tick() - spawnTick)
            local timeStr
            if secs < 60 then
                timeStr = "⏱ " .. secs .. "s"
            else
                timeStr = "⏱ " .. math.floor(secs/60) .. "m " .. (secs%60) .. "s"
            end
            -- pcall để tránh crash nếu label bị xóa giữa chừng
            pcall(function() timerLbl.Text = timeStr end)
            task.wait(1)
        end
    end)

    markerRegistry[eggInstance] = {
        billboard   = bb,
        spawnTick   = spawnTick,
        timerLbl    = timerLbl,
        anchorPart  = anchorPart,
        stopTimer   = function() timerRunning = false end,  -- dùng để dừng loop khi xóa
    }
end

local function removeMarker(eggInstance)
    local entry = markerRegistry[eggInstance]
    if entry then
        -- Dừng vòng lặp timer trước khi destroy
        pcall(function() entry.stopTimer() end)
        pcall(function() entry.billboard:Destroy() end)
        markerRegistry[eggInstance] = nil
    end
end

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
--  FARM LOGIC
-- ═══════════════════════════════════════════════════════════
-- Priority: Easter Legendary=1, Epic=2, Rare=3, Uncommon=4, Common=5,
--           random_potion_egg=6, point_egg=7
local EASTER_PRIORITY = {
    ["Legendary"] = 1, ["Epic"] = 2, ["Rare"] = 3,
    ["Uncommon"]  = 4, ["Common"] = 5, ["Unknown"] = 5,
}
local function getEggPriority(n, tName)
    if tName then
        local info = getEasterInfo(tName)
        return EASTER_PRIORITY[info.rarity] or 5
    end
    if n:match("^random_potion_egg_%d+$") then return 6 end
    if n:match("^point_egg_%d+$") then return 7 end
    return 8
end

local function dist(pos)
    if not rootPart or not rootPart.Parent then return math.huge end
    return (rootPart.Position-pos).Magnitude
end

local function findAllEggs()
    local eggs = {}
    for _,obj in ipairs(workspace:GetDescendants()) do
        if not ignoredEggs[obj] then
            local isNormal = isEggName(obj.Name)
            local tName    = nil
            if not isNormal then
                -- Chỉ chạy similarity nếu là Model hoặc BasePart và không phải egg thường
                if (obj:IsA("Model") or obj:IsA("BasePart"))
                    and not obj.Name:match("^point_egg_%d+$")
                    and not obj.Name:match("^random_potion_egg_%d+$") then
                    tName = matchEasterTemplate(obj)
                end
            end
            local isEaster = tName ~= nil and isEasterAutoFarm(tName)
            if isNormal or isEaster then
                local part = getAnchor(obj)
                if part and part.Position.Y<=SETTINGS.MAX_EGG_HEIGHT and not inExcluded(part.Position) then
                    eggs[#eggs+1] = {
                        instance     = obj,
                        part         = part,
                        position     = part.Position,
                        prompt       = obj:FindFirstChildWhichIsA("ProximityPrompt",true),
                        name         = obj.Name,
                        priority     = getEggPriority(obj.Name, tName),
                        isEaster     = isEaster,
                        templateName = tName,
                    }
                end
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
    -- Xóa thông báo Easter nếu có
    if egg.isEaster and easterNotifRegistry[egg.instance] then
        local entry = easterNotifRegistry[egg.instance]
        if entry then
            pcall(function() entry.stopTimer() end)
            pcall(function()
                UI.tween(entry.card, 0.2, {BackgroundTransparency=1, Size=UDim2.new(1,0,0,0)})
                task.delay(0.22, function() pcall(function() entry.card:Destroy() end); updateNotifContainerSize() end)
            end)
            easterNotifRegistry[egg.instance] = nil
        end
    end
    STATE.eggsCollected += 1
    local eggInfo = egg.isEaster and getEasterInfo(egg.templateName or egg.name) or nil
    local label   = eggInfo and ("🐣 "..eggInfo.label) or ("✓ "..egg.name)
    local col     = eggInfo and eggInfo.color or C.green
    guiLog(label, col)
    UI.pulse(valCollected, C.green)
    updateGUI()
end

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

guiLog("Ready — press START.", C.accent)
guiLog("Chat detection active for [Egg Spawned].", C.pink)
updateGUI()
