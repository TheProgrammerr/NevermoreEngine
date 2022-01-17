--[=[
	@class Viewport
]=]

local require = require(script.Parent.loader).load(script)

local BasicPane = require("BasicPane")
local Blend = require("Blend")
local ValueObject = require("ValueObject")
local CameraUtils = require("CameraUtils")
local AdorneeUtils = require("AdorneeUtils")
local Maid = require("Maid")
local Observable = require("Observable")
local ViewportControls = require("ViewportControls")
local SpringObject = require("SpringObject")
local CircleUtils = require("CircleUtils")

local MAX_PITCH = math.pi/3
local MIN_PITCH = -math.pi/3
local TAU = math.pi*2

local Viewport = setmetatable({}, BasicPane)
Viewport.ClassName = "Viewport"
Viewport.__index = Viewport

function Viewport.new()
	local self = setmetatable(BasicPane.new(), Viewport)

	self._current = ValueObject.new()
	self._maid:GiveTask(self._current)

	self._absoluteSize = ValueObject.new(Vector2.new())
	self._maid:GiveTask(self._absoluteSize)

	self._fieldOfView = ValueObject.new(20)
	self._maid:GiveTask(self._fieldOfView)

	self._rotationYawSpring = SpringObject.new(math.pi/4)
	self._rotationYawSpring.Speed = 30
	self._maid:GiveTask(self._rotationYawSpring)

	self._rotationPitchSpring = SpringObject.new(-math.pi/6)
	self._rotationPitchSpring.Speed = 30
	self._maid:GiveTask(self._rotationPitchSpring)

	return self
end

function Viewport.blend(props)
	assert(type(props) == "table", "Bad props")
	return Observable.new(function(sub)
		local maid = Maid.new()

		local viewport = Viewport.new()
		if props.FieldOfView then
			viewport:SetFieldOfView(props.FieldOfView)
		end

		if props.Instance then
			viewport:SetInstance(props.Instance)
		end

		maid:GiveTask(viewport:Render(props):Subscribe(function(result)
			sub:Fire(result)
		end))

		return maid
	end)
end

function Viewport:SetFieldOfView(fieldOfView)
	assert(type(fieldOfView) == "number", "Bad fieldOfView")

	self._fieldOfView.Value = fieldOfView
end

function Viewport:SetInstance(instance)
	assert(typeof(instance) == "Instance", "Bad instance")

	self._current.Value = instance
end

function Viewport:RotateBy(deltaV2, doNotAnimate)
	local target = (self._rotationYawSpring.Value + deltaV2.x) % TAU
	self._rotationYawSpring.Position = CircleUtils.updatePositionToSmallestDistOnCircle(self._rotationYawSpring.Position, target, TAU)

	self._rotationYawSpring.Target = target

	if doNotAnimate then
		self._rotationYawSpring.Position = self._rotationYawSpring.Target
	end

	self._rotationPitchSpring.Target = math.clamp(self._rotationPitchSpring.Value + deltaV2.y, MIN_PITCH, MAX_PITCH)
	if doNotAnimate then
		self._rotationPitchSpring.Position = self._rotationPitchSpring.Target
	end
end

function Viewport:Render(props)
	local currentCamera = ValueObject.new()

	return Blend.New "ViewportFrame" {
		Parent = props.Parent;
		Size = props.Size or UDim2.new(1, 0, 1, 0);
		AnchorPoint = props.AnchorPoint;
		Position = props.Position;
		LayoutOrder = props.LayoutOrder;
		BackgroundTransparency = 1;
		CurrentCamera = currentCamera;
		LightColor = props.LightColor or Color3.new(1, 1, 1);
		Ambient = props.Ambient or Color3.new(1, 1, 1);
		[Blend.OnChange "AbsoluteSize"] = self._absoluteSize;
		[Blend.Attached(function(viewport)
			return ViewportControls.new(viewport, self)
		end)] = true;
		[Blend.Children] = {
			self._current;
			Blend.New "Camera" {
				[Blend.Instance] = currentCamera;
				Name = "CurrentCamera";
				FieldOfView = self._fieldOfView;
				CFrame = Blend.Computed(self._current, self._absoluteSize, self._fieldOfView,
					self._rotationYawSpring:ObserveRenderStepped(),
					self._rotationPitchSpring:ObserveRenderStepped(),
					function(inst, absSize, fov, rotationYaw, rotationPitch)
						if typeof(inst) ~= "Instance" then
							return CFrame.new()
						end

						local aspectRatio = absSize.x/absSize.y
						local bbCFrame, bbSize = AdorneeUtils.getBoundingBox(inst)
						if not bbCFrame then
							return CFrame.new()
						end


						local fit = CameraUtils.fitBoundingBoxToCamera(bbSize, fov, aspectRatio)
						return CFrame.new(bbCFrame.p) * CFrame.Angles(0, rotationYaw, 0) * CFrame.Angles(rotationPitch, 0, 0) * CFrame.new(0, 0, fit)
					end);
			}
		}
	};
end

return Viewport