local LatencyMonitorClient = {}

function LatencyMonitorClient:new()	
	local inst = {
	}
	setmetatable(inst, self)
	self.__index = self
	
	local lc = game.ReplicatedStorage:WaitForChild("LatencyMonitor")
	local player = game.Players.LocalPlayer
	
	-- Checking for "Connected-" .. player.UserId isn't actually necessary but is here as a
	-- harmless validation.
	-- Appending the player.UserId isn't needed when FilteringEnabled is true. When
	-- FilteringEnabled is false however, it allows us to validate that each player has their own
	-- OnClientInvoke handler.
	if (lc:WaitForChild("PingClient"):FindFirstChild("Connected-" .. player.UserId) == nil) then
		lc.PingClient.OnClientInvoke = function()			
			return tick()
		end
		
		local connected = Instance.new("BoolValue", lc.PingClient)
		connected.Name = "Connected-" .. player.UserId
		connected.Value = true
	end
	
	return inst
end

return LatencyMonitorClient:new()
