--[=[
	@class TieDefinition
]=]

local require = require(script.Parent.loader).load(script)

local RunService = game:GetService("RunService")

local Brio = require("Brio")
local Maid = require("Maid")
local Observable = require("Observable")
local Rx = require("Rx")
local RxBrioUtils = require("RxBrioUtils")
local RxInstanceUtils = require("RxInstanceUtils")
local String = require("String")
local Symbol = require("Symbol")
local Table = require("Table")
local TieImplementation = require("TieImplementation")
local TieInterface = require("TieInterface")
local TieMethodDefinition = require("TieMethodDefinition")
local TiePropertyDefinition = require("TiePropertyDefinition")
local TieSignalDefinition = require("TieSignalDefinition")
local ValueObject = require("ValueObject")

local UNSET_VALUE = Symbol.named("unsetValue")

local TieDefinition = {}
TieDefinition.ClassName = "TieDefinition"
TieDefinition.__index = TieDefinition

TieDefinition.Types = Table.readonly({
	METHOD = "method";
	SIGNAL = "signal";
	PROPERTY = "valueobject";
})

function TieDefinition.new(definitionName, methods)
	local self = setmetatable({}, TieDefinition)

	self._definitionName = assert(definitionName, "No definitionName")
	self._memberMap = {}

	for memberName, memberType in pairs(methods) do
		assert(type(memberName) == "string", "Bad memberName")

		if memberType == TieDefinition.Types.METHOD then
			self._memberMap[memberName] = TieMethodDefinition.new(self, memberName)
		elseif memberType == TieDefinition.Types.SIGNAL then
			self._memberMap[memberName] = TieSignalDefinition.new(self, memberName)
		elseif memberType == TieDefinition.Types.PROPERTY then
			self._memberMap[memberName] = TiePropertyDefinition.new(self, memberName)
		else
			error(("Bad memberType %q for member %q for %q"):format(
				tostring(memberType), tostring(memberName), self._definitionName))
		end
	end

	return self
end

--[=[
	Returns true if the adornee implements the interface, and false otherwise.
	@param adornee Instance
	@return boolean
]=]
function TieDefinition:HasImplementation(adornee: Instance)
	assert(typeof(adornee) == "Instance", "Bad adornee")

	local folder = adornee:FindFirstChild(self:GetContainerName())
	if not folder then
		return false
	end

	return self:_checkImplementation(folder)
end

--[=[
	Observes whether the adornee implements the interface.
	@param adornee Instance
	@return Observable<boolean>>
]=]
function TieDefinition:ObserveIsImplemented(adornee: Instance): boolean
	assert(typeof(adornee) == "Instance", "Bad adornee")

	return self:ObserveImplementationBrio(adornee)
		:Pipe({
			RxBrioUtils.map(function(result)
				return result and true or false
			end);
			RxBrioUtils.emitOnDeath(false);
			Rx.defaultsTo(false);
			Rx.distinct();
		})
end

--[=[
	Observes a valid implementation wrapped in a brio if it exists.
	@param adornee Instance
	@return Observable<Brio<TieImplementation<T>>>
]=]
function TieDefinition:ObserveImplementationBrio(adornee: Instance)
	assert(typeof(adornee) == "Instance", "Bad adornee")

	return RxInstanceUtils.observeLastNamedChildBrio(adornee, "Folder", self:GetContainerName())
		:Pipe({
			RxBrioUtils.switchMapBrio(function(folder)
				return Observable.new(function(sub)
					-- Bind to all children, instead of individually. This is a
					-- performance gain.

					local maid = Maid.new()

					local update
					do
						local isImplemented = ValueObject.new(UNSET_VALUE)
						maid:GiveTask(isImplemented)

						maid:GiveTask(isImplemented.Changed:Connect(function()
							maid._brio = nil

							if isImplemented.Value then
								local brio = Brio.new(self:Get(adornee))
								sub:Fire(brio)
								maid._brio = brio
							else
								maid._brio = nil
							end
						end))

						function update()
							isImplemented.Value = self:_checkImplementation(folder)
						end
					end

					maid:GiveTask(folder.ChildAdded:Connect(function(child)
						maid[child] = child:GetPropertyChangedSignal("Name"):Connect(update)
						update()
					end))

					maid:GiveTask(folder.ChildRemoved:Connect(function(child)
						maid[child] = nil
						update()
					end))

					for _, child in pairs(folder:GetChildren()) do
						maid[child] = child:GetPropertyChangedSignal("Name"):Connect(update)
					end

					update()

					return maid
				end)
			end)
		})
end

--[=[
	Ensures implementation of the object, binding table values and Lua OOP objects
	to Roblox objects that can be invoked generally.

	@param adornee Instance -- Adornee to implement interface on
	@param implementer table -- Table with all interface values
	@return TieImplementation<T>
]=]
function TieDefinition:Implement(adornee: Instance, implementer)
	assert(typeof(adornee) == "Instance", "Bad adornee")
	assert(type(implementer) == "table", "Bad implementer")

	return TieImplementation.new(self, adornee, implementer)
end

--[=[
	Gets an interface to the tie definition. Not this can be done
	on any Roblox instance. If the instance does not implement the interface,
	invoking interface methods, or querying the interface will result
	in errors.

	@param adornee Instance -- Adornee to get interface on
	@return TieInterface<T>
]=]
function TieDefinition:Get(adornee: Instance)
	assert(typeof(adornee) == "Instance", "Bad adornee")

	return TieInterface.new(self, adornee)
end

--[=[
	Gets the name of the definition
	@return string
]=]
function TieDefinition:GetName(): string
	return self._definitionName
end

function TieDefinition:GetContainerName(): string
	if RunService:IsClient() then
		return self._definitionName .. "Client"
	else
		return self._definitionName
	end
end

function TieDefinition:GetMemberMap()
	return self._memberMap
end

function TieDefinition:_checkImplementation(folder)
	local children = {}
	for _, item in pairs(folder:GetChildren()) do
		children[item.Name] = item
	end

	for memberName, member in pairs(self._memberMap) do
		local found = children[memberName]
		if not found then
			return false
		end

		if member.ClassName == "TieMethodDefinition" then
			if not found:IsA("BindableFunction") then
				return false
			end
		elseif member.ClassName == "TieSignalDefinition" then
			if not found:IsA("BindableEvent") then
				return false
			end
		elseif member.ClassName == "TiePropertyDefinition" then
			if not (found:IsA("BindableFunction") or String.endsWith(found.ClassName, "Value")) then
				return false
			end
		else
			error("Unknown member type")
		end
	end

	return true
end

return TieDefinition