-- Workspace Explorer UI + Export
-- LocalScript trong StarterGui
-- Version 2.0 — Full Property Serialization

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

-- ==================== Serialize ====================

-- Helper convert types sang serializable
local function serializeValue(val)
	local t = typeof(val)
	if t == "Vector3" then
		return {_t="Vector3", x=val.X, y=val.Y, z=val.Z}
	elseif t == "Vector2" then
		return {_t="Vector2", x=val.X, y=val.Y}
	elseif t == "Color3" then
		return {_t="Color3", r=math.floor(val.R*255), g=math.floor(val.G*255), b=math.floor(val.B*255)}
	elseif t == "BrickColor" then
		return {_t="BrickColor", name=tostring(val)}
	elseif t == "UDim2" then
		return {_t="UDim2", xs=val.X.Scale, xo=val.X.Offset, ys=val.Y.Scale, yo=val.Y.Offset}
	elseif t == "UDim" then
		return {_t="UDim", s=val.Scale, o=val.Offset}
	elseif t == "CFrame" then
		local x,y,z,r00,r01,r02,r10,r11,r12,r20,r21,r22 = val:GetComponents()
		return {_t="CFrame", x=x,y=y,z=z,r00=r00,r01=r01,r02=r02,r10=r10,r11=r11,r12=r12,r20=r20,r21=r21,r22=r22}
	elseif t == "NumberRange" then
		return {_t="NumberRange", min=val.Min, max=val.Max}
	elseif t == "NumberSequence" then
		local kps = {}
		for _, kp in ipairs(val.Keypoints) do
			table.insert(kps, {t=kp.Time, v=kp.Value, e=kp.Envelope})
		end
		return {_t="NumberSequence", keypoints=kps}
	elseif t == "ColorSequence" then
		local kps = {}
		for _, kp in ipairs(val.Keypoints) do
			table.insert(kps, {t=kp.Time, r=math.floor(kp.Value.R*255), g=math.floor(kp.Value.G*255), b=math.floor(kp.Value.B*255)})
		end
		return {_t="ColorSequence", keypoints=kps}
	elseif t == "EnumItem" then
		return {_t="Enum", name=tostring(val)}
	elseif t == "boolean" then
		return val
	elseif t == "number" then
		return math.floor(val*10000)/10000
	elseif t == "string" then
		return val
	else
		return tostring(val)
	end
end

-- Map className -> properties cần check
local PROP_MAP = {
	-- ===== BASE PARTS =====
	BasePart = {
		"Size","Position","CFrame","Color","BrickColor","Material","Transparency",
		"Reflectance","Anchored","CanCollide","CanTouch","CastShadow","Locked",
		"Massless","RootPriority",
	},
	Part = {
		"Shape",
	},
	MeshPart = {
		"MeshId","TextureID","MeshSize",
	},
	SpecialMesh = {
		"MeshId","TextureId","MeshType","Scale","Offset","VertexColor",
	},
	UnionOperation = {
		"UsePartColor",
	},
	CornerWedgePart = {},
	WedgePart = {},
	TrussPart = {
		"Style",
	},
	-- ===== TEXTURES =====
	Texture = {
		"Texture","Color3","Transparency","StudsPerTileU","StudsPerTileV",
		"OffsetStudsU","OffsetStudsV","Face",
	},
	Decal = {
		"Texture","Color3","Transparency","Face","ZIndex",
	},
	-- ===== VFX =====
	ParticleEmitter = {
		"Texture","Color","Size","Transparency","LightEmission","LightInfluence",
		"Speed","SpreadAngle","Rate","Lifetime","Rotation","RotSpeed",
		"Acceleration","Drag","LockedToPart","EmissionDirection",
		"FlipbookFramerate","FlipbookLayout","FlipbookMode",
		"SquashAndStretch","WindAffectsDrag","ZOffset",
		"ShapeStyle","Shape","ShapeInOut","ShapePartial",
	},
	Beam = {
		"Attachment0","Attachment1","Color","Transparency","Width0","Width1",
		"FaceCamera","LightEmission","LightInfluence","Texture","TextureLength",
		"TextureMode","TextureSpeed","Segments","CurveSize0","CurveSize1",
		"ZOffset",
	},
	Trail = {
		"Attachment0","Attachment1","Color","Transparency","WidthScale",
		"LightEmission","LightInfluence","Texture","TextureLength","TextureMode",
		"Lifetime","MinLength","FaceCamera",
	},
	Smoke = {
		"Color","Opacity","RiseVelocity","Size","Enabled","TimeScale",
	},
	Fire = {
		"Color","SecondaryColor","Heat","Size","Enabled","TimeScale",
	},
	Sparkles = {
		"SparkleColor","Enabled","TimeScale",
	},
	-- ===== LIGHTS =====
	PointLight = {
		"Brightness","Color","Range","Enabled","Shadows",
	},
	SpotLight = {
		"Brightness","Color","Range","Angle","Face","Enabled","Shadows",
	},
	SurfaceLight = {
		"Brightness","Color","Range","Angle","Face","Enabled","Shadows",
	},
	-- ===== SOUNDS =====
	Sound = {
		"SoundId","Volume","PlaybackSpeed","Looped","Playing","RollOffMaxDistance",
		"RollOffMinDistance","RollOffMode","SpatialSound","TimePosition",
	},
	-- ===== CONSTRAINTS =====
	WeldConstraint = {
		"Part0","Part1","Enabled",
	},
	Motor6D = {
		"Part0","Part1","C0","C1","CurrentAngle","MaxVelocity",
	},
	HingeConstraint = {
		"Attachment0","Attachment1","ActuatorType","AngularSpeed","MotorMaxAcceleration",
		"MotorMaxTorque","TargetAngle","LowerAngle","UpperAngle","LimitsEnabled",
	},
	RodConstraint = {
		"Attachment0","Attachment1","Length","LimitAngle0","LimitAngle1","LimitsEnabled",
	},
	SpringConstraint = {
		"Attachment0","Attachment1","Coils","Damping","FreeLength","LimitsEnabled",
		"MaxLength","MinLength","Radius","Stiffness","Thickness",
	},
	-- ===== BODY MOVERS =====
	BodyVelocity = {
		"Velocity","MaxForce","P",
	},
	BodyPosition = {
		"Position","MaxForce","P","D",
	},
	BodyAngularVelocity = {
		"AngularVelocity","MaxTorque","P",
	},
	BodyGyro = {
		"CFrame","MaxTorque","P","D",
	},
	-- ===== GUI =====
	ScreenGui = {
		"Enabled","DisplayOrder","IgnoreGuiInset","ResetOnSpawn","ZIndexBehavior",
	},
	Frame = {
		"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency",
		"BorderColor3","BorderSizePixel","ClipsDescendants","Visible","ZIndex","LayoutOrder","Rotation",
	},
	TextLabel = {
		"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency",
		"BorderColor3","Visible","ZIndex","LayoutOrder","Rotation",
		"Text","TextColor3","TextTransparency","TextSize","Font","FontFace",
		"TextWrapped","TextScaled","TextXAlignment","TextYAlignment","RichText",
		"LineHeight","MaxVisibleGraphemes",
	},
	TextButton = {
		"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency",
		"BorderColor3","Visible","ZIndex","LayoutOrder","Rotation","AutoButtonColor",
		"Text","TextColor3","TextTransparency","TextSize","Font","FontFace",
		"TextWrapped","TextScaled","TextXAlignment","TextYAlignment","RichText",
		"Modal","Selected",
	},
	TextBox = {
		"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency",
		"Visible","ZIndex","LayoutOrder","Text","PlaceholderText","PlaceholderColor3",
		"TextColor3","TextSize","Font","ClearTextOnFocus","MultiLine","TextEditable",
	},
	ImageLabel = {
		"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency",
		"Visible","ZIndex","LayoutOrder","Rotation",
		"Image","ImageColor3","ImageTransparency","ScaleType","SliceCenter","TileSize",
		"ImageRectOffset","ImageRectSize","ResampleMode",
	},
	ImageButton = {
		"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency",
		"Visible","ZIndex","LayoutOrder","Rotation","AutoButtonColor",
		"Image","ImageColor3","ImageTransparency","ScaleType","HoverImage","PressedImage",
	},
	ScrollingFrame = {
		"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency",
		"Visible","ZIndex","CanvasSize","CanvasPosition","ScrollBarThickness",
		"ScrollBarImageColor3","ScrollBarImageTransparency","ScrollingDirection",
		"AutomaticCanvasSize","ElasticBehavior","HorizontalScrollBarInset","VerticalScrollBarInset",
	},
	ViewportFrame = {
		"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency",
		"Visible","ZIndex","Ambient","LightColor","LightDirection","ImageColor3","ImageTransparency",
	},
	VideoFrame = {
		"Position","Size","AnchorPoint","BackgroundColor3","BackgroundTransparency",
		"Visible","ZIndex","Video","Looped","Playing","Volume","TimePosition",
	},
	-- GUI LAYOUT
	UICorner = {"CornerRadius"},
	UIStroke = {"Color","Thickness","Transparency","LineJoinMode","ApplyStrokeMode"},
	UIGradient = {"Color","Transparency","Offset","Rotation"},
	UIPadding = {"PaddingTop","PaddingBottom","PaddingLeft","PaddingRight"},
	UIListLayout = {"FillDirection","HorizontalAlignment","VerticalAlignment","SortOrder","Padding","Wraps"},
	UIGridLayout = {"CellSize","CellPadding","FillDirection","HorizontalAlignment","VerticalAlignment","SortOrder","StartCorner"},
	UITableLayout = {"FillDirection","HorizontalAlignment","VerticalAlignment","SortOrder","Padding","FillEmptySpaceColumns","FillEmptySpaceRows","MajorAxis"},
	UISizeConstraint = {"MaxSize","MinSize"},
	UIAspectRatioConstraint = {"AspectRatio","AspectType","DominantAxis"},
	UIScale = {"Scale"},
	-- ===== MISC =====
	Model = {
		"PrimaryPart","LevelOfDetail","ModelLod",
	},
	SpawnLocation = {
		"Duration","Enabled","Neutral","TeamColor","AllowTeamChangeOnTouch",
	},
	Humanoid = {
		"MaxHealth","Health","WalkSpeed","JumpHeight","JumpPower","HipHeight",
		"AutoRotate","AutoJumpEnabled","DisplayDistanceType","HealthDisplayType",
		"NameDisplayDistance","HealthDisplayDistance","BreakJointsOnDeath",
	},
	HumanoidDescription = {
		"HatAccessory","HairAccessory","FaceAccessory","NeckAccessory","ShouldersAccessory",
		"FrontAccessory","BackAccessory","WaistAccessory","Face","Head","Torso",
		"RightArm","LeftArm","RightLeg","LeftLeg","BodyTypeScale","HeadScale",
		"HeightScale","ProportionScale","WidthScale","GraphicTShirt",
	},
	Attachment = {
		"Position","Orientation","CFrame","WorldPosition","WorldCFrame","Visible",
	},
	BillboardGui = {
		"Adornee","Active","AlwaysOnTop","ClipsDescendants","Enabled",
		"Size","SizeOffset","StudsOffset","StudsOffsetWorldSpace",
		"ExtentsOffset","ExtentsOffsetWorldSpace","LightInfluence",
		"MaxDistance","RenderInPassthrough",
	},
	SurfaceGui = {
		"Adornee","Active","AlwaysOnTop","ClipsDescendants","Enabled",
		"Face","PixelsPerStud","SizingMode","ToolPunchThroughDistance","ZOffset",
		"LightInfluence","MaxDistance",
	},
	SelectionBox = {
		"Adornee","Color3","LineThickness","SurfaceColor3","SurfaceTransparency","Visible",
	},
	SelectionSphere = {
		"Adornee","Color3","SurfaceColor3","SurfaceTransparency","Visible",
	},
	ClickDetector = {
		"MaxActivationDistance","CursorIcon",
	},
	ProximityPrompt = {
		"ActionText","ObjectText","HoldDuration","MaxActivationDistance",
		"RequiresLineOfSight","Style","UIOffset","KeyboardKeyCode","GamepadKeyCode","Enabled",
	},
	IntValue = {"Value"},
	NumberValue = {"Value"},
	StringValue = {"Value"},
	BoolValue = {"Value"},
	Vector3Value = {"Value"},
	CFrameValue = {"Value"},
	Color3Value = {"Value"},
	ObjectValue = {"Value"},
	-- Sky & atmosphere
	Sky = {
		"SkyboxBk","SkyboxDn","SkyboxFt","SkyboxLf","SkyboxRt","SkyboxUp",
		"MoonAngularSize","SunAngularSize","MoonTextureId","SunTextureId","StarCount","CelestialBodiesShown",
	},
	Atmosphere = {
		"Density","Offset","Color","Decay","Glare","Haze",
	},
	-- Animation
	Animation = {"AnimationId"},
	AnimationTrack = {},
}

-- Inherit BasePart props untuk semua BasePart subclasses
local BASE_PART_CLASSES = {
	"Part","MeshPart","UnionOperation","CornerWedgePart","WedgePart",
	"TrussPart","SpawnLocation","FlagStand",
}
for _, cls in ipairs(BASE_PART_CLASSES) do
	if not PROP_MAP[cls] then PROP_MAP[cls] = {} end
	for _, p in ipairs(PROP_MAP.BasePart) do
		table.insert(PROP_MAP[cls], p)
	end
end

local function getProps(inst)
	local result = {}
	local className = inst.ClassName

	-- Collect props từ class và parent classes
	local propsToCheck = {}
	local seen = {}

	local function addProps(cls)
		if PROP_MAP[cls] then
			for _, p in ipairs(PROP_MAP[cls]) do
				if not seen[p] then
					seen[p] = true
					table.insert(propsToCheck, p)
				end
			end
		end
	end

	addProps(className)
	-- Thêm BasePart nếu là part
	addProps("BasePart")

	for _, prop in ipairs(propsToCheck) do
		local ok, val = pcall(function()
			return inst[prop]
		end)
		if ok and val ~= nil then
			local serialized = serializeValue(val)
			if serialized ~= nil then
				result[prop] = serialized
			end
		end
	end

	return result
end

local function serialize(inst)
	local data = {
		ClassName = inst.ClassName,
		Name = inst.Name,
		Properties = getProps(inst),
		Children = {}
	}
	for _, child in ipairs(inst:GetChildren()) do
		table.insert(data.Children, serialize(child))
	end
	return data
end

-- ==================== Lua Code Generator ====================

local function valueToLua(val)
	if type(val) == "table" then
		local t = val._t
		if t == "Vector3" then
			return string.format("Vector3.new(%g, %g, %g)", val.x, val.y, val.z)
		elseif t == "Vector2" then
			return string.format("Vector2.new(%g, %g)", val.x, val.y)
		elseif t == "Color3" then
			return string.format("Color3.fromRGB(%d, %d, %d)", val.r, val.g, val.b)
		elseif t == "BrickColor" then
			return string.format('BrickColor.new("%s")', val.name)
		elseif t == "UDim2" then
			return string.format("UDim2.new(%g, %g, %g, %g)", val.xs, val.xo, val.ys, val.yo)
		elseif t == "UDim" then
			return string.format("UDim.new(%g, %g)", val.s, val.o)
		elseif t == "CFrame" then
			return string.format("CFrame.new(%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g)",
				val.x,val.y,val.z,val.r00,val.r01,val.r02,val.r10,val.r11,val.r12,val.r20,val.r21,val.r22)
		elseif t == "NumberRange" then
			return string.format("NumberRange.new(%g, %g)", val.min, val.max)
		elseif t == "NumberSequence" then
			local kps = {}
			for _, kp in ipairs(val.keypoints) do
				table.insert(kps, string.format("NumberSequenceKeypoint.new(%g,%g,%g)", kp.t, kp.v, kp.e))
			end
			return "NumberSequence.new({" .. table.concat(kps, ",") .. "})"
		elseif t == "ColorSequence" then
			local kps = {}
			for _, kp in ipairs(val.keypoints) do
				table.insert(kps, string.format("ColorSequenceKeypoint.new(%g,Color3.fromRGB(%d,%d,%d))", kp.t, kp.r, kp.g, kp.b))
			end
			return "ColorSequence.new({" .. table.concat(kps, ",") .. "})"
		elseif t == "Enum" then
			return val.name
		end
		return "nil"
	elseif type(val) == "boolean" then
		return tostring(val)
	elseif type(val) == "number" then
		return tostring(val)
	elseif type(val) == "string" then
		return string.format('"%s"', val:gsub('"', '\\"'))
	end
	return "nil"
end

local function generateLua(data, parentVar, depth)
	local indent = string.rep("    ", depth)
	local safeName = data.Name:gsub("[^%w]", "_")
	local varName = safeName .. "_" .. depth
	local lines = {}

	table.insert(lines, indent .. string.format('local %s = Instance.new("%s")', varName, data.ClassName))

	-- Properties
	for prop, val in pairs(data.Properties or {}) do
		local lua = valueToLua(val)
		if lua ~= "nil" then
			table.insert(lines, indent .. string.format('%s.%s = %s', varName, prop, lua))
		end
	end

	table.insert(lines, indent .. string.format('%s.Name = "%s"', varName, data.Name))
	table.insert(lines, indent .. string.format('%s.Parent = %s', varName, parentVar))

	-- Children
	for i, child in ipairs(data.Children or {}) do
		table.insert(lines, "")
		local childLines = generateLua(child, varName, depth + 1)
		for _, line in ipairs(childLines) do
			table.insert(lines, line)
		end
	end

	return lines
end

local function buildLuaCode(data)
	local lines = {
		"-- Generated by Workspace Explorer",
		string.format('-- Object: %s [%s]', data.Name, data.ClassName),
		"",
	}
	local bodyLines = generateLua(data, "workspace", 0)
	for _, l in ipairs(bodyLines) do
		table.insert(lines, l)
	end
	return table.concat(lines, "\n")
end

-- ==================== UI Setup ====================
local gui = Instance.new("ScreenGui")
gui.Name = "WorkspaceExplorer"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player.PlayerGui

-- Main frame (tree panel)
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 260, 0, 420)
mainFrame.Position = UDim2.new(0, 10, 0, 10)
mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 26)
mainFrame.BorderSizePixel = 0
mainFrame.Parent = gui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

-- Drop shadow effect
local shadow = Instance.new("ImageLabel")
shadow.Size = UDim2.new(1, 20, 1, 20)
shadow.Position = UDim2.new(0, -10, 0, -10)
shadow.BackgroundTransparency = 1
shadow.Image = "rbxassetid://6015897843"
shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
shadow.ImageTransparency = 0.5
shadow.ScaleType = Enum.ScaleType.Slice
shadow.SliceCenter = Rect.new(49, 49, 450, 450)
shadow.ZIndex = 0
shadow.Parent = mainFrame

-- Header
local header = Instance.new("Frame")
header.Size = UDim2.new(1, 0, 0, 34)
header.BackgroundColor3 = Color3.fromRGB(22, 33, 62)
header.BorderSizePixel = 0
header.ZIndex = 2
header.Parent = mainFrame
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 8)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -80, 1, 0)
title.Position = UDim2.new(0, 10, 0, 0)
title.BackgroundTransparency = 1
title.Text = "⬡ WORKSPACE"
title.TextColor3 = Color3.fromRGB(0, 212, 255)
title.TextSize = 11
title.Font = Enum.Font.Code
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 3
title.Parent = header

-- Toggle output panel button
local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(0, 66, 0, 22)
toggleBtn.Position = UDim2.new(1, -70, 0.5, -11)
toggleBtn.BackgroundColor3 = Color3.fromRGB(30, 50, 80)
toggleBtn.TextColor3 = Color3.fromRGB(0, 212, 255)
toggleBtn.Text = "{ } View"
toggleBtn.Font = Enum.Font.Code
toggleBtn.TextSize = 10
toggleBtn.BorderSizePixel = 0
toggleBtn.ZIndex = 3
toggleBtn.Parent = header
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 5)

-- Scroll frame (tree)
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, 0, 1, -82)
scroll.Position = UDim2.new(0, 0, 0, 34)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = Color3.fromRGB(0, 212, 255)
scroll.ZIndex = 2
scroll.Parent = mainFrame

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = scroll

-- Footer
local footer = Instance.new("Frame")
footer.Size = UDim2.new(1, 0, 0, 48)
footer.Position = UDim2.new(0, 0, 1, -48)
footer.BackgroundColor3 = Color3.fromRGB(18, 18, 32)
footer.BorderSizePixel = 0
footer.ZIndex = 2
footer.Parent = mainFrame

local exportBtn = Instance.new("TextButton")
exportBtn.Size = UDim2.new(0.58, -6, 0, 30)
exportBtn.Position = UDim2.new(0.42, 3, 0, 9)
exportBtn.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
exportBtn.TextColor3 = Color3.fromRGB(10, 10, 20)
exportBtn.Text = "📤 EXPORT"
exportBtn.Font = Enum.Font.Code
exportBtn.TextSize = 11
exportBtn.BorderSizePixel = 0
exportBtn.ZIndex = 3
exportBtn.Parent = footer
Instance.new("UICorner", exportBtn).CornerRadius = UDim.new(0, 6)

local clearBtn = Instance.new("TextButton")
clearBtn.Size = UDim2.new(0.42, -9, 0, 30)
clearBtn.Position = UDim2.new(0, 6, 0, 9)
clearBtn.BackgroundColor3 = Color3.fromRGB(35, 35, 60)
clearBtn.TextColor3 = Color3.fromRGB(130, 130, 155)
clearBtn.Text = "Clear"
clearBtn.Font = Enum.Font.Code
clearBtn.TextSize = 11
clearBtn.BorderSizePixel = 0
clearBtn.ZIndex = 3
clearBtn.Parent = footer
Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 6)

-- ==================== Output Panel ====================
local outputPanel = Instance.new("Frame")
outputPanel.Name = "OutputPanel"
outputPanel.Size = UDim2.new(0, 340, 0, 420)
outputPanel.Position = UDim2.new(0, 278, 0, 10)
outputPanel.BackgroundColor3 = Color3.fromRGB(10, 10, 20)
outputPanel.BorderSizePixel = 0
outputPanel.Visible = false
outputPanel.ZIndex = 2
outputPanel.Parent = gui
Instance.new("UICorner", outputPanel).CornerRadius = UDim.new(0, 8)

-- Output header
local outHeader = Instance.new("Frame")
outHeader.Size = UDim2.new(1, 0, 0, 34)
outHeader.BackgroundColor3 = Color3.fromRGB(20, 30, 55)
outHeader.BorderSizePixel = 0
outHeader.ZIndex = 3
outHeader.Parent = outputPanel
Instance.new("UICorner", outHeader).CornerRadius = UDim.new(0, 8)

-- Tab buttons
local tabJson = Instance.new("TextButton")
tabJson.Size = UDim2.new(0, 70, 0, 24)
tabJson.Position = UDim2.new(0, 6, 0.5, -12)
tabJson.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
tabJson.TextColor3 = Color3.fromRGB(10, 10, 20)
tabJson.Text = "{ } JSON"
tabJson.Font = Enum.Font.Code
tabJson.TextSize = 10
tabJson.BorderSizePixel = 0
tabJson.ZIndex = 4
tabJson.Parent = outHeader
Instance.new("UICorner", tabJson).CornerRadius = UDim.new(0, 5)

local tabLua = Instance.new("TextButton")
tabLua.Size = UDim2.new(0, 70, 0, 24)
tabLua.Position = UDim2.new(0, 80, 0.5, -12)
tabLua.BackgroundColor3 = Color3.fromRGB(35, 35, 60)
tabLua.TextColor3 = Color3.fromRGB(130, 130, 155)
tabLua.Text = "📜 Lua"
tabLua.Font = Enum.Font.Code
tabLua.TextSize = 10
tabLua.BorderSizePixel = 0
tabLua.ZIndex = 4
tabLua.Parent = outHeader
Instance.new("UICorner", tabLua).CornerRadius = UDim.new(0, 5)

-- Include children toggle
local inclLabel = Instance.new("TextLabel")
inclLabel.Size = UDim2.new(0, 110, 1, 0)
inclLabel.Position = UDim2.new(0, 155, 0, 0)
inclLabel.BackgroundTransparency = 1
inclLabel.Text = "☑ w/ Children"
inclLabel.TextColor3 = Color3.fromRGB(0, 212, 255)
inclLabel.TextSize = 10
inclLabel.Font = Enum.Font.Code
inclLabel.TextXAlignment = Enum.TextXAlignment.Left
inclLabel.ZIndex = 4
inclLabel.Parent = outHeader

local inclToggle = true

local inclBtn = Instance.new("TextButton")
inclBtn.Size = UDim2.new(0, 110, 1, 0)
inclBtn.Position = UDim2.new(0, 155, 0, 0)
inclBtn.BackgroundTransparency = 1
inclBtn.Text = ""
inclBtn.ZIndex = 5
inclBtn.Parent = outHeader

-- Copy button
local copyBtn = Instance.new("TextButton")
copyBtn.Size = UDim2.new(0, 50, 0, 24)
copyBtn.Position = UDim2.new(1, -56, 0.5, -12)
copyBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
copyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
copyBtn.Text = "Copy"
copyBtn.Font = Enum.Font.Code
copyBtn.TextSize = 10
copyBtn.BorderSizePixel = 0
copyBtn.ZIndex = 4
copyBtn.Parent = outHeader
Instance.new("UICorner", copyBtn).CornerRadius = UDim.new(0, 5)

-- Output text box (scrollable)
local outScroll = Instance.new("ScrollingFrame")
outScroll.Size = UDim2.new(1, 0, 1, -34)
outScroll.Position = UDim2.new(0, 0, 0, 34)
outScroll.BackgroundTransparency = 1
outScroll.BorderSizePixel = 0
outScroll.ScrollBarThickness = 3
outScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 120)
outScroll.ZIndex = 3
outScroll.Parent = outputPanel

local outText = Instance.new("TextBox")
outText.Size = UDim2.new(1, -12, 0, 0)
outText.Position = UDim2.new(0, 8, 0, 8)
outText.BackgroundTransparency = 1
outText.Text = "-- Chọn object để xem output"
outText.TextColor3 = Color3.fromRGB(100, 120, 150)
outText.TextSize = 10
outText.Font = Enum.Font.Code
outText.TextXAlignment = Enum.TextXAlignment.Left
outText.TextYAlignment = Enum.TextYAlignment.Top
outText.TextWrapped = true
outText.AutomaticSize = Enum.AutomaticSize.Y
outText.ZIndex = 4
outText.Parent = outScroll

outText:GetPropertyChangedSignal("TextBounds"):Connect(function()
	outScroll.CanvasSize = UDim2.new(0, 0, 0, outText.TextBounds.Y + 20)
end)

-- ==================== State ====================
local selectedRow = nil
local selectedInst = nil
local currentTab = "json" -- "json" | "lua"
local currentData = nil

local COLOR_SELECT = Color3.fromRGB(0, 51, 85)
local icons = {
	Part = "🟦", MeshPart = "🔷", UnionOperation = "🔶",
	Model = "📁", Folder = "📂",
	Script = "📜", LocalScript = "📜", ModuleScript = "📦",
	Camera = "📷", SpawnLocation = "🏁",
	ParticleEmitter = "✨", Beam = "〰", Trail = "〰",
	Fire = "🔥", Smoke = "💨", Sparkles = "⭐",
	PointLight = "💡", SpotLight = "💡", SurfaceLight = "💡",
	Sound = "🔊", Humanoid = "🧍",
	Frame = "▭", TextLabel = "Ⓣ", TextButton = "🔘",
	ImageLabel = "🖼", ScreenGui = "🖥",
	Attachment = "📌", WeldConstraint = "🔗",
	BillboardGui = "🪧", SurfaceGui = "🪧",
	ClickDetector = "👆", ProximityPrompt = "⚡",
	Sky = "🌅", Atmosphere = "🌫",
	Animation = "🎬", Animator = "🎬",
}

-- ==================== Output ====================
local function jsonEncode(val, depth)
	depth = depth or 0
	local indent = string.rep("  ", depth)
	local t = type(val)
	if t == "boolean" then return tostring(val)
	elseif t == "number" then return tostring(val)
	elseif t == "string" then return '"' .. val:gsub('"', '\\"'):gsub("\n", "\\n") .. '"'
	elseif t == "table" then
		-- Check array
		local isArray = #val > 0
		if isArray then
			local items = {}
			for _, v in ipairs(val) do
				table.insert(items, indent .. "  " .. jsonEncode(v, depth+1))
			end
			return "[\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "]"
		else
			local items = {}
			for k, v in pairs(val) do
				table.insert(items, indent .. '  "' .. tostring(k) .. '": ' .. jsonEncode(v, depth+1))
			end
			return "{\n" .. table.concat(items, ",\n") .. "\n" .. indent .. "}"
		end
	end
	return "null"
end

local function stripChildren(data)
	return {
		ClassName = data.ClassName,
		Name = data.Name,
		Properties = data.Properties,
		Children = {}
	}
end

local function refreshOutput()
	if not currentData then return end
	local displayData = inclToggle and currentData or stripChildren(currentData)

	if currentTab == "json" then
		outText.Text = jsonEncode(displayData)
		outText.TextColor3 = Color3.fromRGB(140, 200, 160)
	else
		outText.Text = buildLuaCode(displayData)
		outText.TextColor3 = Color3.fromRGB(180, 180, 220)
	end
end

-- Tab switching
local function setTab(tab)
	currentTab = tab
	if tab == "json" then
		tabJson.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
		tabJson.TextColor3 = Color3.fromRGB(10, 10, 20)
		tabLua.BackgroundColor3 = Color3.fromRGB(35, 35, 60)
		tabLua.TextColor3 = Color3.fromRGB(130, 130, 155)
	else
		tabLua.BackgroundColor3 = Color3.fromRGB(0, 212, 255)
		tabLua.TextColor3 = Color3.fromRGB(10, 10, 20)
		tabJson.BackgroundColor3 = Color3.fromRGB(35, 35, 60)
		tabJson.TextColor3 = Color3.fromRGB(130, 130, 155)
	end
	refreshOutput()
end

tabJson.MouseButton1Click:Connect(function() setTab("json") end)
tabLua.MouseButton1Click:Connect(function() setTab("lua") end)

inclBtn.MouseButton1Click:Connect(function()
	inclToggle = not inclToggle
	inclLabel.Text = inclToggle and "☑ w/ Children" or "☐ w/ Children"
	inclLabel.TextColor3 = inclToggle and Color3.fromRGB(0,212,255) or Color3.fromRGB(100,100,130)
	refreshOutput()
end)

copyBtn.MouseButton1Click:Connect(function()
	if outText.Text == "" then return end
	-- Roblox không có clipboard API trực tiếp, dùng setclipboard nếu có exploit
	-- Hoặc print ra Output để copy
	print("=== COPY OUTPUT ===")
	print(outText.Text)
	print("===================")
	copyBtn.Text = "✅ Done"
	copyBtn.BackgroundColor3 = Color3.fromRGB(0, 150, 100)
	task.wait(1.5)
	copyBtn.Text = "Copy"
	copyBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
end)

-- Toggle output panel
local panelOpen = false
toggleBtn.MouseButton1Click:Connect(function()
	panelOpen = not panelOpen
	outputPanel.Visible = panelOpen
	toggleBtn.Text = panelOpen and "✕ Close" or "{ } View"
	toggleBtn.BackgroundColor3 = panelOpen and Color3.fromRGB(60, 20, 20) or Color3.fromRGB(30, 50, 80)
	toggleBtn.TextColor3 = panelOpen and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(0, 212, 255)
end)

-- ==================== Tree ====================
local function selectRow(row, inst)
	if selectedRow then
		selectedRow.BackgroundTransparency = 1
	end
	selectedRow = row
	selectedInst = inst
	row.BackgroundTransparency = 0
	row.BackgroundColor3 = COLOR_SELECT

	-- Serialize và refresh output
	currentData = serialize(inst)
	refreshOutput()
end

local function makeRow(inst, depth)
	local hasChildren = #inst:GetChildren() > 0
	local icon = icons[inst.ClassName] or "📄"

	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, 0, 0, 22)
	row.BackgroundTransparency = 1
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = false
	row.ZIndex = 2
	row.Parent = scroll

	-- Indent fill
	local indentFill = Instance.new("Frame")
	indentFill.Size = UDim2.new(0, depth * 14, 1, 0)
	indentFill.BackgroundTransparency = 1
	indentFill.ZIndex = 2
	indentFill.Parent = row

	-- Arrow
	local arrow = Instance.new("TextButton")
	arrow.Size = UDim2.new(0, 14, 1, 0)
	arrow.Position = UDim2.new(0, depth * 14, 0, 0)
	arrow.BackgroundTransparency = 1
	arrow.Text = hasChildren and "▶" or ""
	arrow.TextColor3 = Color3.fromRGB(80, 80, 120)
	arrow.TextSize = 9
	arrow.Font = Enum.Font.Code
	arrow.BorderSizePixel = 0
	arrow.AutoButtonColor = false
	arrow.ZIndex = 3
	arrow.Parent = row

	-- Label
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -(depth * 14 + 18), 1, 0)
	label.Position = UDim2.new(0, depth * 14 + 18, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = icon .. " " .. inst.Name
	label.TextColor3 = Color3.fromRGB(190, 200, 220)
	label.TextSize = 11
	label.Font = Enum.Font.Code
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 3
	label.Parent = row

	-- Children
	local childRows = {}
	local open = false

	if hasChildren then
		for _, child in ipairs(inst:GetChildren()) do
			local childRow = makeRow(child, depth + 1)
			childRow.Visible = false
			table.insert(childRows, childRow)
		end

		arrow.MouseButton1Click:Connect(function()
			open = not open
			arrow.Text = open and "▼" or "▶"
			arrow.TextColor3 = open
				and Color3.fromRGB(0, 212, 255)
				or Color3.fromRGB(80, 80, 120)
			for _, cr in ipairs(childRows) do
				cr.Visible = open
			end
		end)
	end

	row.MouseButton1Click:Connect(function()
		selectRow(row, inst)
		label.TextColor3 = Color3.fromRGB(0, 212, 255)
		if selectedRow ~= row then
			label.TextColor3 = Color3.fromRGB(190, 200, 220)
		end
	end)

	return row
end

-- Build tree
for _, obj in ipairs(workspace:GetChildren()) do
	makeRow(obj, 0)
end

layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scroll.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y)
end)

-- ==================== Export (print to Output) ====================
exportBtn.MouseButton1Click:Connect(function()
	if not selectedInst then
		exportBtn.Text = "⚠ Chọn object!"
		task.wait(1.5)
		exportBtn.Text = "📤 EXPORT"
		return
	end

	exportBtn.Text = "⏳ Processing..."
	local data = serialize(selectedInst)
	local json = HttpService:JSONEncode(data)

	-- Print ra Output để copy paste vào web
	print("=== WORKSPACE EXPORT ===")
	print(json)
	print("========================")

	exportBtn.Text = "✅ Check Output!"
	task.wait(2.5)
	exportBtn.Text = "📤 EXPORT"
end)

clearBtn.MouseButton1Click:Connect(function()
	if selectedRow then
		selectedRow.BackgroundTransparency = 1
		selectedRow = nil
		selectedInst = nil
		currentData = nil
		outText.Text = "-- Chọn object để xem output"
		outText.TextColor3 = Color3.fromRGB(100, 120, 150)
	end
end)
