-- ╔══════════════════════════════════════════╗
-- ║     Sols RNG Egg Farm  |  v3.2           ║
-- ║     Admin Test Build                     ║
-- ╚══════════════════════════════════════════╝

do if game:GetService("CoreGui"):FindFirstChild("SolsEggFarmGUI") then
    game:GetService("CoreGui"):FindFirstChild("SolsEggFarmGUI"):Destroy()
end end

-- ─── Services ────────────────────────────────────────────────
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local UserInputService    = game:GetService("UserInputService")
local TweenService        = game:GetService("TweenService")
local CoreGui             = game:GetService("CoreGui")
local VirtualInputManager = game:GetService("VirtualInputManager")
local HttpService         = game:GetService("HttpService")

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
    AUTO_EQUIP_ABYSSAL = false,
    MAX_EGG_HEIGHT     = 130,
    SHOW_NOTIFICATIONS = true,
    AUTO_RESPAWN       = true,
    WEBHOOK_URL        = "",
    WEBHOOK_ENABLED    = false,
    SHOW_EGG_MARKERS   = true,   -- billboard markers in world
}

local CONFIG_FILE = "SolsRngSettingsV3.json"
local function saveConfig()
    if writefile then pcall(function() writefile(CONFIG_FILE,HttpService:JSONEncode(SETTINGS)) end) end
end
local function loadConfig()
    if readfile and isfile and isfile(CONFIG_FILE) then pcall(function()
        local d=HttpService:JSONDecode(readfile(CONFIG_FILE))
        if d then for k,v in pairs(d) do if SETTINGS[k]~=nil then SETTINGS[k]=v end end end
    end) end
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
}

local ignoredEggs = setmetatable({},{__mode="k"})
game:GetService("LogService").MessageOut:Connect(function(msg)
    if msg:match("Invalid egg") and STATE.currentEggInstance then
        ignoredEggs[STATE.currentEggInstance]=true
    end
end)

-- ─── Egg config ──────────────────────────────────────────────
local EGG_PATTERNS   = {"^point_egg_%d+$","^random_potion_egg_%d+$"}
local EXCLUDED_ZONES = {
    {center=Vector3.new(55.676,102.85,-594.476),radius=100},
    {center=Vector3.new(-50.29,95.5,-102.54),   radius=80 },
    {center=Vector3.new(16.326,93.75,-438.988), radius=20 },
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
    textMain = Color3.fromRGB(228, 228, 240),
    textDim  = Color3.fromRGB(110, 110, 140),
    logBg    = Color3.fromRGB(8,   8,   14),
    border   = Color3.fromRGB(48,  48,  72),
}

-- ─── Helpers ─────────────────────────────────────────────────
local function tw(obj,t,props)
    TweenService:Create(obj,TweenInfo.new(t,Enum.EasingStyle.Quart,Enum.EasingDirection.Out),props):Play()
end
local function corner(p,r) Instance.new("UICorner",p).CornerRadius=UDim.new(0,r or 8) end
local function stroke(p,col,th,tr)
    local s=Instance.new("UIStroke",p);s.Color=col;s.Thickness=th or 1;s.Transparency=tr or 0;return s
end
local function newLabel(parent,props)
    local l=Instance.new("TextLabel",parent)
    l.BackgroundTransparency=1;l.Font=Enum.Font.GothamBold;l.TextColor3=C.textMain;l.TextSize=12
    for k,v in pairs(props) do l[k]=v end;return l
end
local function newBtn(parent,props)
    local b=Instance.new("TextButton",parent)
    b.Font=Enum.Font.GothamBold;b.TextSize=12;b.BorderSizePixel=0;b.AutoButtonColor=false
    for k,v in pairs(props) do b[k]=v end;return b
end
local function hov(btn,base,hi,baseTr,hiTr)
    baseTr=baseTr or 0;hiTr=hiTr or 0
    btn.MouseEnter:Connect(function() tw(btn,.12,{BackgroundColor3=hi,BackgroundTransparency=hiTr}) end)
    btn.MouseLeave:Connect(function() tw(btn,.15,{BackgroundColor3=base,BackgroundTransparency=baseTr}) end)
end
local function pulse(lbl,color)
    tw(lbl,.08,{TextColor3=Color3.new(1,1,1)})
    task.delay(.12,function() tw(lbl,.2,{TextColor3=color}) end)
end

-- ═══════════════════════════════════════════════════════════
--  GUI ROOT
-- ═══════════════════════════════════════════════════════════
local gui=Instance.new("ScreenGui")
gui.Name="SolsEggFarmGUI";gui.ResetOnSpawn=false;gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
pcall(function() gui.Parent=CoreGui end)
if not gui.Parent then gui.Parent=player:WaitForChild("PlayerGui") end

local FULL_H,MINI_H,W=632,53,360
local main=Instance.new("Frame",gui)
main.Name="Main";main.Size=UDim2.new(0,W,0,FULL_H)
main.Position=UDim2.new(0.5,-180,0.5,-(FULL_H/2))
main.BackgroundColor3=C.bg;main.BorderSizePixel=0;main.ClipsDescendants=true
corner(main,14);stroke(main,C.border,1.5,0.25)

-- glow bar
local gbar=Instance.new("Frame",main)
gbar.Size=UDim2.new(1,0,0,3);gbar.BorderSizePixel=0;gbar.BackgroundColor3=C.accent
local gg=Instance.new("UIGradient",gbar)
gg.Color=ColorSequence.new({
    ColorSequenceKeypoint.new(0,   Color3.fromRGB(108,58,255)),
    ColorSequenceKeypoint.new(0.4, Color3.fromRGB(200,80,255)),
    ColorSequenceKeypoint.new(0.8, Color3.fromRGB(48,160,255)),
    ColorSequenceKeypoint.new(1,   Color3.fromRGB(108,58,255)),
})
task.spawn(function()
    local t=0
    while gui.Parent do t=(t+.004)%1;gg.Offset=Vector2.new(t,0);RunService.RenderStepped:Wait() end
end)

-- ── Header ───────────────────────────────────────────────────
local header=Instance.new("Frame",main)
header.Name="Header";header.Size=UDim2.new(1,0,0,50);header.Position=UDim2.new(0,0,0,3)
header.BackgroundTransparency=1

local headerHit=newBtn(header,{Size=UDim2.new(1,-80,1,0),BackgroundTransparency=1,Text=""})

local iconBox=Instance.new("Frame",header)
iconBox.Size=UDim2.new(0,36,0,36);iconBox.Position=UDim2.new(0,12,0.5,-18)
iconBox.BackgroundColor3=C.accent;iconBox.BorderSizePixel=0;corner(iconBox,10)
newLabel(iconBox,{Size=UDim2.new(1,0,1,0),Text="🥚",TextSize=18})

newLabel(header,{Size=UDim2.new(0,200,0,20),Position=UDim2.new(0,56,0,6),
    Text="Sols RNG  •  Egg Farm",TextSize=15,TextXAlignment=Enum.TextXAlignment.Left})
local subtitleLbl=newLabel(header,{Size=UDim2.new(0,220,0,14),Position=UDim2.new(0,56,0,27),
    Text="Admin Test  v3.2  •  click bar to minimize",TextSize=9,
    Font=Enum.Font.Gotham,TextColor3=C.textDim,TextXAlignment=Enum.TextXAlignment.Left})

local closeBtn=newBtn(header,{Size=UDim2.new(0,28,0,28),Position=UDim2.new(1,-38,0.5,-14),
    BackgroundColor3=C.red,BackgroundTransparency=0.65,Text="✕",TextColor3=C.red,TextSize=12})
corner(closeBtn,6);hov(closeBtn,C.red,C.red,.65,.3)
closeBtn.MouseButton1Click:Connect(function() STATE.running=false;task.wait(.2);gui:Destroy() end)

local minimized=false
local function setMin(v)
    minimized=v
    tw(main,.28,{Size=UDim2.new(0,W,0,minimized and MINI_H or FULL_H)})
    subtitleLbl.Text=minimized and "Admin Test  v3.2  •  click bar to expand"
                               or  "Admin Test  v3.2  •  click bar to minimize"
end
headerHit.MouseButton1Click:Connect(function() setMin(not minimized) end)
headerHit.MouseEnter:Connect(function() tw(gbar,.2,{BackgroundTransparency=0.3}) end)
headerHit.MouseLeave:Connect(function() tw(gbar,.2,{BackgroundTransparency=0}) end)

-- drag
local dragging,dragInput,dragStart,startPos=false,nil,nil,nil
header.InputBegan:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 then
        dragging=true;dragStart=inp.Position;startPos=main.Position
    end
end)
header.InputChanged:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseMovement then dragInput=inp end
end)
header.InputEnded:Connect(function(inp)
    if inp.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)
UserInputService.InputChanged:Connect(function(inp)
    if inp==dragInput and dragging and startPos then
        local d=inp.Position-dragStart
        if d.Magnitude>4 then
            main.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end
end)

-- ── Stat cards ───────────────────────────────────────────────
local statsRow=Instance.new("Frame",main)
statsRow.Size=UDim2.new(1,-24,0,58);statsRow.Position=UDim2.new(0,12,0,58)
statsRow.BackgroundTransparency=1

local function statCard(parent,x,w,label,val,col)
    local f=Instance.new("Frame",parent)
    f.Size=UDim2.new(0,w,1,0);f.Position=UDim2.new(0,x,0,0)
    f.BackgroundColor3=C.card;f.BorderSizePixel=0;corner(f,8)
    local v=newLabel(f,{Name="Val",Size=UDim2.new(1,0,0,30),Position=UDim2.new(0,0,0,5),
        Text=val,TextColor3=col,TextSize=22,Font=Enum.Font.GothamBold})
    newLabel(f,{Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,0,1,-18),
        Text=label,TextColor3=C.textDim,TextSize=9,Font=Enum.Font.Gotham})
    return v
end

local sw=math.floor((W-24-16)/3)
local valCollected=statCard(statsRow,0,      sw,"COLLECTED","0",C.green)
local valFound    =statCard(statsRow,sw+8,   sw,"FOUND",    "0",C.orange)
local valTime     =statCard(statsRow,(sw+8)*2,sw,"TIME",   "0s",C.cyan)

-- ── Target bar ───────────────────────────────────────────────
local tbar=Instance.new("Frame",main)
tbar.Size=UDim2.new(1,-24,0,30);tbar.Position=UDim2.new(0,12,0,122)
tbar.BackgroundColor3=C.card;tbar.BorderSizePixel=0;corner(tbar,8)
newLabel(tbar,{Size=UDim2.new(0,56,1,0),Position=UDim2.new(0,10,0,0),
    Text="TARGET:",TextColor3=C.textDim,TextSize=9,Font=Enum.Font.GothamBold,
    TextXAlignment=Enum.TextXAlignment.Left})
local targetLbl=newLabel(tbar,{Size=UDim2.new(1,-70,1,0),Position=UDim2.new(0,66,0,0),
    Text="—",TextColor3=C.accentHi,TextSize=11,TextXAlignment=Enum.TextXAlignment.Left,
    TextTruncate=Enum.TextTruncate.AtEnd})

-- ── START / STOP ──────────────────────────────────────────────
local ctrlRow=Instance.new("Frame",main)
ctrlRow.Size=UDim2.new(1,-24,0,36);ctrlRow.Position=UDim2.new(0,12,0,158)
ctrlRow.BackgroundTransparency=1
local bw=math.floor((W-24-8)/2)
local startBtn=newBtn(ctrlRow,{Size=UDim2.new(0,bw,1,0),BackgroundColor3=C.green,
    Text="▶  START",TextColor3=Color3.new(1,1,1),TextSize=12});corner(startBtn,8)
hov(startBtn,C.green,Color3.fromRGB(60,230,115))
local stopBtn=newBtn(ctrlRow,{Size=UDim2.new(0,bw,1,0),Position=UDim2.new(0,bw+8,0,0),
    BackgroundColor3=C.red,BackgroundTransparency=0.55,
    Text="■  STOP",TextColor3=Color3.new(1,1,1),TextSize=12});corner(stopBtn,8)
hov(stopBtn,C.red,C.red,.55,.25)

-- ── Settings ─────────────────────────────────────────────────
newLabel(main,{Size=UDim2.new(1,-24,0,16),Position=UDim2.new(0,12,0,202),
    Text="⚙  SETTINGS",TextColor3=C.textDim,TextSize=9,Font=Enum.Font.GothamBold,
    TextXAlignment=Enum.TextXAlignment.Left})

local function mkSlider(yPos,label,minV,maxV,settingKey)
    local f=Instance.new("Frame",main)
    f.Size=UDim2.new(1,-24,0,30);f.Position=UDim2.new(0,12,0,yPos)
    f.BackgroundColor3=C.card;f.BorderSizePixel=0;corner(f,7)
    newLabel(f,{Size=UDim2.new(0.55,0,1,0),Position=UDim2.new(0,10,0,0),
        Text=label,TextColor3=C.textMain,TextSize=10,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left})
    local valD=newLabel(f,{Size=UDim2.new(0,38,1,0),Position=UDim2.new(1,-46,0,0),
        Text=tostring(SETTINGS[settingKey]),TextColor3=C.accent,TextSize=12})
    local track=Instance.new("Frame",f)
    track.Size=UDim2.new(0.28,0,0,4);track.Position=UDim2.new(0.55,0,0.5,-2)
    track.BackgroundColor3=C.bg;track.BorderSizePixel=0;corner(track,4)
    local fill=Instance.new("Frame",track);fill.BackgroundColor3=C.accent;fill.BorderSizePixel=0;corner(fill,4)
    local knob=Instance.new("Frame",track);knob.Size=UDim2.new(0,12,0,12)
    knob.BackgroundColor3=Color3.new(1,1,1);knob.BorderSizePixel=0;corner(knob,6)
    local function upd(rel)
        rel=math.clamp(rel,0,1)
        local v=math.floor(minV+rel*(maxV-minV))
        fill.Size=UDim2.new(rel,0,1,0);knob.Position=UDim2.new(rel,-6,0.5,-6)
        valD.Text=tostring(v);SETTINGS[settingKey]=v;saveConfig()
    end
    upd((SETTINGS[settingKey]-minV)/(maxV-minV))
    local sliding=false
    track.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then
            sliding=true;upd((i.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X) end
    end)
    knob.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then sliding=true end end)
    UserInputService.InputChanged:Connect(function(i)
        if sliding and i.UserInputType==Enum.UserInputType.MouseMovement then
            upd((i.Position.X-track.AbsolutePosition.X)/track.AbsoluteSize.X) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then sliding=false end end)
end

local function mkToggle(yPos,label,settingKey,onChange)
    local f=Instance.new("Frame",main)
    f.Size=UDim2.new(1,-24,0,30);f.Position=UDim2.new(0,12,0,yPos)
    f.BackgroundColor3=C.card;f.BorderSizePixel=0;corner(f,7)
    newLabel(f,{Size=UDim2.new(0.72,0,1,0),Position=UDim2.new(0,10,0,0),
        Text=label,TextColor3=C.textMain,TextSize=10,Font=Enum.Font.Gotham,
        TextXAlignment=Enum.TextXAlignment.Left})
    local sw=newBtn(f,{Size=UDim2.new(0,40,0,20),Position=UDim2.new(1,-48,0.5,-10),
        BackgroundColor3=SETTINGS[settingKey] and C.green or C.border,Text=""});corner(sw,10)
    local kn=Instance.new("Frame",sw);kn.Size=UDim2.new(0,16,0,16)
    kn.BackgroundColor3=Color3.new(1,1,1);kn.BorderSizePixel=0;corner(kn,8)
    kn.Position=SETTINGS[settingKey] and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)
    sw.MouseButton1Click:Connect(function()
        SETTINGS[settingKey]=not SETTINGS[settingKey];saveConfig()
        local on=SETTINGS[settingKey]
        tw(sw,.18,{BackgroundColor3=on and C.green or C.border})
        tw(kn,.18,{Position=on and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)})
        if onChange then onChange(on) end
    end)
end

mkSlider(220,"Collect Distance",2,12,"PROMPT_DISTANCE")
mkSlider(254,"Path Retries",    1,10,"PATH_RECOMPUTE_MAX")
mkSlider(288,"WalkSpeed Boost", 0,80,"WALK_SPEED_BOOST")
mkToggle(322,"Auto Equip Abyssal",    "AUTO_EQUIP_ABYSSAL")
mkToggle(356,"Show Notifications",    "SHOW_NOTIFICATIONS")
mkToggle(390,"Auto Respawn on Death", "AUTO_RESPAWN")

-- egg marker toggle — callback updates all existing markers
mkToggle(424,"Show Egg Markers on Map","SHOW_EGG_MARKERS",function(on)
    -- toggled — visibility update handled in marker system below
end)

-- ── Webhook section ───────────────────────────────────────────
newLabel(main,{Size=UDim2.new(1,-24,0,16),Position=UDim2.new(0,12,0,462),
    Text="🔔  WEBHOOK",TextColor3=C.textDim,TextSize=9,Font=Enum.Font.GothamBold,
    TextXAlignment=Enum.TextXAlignment.Left})

local wbox=Instance.new("Frame",main)
wbox.Size=UDim2.new(1,-24,0,30);wbox.Position=UDim2.new(0,12,0,480)
wbox.BackgroundColor3=C.card;wbox.BorderSizePixel=0;corner(wbox,7)
local wStroke=stroke(wbox,C.border,1,0.4)

local webhookInput=Instance.new("TextBox",wbox)
webhookInput.Size=UDim2.new(1,-12,1,0);webhookInput.Position=UDim2.new(0,8,0,0)
webhookInput.BackgroundTransparency=1;webhookInput.Font=Enum.Font.Code
webhookInput.TextSize=9;webhookInput.TextColor3=C.textMain
webhookInput.PlaceholderText="Paste Discord webhook URL here..."
webhookInput.PlaceholderColor3=C.textDim
webhookInput.TextXAlignment=Enum.TextXAlignment.Left
webhookInput.ClearTextOnFocus=false;webhookInput.Text=SETTINGS.WEBHOOK_URL
webhookInput.FocusLost:Connect(function() SETTINGS.WEBHOOK_URL=webhookInput.Text;saveConfig() end)
webhookInput.Focused:Connect(function()  wStroke.Color=C.accent;wStroke.Transparency=0 end)
webhookInput.FocusLost:Connect(function() wStroke.Color=C.border;wStroke.Transparency=0.4 end)

mkToggle(514,"Auto Webhook on Egg Detect","WEBHOOK_ENABLED")

-- ── Log ───────────────────────────────────────────────────────
local logHdr=Instance.new("Frame",main)
logHdr.Size=UDim2.new(1,-24,0,18);logHdr.Position=UDim2.new(0,12,0,550)
logHdr.BackgroundTransparency=1
newLabel(logHdr,{Size=UDim2.new(0.5,0,1,0),Text="📋  LOG",TextColor3=C.textDim,
    TextSize=9,Font=Enum.Font.GothamBold,TextXAlignment=Enum.TextXAlignment.Left})
local clearBtn=newBtn(logHdr,{Size=UDim2.new(0,52,0,16),Position=UDim2.new(1,-52,0.5,-8),
    BackgroundColor3=C.card,Text="CLEAR",TextColor3=C.textDim,TextSize=9});corner(clearBtn,4)
hov(clearBtn,C.card,C.cardHov)

local logScroll=Instance.new("ScrollingFrame",main)
logScroll.Size=UDim2.new(1,-24,0,68);logScroll.Position=UDim2.new(0,12,0,570)
logScroll.BackgroundColor3=C.logBg;logScroll.BorderSizePixel=0
logScroll.ScrollBarThickness=3;logScroll.ScrollBarImageColor3=C.accent
logScroll.CanvasSize=UDim2.new(0,0,0,0);logScroll.AutomaticCanvasSize=Enum.AutomaticSize.Y
corner(logScroll,6)
Instance.new("UIListLayout",logScroll).SortOrder=Enum.SortOrder.LayoutOrder
local lp=Instance.new("UIPadding",logScroll);lp.PaddingLeft=UDim.new(0,6);lp.PaddingTop=UDim.new(0,3)

local logOrder=0;local MAX_LINES=40
local lastLogMsg="";local lastLogCount=1;local lastLogLbl=nil

local function guiLog(msg,color)
    color=color or C.textDim
    if msg==lastLogMsg and lastLogLbl and lastLogLbl.Parent then
        lastLogCount+=1
        lastLogLbl.Text=os.date("%H:%M:%S").."  "..msg.."  ×"..lastLogCount
        task.defer(function() logScroll.CanvasPosition=Vector2.new(0,logScroll.AbsoluteCanvasSize.Y) end)
        return
    end
    lastLogMsg=msg;lastLogCount=1;logOrder+=1
    local lbl=Instance.new("TextLabel",logScroll)
    lbl.Size=UDim2.new(1,0,0,13);lbl.BackgroundTransparency=1
    lbl.Text=os.date("%H:%M:%S").."  "..msg
    lbl.TextColor3=color;lbl.TextSize=9;lbl.Font=Enum.Font.Code
    lbl.TextXAlignment=Enum.TextXAlignment.Left;lbl.TextTruncate=Enum.TextTruncate.AtEnd
    lbl.LayoutOrder=logOrder;lastLogLbl=lbl
    local kids={}
    for _,c in ipairs(logScroll:GetChildren()) do if c:IsA("TextLabel") then kids[#kids+1]=c end end
    table.sort(kids,function(a,b) return a.LayoutOrder<b.LayoutOrder end)
    while #kids>MAX_LINES do table.remove(kids,1):Destroy() end
    task.defer(function() logScroll.CanvasPosition=Vector2.new(0,logScroll.AbsoluteCanvasSize.Y) end)
end

clearBtn.MouseButton1Click:Connect(function()
    lastLogMsg="";lastLogLbl=nil;lastLogCount=1
    for _,c in ipairs(logScroll:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
    guiLog("Log cleared.",C.textDim)
end)

-- ── GUI updater ───────────────────────────────────────────────
local function updateGUI()
    valCollected.Text=tostring(STATE.eggsCollected)
    valFound.Text=tostring(STATE.eggsFound)
    if STATE.running then
        local s=math.floor(tick()-STATE.startTime)
        valTime.Text=s<60 and s.."s" or math.floor(s/60).."m"..(s%60).."s"
    else valTime.Text="0s" end
    targetLbl.Text=STATE.currentTarget
end

task.spawn(function()
    while gui.Parent do if STATE.running then updateGUI() end;task.wait(1) end
end)

-- ═══════════════════════════════════════════════════════════
--  EGG BILLBOARD MARKERS
-- ═══════════════════════════════════════════════════════════
-- tracks: eggInstance -> {billboard, spawnTick, timerLbl}
local markerRegistry = {}

local MARKER_COLORS = {
    point_egg          = Color3.fromRGB(80, 180, 255),
    random_potion_egg  = Color3.fromRGB(200, 80, 255),
}

local function getMarkerColor(name)
    if name:match("random_potion") then return MARKER_COLORS.random_potion_egg end
    return MARKER_COLORS.point_egg
end

local function getEggLabel(name)
    if name:match("random_potion") then return "🧪 Potion Egg" end
    if name:match("point_egg")     then return "✨ Point Egg"  end
    return "🥚 Egg"
end

local function createBillboard(eggInstance, anchorPart)
    if markerRegistry[eggInstance] then return end -- already exists

    local bb = Instance.new("BillboardGui")
    bb.Name        = "EggMarker"
    bb.Size        = UDim2.new(0, 110, 0, 52)
    bb.StudsOffset = Vector3.new(0, 5, 0)
    bb.AlwaysOnTop = true
    bb.Adornee     = anchorPart
    bb.Parent      = anchorPart
    bb.Enabled     = SETTINGS.SHOW_EGG_MARKERS

    -- background card
    local bg = Instance.new("Frame", bb)
    bg.Size              = UDim2.new(1,0,1,0)
    bg.BackgroundColor3  = Color3.fromRGB(10,10,18)
    bg.BackgroundTransparency = 0.25
    bg.BorderSizePixel   = 0
    corner(bg, 8)
    stroke(bg, getMarkerColor(eggInstance.Name), 1.5, 0)

    -- icon + name row
    local nameLbl = Instance.new("TextLabel", bg)
    nameLbl.Size               = UDim2.new(1,-6,0,22)
    nameLbl.Position           = UDim2.new(0,3,0,2)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text               = getEggLabel(eggInstance.Name)
    nameLbl.TextColor3         = getMarkerColor(eggInstance.Name)
    nameLbl.TextSize           = 12
    nameLbl.Font               = Enum.Font.GothamBold
    nameLbl.TextXAlignment     = Enum.TextXAlignment.Center

    -- timer label
    local timerLbl = Instance.new("TextLabel", bg)
    timerLbl.Size              = UDim2.new(1,-6,0,16)
    timerLbl.Position          = UDim2.new(0,3,0,26)
    timerLbl.BackgroundTransparency = 1
    timerLbl.Text              = "⏱ 0s"
    timerLbl.TextColor3        = Color3.fromRGB(180,180,200)
    timerLbl.TextSize          = 10
    timerLbl.Font              = Enum.Font.Gotham
    timerLbl.TextXAlignment    = Enum.TextXAlignment.Center

    markerRegistry[eggInstance] = {
        billboard  = bb,
        spawnTick  = tick(),
        timerLbl   = timerLbl,
        anchorPart = anchorPart,
    }
end

local function removeMarker(eggInstance)
    local entry = markerRegistry[eggInstance]
    if entry then
        pcall(function() entry.billboard:Destroy() end)
        markerRegistry[eggInstance] = nil
    end
end

local function removeAllMarkers()
    for inst,_ in pairs(markerRegistry) do removeMarker(inst) end
end

-- update timer labels every second
task.spawn(function()
    while gui.Parent do
        local now = tick()
        for eggInst, entry in pairs(markerRegistry) do
            if not eggInst or not eggInst.Parent then
                removeMarker(eggInst)
            else
                -- update visibility
                entry.billboard.Enabled = SETTINGS.SHOW_EGG_MARKERS
                -- update timer
                local secs = math.floor(now - entry.spawnTick)
                local timeStr
                if secs < 60 then timeStr = secs.."s"
                else timeStr = math.floor(secs/60).."m "..(secs%60).."s" end
                entry.timerLbl.Text = "⏱ "..timeStr
            end
        end
        task.wait(1)
    end
end)

-- ── Watch workspace for new eggs spawning ────────────────────
local function isEggName(n)
    for _,p in ipairs(EGG_PATTERNS) do if string.match(n,p) then return true end end
    return false
end

local function getAnchor(obj)
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then return obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart",true) end
    return nil
end

local function inExcluded(pos)
    for _,z in ipairs(EXCLUDED_ZONES) do
        if(pos-z.center).Magnitude<=z.radius then return true end
    end
    return false
end

local function onNewEgg(obj)
    if ignoredEggs[obj] then return end
    local anchor=getAnchor(obj)
    if not anchor then return end
    if anchor.Position.Y>SETTINGS.MAX_EGG_HEIGHT then return end
    if inExcluded(anchor.Position) then return end

    createBillboard(obj, anchor)
    guiLog("🥚 Egg appeared: "..obj.Name, C.yellow)

    -- webhook on detect (workspace, not chat)
    if SETTINGS.WEBHOOK_ENABLED then
        task.spawn(function() sendWebhook(obj.Name,"workspace detect") end)
    end
end

-- scan existing eggs on load
task.spawn(function()
    task.wait(1)
    for _,obj in ipairs(workspace:GetDescendants()) do
        if isEggName(obj.Name) then onNewEgg(obj) end
    end
end)

-- watch for new ones
workspace.DescendantAdded:Connect(function(obj)
    if isEggName(obj.Name) then
        task.wait(0.1) -- wait a frame for PrimaryPart to be set on Models
        onNewEgg(obj)
    end
end)

-- watch for removed eggs (game removed them = expired/collected by server)
workspace.DescendantRemoving:Connect(function(obj)
    if markerRegistry[obj] then
        removeMarker(obj)
    end
end)

-- ═══════════════════════════════════════════════════════════
--  WEBHOOK
-- ═══════════════════════════════════════════════════════════
local webhookCooldown={}

function sendWebhook(eggName, source)
    if not SETTINGS.WEBHOOK_ENABLED then return end
    local url=SETTINGS.WEBHOOK_URL
    if url=="" or not url:match("^https://discord%.com/api/webhooks/") then
        guiLog("⚠ Invalid webhook URL",C.orange); return
    end
    local key=eggName..(source or "")
    if webhookCooldown[key] and tick()-webhookCooldown[key]<10 then return end
    webhookCooldown[key]=tick()

    local body=HttpService:JSONEncode({
        username="Sols Egg Farm",
        content="@everyone",
        embeds={{
            color=0x6C3AFF,
            title="🥚 Egg Detected!",
            fields={
                {name="Egg",     value="`"..eggName.."`",     inline=true},
                {name="Source",  value=source or "scan",       inline=true},
                {name="Player",  value=player.Name,            inline=true},
                {name="Collected",value=tostring(STATE.eggsCollected), inline=true},
                {name="Server",  value=game.JobId~="" and game.JobId:sub(1,18).."…" or "private", inline=false},
            },
            footer={text="Sols RNG Egg Farm v3.2  •  "..os.date("%H:%M:%S")},
            color=0x6C3AFF,
        }}
    })

    pcall(function()
        HttpService:RequestAsync({
            Url    = url,
            Method = "POST",
            Headers= {["Content-Type"]="application/json"},
            Body   = body,
        })
    end)
    guiLog("📨 Webhook sent: "..eggName,C.cyan)
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
    local eggs={}
    for _,obj in ipairs(workspace:GetDescendants()) do
        if isEggName(obj.Name) and not ignoredEggs[obj] then
            local part=getAnchor(obj)
            if part and part.Position.Y<=SETTINGS.MAX_EGG_HEIGHT and not inExcluded(part.Position) then
                eggs[#eggs+1]={
                    instance=obj,part=part,position=part.Position,
                    prompt=obj:FindFirstChildWhichIsA("ProximityPrompt",true),
                    name=obj.Name,priority=getEggPriority(obj.Name)
                }
            end
        end
    end
    table.sort(eggs,function(a,b)
        if a.priority~=b.priority then return a.priority<b.priority end
        return dist(a.position)<dist(b.position)
    end)
    STATE.eggsFound=#eggs
    return eggs
end

local function firePrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    if fireproximityprompt then fireproximityprompt(prompt);return true end
    local oh,od=prompt.HoldDuration,prompt.MaxActivationDistance
    prompt.MaxActivationDistance=9999;prompt.HoldDuration=0
    prompt:InputHoldBegin();task.wait(0.1);prompt:InputHoldEnd()
    prompt.HoldDuration=oh;prompt.MaxActivationDistance=od
    return true
end

local function collectEgg(egg)
    local prompt=egg.prompt or egg.instance:FindFirstChildWhichIsA("ProximityPrompt",true)
    if prompt then firePrompt(prompt)
    else
        if VirtualInputManager then
            VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.E,false,game)
            task.wait(0.15)
            VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.E,false,game)
        end
    end
    task.wait(0.35)
    -- remove billboard as soon as we collect it
    removeMarker(egg.instance)

    STATE.eggsCollected+=1
    guiLog("✓ "..egg.name,C.green)
    pulse(valCollected,C.green)
    updateGUI()
end

-- ── SimplePath ────────────────────────────────────────────────
local SimplePath
pcall(function()
    SimplePath=loadstring(game:HttpGet(
        "https://raw.githubusercontent.com/grayzcale/simplepath/main/src/SimplePath.lua"
    ))()
end)

local pathAgent=nil
local function initPath()
    if pathAgent then pcall(function() pathAgent:Destroy() end) end
    if not SimplePath or not character then return end
    pathAgent=SimplePath.new(character,{
        AgentRadius=3,AgentHeight=5.5,AgentCanJump=true,AgentCanClimb=true,
        AgentJumpHeight=7.2,WaypointSpacing=3,Costs={Water=100,Climb=1},
    })
end
if character then initPath() end
player.CharacterAdded:Connect(function() task.wait(1);initPath() end)

local function walkToEgg(egg)
    STATE.currentEggInstance=egg.instance
    if not rootPart or not egg.part or not egg.part.Parent then return false end
    if not pathAgent then guiLog("❌ SimplePath missing!",C.red);return false end

    guiLog("→ "..egg.name,C.accentHi)
    local baseSpeed=16
    if SETTINGS.WALK_SPEED_BOOST>0 and humanoid then
        humanoid.WalkSpeed=baseSpeed+SETTINGS.WALK_SPEED_BOOST
    end

    local done,errors=false,0
    local maxErr=SETTINGS.PATH_RECOMPUTE_MAX*3
    local conR,conB,conE,conW

    local function cleanup()
        for _,c in ipairs({conR,conB,conE,conW}) do if c then c:Disconnect() end end
        pcall(function() pathAgent:Stop() end)
        if humanoid then humanoid.WalkSpeed=baseSpeed end
    end

    conR=pathAgent.Reached:Connect(function() done=true end)
    conB=pathAgent.Blocked:Connect(function() pcall(function() pathAgent:Run(egg.part.Position) end) end)
    conE=pathAgent.Error:Connect(function()
        errors+=1;if humanoid then humanoid.Jump=true end;task.wait(0.2)
        pcall(function() pathAgent:Run(egg.part.Position) end)
    end)
    conW=pathAgent.WaypointReached:Connect(function()
        local d=dist(egg.part.Position)
        if d<=SETTINGS.PROMPT_DISTANCE then done=true end
        STATE.currentTarget=egg.name..string.format(" (%.0fm)",d)
        targetLbl.Text=STATE.currentTarget
    end)

    pcall(function() pathAgent:Run(egg.part.Position) end)
    local lastP=rootPart.Position;local stuck=0

    while STATE.running and not done do
        if not egg.part or not egg.part.Parent then guiLog("⚠ Gone: "..egg.name,C.orange);break end
        if dist(egg.part.Position)<=SETTINGS.PROMPT_DISTANCE then done=true;break end
        if errors>maxErr then guiLog("⚠ Too many errors",C.orange);break end
        local cur=rootPart.Position
        if(cur-lastP).Magnitude<0.2 then
            stuck+=0.1
            if stuck>1.5 then
                if humanoid then
                    humanoid.Jump=true
                    humanoid:MoveTo(cur+rootPart.CFrame.RightVector*math.random(-5,5))
                end
                errors+=1;task.wait(0.4)
                pcall(function() pathAgent:Run(egg.part.Position) end)
                stuck=0
            end
        else stuck=0 end
        lastP=cur;task.wait(0.1)
    end

    cleanup()
    if not STATE.running then return false end
    if done or(egg.part and egg.part.Parent and dist(egg.part.Position)<=SETTINGS.PROMPT_DISTANCE) then
        collectEgg(egg);return true
    end
    guiLog("✗ Failed: "..egg.name,C.red)
    STATE.failedAttempts+=1
    return false
end

-- ── Map fix ───────────────────────────────────────────────────
local mapFixed=false
local function fixMap()
    if mapFixed then return end;mapFixed=true
    local lg=workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("leafygrass")
    if not lg then return end
    guiLog("🛠 Patching geometry...",C.textDim)
    for _,obj in ipairs(lg:GetDescendants()) do
        if obj:IsA("BasePart") and obj.Name~="PathBlocker" then
            local b=Instance.new("Part")
            b.Name="PathBlocker";b.Size=Vector3.new(obj.Size.X,25,obj.Size.Z)
            b.CFrame=obj.CFrame*CFrame.new(0,-(obj.Size.Y/2+12.5),0)
            b.Anchored=true;b.CanCollide=true;b.Transparency=1;b.Parent=obj
        end
    end
end

-- ── Auto Equip Abyssal ────────────────────────────────────────
local function autoEquipAbyssal()
    local PG=player:WaitForChild("PlayerGui");local GS=game:GetService("GuiService")
    local function click(t) pcall(function()
        GS.SelectedObject=t;task.wait()
        VirtualInputManager:SendKeyEvent(true,Enum.KeyCode.Return,false,game);task.wait()
        VirtualInputManager:SendKeyEvent(false,Enum.KeyCode.Return,false,game);GS.SelectedObject=nil
    end) end
    local function openBag()
        local sb=PG:FindFirstChild("MainInterface") and PG.MainInterface:FindFirstChild("SideButtons")
        if not sb then return end
        local btns={}
        for _,b in ipairs(sb:GetChildren()) do if b:IsA("TextButton") then btns[#btns+1]=b end end
        table.sort(btns,function(a,b) return a.AbsolutePosition.Y<b.AbsolutePosition.Y end)
        if btns[1] then click(btns[1]);task.wait(0.1) end
    end
    guiLog("🎒 Equipping Abyssal...",C.accent);openBag()
    local hit=false
    for _,o in ipairs(PG:GetDescendants()) do
        if(o:IsA("TextLabel") or o:IsA("TextButton")) and string.match(string.lower(o.Text),"abyssal") then
            if o.AbsoluteSize.X>0 then
                local btn=o:FindFirstAncestorWhichIsA("GuiButton")
                if btn then click(btn);hit=true;break end
            end
        end
    end
    if not hit then guiLog("⚠ Abyssal not found",C.orange);openBag();return end
    task.wait(0.1)
    for _,o in ipairs(PG:GetDescendants()) do
        if o:IsA("ImageButton") and o:GetFullName():match("MainInterface%.Frame%.Frame%.Frame%.Frame%.ImageButton%.ImageButton$") then
            click(o);guiLog("✅ Aura equipped",C.green);break
        end
    end
    openBag()
end

-- ── Auto Respawn ──────────────────────────────────────────────
local function watchDeath()
    if not humanoid then return end
    humanoid.Died:Connect(function()
        if not STATE.running or not SETTINGS.AUTO_RESPAWN then return end
        guiLog("💀 Died — respawning...",C.orange);task.wait(3);player:LoadCharacter()
    end)
end
watchDeath()
player.CharacterAdded:Connect(function() task.wait(1);watchDeath() end)

local function notify(title,body,dur)
    if not SETTINGS.SHOW_NOTIFICATIONS then return end
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification",{Title=title,Text=body,Duration=dur or 4})
    end)
end

-- ── Main loop ─────────────────────────────────────────────────
local function mainLoop()
    fixMap()
    STATE.startTime=tick();STATE.eggsCollected=0;STATE.failedAttempts=0
    guiLog("▶ Farming started!",C.green)
    notify("Egg Farm","Farming started!",3)
    updateGUI()

    while STATE.running do
        if SETTINGS.AUTO_EQUIP_ABYSSAL then
            if rootPart and rootPart.Parent then autoEquipAbyssal() end
            task.wait(0.5)
        end
        local eggs=findAllEggs();updateGUI()
        if #eggs==0 then
            STATE.currentTarget="Scanning...";targetLbl.Text=STATE.currentTarget
            guiLog("No eggs — scanning...",C.textDim)
            task.wait(SETTINGS.SEARCH_INTERVAL)
        else
            guiLog("Found "..(#eggs).." egg(s)",C.accent)
            for _,egg in ipairs(eggs) do
                if not STATE.running then break end
                if egg.part and egg.part.Parent then
                    walkToEgg(egg);task.wait(0.3)
                end
            end
            task.wait(SETTINGS.SEARCH_INTERVAL)
        end
    end

    STATE.currentTarget="—";targetLbl.Text="—"
    updateGUI()
    guiLog("⏸ Stopped. Collected: "..STATE.eggsCollected,C.orange)
    notify("Egg Farm","Stopped. Collected: "..STATE.eggsCollected,5)
end

-- ── Buttons ───────────────────────────────────────────────────
startBtn.MouseButton1Click:Connect(function()
    if STATE.running then return end
    STATE.running=true
    tw(startBtn,.1,{BackgroundTransparency=0.5})
    task.delay(.15,function() tw(startBtn,.1,{BackgroundTransparency=0}) end)
    task.spawn(mainLoop)
end)

stopBtn.MouseButton1Click:Connect(function()
    if not STATE.running then return end
    STATE.running=false
    tw(stopBtn,.1,{BackgroundTransparency=0})
    task.delay(.15,function() tw(stopBtn,.1,{BackgroundTransparency=0.55}) end)
    updateGUI()
end)

-- ─── Ready ────────────────────────────────────────────────────
guiLog("Ready — press START.",C.accent)
updateGUI()
