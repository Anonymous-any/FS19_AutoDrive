AutoDriveCourseDownloadEvent = {};
AutoDriveCourseDownloadEvent_mt = Class(AutoDriveCourseDownloadEvent, Event);

InitEventClass(AutoDriveCourseDownloadEvent, "AutoDriveCourseDownloadEvent");

function AutoDriveCourseDownloadEvent:emptyNew()
	local self = Event:new(AutoDriveCourseDownloadEvent_mt);
	self.className="AutoDriveCourseDownloadEvent";
	return self;
end;

function AutoDriveCourseDownloadEvent:new(vehicle)
	local self = AutoDriveCourseDownloadEvent:emptyNew()
	self.vehicle = vehicle;
	return self;
end;

function AutoDriveCourseDownloadEvent:writeStream(streamId, connection)
	if AutoDrive == nil then
		return;
	end;
	
	if g_server ~= nil or AutoDrive.playerSendsMapToServer == true then
		streamWriteInt16(streamId, AutoDrive.requestedWaypointCount);

		AutoDrive:writeWaypointsToStream(	
			streamId, 
			AutoDrive.requestedWaypointCount, 
			math.min(AutoDrive.requestedWaypointCount + (AutoDrive.WAYPOINTS_PER_PACKET -1), AutoDrive.mapWayPointsCounter)
		)

		--print("Broadcasting waypoints from " .. AutoDrive.requestedWaypointCount .. " to " ..  math.min(AutoDrive.requestedWaypointCount + (AutoDrive.WAYPOINTS_PER_PACKET -1), AutoDrive.mapWayPointsCounter));
				
		if g_server ~= nil then
			for userID, user in pairs(AutoDrive.Server.Users) do
				user.ackReceived = false;
			end;
		end;

		if (AutoDrive.requestedWaypointCount + AutoDrive.WAYPOINTS_PER_PACKET) >= AutoDrive.mapWayPointsCounter then
			AutoDrive:writeMapMarkersToStream(streamId);			
		else
			streamWriteFloat32(streamId, 0);
		end;		
	else
		--print("Requesting waypoints");
		streamWriteInt32(streamId, NetworkUtil.getObjectId(self.vehicle));
	end;
end;

function AutoDriveCourseDownloadEvent:readStream(streamId, connection)
	--print("Received Event");
	if AutoDrive == nil then
		return;
	end;

	local lowestID = streamReadInt16(streamId);
	local numberOfWayPoints = streamReadFloat32(streamId);
	
	if AutoDrive.receivedWaypoints ~= true then
		AutoDrive.receivedWaypoints = true;
		if numberOfWayPoints > 0 then
			AutoDrive.mapWayPoints = {};
		end;
	end;

	if lowestID == 1 then
		AutoDrive.mapWayPoints = {};
		AutoDrive.mapMarker = {};
	end;
	
	AutoDrive:readWayPointsFromStream(streamId, numberOfWayPoints)

	AutoDrive.highestIndex = math.max(1, AutoDrive:getHighestConsecutiveIndex());
	AutoDrive.mapWayPointsCounter = AutoDrive.highestIndex;

	local numberOfMapMarkers = streamReadFloat32(streamId);

	if (numberOfMapMarkers ~= nil) and (numberOfMapMarkers > 0) then
		AutoDrive.mapMarker = {}
		if AutoDrive.Recalculation ~= nil then
			AutoDrive.Recalculation.continue = false; --used to signal a client that recalculation is over
		end;
		--print("Received mapMarkers: " .. numberOfMapMarkers);
		
		AutoDrive:readMapMarkerFromStream(streamId, numberOfMapMarkers)
	end;


	if g_server == nil then
		AutoDriveAcknowledgeCourseUpdateEvent:sendEvent(AutoDrive.highestIndex);
	end;
end;

function AutoDriveCourseDownloadEvent:sendEvent(vehicle)
	if g_server ~= nil then
		g_server:broadcastEvent(AutoDriveCourseDownloadEvent:new(vehicle), nil, nil, nil);
		AutoDrive.requestedWaypointCount = math.min(AutoDrive.requestedWaypointCount + AutoDrive.WAYPOINTS_PER_PACKET, AutoDrive.mapWayPointsCounter);
	else
		g_client:getServerConnection():sendEvent(AutoDriveCourseDownloadEvent:new(vehicle));
		AutoDrive.requestedWaypointCount = math.min(AutoDrive.requestedWaypointCount + AutoDrive.WAYPOINTS_PER_PACKET, AutoDrive.mapWayPointsCounter);
	end;
end;
