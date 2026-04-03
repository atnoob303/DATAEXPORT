-- WorkspaceExplorer v4.0
-- LocalScript trong StarterGui
-- Lazy-load, Smart Pagination, Comment toggle, Refresh, Dupe check

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

-- ==================== DUPE CHECK ====================
if player.PlayerGui:FindFirstChild("WorkspaceExplorer") then
	warn("[WorkspaceExplorer] GUI đã tồn tại, bỏ qua load!")
	return
end

-- ==================== SERIALIZE ====================

local function serializeValue(val)
	local t=typeof(val)
	if t=="Vector3" then return{_t="Vector3",x=val.X,y=val.Y,z=val.Z}
	elseif t=="Vector2" then return{_t="Vector2",x=val.X,y=val.Y}
	elseif t=="Color3" then return{_t="Color3",r=math.floor(val.R*255),g=math.floor(val.G*255),b=math.floor(val.B*255)}
	elseif t=="BrickColor" then return{_t="BrickColor",name=tostring(val)}
	elseif t=="UDim2" then return{_t="UDim2",xs=val.X.Scale,xo=val.X.Offset,ys=val.Y.Scale,yo=val.Y.Offset}
	elseif t=="UDim" then return{_t="UDim",s=val.Scale,o=val.Offset}
	elseif t=="CFrame" then
		local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22=val:GetComponents()
		return{_t="CFrame",x=x,y=y,z=z,r00=r00,r01=r01,r02=r02,r10=r10,r11=r11,r12=r12,r20=r20,r21=r21,r22=r22}
	elseif t=="NumberRange" then return{_t="NumberRange",min=val.Min,max=val.Max}
	elseif t=="NumberSequence" then
		local kps={}
		for _,kp in ipairs(val.Keypoints) do table.insert(kps,{t=kp.Time,v=kp.Value,e=kp.Envelope}) end
		return{_t="NumberSequence",keypoints=kps}
	elseif t=="ColorSequence" then
		local kps={}
		for _,kp in ipairs(val.Keypoints) do table.insert(kps,{t=kp.Time,r=math.floor(kp.Value.R*255),g=math.floor(kp.Value.G*255),b=math.floor(kp.Value.B*255)}) end
		return{_t="ColorSequence",keypoints=kps}
	elseif t=="EnumItem" then return{_t="Enum",name=tostring(val)}
	elseif t=="boolean" then return val
	elseif t=="number" then return math.floor(val*10000)/10000
	elseif t=="string" then return val
	else return tostring(val) end
end

local PROPS={
	BasePart={"Size","Position","CFrame","Color","BrickColor","Material","Transparency","Reflectance","Anchored","CanCollide","CanTouch","CastShadow","Locked","Massless","RootPriority"},
	Part={"Shape"},MeshPart={"MeshId","TextureID","MeshSize"},
	SpecialMesh={"MeshId","TextureId","MeshType","Scale","Offset","VertexColor"},
	UnionOperation={"UsePartColor"},CornerWedgePart={},WedgePart={},TrussPart={"Style"},
	Texture={"Texture","Color3","Transparency","StudsPerTileU","StudsPerTileV","OffsetStudsU","OffsetStudsV","Face"},
	Decal={"Texture","Color3","Transparency","Face","ZIndex"},
	ParticleEmitter={"Texture","Color","Size","Transparency","LightEmission","LightInfluence","Speed","SpreadAngle","Rate","Lifetime","Rotation","RotSpeed","Acceleration","Drag","LockedToPart","EmissionDirection","ZOffset"},
	Beam={"Attachment0","Attachment1","Color","Transparency","Width0","Width1","FaceCamera","LightEmission","Texture","TextureLength","TextureMode","TextureSpeed","Segments","CurveSize0","CurveSize1","ZOffset"},
	Trail={"Attachment0","Attachment1","Color","Transparency","WidthScale","LightEmission","Texture","TextureLength","TextureMode","Lifetime","MinLength","FaceCamera"},
	Smoke={"Color","Opacity","RiseVelocity","Size","Enabled"},Fire={"Color","SecondaryColor","Heat","Size","Enabled"},Sparkles={"SparkleColor","Enabled"},
	PointLight={"Brightness","Color","Range","Enabled","Shadows"},SpotLight={"Brightness","Color","Range","Angle","Face","Enabled","Shadows"},SurfaceLight={"Brightness","Color","Range","Angle","Face","Enabled","Shadows"},
	Sound={"SoundId","Volume","PlaybackSpeed","Looped","Playing","RollOffMaxDistance","RollOffMinDistance","RollOffMode","SpatialSound"},
	WeldConstraint={"Part0","Part1","Enabled"},Motor6D={"Part0","Part1","C0","C1","CurrentAngle","MaxVelocity"},
	HingeConstraint={"Attachment0","Attachment1","ActuatorType","AngularSpeed","MotorMaxTorque","TargetAngle","LowerAngle","UpperAngle","LimitsEnabled"},
	RodConstraint={"Attachment0","Attachment1","Length","LimitAngle0","LimitAngle1","LimitsEnabled"},
	SpringConstraint={"Attachment0","Attachment1","Coils","Damping","FreeLength","LimitsEnabled","MaxLength","MinLength","Radius","Stiffness","Thickness"},
	BodyVelocity={"Velocity","MaxForce","P"},BodyPosition={"Position","MaxForce","P","D"},BodyAngularVelocity={"AngularVelocity","MaxTorque","P"},BodyGyro={"CFrame","MaxTorque","P","D"},
	ScreenGui={"Enabled","DisplayOrder","IgnoreGuiInset","ResetOnSpawn","ZIndexBehavior"},
	Frame={"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency","BorderColor3","BorderSizePixel","ClipsDescendants","Visible","ZIndex","LayoutOrder","Rotation"},
	TextLabel={"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency","BorderColor3","Visible","ZIndex","LayoutOrder","Rotation","Text","TextColor3","TextTransparency","TextSize","Font","FontFace","TextWrapped","TextScaled","TextXAlignment","TextYAlignment","RichText","LineHeight"},
	TextButton={"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency","BorderColor3","Visible","ZIndex","LayoutOrder","Rotation","AutoButtonColor","Text","TextColor3","TextTransparency","TextSize","Font","FontFace","TextWrapped","TextScaled","TextXAlignment","TextYAlignment","RichText","Modal","Selected"},
	TextBox={"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency","Visible","ZIndex","LayoutOrder","Text","PlaceholderText","PlaceholderColor3","TextColor3","TextSize","Font","ClearTextOnFocus","MultiLine","TextEditable"},
	ImageLabel={"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency","Visible","ZIndex","LayoutOrder","Rotation","Image","ImageColor3","ImageTransparency","ScaleType","SliceCenter","TileSize","ImageRectOffset","ImageRectSize"},
	ImageButton={"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency","Visible","ZIndex","LayoutOrder","Rotation","AutoButtonColor","Image","ImageColor3","ImageTransparency","ScaleType","HoverImage","PressedImage"},
	ScrollingFrame={"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency","Visible","ZIndex","CanvasSize","CanvasPosition","ScrollBarThickness","ScrollBarImageColor3","ScrollingDirection","AutomaticCanvasSize","ElasticBehavior"},
	UICorner={"CornerRadius"},UIStroke={"Color","Thickness","Transparency","LineJoinMode","ApplyStrokeMode"},UIGradient={"Color","Transparency","Offset","Rotation"},
	UIPadding={"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"},
	UIListLayout={"FillDirection","HorizontalAlignment","VerticalAlignment","SortOrder","Padding","Wraps"},
	UIGridLayout={"CellSize","CellPadding","FillDirection","HorizontalAlignment","VerticalAlignment","SortOrder","StartCorner"},
	UISizeConstraint={"MaxSize","MinSize"},UIAspectRatioConstraint={"AspectRatio","AspectType","DominantAxis"},UIScale={"Scale"},
	Model={"PrimaryPart","LevelOfDetail"},SpawnLocation={"Duration","Enabled","Neutral","TeamColor","AllowTeamChangeOnTouch"},
	Humanoid={"MaxHealth","Health","WalkSpeed","JumpHeight","JumpPower","HipHeight","AutoRotate","AutoJumpEnabled","DisplayDistanceType","HealthDisplayType"},
	HumanoidDescription={"HatAccessory","HairAccessory","FaceAccessory","NeckAccessory","ShouldersAccessory","FrontAccessory","BackAccessory","WaistAccessory","Face","Head","Torso","RightArm","LeftArm","RightLeg","LeftLeg","BodyTypeScale","HeadScale","HeightScale","ProportionScale","WidthScale"},
	Attachment={"Position","Orientation","CFrame","WorldPosition","WorldCFrame","Visible"},
	BillboardGui={"Adornee","Active","AlwaysOnTop","ClipsDescendants","Enabled","Size","SizeOffset","StudsOffset","ExtentsOffset","LightInfluence","MaxDistance"},
	SurfaceGui={"Adornee","Active","AlwaysOnTop","ClipsDescendants","Enabled","Face","PixelsPerStud","SizingMode","ZOffset","LightInfluence","MaxDistance"},
	SelectionBox={"Adornee","Color3","LineThickness","SurfaceColor3","SurfaceTransparency","Visible"},
	SelectionSphere={"Adornee","Color3","SurfaceColor3","SurfaceTransparency","Visible"},
	ClickDetector={"MaxActivationDistance","CursorIcon"},
	ProximityPrompt={"ActionText","ObjectText","HoldDuration","MaxActivationDistance","RequiresLineOfSight","Style","UIOffset","KeyboardKeyCode","GamepadKeyCode","Enabled"},
	IntValue={"Value"},NumberValue={"Value"},StringValue={"Value"},BoolValue={"Value"},Vector3Value={"Value"},CFrameValue={"Value"},Color3Value={"Value"},ObjectValue={"Value"},
	Sky={"SkyboxBk","SkyboxDn","SkyboxFt","SkyboxLf","SkyboxRt","SkyboxUp","MoonAngularSize","SunAngularSize","MoonTextureId","SunTextureId","StarCount"},
	Atmosphere={"Density","Offset","Color","Decay","Glare","Haze"},Animation={"AnimationId"},
}

local BASE_PART_CLASSES={"Part","MeshPart","UnionOperation","CornerWedgePart","WedgePart","TrussPart","SpawnLocation","FlagStand"}
for _,cls in ipairs(BASE_PART_CLASSES) do
	if not PROPS[cls] then PROPS[cls]={} end
	for _,p in ipairs(PROPS.BasePart) do table.insert(PROPS[cls],p) end
end

local function getProps(inst)
	local result,seen,list={},{},{}
	local function add(cls)
		if PROPS[cls] then for _,p in ipairs(PROPS[cls]) do if not seen[p] then seen[p]=true;table.insert(list,p) end end end
	end
	add(inst.ClassName);add("BasePart")
	for _,prop in ipairs(list) do
		local ok,val=pcall(function() return inst[prop] end)
		if ok and val~=nil then local s=serializeValue(val);if s~=nil then result[prop]=s end end
	end
	return result
end

local function serialize(inst,withChildren)
	local data={ClassName=inst.ClassName,Name=inst.Name,Properties=getProps(inst),Children={}}
	if withChildren then
		for _,child in ipairs(inst:GetChildren()) do table.insert(data.Children,serialize(child,true)) end
	end
	return data
end

-- ==================== LUA CODE GEN ====================

local function valToLua(val)
	if type(val)=="table" then
		local t=val._t
		if t=="Vector3" then return string.format("Vector3.new(%g,%g,%g)",val.x,val.y,val.z)
		elseif t=="Vector2" then return string.format("Vector2.new(%g,%g)",val.x,val.y)
		elseif t=="Color3" then return string.format("Color3.fromRGB(%d,%d,%d)",val.r,val.g,val.b)
		elseif t=="BrickColor" then return string.format('BrickColor.new("%s")',val.name)
		elseif t=="UDim2" then return string.format("UDim2.new(%g,%g,%g,%g)",val.xs,val.xo,val.ys,val.yo)
		elseif t=="UDim" then return string.format("UDim.new(%g,%g)",val.s,val.o)
		elseif t=="CFrame" then return string.format("CFrame.new(%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g)",val.x,val.y,val.z,val.r00,val.r01,val.r02,val.r10,val.r11,val.r12,val.r20,val.r21,val.r22)
		elseif t=="NumberRange" then return string.format("NumberRange.new(%g,%g)",val.min,val.max)
		elseif t=="NumberSequence" then
			local kps={}
			for _,kp in ipairs(val.keypoints) do table.insert(kps,string.format("NumberSequenceKeypoint.new(%g,%g,%g)",kp.t,kp.v,kp.e)) end
			return "NumberSequence.new({"..table.concat(kps,",").."})"
		elseif t=="ColorSequence" then
			local kps={}
			for _,kp in ipairs(val.keypoints) do table.insert(kps,string.format("ColorSequenceKeypoint.new(%g,Color3.fromRGB(%d,%d,%d))",kp.t,kp.r,kp.g,kp.b)) end
			return "ColorSequence.new({"..table.concat(kps,",").."})"
		elseif t=="Enum" then return val.name end
		return "nil"
	elseif type(val)=="boolean" then return tostring(val)
	elseif type(val)=="number" then return tostring(val)
	elseif type(val)=="string" then return string.format('"%s"',val:gsub('"','\\"')) end
	return "nil"
end

-- Sinh lines lua cho 1 object (đệ quy, trả về table of strings)
local function genLuaLines(data,parentVar,depth,showComments)
	local ind=string.rep("    ",depth)
	local varName=data.Name:gsub("[^%w]","_").."_"..depth
	local lines={}
	if showComments then table.insert(lines,ind.."-- "..data.ClassName..": "..data.Name) end
	table.insert(lines,ind..string.format('local %s = Instance.new("%s")',varName,data.ClassName))
	for prop,val in pairs(data.Properties or {}) do
		local lua=valToLua(val)
		if lua~="nil" then table.insert(lines,ind..string.format('%s.%s = %s',varName,prop,lua)) end
	end
	table.insert(lines,ind..string.format('%s.Name = "%s"',varName,data.Name))
	table.insert(lines,ind..string.format('%s.Parent = %s',varName,parentVar))
	for _,child in ipairs(data.Children or {}) do
		table.insert(lines,"")
		for _,l in ipairs(genLuaLines(child,varName,depth+1,showComments)) do table.insert(lines,l) end
	end
	return lines
end

-- ==================== SMART PAGINATION ====================
--[[
  Logic:
  - Mỗi "segment" = 1 top-level child object hoàn chỉnh (không bị cắt ngang)
  - Gom các segments thành pages theo maxLines
  - Nếu 1 segment đơn lẻ đã vượt maxLines → nó tự thành 1 trang riêng (không cắt)
  - Trang 0 = header + khai báo parent object (không children)
]]

local function buildSegments(data,showComments)
	local segments={}
	local varName=data.Name:gsub("[^%w]","_").."_0"

	-- Segment 0: header + khai báo parent (không children)
	local seg0Lines={}
	if showComments then
		table.insert(seg0Lines,"-- Generated by WorkspaceExplorer v4.0")
		table.insert(seg0Lines,string.format("-- Object: %s [%s]",data.Name,data.ClassName))
		table.insert(seg0Lines,"")
	end
	local parentOnly={ClassName=data.ClassName,Name=data.Name,Properties=data.Properties,Children={}}
	for _,l in ipairs(genLuaLines(parentOnly,"workspace",0,showComments)) do table.insert(seg0Lines,l) end
	table.insert(segments,{lines=seg0Lines,label="[Init] "..data.Name})

	-- Segment per child
	for _,child in ipairs(data.Children or {}) do
		local childLines={}
		table.insert(childLines,"")
		for _,l in ipairs(genLuaLines(child,varName,1,showComments)) do table.insert(childLines,l) end
		table.insert(segments,{lines=childLines,label=child.Name.." ["..child.ClassName.."]"})
	end

	-- Nếu không có children → chỉ 1 segment tổng
	if #data.Children==0 then
		segments={}
		local allLines={}
		if showComments then
			table.insert(allLines,"-- Generated by WorkspaceExplorer v4.0")
			table.insert(allLines,string.format("-- Object: %s [%s]",data.Name,data.ClassName))
			table.insert(allLines,"")
		end
		for _,l in ipairs(genLuaLines(data,"workspace",0,showComments)) do table.insert(allLines,l) end
		table.insert(segments,{lines=allLines,label=data.Name})
	end

	return segments
end

-- Gom segments thành pages (không cắt ngang segment)
local function buildPages(segments,maxLines)
	if #segments==0 then return {} end
	local pages={}
	local cur={lines={},labels={},segCount=0}

	for _,seg in ipairs(segments) do
		local sLen=#seg.lines
		-- Nếu trang hiện tại có nội dung VÀ thêm segment này vượt maxLines → flush trang
		if cur.segCount>0 and (#cur.lines+sLen)>maxLines then
			table.insert(pages,cur)
			cur={lines={},labels={},segCount=0}
		end
		for _,l in ipairs(seg.lines) do table.insert(cur.lines,l) end
		table.insert(cur.labels,seg.label)
		cur.segCount=cur.segCount+1
	end
	if cur.segCount>0 then table.insert(pages,cur) end
	return pages
end

-- ==================== JSON ====================

local function jsonEncode(val,depth)
	depth=depth or 0
	local ind=string.rep("  ",depth)
	local t=type(val)
	if t=="boolean" then return tostring(val)
	elseif t=="number" then return tostring(val)
	elseif t=="string" then return'"'..val:gsub('"','\\"'):gsub("\n","\\n")..'"'
	elseif t=="table" then
		if #val>0 then
			local items={}
			for _,v in ipairs(val) do table.insert(items,ind.."  "..jsonEncode(v,depth+1)) end
			return"[\n"..table.concat(items,",\n").."\n"..ind.."]"
		else
			local items={}
			for k,v in pairs(val) do table.insert(items,ind..'  "'..tostring(k)..'": '..jsonEncode(v,depth+1)) end
			return"{\n"..table.concat(items,",\n").."\n"..ind.."}"
		end
	end
	return"null"
end

-- ==================== UI HELPERS ====================

local function mkCorner(p,r) local c=Instance.new("UICorner",p);c.CornerRadius=UDim.new(0,r or 8);return c end

local function mkFrame(parent,size,pos,color,alpha)
	local f=Instance.new("Frame",parent)
	f.Size=size;f.Position=pos or UDim2.new(0,0,0,0)
	f.BackgroundColor3=color or Color3.fromRGB(15,15,26)
	f.BackgroundTransparency=alpha or 0;f.BorderSizePixel=0
	return f
end

local function mkBtn(parent,size,pos,bg,tc,txt,fsize)
	local b=Instance.new("TextButton",parent)
	b.Size=size;b.Position=pos;b.BackgroundColor3=bg
	b.TextColor3=tc;b.Text=txt;b.Font=Enum.Font.Code
	b.TextSize=fsize or 10;b.BorderSizePixel=0;b.AutoButtonColor=false
	mkCorner(b,5);return b
end

local function mkLabel(parent,size,pos,txt,color,fsize,align)
	local l=Instance.new("TextLabel",parent)
	l.Size=size;l.Position=pos;l.BackgroundTransparency=1
	l.Text=txt;l.TextColor3=color;l.TextSize=fsize or 11
	l.Font=Enum.Font.Code;l.TextXAlignment=align or Enum.TextXAlignment.Left
	return l
end

-- ==================== COLORS ====================

local CLR={
	bg=Color3.fromRGB(13,13,24),
	header=Color3.fromRGB(20,30,58),
	accent=Color3.fromRGB(0,212,255),
	accentDim=Color3.fromRGB(30,50,80),
	select=Color3.fromRGB(0,45,75),
	text=Color3.fromRGB(190,200,220),
	dim=Color3.fromRGB(80,80,120),
	green=Color3.fromRGB(16,185,129),
	dark=Color3.fromRGB(16,16,30),
	pageBg=Color3.fromRGB(25,25,45),
	pageActive=Color3.fromRGB(0,140,200),
	allActive=Color3.fromRGB(16,185,129),
}

-- ==================== GUI ====================

local gui=Instance.new("ScreenGui")
gui.Name="WorkspaceExplorer"
gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
gui.Parent=player.PlayerGui

-- ===== TREE PANEL =====
local mainFrame=mkFrame(gui,UDim2.new(0,265,0,460),UDim2.new(0,10,0,10),CLR.bg)
mkCorner(mainFrame)

local treeHeader=mkFrame(mainFrame,UDim2.new(1,0,0,34),nil,CLR.header)
mkCorner(treeHeader);treeHeader.ZIndex=2
mkLabel(treeHeader,UDim2.new(0,90,1,0),UDim2.new(0,8,0,0),"⬡ WORKSPACE",CLR.accent,11).ZIndex=3

local refreshBtn=mkBtn(treeHeader,UDim2.new(0,28,0,22),UDim2.new(1,-128,0.5,-11),CLR.accentDim,CLR.accent,"↺",13)
refreshBtn.ZIndex=3
local toggleBtn=mkBtn(treeHeader,UDim2.new(0,66,0,22),UDim2.new(1,-66,0.5,-11),CLR.accentDim,CLR.accent,"{ } View",10)
toggleBtn.ZIndex=3

local scroll=Instance.new("ScrollingFrame",mainFrame)
scroll.Size=UDim2.new(1,0,1,-86);scroll.Position=UDim2.new(0,0,0,34)
scroll.BackgroundTransparency=1;scroll.BorderSizePixel=0
scroll.ScrollBarThickness=3;scroll.ScrollBarImageColor3=CLR.accent;scroll.ZIndex=2

local treeLayout=Instance.new("UIListLayout",scroll)
treeLayout.SortOrder=Enum.SortOrder.LayoutOrder

local loadLabel=mkLabel(scroll,UDim2.new(1,0,0,30),UDim2.new(0,0,0,4),"⏳ Loading...",Color3.fromRGB(0,180,220),11,Enum.TextXAlignment.Center)
loadLabel.ZIndex=3;loadLabel.Visible=false

local footer=mkFrame(mainFrame,UDim2.new(1,0,0,52),UDim2.new(0,0,1,-52),CLR.dark)
footer.ZIndex=2
local exportBtn=mkBtn(footer,UDim2.new(0.58,-6,0,32),UDim2.new(0.42,3,0,10),CLR.accent,Color3.fromRGB(10,10,20),"📤 EXPORT",11)
exportBtn.ZIndex=3
local clearBtn=mkBtn(footer,UDim2.new(0.42,-9,0,32),UDim2.new(0,6,0,10),CLR.pageBg,Color3.fromRGB(130,130,155),"⟳ Clear",11)
clearBtn.ZIndex=3

-- ===== OUTPUT PANEL =====
local outputPanel=mkFrame(gui,UDim2.new(0,360,0,460),UDim2.new(0,283,0,10),Color3.fromRGB(10,10,20))
mkCorner(outputPanel);outputPanel.Visible=false;outputPanel.ZIndex=2

-- Row 1: Tab + controls
local outHeader=mkFrame(outputPanel,UDim2.new(1,0,0,34),UDim2.new(0,0,0,0),Color3.fromRGB(18,28,52))
mkCorner(outHeader);outHeader.ZIndex=3

local tabJson=mkBtn(outHeader,UDim2.new(0,58,0,24),UDim2.new(0,4,0.5,-12),CLR.accent,Color3.fromRGB(10,10,20),"{ } JSON",10)
tabJson.ZIndex=4
local tabLua=mkBtn(outHeader,UDim2.new(0,50,0,24),UDim2.new(0,66,0.5,-12),CLR.pageBg,Color3.fromRGB(130,130,155),"📜 Lua",10)
tabLua.ZIndex=4
local commentBtn=mkBtn(outHeader,UDim2.new(0,50,0,24),UDim2.new(0,120,0.5,-12),CLR.pageBg,Color3.fromRGB(130,130,155),"-- off",10)
commentBtn.ZIndex=4

local inclLabel=mkLabel(outHeader,UDim2.new(0,26,1,0),UDim2.new(0,175,0,0),"☑",CLR.accent,13,Enum.TextXAlignment.Center)
inclLabel.ZIndex=4
local inclBtn=Instance.new("TextButton",outHeader)
inclBtn.Size=UDim2.new(0,26,1,0);inclBtn.Position=UDim2.new(0,175,0,0)
inclBtn.BackgroundTransparency=1;inclBtn.Text="";inclBtn.ZIndex=5

local copyBtn=mkBtn(outHeader,UDim2.new(0,48,0,24),UDim2.new(1,-52,0.5,-12),CLR.green,Color3.fromRGB(255,255,255),"Copy",10)
copyBtn.ZIndex=4

-- Row 2: Page bar (chỉ hiện ở tab Lua)
local pageBarFrame=mkFrame(outputPanel,UDim2.new(1,0,0,28),UDim2.new(0,0,0,34),Color3.fromRGB(14,14,28))
pageBarFrame.ZIndex=3;pageBarFrame.Visible=false

local pageScroll=Instance.new("ScrollingFrame",pageBarFrame)
pageScroll.Size=UDim2.new(1,-8,1,0);pageScroll.Position=UDim2.new(0,4,0,0)
pageScroll.BackgroundTransparency=1;pageScroll.BorderSizePixel=0
pageScroll.ScrollBarThickness=2;pageScroll.ScrollBarImageColor3=CLR.dim
pageScroll.ScrollingDirection=Enum.ScrollingDirection.X;pageScroll.ZIndex=4

local pageLayout=Instance.new("UIListLayout",pageScroll)
pageLayout.FillDirection=Enum.FillDirection.Horizontal
pageLayout.SortOrder=Enum.SortOrder.LayoutOrder
pageLayout.Padding=UDim.new(0,3)
pageLayout.VerticalAlignment=Enum.VerticalAlignment.Center

-- Row 3: Settings bar (chỉ hiện ở tab Lua)
local settingsBar=mkFrame(outputPanel,UDim2.new(1,0,0,22),UDim2.new(0,0,0,62),Color3.fromRGB(11,11,20))
settingsBar.ZIndex=3;settingsBar.Visible=false

mkLabel(settingsBar,UDim2.new(0,78,1,0),UDim2.new(0,5,0,0),"Max dòng/trang:",Color3.fromRGB(90,110,140),9).ZIndex=4

local maxLinesBox=Instance.new("TextBox",settingsBar)
maxLinesBox.Size=UDim2.new(0,44,0,16);maxLinesBox.Position=UDim2.new(0,84,0.5,-8)
maxLinesBox.BackgroundColor3=Color3.fromRGB(22,22,40);maxLinesBox.BorderSizePixel=0
maxLinesBox.TextColor3=CLR.accent;maxLinesBox.TextSize=10;maxLinesBox.Font=Enum.Font.Code
maxLinesBox.Text="500";maxLinesBox.ClearTextOnFocus=false;maxLinesBox.ZIndex=4
mkCorner(maxLinesBox,4)

local applyBtn=mkBtn(settingsBar,UDim2.new(0,40,0,16),UDim2.new(0,132,0.5,-8),CLR.accentDim,CLR.accent,"Apply",9)
applyBtn.ZIndex=4

local pageInfoLabel=mkLabel(settingsBar,UDim2.new(0,140,1,0),UDim2.new(0,178,0,0),"",Color3.fromRGB(90,120,155),9)
pageInfoLabel.ZIndex=4

-- Output text scroll
-- JSON mode: offset 34 | Lua mode: offset 34+28+22=84
local outScroll=Instance.new("ScrollingFrame",outputPanel)
outScroll.Size=UDim2.new(1,0,1,-34);outScroll.Position=UDim2.new(0,0,0,34)
outScroll.BackgroundTransparency=1;outScroll.BorderSizePixel=0
outScroll.ScrollBarThickness=3;outScroll.ScrollBarImageColor3=Color3.fromRGB(80,80,120);outScroll.ZIndex=3

local outText=Instance.new("TextBox",outScroll)
outText.Size=UDim2.new(1,-12,0,0);outText.Position=UDim2.new(0,8,0,6)
outText.BackgroundTransparency=1
outText.Text="-- Chọn object để xem output"
outText.TextColor3=Color3.fromRGB(100,120,150);outText.TextSize=10
outText.Font=Enum.Font.Code;outText.TextXAlignment=Enum.TextXAlignment.Left
outText.TextYAlignment=Enum.TextYAlignment.Top;outText.TextWrapped=true
outText.AutomaticSize=Enum.AutomaticSize.Y;outText.ZIndex=4
outText.ClearTextOnFocus=false  -- ✅ Không mất text khi click
outText.TextEditable=false       -- Readonly display

outText:GetPropertyChangedSignal("TextBounds"):Connect(function()
	outScroll.CanvasSize=UDim2.new(0,0,0,outText.TextBounds.Y+16)
end)

-- ==================== STATE ====================

local selectedRow,selectedInst,currentData=nil,nil,nil
local currentTab="json"
local panelOpen=false
local showComments=false
local inclToggle=true
local maxLinesPerPage=500

local currentPages={}
local currentPageIdx=1
local currentAllBtn=nil
local pageButtons={}

local ICONS={
	Part="🟦",MeshPart="🔷",UnionOperation="🔶",Model="📁",Folder="📂",
	Script="📜",LocalScript="📜",ModuleScript="📦",Camera="📷",SpawnLocation="🏁",
	ParticleEmitter="✨",Beam="〰",Trail="〰",Fire="🔥",Smoke="💨",Sparkles="⭐",
	PointLight="💡",SpotLight="💡",SurfaceLight="💡",Sound="🔊",Humanoid="🧍",
	Frame="▭",TextLabel="Ⓣ",TextButton="🔘",ImageLabel="🖼",ScreenGui="🖥",
	Attachment="📌",WeldConstraint="🔗",BillboardGui="🪧",SurfaceGui="🪧",
	ClickDetector="👆",ProximityPrompt="⚡",Sky="🌅",Atmosphere="🌫",
	Animation="🎬",Animator="🎬",
}

-- ==================== PAGE BUTTONS ====================

local function clearPageBtns()
	for _,b in ipairs(pageButtons) do if b and b.Parent then b:Destroy() end end
	pageButtons={}
	if currentAllBtn and currentAllBtn.Parent then currentAllBtn:Destroy() end
	currentAllBtn=nil
end

local function setPageDisplay(idx)
	-- idx=0 → ALL mode
	if idx==0 then
		local allLines={}
		for _,pg in ipairs(currentPages) do
			for _,l in ipairs(pg.lines) do table.insert(allLines,l) end
		end
		outText.Text=table.concat(allLines,"\n")
		outText.TextColor3=Color3.fromRGB(180,180,220)
		outScroll.CanvasPosition=Vector2.new(0,0)
		if currentAllBtn then
			currentAllBtn.BackgroundColor3=CLR.allActive
			currentAllBtn.TextColor3=Color3.fromRGB(10,10,20)
		end
		for _,b in ipairs(pageButtons) do
			b.BackgroundColor3=CLR.pageBg
			b.TextColor3=Color3.fromRGB(150,170,200)
		end
		local total=0
		for _,pg in ipairs(currentPages) do total=total+#pg.lines end
		pageInfoLabel.Text=string.format("ALL | %d trang | %d dòng",#currentPages,total)
	else
		idx=math.clamp(idx,1,#currentPages)
		currentPageIdx=idx
		local pg=currentPages[idx]
		outText.Text=table.concat(pg.lines,"\n")
		outText.TextColor3=Color3.fromRGB(180,180,220)
		outScroll.CanvasPosition=Vector2.new(0,0)
		if currentAllBtn then
			currentAllBtn.BackgroundColor3=CLR.pageBg
			currentAllBtn.TextColor3=Color3.fromRGB(150,200,150)
		end
		for i,b in ipairs(pageButtons) do
			if i==idx then
				b.BackgroundColor3=CLR.pageActive
				b.TextColor3=Color3.fromRGB(255,255,255)
			else
				b.BackgroundColor3=CLR.pageBg
				b.TextColor3=Color3.fromRGB(150,170,200)
			end
		end
		pageInfoLabel.Text=string.format("Trang %d/%d | %d dòng",idx,#currentPages,#pg.lines)
	end
end

local function buildPageUI()
	clearPageBtns()

	if #currentPages==0 then pageInfoLabel.Text="";return end

	-- Nút ALL
	local allBtn=mkBtn(pageScroll,UDim2.new(0,32,0,20),UDim2.new(0,0,0,4),CLR.pageBg,Color3.fromRGB(150,200,150),"ALL",9)
	allBtn.ZIndex=5;allBtn.LayoutOrder=0
	mkCorner(allBtn,4)
	currentAllBtn=allBtn
	allBtn.MouseButton1Click:Connect(function() setPageDisplay(0) end)

	-- Nút từng trang: 1, 2, 3, ...
	for i=1,#currentPages do
		local btn=mkBtn(pageScroll,UDim2.new(0,26,0,20),UDim2.new(0,0,0,4),CLR.pageBg,Color3.fromRGB(150,170,200),tostring(i),9)
		btn.ZIndex=5;btn.LayoutOrder=i
		mkCorner(btn,4)
		table.insert(pageButtons,btn)
		local ci=i
		btn.MouseButton1Click:Connect(function() setPageDisplay(ci) end)
	end

	task.wait()
	pageScroll.CanvasSize=UDim2.new(0,pageLayout.AbsoluteContentSize.X+8,1,0)

	-- Mặc định show trang 1 nếu nhiều trang, ALL nếu 1 trang
	if #currentPages>1 then
		setPageDisplay(1)
	else
		setPageDisplay(0)
	end
end

-- ==================== OUTPUT REFRESH ====================

local function setLuaExtras(show)
	pageBarFrame.Visible=show
	settingsBar.Visible=show
	if show then
		outScroll.Size=UDim2.new(1,0,1,-84)
		outScroll.Position=UDim2.new(0,0,0,84)
	else
		outScroll.Size=UDim2.new(1,0,1,-34)
		outScroll.Position=UDim2.new(0,0,0,34)
	end
end

local function stripChildren(data)
	return{ClassName=data.ClassName,Name=data.Name,Properties=data.Properties,Children={}}
end

local function refreshOutput()
	if not currentData then return end
	local d=inclToggle and currentData or stripChildren(currentData)

	if currentTab=="json" then
		setLuaExtras(false)
		clearPageBtns();currentPages={}
		outText.Text=jsonEncode(d)
		outText.TextColor3=Color3.fromRGB(140,200,160)
	else
		setLuaExtras(true)
		local segs=buildSegments(d,showComments)
		currentPages=buildPages(segs,maxLinesPerPage)
		buildPageUI()
	end
end

-- ==================== TABS & CONTROLS ====================

local function setTab(tab)
	currentTab=tab
	if tab=="json" then
		tabJson.BackgroundColor3=CLR.accent;tabJson.TextColor3=Color3.fromRGB(10,10,20)
		tabLua.BackgroundColor3=CLR.pageBg;tabLua.TextColor3=Color3.fromRGB(130,130,155)
	else
		tabLua.BackgroundColor3=CLR.accent;tabLua.TextColor3=Color3.fromRGB(10,10,20)
		tabJson.BackgroundColor3=CLR.pageBg;tabJson.TextColor3=Color3.fromRGB(130,130,155)
	end
	refreshOutput()
end

tabJson.MouseButton1Click:Connect(function() setTab("json") end)
tabLua.MouseButton1Click:Connect(function() setTab("lua") end)

commentBtn.MouseButton1Click:Connect(function()
	showComments=not showComments
	commentBtn.Text=showComments and "-- on" or "-- off"
	commentBtn.BackgroundColor3=showComments and Color3.fromRGB(0,80,60) or CLR.pageBg
	commentBtn.TextColor3=showComments and CLR.green or Color3.fromRGB(130,130,155)
	refreshOutput()
end)

inclBtn.MouseButton1Click:Connect(function()
	inclToggle=not inclToggle
	inclLabel.Text=inclToggle and "☑" or "☐"
	inclLabel.TextColor3=inclToggle and CLR.accent or Color3.fromRGB(100,100,130)
	if selectedInst then currentData=serialize(selectedInst,inclToggle) end
	refreshOutput()
end)

copyBtn.MouseButton1Click:Connect(function()
	if outText.Text=="" then return end
	print("=== WorkspaceExplorer OUTPUT ===")
	print(outText.Text)
	print("================================")
	copyBtn.Text="✅";copyBtn.BackgroundColor3=Color3.fromRGB(0,150,100)
	task.wait(1.5)
	copyBtn.Text="Copy";copyBtn.BackgroundColor3=CLR.green
end)

applyBtn.MouseButton1Click:Connect(function()
	local v=tonumber(maxLinesBox.Text)
	if v and v>=50 then
		maxLinesPerPage=math.floor(v)
		refreshOutput()
		applyBtn.Text="✅";task.wait(1);applyBtn.Text="Apply"
	else
		maxLinesBox.Text=tostring(maxLinesPerPage)
	end
end)

toggleBtn.MouseButton1Click:Connect(function()
	panelOpen=not panelOpen
	outputPanel.Visible=panelOpen
	toggleBtn.Text=panelOpen and "✕ Close" or "{ } View"
	toggleBtn.BackgroundColor3=panelOpen and Color3.fromRGB(60,20,20) or CLR.accentDim
	toggleBtn.TextColor3=panelOpen and Color3.fromRGB(255,100,100) or CLR.accent
end)

-- ==================== TREE (LAZY LOAD) ====================

local function selectRow(row,inst)
	if selectedRow then selectedRow.BackgroundTransparency=1 end
	selectedRow=row;selectedInst=inst
	row.BackgroundTransparency=0;row.BackgroundColor3=CLR.select
	currentData=serialize(inst,inclToggle)
	refreshOutput()
end

local function makeRow(inst,depth,parentLayout)
	local hasChildren=#inst:GetChildren()>0
	local icon=ICONS[inst.ClassName] or "📄"
	local target=parentLayout or scroll

	local row=Instance.new("TextButton",target)
	row.Size=UDim2.new(1,0,0,22)
	row.BackgroundTransparency=1;row.BorderSizePixel=0
	row.Text="";row.AutoButtonColor=false;row.ZIndex=2

	local indW=depth*14
	local arrow=Instance.new("TextButton",row)
	arrow.Size=UDim2.new(0,14,1,0);arrow.Position=UDim2.new(0,indW,0,0)
	arrow.BackgroundTransparency=1;arrow.Text=hasChildren and "▶" or ""
	arrow.TextColor3=CLR.dim;arrow.TextSize=9;arrow.Font=Enum.Font.Code
	arrow.BorderSizePixel=0;arrow.AutoButtonColor=false;arrow.ZIndex=3

	local lbl=Instance.new("TextLabel",row)
	lbl.Size=UDim2.new(1,-(indW+18),1,0);lbl.Position=UDim2.new(0,indW+18,0,0)
	lbl.BackgroundTransparency=1;lbl.Text=icon.." "..inst.Name
	lbl.TextColor3=CLR.text;lbl.TextSize=11;lbl.Font=Enum.Font.Code
	lbl.TextXAlignment=Enum.TextXAlignment.Left;lbl.ZIndex=3

	-- Children container (lazy)
	local childContainer=Instance.new("Frame",target)
	childContainer.Size=UDim2.new(1,0,0,0)
	childContainer.BackgroundTransparency=1;childContainer.BorderSizePixel=0
	childContainer.ClipsDescendants=false;childContainer.Visible=false

	local childLayout=Instance.new("UIListLayout",childContainer)
	childLayout.SortOrder=Enum.SortOrder.LayoutOrder

	local childrenLoaded=false
	local open=false

	local function updateHeights()
		childContainer.Size=UDim2.new(1,0,0,childLayout.AbsoluteContentSize.Y)
		scroll.CanvasSize=UDim2.new(0,0,0,treeLayout.AbsoluteContentSize.Y)
	end

	local function loadChildren()
		if childrenLoaded then return end
		childrenLoaded=true
		local children=inst:GetChildren()
		for i,child in ipairs(children) do
			makeRow(child,depth+1,childContainer)
			if i%10==0 then task.wait() end
		end
		childLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateHeights)
		updateHeights()
	end

	if hasChildren then
		arrow.MouseButton1Click:Connect(function()
			open=not open
			if open then
				loadChildren()
				childContainer.Visible=true
				arrow.Text="▼";arrow.TextColor3=CLR.accent
			else
				childContainer.Visible=false
				arrow.Text="▶";arrow.TextColor3=CLR.dim
			end
			scroll.CanvasSize=UDim2.new(0,0,0,treeLayout.AbsoluteContentSize.Y)
		end)
	end

	row.MouseButton1Click:Connect(function() selectRow(row,inst) end)
	return row
end

-- ==================== BUILD TREE ====================

local function buildTree()
	for _,c in ipairs(scroll:GetChildren()) do
		if c:IsA("TextButton") or c:IsA("Frame") then c:Destroy() end
	end
	loadLabel.Visible=true
	local children=workspace:GetChildren()
	for i,obj in ipairs(children) do
		makeRow(obj,0)
		if i%10==0 then task.wait() end
	end
	loadLabel.Visible=false
	treeLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		scroll.CanvasSize=UDim2.new(0,0,0,treeLayout.AbsoluteContentSize.Y)
	end)
	scroll.CanvasSize=UDim2.new(0,0,0,treeLayout.AbsoluteContentSize.Y)
end

-- ==================== FOOTER BUTTONS ====================

refreshBtn.MouseButton1Click:Connect(function()
	selectedRow=nil;selectedInst=nil;currentData=nil
	clearPageBtns();currentPages={}
	outText.Text="-- Chọn object để xem output"
	outText.TextColor3=Color3.fromRGB(100,120,150)
	pageInfoLabel.Text=""
	refreshBtn.Text="⏳"
	buildTree()
	refreshBtn.Text="↺"
end)

exportBtn.MouseButton1Click:Connect(function()
	if not selectedInst then
		exportBtn.Text="⚠ Chọn trước!";task.wait(1.5);exportBtn.Text="📤 EXPORT";return
	end
	exportBtn.Text="⏳..."
	local data=serialize(selectedInst,true)
	print("=== WORKSPACE EXPORT ===")
	print(HttpService:JSONEncode(data))
	print("========================")
	exportBtn.Text="✅ Done!";task.wait(2);exportBtn.Text="📤 EXPORT"
end)

clearBtn.MouseButton1Click:Connect(function()
	if selectedRow then selectedRow.BackgroundTransparency=1 end
	selectedRow=nil;selectedInst=nil;currentData=nil
	clearPageBtns();currentPages={}
	outText.Text="-- Chọn object để xem output"
	outText.TextColor3=Color3.fromRGB(100,120,150)
	pageInfoLabel.Text=""
end)

-- ==================== INIT ====================
setLuaExtras(false)
task.spawn(buildTree)
