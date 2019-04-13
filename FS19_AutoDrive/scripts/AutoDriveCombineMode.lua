AutoDrive.COMBINE_UNINITIALIZED = 0;
AutoDrive.WAIT_FOR_COMBINE = 1;
AutoDrive.DRIVE_TO_COMBINE = 2;
AutoDrive.WAIT_TILL_UNLOADED = 3;
AutoDrive.DRIVE_TO_PARK_POS = 4;
AutoDrive.DRIVE_TO_START_POS = 5;
AutoDrive.DRIVE_TO_UNLOAD_POS = 6;
AutoDrive.UNLOAD_WAIT_TIMER = 15000;

function AutoDrive:handleCombineHarvester(vehicle, dt)    
    if vehicle.ad.currentDriver ~= nil then
        return;
    end;

    if vehicle.spec_dischargeable ~= nil then
        local leftCapacity = 0;
        local maxCapacity = 0;
        if vehicle.getFillUnits ~= nil then
            for fillUnitIndex,fillUnit in pairs(vehicle:getFillUnits()) do
                if vehicle:getFillUnitCapacity(fillUnitIndex) > 2000 then
                    maxCapacity = maxCapacity + vehicle:getFillUnitCapacity(fillUnitIndex);
                    leftCapacity = leftCapacity + vehicle:getFillUnitFreeCapacity(fillUnitIndex)
                end;
            end
        end;

        if maxCapacity > 0 and leftCapacity <= 1.0 and vehicle.lastSpeedReal <= 0.0005 then
            AutoDrive:callDriverToCombine(vehicle);
        end;
    end;
end;

function AutoDrive:callDriverToCombine(combine)
    local spec = combine.spec_pipe
    if spec.currentState == spec.targetState and spec.currentState == 2 then
    
        local worldX,worldY,worldZ = getWorldTranslation( combine.components[1].node );

        for _,dischargeNode in pairs(combine.spec_dischargeable.dischargeNodes) do
            local nodeX,nodeY,nodeZ = getWorldTranslation( dischargeNode.node );
            if ADTableLength(AutoDrive.waitingUnloadDrivers) > 0 then
                local closestDriver = nil;
                local closestDistance = math.huge;
                for _,driver in pairs(AutoDrive.waitingUnloadDrivers) do
                    local driverX, driverY, driverZ = getWorldTranslation( driver.components[1].node );
                    local distance = math.sqrt( math.pow((driverX-worldX),2) + math.pow((driverZ - worldZ), 2));
                    
                    if distance < closestDistance and (distance < 300 or driver.ad.targetSelected == combine.ad.targetSelected) then
                        closestDistance = distance;
                        closestDriver = driver;							
                    end;
                end;

                if closestDriver ~= nil then                    		
                    AutoDrivePathFinder:startPathPlanningToCombine(closestDriver, combine, dischargeNode.node);
                    closestDriver.ad.currentCombine = combine;
                    AutoDrive.waitingUnloadDrivers[closestDriver] = nil;
                    closestDriver.ad.combineState = AutoDrive.DRIVE_TO_COMBINE;
                    combine.ad.currentDriver = closestDriver;
                    closestDriver.ad.isPaused = false;
                    closestDriver.ad.isUnloading = false;
                    closestDriver.ad.isLoading = false;
                    closestDriver.ad.initialized = false 
                    closestDriver.ad.wayPoints = {};
                end;
            end;
        end;
    end;
end;

function AutoDrive:handleReachedWayPointCombine(vehicle)
    if vehicle.ad.combineState == AutoDrive.COMBINE_UNINITIALIZED then --register Driver as available unloader if target point is reached (Hopefully field position!)
        --print("Registering " .. vehicle.name .. " as driver");
        AutoDrive.waitingUnloadDrivers[vehicle] = vehicle;
        vehicle.ad.combineState = AutoDrive.WAIT_FOR_COMBINE;
        vehicle.ad.isPaused = true;
        vehicle.ad.wayPoints = {};
    elseif vehicle.ad.combineState == AutoDrive.DRIVE_TO_COMBINE then
        vehicle.ad.combineState = AutoDrive.WAIT_TILL_UNLOADED;
        vehicle.ad.initialized = false;
        vehicle.ad.wayPoints = {};
        vehicle.ad.isPaused = true;
    elseif vehicle.ad.combineState == AutoDrive.DRIVE_TO_PARK_POS then    
        AutoDrive.waitingUnloadDrivers[vehicle] = vehicle;
        vehicle.ad.combineState = AutoDrive.WAIT_FOR_COMBINE;
        --vehicle.ad.initialized = false;
        vehicle.ad.wayPoints = {};
        vehicle.ad.isPaused = true;
        if vehicle.ad.currentCombine ~= nil then
            vehicle.ad.currentCombine.ad.currentDriver = nil;
            vehicle.ad.currentCombine = nil;
        end;
    elseif vehicle.ad.combineState == AutoDrive.DRIVE_TO_START_POS then
        --local closest = vehicle.ad.wayPoints[vehicle.ad.currentWayPoint].id;
        local closest = AutoDrive:findClosestWayPoint(vehicle);
        vehicle.ad.wayPoints = AutoDrive:FastShortestPath(AutoDrive.mapWayPoints, closest, AutoDrive.mapMarker[vehicle.ad.mapMarkerSelected_Unload].name, AutoDrive.mapMarker[vehicle.ad.mapMarkerSelected_Unload].id);
        vehicle.ad.wayPointsChanged = true;
        vehicle.ad.currentWayPoint = 1;

        vehicle.ad.targetX = vehicle.ad.wayPoints[vehicle.ad.currentWayPoint].x;
        vehicle.ad.targetZ = vehicle.ad.wayPoints[vehicle.ad.currentWayPoint].z;
        if vehicle.ad.currentCombine ~= nil then
            vehicle.ad.currentCombine.ad.currentDriver = nil;
            vehicle.ad.currentCombine = nil;
        end;
        vehicle.ad.combineState = AutoDrive.DRIVE_TO_UNLOAD_POS;
    elseif vehicle.ad.combineState == AutoDrive.DRIVE_TO_UNLOAD_POS then
        vehicle.ad.timeTillDeadLock = 15000;

        local closest = vehicle.ad.wayPoints[vehicle.ad.currentWayPoint].id;
        vehicle.ad.wayPoints = AutoDrive:FastShortestPath(AutoDrive.mapWayPoints, closest, AutoDrive.mapMarker[vehicle.ad.mapMarkerSelected].name, vehicle.ad.targetSelected);
        vehicle.ad.wayPointsChanged = true;
        vehicle.ad.currentWayPoint = 1;

        vehicle.ad.targetX = vehicle.ad.wayPoints[vehicle.ad.currentWayPoint].x;
        vehicle.ad.targetZ = vehicle.ad.wayPoints[vehicle.ad.currentWayPoint].z;
        vehicle.ad.isPaused = true;                    
        vehicle.ad.combineState = AutoDrive.COMBINE_UNINITIALIZED;
        if vehicle.ad.currentCombine ~= nil then
            vehicle.ad.currentCombine.ad.currentDriver = nil;
            vehicle.ad.currentCombine = nil;
        end;
    end;
end;

function AutoDrive:initializeADCombine(vehicle, dt)   
    if vehicle.ad.wayPoints == nil or vehicle.ad.wayPoints[1] == nil then
        vehicle.ad.initialized = false;
        vehicle.ad.timeTillDeadLock = 15000;
        if vehicle.ad.combineState == AutoDrive.DRIVE_TO_COMBINE then
            if vehicle.ad.currentCombine ~= nil then
                AutoDrivePathFinder:updatePathPlanning(vehicle);

                if AutoDrivePathFinder:isPathPlanningFinished(vehicle) then
                    vehicle.ad.wayPoints = vehicle.ad.pf.wayPoints;
                    vehicle.ad.currentWayPoint = 1;
                else
                    return true;
                end;
            else
                return true;
            end;
        elseif vehicle.ad.combineState == AutoDrive.WAIT_TILL_UNLOADED then
            local maxCapacity = 0;
            local leftCapacity = 0;
            local trailers, trailerCount = AutoDrive:getTrailersOf(vehicle);     
            if trailerCount > 0 then        
                for _,trailer in pairs(trailers) do
                    if trailer.getFillUnits ~= nil then
                        for fillUnitIndex,fillUnit in pairs(trailer:getFillUnits()) do
                            if trailer:getFillUnitCapacity(fillUnitIndex) > 2000 then
                                maxCapacity = maxCapacity + trailer:getFillUnitCapacity(fillUnitIndex);
                                leftCapacity = leftCapacity + trailer:getFillUnitFreeCapacity(fillUnitIndex)
                            end;
                        end
                    end;
                end;
            end;

            local combineLeftCapacity = 0;
            local combineMaxCapacity = 0;
            if vehicle.ad.currentCombine.getFillUnits ~= nil then
                for fillUnitIndex,fillUnit in pairs(vehicle.ad.currentCombine:getFillUnits()) do
                    if vehicle.ad.currentCombine:getFillUnitCapacity(fillUnitIndex) > 2000 then
                        combineMaxCapacity = combineMaxCapacity + vehicle.ad.currentCombine:getFillUnitCapacity(fillUnitIndex);
                        combineLeftCapacity = combineLeftCapacity + vehicle.ad.currentCombine:getFillUnitFreeCapacity(fillUnitIndex)
                    end;
                end
            end;

            if (combineLeftCapacity == combineMaxCapacity) or leftCapacity <= 500 then
                if vehicle.ad.combineUnloadInFruit == true then
                    --wait for combine to move away. Currently by fixed timer of 15s
                    if vehicle.ad.combineUnloadInFruitWaitTimer > 0 then
                        vehicle.ad.combineUnloadInFruitWaitTimer = vehicle.ad.combineUnloadInFruitWaitTimer - dt;
                        return true;
                    end;
                end;                                       
                
                if leftCapacity < 4000 then
                    vehicle.ad.combineState = AutoDrive.DRIVE_TO_START_POS;
                    AutoDrivePathFinder:startPathPlanningToStartPosition(vehicle, vehicle.ad.currentCombine);
                    if vehicle.ad.currentCombine ~= nil then
                        vehicle.ad.currentCombine.ad.currentDriver = nil;
                        vehicle.ad.currentCombine = nil;
                    end;
                else
                    if vehicle.ad.combineUnloadInFruit == true then
                        vehicle.ad.combineState = AutoDrive.DRIVE_TO_PARK_POS;
                        --ToDo: plot path to suitable park pos;
                        AutoDrivePathFinder:startPathPlanningToStartPosition(vehicle, vehicle.ad.currentCombine);
                        if vehicle.ad.currentCombine ~= nil then
                            vehicle.ad.currentCombine.ad.currentDriver = nil;
                            vehicle.ad.currentCombine = nil;
                        end;
                    else
                        --wait in field
                        
                        AutoDrive.waitingUnloadDrivers[vehicle] = vehicle;
                        vehicle.ad.combineState = AutoDrive.WAIT_FOR_COMBINE;
                        --vehicle.ad.initialized = false;
                        vehicle.ad.wayPoints = {};
                        vehicle.ad.isPaused = true;
                        if vehicle.ad.currentCombine ~= nil then
                            vehicle.ad.currentCombine.ad.currentDriver = nil;
                            vehicle.ad.currentCombine = nil;
                        end;
                    end;
                end;
            end;

            return true;
        elseif vehicle.ad.combineState == AutoDrive.DRIVE_TO_START_POS then
            AutoDrivePathFinder:updatePathPlanning(vehicle);

            if AutoDrivePathFinder:isPathPlanningFinished(vehicle) then
                vehicle.ad.wayPoints = vehicle.ad.pf.wayPoints;
                vehicle.ad.currentWayPoint = 1;
            else
                return true;
            end;
        elseif vehicle.ad.combineState == AutoDrive.DRIVE_TO_PARK_POS then
            AutoDrivePathFinder:updatePathPlanning(vehicle);

            if AutoDrivePathFinder:isPathPlanningFinished(vehicle) then
                vehicle.ad.wayPoints = vehicle.ad.pf.wayPoints;
                vehicle.ad.currentWayPoint = 1;
            else
                return true;
            end;
        end;
    end; 

    return false;
end;

function AutoDrive:combineStateToDescription(vehicle)
    if vehicle.ad.combineState == AutoDrive.WAIT_FOR_COMBINE then
        return g_i18n:getText('ad_wait_for_combine');
    elseif vehicle.ad.combineState == AutoDrive.DRIVE_TO_COMBINE then
        return g_i18n:getText('ad_drive_to_combine');
    elseif vehicle.ad.combineState == AutoDrive.WAIT_TILL_UNLOADED then
        return g_i18n:getText('ad_unloading_combine');
    elseif vehicle.ad.combineState == AutoDrive.DRIVE_TO_PARK_POS then
        return g_i18n:getText('ad_drive_to_parkpos');
    elseif vehicle.ad.combineState == AutoDrive.DRIVE_TO_START_POS then
        return g_i18n:getText('ad_drive_to_startpos');
    elseif vehicle.ad.combineState == AutoDrive.DRIVE_TO_UNLOAD_POS then
        return g_i18n:getText('ad_drive_to_unloadpos');
    end

    return;
end;