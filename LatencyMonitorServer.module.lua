------------------------------
-- LatencyMonitorServer (LMS)
-- Monitors player latency
------------------------------

-- Used to hold the LMS type definition
local LatencyMonitorServer = {}

---- (Simulated) Private Static Fields -----------------------
-- Lua doesn't actually have access modifiers such as private, public or protected. These are just
-- "closed over" by functions below (AKA closures) rather than added directly on the LMS singleton
-- instance therefore simulating access control.

-- Used to hold a reference to the LMS singleton
local monitor

-- This is a dictionary and linked list container that will store latency information for each
-- active player
local entries = { First = nil, Last = nil }

-- Used to hold a reference to the PingClient remote function
local pingClient

-- Instead of sending a ping out to all active players at once, LMS will ping one 
-- player at a time at the rate specified in LMS.LatencyInterval divided by the
-- number of active players. This field is used directly by wait() so its value
-- is stored as seconds while the value of the public LMS.LatencyInterval property
-- is stored as milliseconds.
local pingInterval = 1

-------------------------------------------------------------

---- Constructor --------------------------------------------

-- This constuctor is actually unnecessary since LMS is a singleton but I generally follow OOP
-- design so here it is.
function LatencyMonitorServer:new()
	-- This bit is to support OOP in Lua. The inst variable holds the object actually returned by
	-- this constructor function.
	local inst = {
		---- Public Properties ------------------------------
		
		-- How frequently (in milliseconds) to update latency of the entire set of active players.
		-- So if LatencyInterval is 1000 milliseconds and there are 10 active players, pingInterval
		-- will be (1000 / 10) or 100 milliseconds. This means that while there are still 10 active
		-- players, LMS will send a ping to one player at a time, every 100 milliseconds (roughly).
		LatencyInterval = 1000
		
		-----------------------------------------------------
	}
	-- Lookup "Lua OOP" to learn about the next two lines (or better yet, read
	-- http://lua-users.org/wiki/InheritanceTutorial)
	setmetatable(inst, self)
	self.__index = self
	
	-- Create PingClient remote function
	if (game.ReplicatedStorage:FindFirstChild("LatencyMonitor") == nil) then
		local lm = Instance.new("Folder")
		lm.Name = "LatencyMonitor"
		
		pingClient = Instance.new("RemoteFunction", lm)
		pingClient.Name = "PingClient"	
		
		lm.Parent = game.ReplicatedStorage
		
		-- Register player added/removed event handlers
		game.Players.PlayerAdded:Connect(registerPlayer)
		game.Players.PlayerRemoving:Connect(unregisterPlayer)
	end
	
	return inst
end

-----------------------------------------------------------------

---- (Simulated) Private Methods --------------------------------

-- Updates the pingInterval based on the LatencyInterval and the number of active players
function updatePingInterval()
	if (game.Players.NumPlayers > 0) then
		pingInterval = (monitor.LatencyInterval / game.Players.NumPlayers) / 1000
	else
		pingInterval = 1
	end
end

-- Adds a new player entry to the entries dictionary/linked list container
function registerPlayer(player)
	if (entries[player.UserId] ~= nil) then
		error("Player with UserId ", player.UserId, " already registered.")
	end

	local playerEntry = { 
		ID = player.UserId, 
		Samples = 0, 
		AvgLatency = 0, 
		AvgTickOffset = 0 
	}
	entries[player.UserId] = playerEntry	
	
	-- Setup linked list to ease iterating over player entries
	-- and clean up of entries when players leave
	if (entries.First == nil) then
		entries.First = playerEntry
	end
	
	if (entries.Last ~= nil) then
		entries.Last.Next = playerEntry
		playerEntry.Prev = entries.Last
	end
	
	entries.Last = playerEntry
	
	updatePingInterval()
	
	print("Monitoring player ", playerEntry.ID, "... ")
end

-- Removes a player entry from the entries dictionary/linked list container
function unregisterPlayer(player)
	local entry = entries[player.UserId]
	
	-- clean up linked list
	if (entries.First == entry) then
		entries.First = entry.Next
	end
	
	if (entries.Last == entry) then
		entries.Last = entry.Prev
	end
	
	if (entry.Prev ~= nil) then
		entry.Prev.Next = entry.Next
	end
	
	if (entry.Next ~= nil) then
		entry.Next.Prev = entry.Prev
	end

	entries[player.UserId] = nil
	
	updatePingInterval()
	
	print("Player ", entry.ID, " removed from monitoring.")
end

-- The LMS main loop
function monitorLatency()
	local nextPlayerEntry
	local player
	local pingClientCompleted
	local result
	local entry
	local pingSentTick
	local clientTick
	while wait(pingInterval) do	
		if (nextPlayerEntry == nil and entries.First ~= nil) then
			nextPlayerEntry = entries.First
			updatePingInterval()
		end

		player = nil
		if (nextPlayerEntry ~= nil) then				
			player = game.Players:GetPlayerByUserId(nextPlayerEntry.ID)
		end
		
		-- Double-check player here before using it. If a user leaves the game while
		-- monitorLatency() is running, game.Players will be updated even though the
		-- game.Players.PlayerRemoving event hasn't been called yet so LMS hasn't had a chance to
		-- update the dictionary yet to prevent the loop from checking this player. 
		if (player ~= nil) then
			entry = nextPlayerEntry
			
			-- Record when the ping request was sent
			pingSentTick = tick()
			
			-- Call PingClient on the player's Roblox instance
			-- In the Roblox wiki, InvokeClient is typically called using 
			-- pcall(function() remoteFunction:InvokeClient()).
			-- Here, I'm avoiding the unnecessary anonymous function which would also cause an
			-- unnecessary memory allocation and garbage collection for each call to the remote 
			-- functon. The ":" operator simply passes the instance to the left of the operator as 
			-- the first parameter to the function on the right of the operator. We can do that
			-- manually and accomplish the same thing. 
			pingClientCompleted, result = pcall(pingClient.InvokeClient, pingClient, player)
			
			if (not pingClientCompleted) then
				print("Failed to ping player ", entry.ID, ". ERROR: ", result)
				nextPlayerEntry = nextPlayerEntry.Next
			else
				clientTick = result
	
				-- Record when the pong was received
				local pongReceivedTick = tick()
				
				if (entry.Samples < 5) then
					entry.Samples = entry.Samples + 1
				end
	
				local latency = pongReceivedTick - pingSentTick 
				local tickOffset = pongReceivedTick - clientTick -- change to AvgLatency?
		
				-- Running average over up to 5 samples		
				local avgLatency = entry.AvgLatency
				local samples = entry.Samples
				avgLatency = avgLatency - (avgLatency / samples)
				avgLatency = avgLatency + (latency / samples)
				entry.AvgLatency = avgLatency
				
				local avgTickOffset = entry.AvgTickOffset
				avgTickOffset = avgTickOffset - (avgTickOffset / samples)
				avgTickOffset = avgTickOffset +  (tickOffset / samples)
				entry.AvgTickOffset = avgTickOffset
				
				print("Player ", entry.ID, " - PingTx: ", pingSentTick, 
					"; ClientTick: ", clientTick,				
					"; PongRx: ", pongReceivedTick,
					"; Latency: ", latency,
					"; AvgLatency: ", avgLatency,
					"; TickOffset: ", tickOffset,
					"; AvgTickOffset: ", avgTickOffset, 
					"; Samples: ", samples)
				
				-- On the next iteration, use the next player entry
			end
			nextPlayerEntry = entry.Next
		else
			-- Either nextPlayerEntry is nil and there are no players to retrieve, or the player
			-- that was about to be pinged left during this call to monitorLatency() but before the
			-- the check to see if the player was valid, so we need to advance to the next player 
			-- entry provided that nextPlayerEntry isn't already nil.
			if (nextPlayerEntry ~= nil) then
				nextPlayerEntry = nextPlayerEntry.Next
			end
		end
	end
end

-----------------------------------------------------------------

monitor = LatencyMonitorServer:new()

-- spawn() will cause monitorLatency() to be executed AFTER this module script returns the LMS
-- singleton
spawn(monitorLatency)

return monitor
