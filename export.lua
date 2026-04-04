-- WorkspaceExplorer v5.0
-- LocalScript trong StarterGui
-- Lazy-load, Smart Pagination, Comment toggle, Refresh, Dupe check
-- Tab Lua: output dạng function (createPart/createAttachments/createEffects/createModel)
-- Tab FX: Smart FX scan effects/attachments

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

-- ==================== VALUE → LUA ====================

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

-- ==================== CLASS TYPE HELPERS ====================

local BASEPART_SET = {}
for _,cls in ipairs(BASE_PART_CLASSES) do BASEPART_SET[cls]=true end

local EFFECT_CLASSES = {
	ParticleEmitter=true,Beam=true,Trail=true,
	Fire=true,Smoke=true,Sparkles=true,
	PointLight=true,SpotLight=true,SurfaceLight=true,
	SelectionBox=true,SelectionSphere=true,
	BillboardGui=true,SurfaceGui=true,
}
local ATTACHMENT_CLASSES = { Attachment=true }

local function safeVar(name,idx)
	return (name:gsub("[^%w]","_")).."_"..idx
end

-- ==================== GENERIC CODEGEN (Tab Lua + Tab FX) ====================
--[[
  Ý tưởng: định nghĩa 3 generic functions 1 lần ở đầu output,
  sau đó mỗi object/part chỉ cần GỌI với props inline dạng table.

  Output mẫu:
  ┌─ PHẦN 1: 3 generic functions (luôn có, dùng chung) ────────────────────┐
  │  local function createPart(name, className, props, parent)             │
  │  local function createAttachment(name, parent, props)                  │
  │  local function createEffect(className, name, parent, att, props)      │
  └────────────────────────────────────────────────────────────────────────┘
  ┌─ PHẦN 2: call lines gọn cho từng object ───────────────────────────────┐
  │  local p1 = createPart("MyPart","Part",{Size=...,Anchored=true},workspace)│
  │  local a1 = createAttachment("AttP",p1,{Position=Vector3.new(0,1,0)}) │
  │  createEffect("ParticleEmitter","FX",p1,{Attachment0=a1},{Rate=20,...})│
  └────────────────────────────────────────────────────────────────────────┘
  createModel wrap toàn bộ cây, bên trong gọi 3 functions trên.
]]

-- ── Serialize props của 1 instance thành chuỗi "{k=v, k2=v2}" ─────────────
local function propsToTable(inst, skipProps)
	skipProps = skipProps or {}
	local props = getProps(inst)
	local priority = {"Size","Position","CFrame","Color","BrickColor","Material",
		"Transparency","Reflectance","Anchored","CanCollide","Shape","MeshId","TextureID"}
	local parts = {}
	local seen = {}
	-- Priority props trước
	for _, prop in ipairs(priority) do
		if props[prop] ~= nil and not skipProps[prop] then
			local lua = valToLua(props[prop])
			if lua ~= "nil" then
				table.insert(parts, string.format('%s=%s', prop, lua))
				seen[prop] = true
			end
		end
	end
	-- Còn lại
	for prop, val in pairs(props) do
		if not seen[prop] and not skipProps[prop] then
			local lua = valToLua(val)
			if lua ~= "nil" then
				table.insert(parts, string.format('%s=%s', prop, lua))
			end
		end
	end
	if #parts == 0 then return "{}" end
	-- Nếu ngắn thì 1 dòng, dài thì multiline
	local inline = "{"..table.concat(parts, ", ").."}"
	if #inline <= 80 then
		return inline
	else
		return "{\n        "..table.concat(parts, ",\n        ").."\n    }"
	end
end

-- ── 3 generic function definitions (xuất ra output 1 lần) ─────────────────
local GENERIC_FUNCTIONS = [[
local function createPart(name, className, props, parent)
    local p = Instance.new(className)
    p.Name = name
    for k, v in pairs(props) do p[k] = v end
    p.Parent = parent or workspace
    return p
end

local function createAttachment(name, parent, props)
    local a = Instance.new("Attachment")
    a.Name = name
    for k, v in pairs(props or {}) do a[k] = v end
    a.Parent = parent
    return a
end

local function createEffect(className, name, parent, att, props)
    local e = Instance.new(className)
    e.Name = name
    if att then
        if att.Attachment0 then e.Attachment0 = att.Attachment0 end
        if att.Attachment1 then e.Attachment1 = att.Attachment1 end
    end
    for k, v in pairs(props or {}) do e[k] = v end
    e.Parent = parent
    return e
end
]]

-- ── Sinh call lines cho 1 BasePart (attachments + effects) ────────────────
local function genPartCallLines(part, partVar, showCmt)
	local lines = {}
	local attachments, effects, others = {}, {}, {}
	for _, child in ipairs(part:GetChildren()) do
		if ATTACHMENT_CLASSES[child.ClassName] then
			table.insert(attachments, child)
		elseif EFFECT_CLASSES[child.ClassName] then
			table.insert(effects, child)
		else
			table.insert(others, child)
		end
	end

	-- Attachment calls → lưu varname để dùng cho effect
	local attVars = {} -- name → varName
	for ai, a in ipairs(attachments) do
		local aVar = string.format("att%d", ai)
		attVars[a.Name] = aVar
		local propStr = propsToTable(a)
		if showCmt then table.insert(lines, string.format('-- Attachment: %s', a.Name)) end
		table.insert(lines, string.format('local %s = createAttachment("%s", %s, %s)',
			aVar, a.Name, partVar, propStr))
	end

	-- Effect calls
	for _, fx in ipairs(effects) do
		local props = getProps(fx)
		-- Tách att refs ra khỏi props table
		local attArg = "nil"
		local att0 = props["Attachment0"]
		local att1 = props["Attachment1"]
		if att0 or att1 then
			local attParts = {}
			if att0 and type(att0)=="string" and attVars[att0] then
				table.insert(attParts, "Attachment0="..attVars[att0])
			end
			if att1 and type(att1)=="string" and attVars[att1] then
				table.insert(attParts, "Attachment1="..attVars[att1])
			end
			if #attParts > 0 then attArg = "{"..table.concat(attParts,", ").."}" end
		end
		-- Props không gồm Attachment0/1
		local propStr = propsToTable(fx, {Attachment0=true, Attachment1=true})
		if showCmt then table.insert(lines, string.format('-- %s: %s', fx.ClassName, fx.Name)) end
		table.insert(lines, string.format('createEffect("%s", "%s", %s, %s, %s)',
			fx.ClassName, fx.Name, partVar, attArg, propStr))
	end

	-- Other children (không phải effect/attachment): tạo inline đơn giản
	for oi, other in ipairs(others) do
		local oVar = string.format("child%d", oi)
		local propStr = propsToTable(other)
		if showCmt then table.insert(lines, string.format('-- %s: %s', other.ClassName, other.Name)) end
		table.insert(lines, string.format('local %s = createPart("%s", "%s", %s, %s)',
			oVar, other.Name, other.ClassName, propStr, partVar))
	end

	return lines
end

-- ── Sinh toàn bộ output cho tab Lua ───────────────────────────────────────
local function genFunctionCode(inst, showCmt)
	local lines = {}

	if showCmt then
		table.insert(lines, "-- Generated by WorkspaceExplorer v5.0")
		table.insert(lines, string.format("-- Object: %s [%s]", inst.Name, inst.ClassName))
		table.insert(lines, "")
	end

	-- Luôn emit 3 generic functions ở đầu
	table.insert(lines, "-- ── Helper functions (dùng chung) ──────────────────────")
	table.insert(lines, GENERIC_FUNCTIONS)

	if BASEPART_SET[inst.ClassName] then
		-- ── Single BasePart ─────────────────────────────────────
		if showCmt then table.insert(lines, "-- ── Tạo Part ──────────────────────────────────────────") end
		local pVar = "p1"
		local propStr = propsToTable(inst)
		table.insert(lines, string.format('local %s = createPart("%s", "%s", %s, workspace)',
			pVar, inst.Name, inst.ClassName, propStr))
		table.insert(lines, "")
		local callLines = genPartCallLines(inst, pVar, showCmt)
		for _, l in ipairs(callLines) do table.insert(lines, l) end

	else
		-- ── Model / Folder / khác ───────────────────────────────
		if showCmt then
			table.insert(lines, "-- ── Tạo Model ─────────────────────────────────────────")
		end
		-- createModel wrapper function
		table.insert(lines, string.format('local function createModel_%s(parent)',
			safeVar(inst.Name, 1)))
		local i1 = "    "
		-- Tạo root container
		local propStr = propsToTable(inst)
		table.insert(lines, i1..string.format('local model = createPart("%s", "%s", %s, parent)',
			inst.Name, inst.ClassName, propStr))
		table.insert(lines, "")

		-- Từng child
		local partIdx = 0
		for _, child in ipairs(inst:GetChildren()) do
			if BASEPART_SET[child.ClassName] then
				partIdx = partIdx + 1
				local pVar = string.format("p%d", partIdx)
				local cPropStr = propsToTable(child)
				if showCmt then table.insert(lines, i1..string.format('-- Part: %s', child.Name)) end
				table.insert(lines, i1..string.format('local %s = createPart("%s", "%s", %s, model)',
					pVar, child.Name, child.ClassName, cPropStr))
				-- Effects/Attachments của child này
				local childCallLines = genPartCallLines(child, pVar, showCmt)
				for _, l in ipairs(childCallLines) do
					table.insert(lines, i1..l)
				end
				table.insert(lines, "")
			else
				-- Non-part child (Script, Sound, etc.)
				local cPropStr = propsToTable(child)
				if showCmt then table.insert(lines, i1..string.format('-- %s: %s', child.ClassName, child.Name)) end
				table.insert(lines, i1..string.format('createPart("%s", "%s", %s, model)',
					child.Name, child.ClassName, cPropStr))
			end
		end

		table.insert(lines, i1.."return model")
		table.insert(lines, "end")
		table.insert(lines, "")
		if showCmt then table.insert(lines, "-- ── Khởi tạo ──────────────────────────────────────────") end
		table.insert(lines, string.format('local model = createModel_%s(workspace)', safeVar(inst.Name, 1)))
	end

	return table.concat(lines, "\n")
end

-- ── Sinh output cho tab FX (chỉ effects/attachments, không có createModel) ─
local function genSmartFX(rootInst, effectOnlyMode, showCmt)
	local lines = {}

	if showCmt then
		table.insert(lines, "-- Generated by WorkspaceExplorer v5.0 (Smart FX Mode)")
		table.insert(lines, string.format("-- Source: %s [%s]", rootInst.Name, rootInst.ClassName))
		table.insert(lines, "")
	end

	-- 3 generic functions luôn có ở đầu
	table.insert(lines, "-- ── Helper functions (dùng chung) ──────────────────────")
	table.insert(lines, GENERIC_FUNCTIONS)

	-- Xác định danh sách parts cần xử lý
	local parts = {}
	if BASEPART_SET[rootInst.ClassName] then
		table.insert(parts, rootInst)
	else
		for _, child in ipairs(rootInst:GetChildren()) do
			if BASEPART_SET[child.ClassName] then table.insert(parts, child) end
		end
		if #parts == 0 then table.insert(parts, rootInst) end
	end

	if showCmt then table.insert(lines, "-- ── Setup ──────────────────────────────────────────────") end

	for idx, part in ipairs(parts) do
		local pVar = string.format("p%d", idx)

		if not effectOnlyMode then
			local propStr = propsToTable(part)
			if showCmt then table.insert(lines, string.format('-- Part: %s', part.Name)) end
			table.insert(lines, string.format('local %s = createPart("%s", "%s", %s, workspace)',
				pVar, part.Name, part.ClassName, propStr))
		else
			if showCmt then table.insert(lines, string.format('-- Dùng part sẵn có: %s', part.Name)) end
			table.insert(lines, string.format('local %s = workspace:WaitForChild("%s")', pVar, part.Name))
		end

		local callLines = genPartCallLines(part, pVar, showCmt)
		for _, l in ipairs(callLines) do table.insert(lines, l) end
		table.insert(lines, "")
	end

	return table.concat(lines, "\n")
end

-- ==================== SMART PAGINATION ====================

local function buildSegmentsFn(code)
	-- Chia theo blank line giữa các top-level functions
	local segments = {}
	local cur = {}
	for line in (code.."\n"):gmatch("([^\n]*)\n") do
		table.insert(cur, line)
		-- Flush khi gặp "end" dòng đứng một mình (kết thúc function top-level)
		if line == "end" then
			table.insert(segments, {lines=cur})
			cur = {}
		end
	end
	if #cur > 0 then table.insert(segments, {lines=cur}) end
	return segments
end

local function buildPages(segments, maxLines)
	if #segments==0 then return {} end
	local pages,cur={},{lines={},segCount=0}
	for _,seg in ipairs(segments) do
		local sLen=#seg.lines
		if cur.segCount>0 and (#cur.lines+sLen)>maxLines then
			table.insert(pages,cur);cur={lines={},segCount=0}
		end
		for _,l in ipairs(seg.lines) do table.insert(cur.lines,l) end
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
	orange=Color3.fromRGB(255,160,50),
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
local outputPanel=mkFrame(gui,UDim2.new(0,380,0,460),UDim2.new(0,283,0,10),Color3.fromRGB(10,10,20))
mkCorner(outputPanel);outputPanel.Visible=false;outputPanel.ZIndex=2

-- Row 1: Tab bar
local outHeader=mkFrame(outputPanel,UDim2.new(1,0,0,34),UDim2.new(0,0,0,0),Color3.fromRGB(18,28,52))
mkCorner(outHeader);outHeader.ZIndex=3

-- Tabs: JSON | Lua | FX  (nới rộng để vừa 3 tab)
local tabJson=mkBtn(outHeader,UDim2.new(0,52,0,24),UDim2.new(0,4,0.5,-12),CLR.accent,Color3.fromRGB(10,10,20),"{ } JSON",10)
tabJson.ZIndex=4
local tabLua=mkBtn(outHeader,UDim2.new(0,46,0,24),UDim2.new(0,60,0.5,-12),CLR.pageBg,Color3.fromRGB(130,130,155),"📜 Lua",10)
tabLua.ZIndex=4
local tabFx=mkBtn(outHeader,UDim2.new(0,40,0,24),UDim2.new(0,110,0.5,-12),CLR.pageBg,Color3.fromRGB(130,130,155),"⚡ FX",10)
tabFx.ZIndex=4

local commentBtn=mkBtn(outHeader,UDim2.new(0,48,0,24),UDim2.new(0,156,0.5,-12),CLR.pageBg,Color3.fromRGB(130,130,155),"-- off",10)
commentBtn.ZIndex=4

local copyBtn=mkBtn(outHeader,UDim2.new(0,48,0,24),UDim2.new(1,-52,0.5,-12),CLR.green,Color3.fromRGB(255,255,255),"Copy",10)
copyBtn.ZIndex=4

-- Row 2: Page bar (Lua + FX)
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

-- Row 3: Settings bar
local settingsBar=mkFrame(outputPanel,UDim2.new(1,0,0,26),UDim2.new(0,0,0,62),Color3.fromRGB(11,11,20))
settingsBar.ZIndex=3;settingsBar.Visible=false

-- Settings cho Lua
mkLabel(settingsBar,UDim2.new(0,78,1,0),UDim2.new(0,5,0,0),"Max dòng/trang:",Color3.fromRGB(90,110,140),9).ZIndex=4

local maxLinesBox=Instance.new("TextBox",settingsBar)
maxLinesBox.Size=UDim2.new(0,44,0,18);maxLinesBox.Position=UDim2.new(0,84,0.5,-9)
maxLinesBox.BackgroundColor3=Color3.fromRGB(22,22,40);maxLinesBox.BorderSizePixel=0
maxLinesBox.TextColor3=CLR.accent;maxLinesBox.TextSize=10;maxLinesBox.Font=Enum.Font.Code
maxLinesBox.Text="500";maxLinesBox.ClearTextOnFocus=false;maxLinesBox.ZIndex=4
mkCorner(maxLinesBox,4)

local applyBtn=mkBtn(settingsBar,UDim2.new(0,38,0,18),UDim2.new(0,132,0.5,-9),CLR.accentDim,CLR.accent,"Apply",9)
applyBtn.ZIndex=4

-- Settings cho FX: Effect Only toggle
local fxOnlyLabel=mkLabel(settingsBar,UDim2.new(0,78,1,0),UDim2.new(0,5,0,0),"Effect Only:",Color3.fromRGB(90,110,140),9)
fxOnlyLabel.ZIndex=4;fxOnlyLabel.Visible=false

local fxOnlyBtn=mkBtn(settingsBar,UDim2.new(0,42,0,18),UDim2.new(0,80,0.5,-9),CLR.pageBg,Color3.fromRGB(130,130,155),"OFF",9)
fxOnlyBtn.ZIndex=4;fxOnlyBtn.Visible=false
mkCorner(fxOnlyBtn,4)

local pageInfoLabel=mkLabel(settingsBar,UDim2.new(0,160,1,0),UDim2.new(0,180,0,0),"",Color3.fromRGB(90,120,155),9)
pageInfoLabel.ZIndex=4

-- Output scroll
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
outText.ClearTextOnFocus=false
outText.TextEditable=false
outText.MultiLine=true

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
local fxEffectOnly=false

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
	if idx==0 then
		local allLines={}
		for _,pg in ipairs(currentPages) do for _,l in ipairs(pg.lines) do table.insert(allLines,l) end end
		outText.Text=table.concat(allLines,"\n")
		outText.TextColor3= currentTab=="fx" and Color3.fromRGB(255,210,100) or Color3.fromRGB(180,200,255)
		outScroll.CanvasPosition=Vector2.new(0,0)
		if currentAllBtn then currentAllBtn.BackgroundColor3=CLR.allActive;currentAllBtn.TextColor3=Color3.fromRGB(10,10,20) end
		for _,b in ipairs(pageButtons) do b.BackgroundColor3=CLR.pageBg;b.TextColor3=Color3.fromRGB(150,170,200) end
		local total=0;for _,pg in ipairs(currentPages) do total=total+#pg.lines end
		pageInfoLabel.Text=string.format("ALL | %d trang | %d dòng",#currentPages,total)
	else
		idx=math.clamp(idx,1,#currentPages);currentPageIdx=idx
		local pg=currentPages[idx]
		outText.Text=table.concat(pg.lines,"\n")
		outText.TextColor3= currentTab=="fx" and Color3.fromRGB(255,210,100) or Color3.fromRGB(180,200,255)
		outScroll.CanvasPosition=Vector2.new(0,0)
		if currentAllBtn then currentAllBtn.BackgroundColor3=CLR.pageBg;currentAllBtn.TextColor3=Color3.fromRGB(150,200,150) end
		for i,b in ipairs(pageButtons) do
			b.BackgroundColor3=i==idx and CLR.pageActive or CLR.pageBg
			b.TextColor3=i==idx and Color3.fromRGB(255,255,255) or Color3.fromRGB(150,170,200)
		end
		pageInfoLabel.Text=string.format("Trang %d/%d | %d dòng",idx,#currentPages,#pg.lines)
	end
end

local function buildPageUI()
	clearPageBtns()
	if #currentPages==0 then pageInfoLabel.Text="";return end
	local allBtn=mkBtn(pageScroll,UDim2.new(0,32,0,20),UDim2.new(0,0,0,4),CLR.pageBg,Color3.fromRGB(150,200,150),"ALL",9)
	allBtn.ZIndex=5;allBtn.LayoutOrder=0;mkCorner(allBtn,4);currentAllBtn=allBtn
	allBtn.MouseButton1Click:Connect(function() setPageDisplay(0) end)
	for i=1,#currentPages do
		local btn=mkBtn(pageScroll,UDim2.new(0,26,0,20),UDim2.new(0,0,0,4),CLR.pageBg,Color3.fromRGB(150,170,200),tostring(i),9)
		btn.ZIndex=5;btn.LayoutOrder=i;mkCorner(btn,4)
		table.insert(pageButtons,btn)
		local ci=i
		btn.MouseButton1Click:Connect(function() setPageDisplay(ci) end)
	end
	task.wait()
	pageScroll.CanvasSize=UDim2.new(0,pageLayout.AbsoluteContentSize.X+8,1,0)
	if #currentPages>1 then setPageDisplay(1) else setPageDisplay(0) end
end

-- ==================== LAYOUT HELPERS ====================

local function setScrollOffset(offset)
	outScroll.Size=UDim2.new(1,0,1,-offset)
	outScroll.Position=UDim2.new(0,0,0,offset)
end

-- offset theo tab:
-- json: 34 (chỉ header)
-- lua:  34+28+26=88 (header+pagebar+settings)
-- fx:   34+28+26=88

local function applyLayoutForTab(tab)
	if tab=="json" then
		pageBarFrame.Visible=false
		settingsBar.Visible=false
		-- Lua settings ẩn, FX settings ẩn
		maxLinesBox.Visible=false; applyBtn.Visible=false
		fxOnlyLabel.Visible=false; fxOnlyBtn.Visible=false
		mkLabel(settingsBar,UDim2.new(0,78,1,0),UDim2.new(0,5,0,0),"",Color3.fromRGB(0,0,0),1)
		setScrollOffset(34)
	elseif tab=="lua" then
		pageBarFrame.Visible=true
		settingsBar.Visible=true
		maxLinesBox.Visible=true; applyBtn.Visible=true
		fxOnlyLabel.Visible=false; fxOnlyBtn.Visible=false
		pageInfoLabel.Position=UDim2.new(0,178,0,0)
		setScrollOffset(88)
	elseif tab=="fx" then
		pageBarFrame.Visible=true
		settingsBar.Visible=true
		maxLinesBox.Visible=false; applyBtn.Visible=false
		fxOnlyLabel.Visible=true; fxOnlyBtn.Visible=true
		pageInfoLabel.Position=UDim2.new(0,130,0,0)
		setScrollOffset(88)
	end
end

-- ==================== OUTPUT REFRESH ====================

local function stripChildren(data)
	return{ClassName=data.ClassName,Name=data.Name,Properties=data.Properties,Children={}}
end

local function setAllTabStyles(active)
	tabJson.BackgroundColor3=CLR.pageBg; tabJson.TextColor3=Color3.fromRGB(130,130,155)
	tabLua.BackgroundColor3=CLR.pageBg;  tabLua.TextColor3=Color3.fromRGB(130,130,155)
	tabFx.BackgroundColor3=CLR.pageBg;   tabFx.TextColor3=Color3.fromRGB(130,130,155)
	if active=="json" then tabJson.BackgroundColor3=CLR.accent; tabJson.TextColor3=Color3.fromRGB(10,10,20)
	elseif active=="lua" then tabLua.BackgroundColor3=CLR.accent; tabLua.TextColor3=Color3.fromRGB(10,10,20)
	elseif active=="fx" then tabFx.BackgroundColor3=CLR.orange; tabFx.TextColor3=Color3.fromRGB(20,10,0)
	end
end

local function refreshOutput()
	if not selectedInst then return end
	clearPageBtns(); currentPages={}
	setAllTabStyles(currentTab)
	applyLayoutForTab(currentTab)

	if currentTab=="json" then
		local d=inclToggle and currentData or stripChildren(currentData)
		outText.Text=jsonEncode(d)
		outText.TextColor3=Color3.fromRGB(140,200,160)

	elseif currentTab=="lua" then
		-- Sinh code dạng function
		local ok, result = pcall(genFunctionCode, selectedInst, showComments)
		if ok then
			-- Chia trang
			local segs = buildSegmentsFn(result)
			currentPages = buildPages(segs, maxLinesPerPage)
			buildPageUI()
		else
			outText.Text = "-- Lỗi generate:\n-- "..tostring(result)
			outText.TextColor3 = Color3.fromRGB(255,80,80)
		end

	elseif currentTab=="fx" then
		local ok, result = pcall(genSmartFX, selectedInst, fxEffectOnly, showComments)
		if ok then
			local segs = buildSegmentsFn(result)
			currentPages = buildPages(segs, maxLinesPerPage)
			buildPageUI()
			-- Đếm thống kê
			local nFx,nAtt=0,0
			local function countFx(inst2)
				for _,c in ipairs(inst2:GetChildren()) do
					if EFFECT_CLASSES[c.ClassName] then nFx=nFx+1 end
					if ATTACHMENT_CLASSES[c.ClassName] then nAtt=nAtt+1 end
					if BASEPART_SET[c.ClassName] or c.ClassName=="Model" then countFx(c) end
				end
			end
			countFx(selectedInst)
			pageInfoLabel.Text=string.format("%d fx | %d att",nFx,nAtt)
		else
			outText.Text = "-- Lỗi FX:\n-- "..tostring(result)
			outText.TextColor3 = Color3.fromRGB(255,80,80)
		end
	end
end

-- ==================== TAB BUTTONS ====================

local function setTab(tab)
	currentTab=tab
	refreshOutput()
end

tabJson.MouseButton1Click:Connect(function() setTab("json") end)
tabLua.MouseButton1Click:Connect(function() setTab("lua") end)
tabFx.MouseButton1Click:Connect(function() setTab("fx") end)

commentBtn.MouseButton1Click:Connect(function()
	showComments=not showComments
	commentBtn.Text=showComments and "-- on" or "-- off"
	commentBtn.BackgroundColor3=showComments and Color3.fromRGB(0,80,60) or CLR.pageBg
	commentBtn.TextColor3=showComments and CLR.green or Color3.fromRGB(130,130,155)
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
		maxLinesPerPage=math.floor(v);refreshOutput()
		applyBtn.Text="✅";task.wait(1);applyBtn.Text="Apply"
	else
		maxLinesBox.Text=tostring(maxLinesPerPage)
	end
end)

fxOnlyBtn.MouseButton1Click:Connect(function()
	fxEffectOnly=not fxEffectOnly
	if fxEffectOnly then
		fxOnlyBtn.Text="ON"
		fxOnlyBtn.BackgroundColor3=Color3.fromRGB(0,80,60)
		fxOnlyBtn.TextColor3=CLR.green
	else
		fxOnlyBtn.Text="OFF"
		fxOnlyBtn.BackgroundColor3=CLR.pageBg
		fxOnlyBtn.TextColor3=Color3.fromRGB(130,130,155)
	end
	if currentTab=="fx" then refreshOutput() end
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
applyLayoutForTab("json")
task.spawn(buildTree)
