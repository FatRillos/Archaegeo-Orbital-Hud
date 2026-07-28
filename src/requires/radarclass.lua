function RadarClass(c, s, u, radar_1, radar_2, warpdrive,
    mabs, sysDestWid, msqrt, svgText, tonum, coreHalfDiag, play, msg) -- Everything related to radar but draw data passed to HUD Class.
    local Radar = {}
    -- Radar Class locals

        local friendlies = {}
        local sizeMap = { XS = 13, S = 27, M = 55, L = 110, XL = 221}
        local cTypeString = {"Universe", "Planet", "Asteroid", "Static", "Dynamic", "Space", "Alien"}
        local knownContacts = {}
        local radarContacts = 0
        local target
        local numKnown
        local static = 0
        local activeRadar
        local radars = {activeRadar}
        local rType = "Atmo"
        local UpdateRadarCoroutine
        local perisPanelID
        local peris = 0
        local contacts = {}
        local radarData
        local lastPlay = 0
        local wreckChasePhase = 0 -- 0 idle, 1 braking to WreckChaseSpeed, 2 enroute to wreck
        local wreckChaseTarget
        local wreckChaseDist = 0
        local wreckChaseBraked = false
        local wreckChaseBurning = false
        local wreckVisited = {} -- vec3 positions of wrecks already visited; persisted to dbHud
    local function saveWreckVisited()
        if dbHud_1 then
            local parts = {}
            for i = 1, #wreckVisited do
                local v = wreckVisited[i]
                parts[#parts+1] = string.format("%.0f,%.0f,%.0f", v.x, v.y, v.z)
            end
            dbHud_1.setStringValue("WreckVisited", table.concat(parts, ";"))
        end
    end
    local function loadWreckVisited()
        if dbHud_1 and dbHud_1.hasKey("WreckVisited") == 1 then
            for entry in string.gmatch(dbHud_1.getStringValue("WreckVisited") or "", "([^;]+)") do
                local x, y, z = string.match(entry, "([-%d%.]+),([-%d%.]+),([-%d%.]+)")
                if x then wreckVisited[#wreckVisited+1] = vec3(tonum(x), tonum(y), tonum(z)) end
            end
        end
    end
    local function isWreckVisited(pos)
        for i = 1, #wreckVisited do
            if (wreckVisited[i] - pos):len() < 1000 then return true end
        end
        return false
    end
    local function markWreckVisited(pos)
        if isWreckVisited(pos) then return end
        wreckVisited[#wreckVisited+1] = pos
        if #wreckVisited > 30 then table.remove(wreckVisited, 1) end
        saveWreckVisited()
    end
        local insert = table.insert
        local activeRadarState = -4
        local radarStatus = {
            [1] = "Operational",
            [0] = "broken",
            [-1] = "jammed",
            [-2] = "obstructed",
            [-3] = "in use"
          }
        local radarWidgetId, perisWidgetId
        local radarDataId, perisDataId
        local hasMatchingTransponder 
        local getConstructKind 
        local isConstructAbandoned 
        local getConstructName 
        local getDistance 
        local getSize 
        local conWorldPos 
    local function toggleRadarPanel()
        if radarPanelId ~= nil and peris == 0 then
            sysDestWid(radarPanelId)
            s.destroyWidget(radarWidgetId)
            s.destroyData(radarDataId)
            radarWidgetId, radarDataId, radarPanelId = nil, nil, nil
            if perisPanelID ~= nil then
                sysDestWid(perisPanelID)
                s.destroyWidget(perisWidgetId)
                s.destroyData(perisDataId)
                perisPanelID, perisWidgetId, perisDataId = nil, nil, nil
            end
        else
            -- If radar is installed but no weapon, don't show periscope
            if peris == 1 then
                --sysDestWid(radarPanelId)
                --radarPanelId = nil
                perisPanelID = s.createWidgetPanel("PeriWinkle")
                perisWidgetId = s.createWidget(perisPanelID, 'periscope')
                perisDataId = activeRadar.getWidgetDataId()
                s.addDataToWidget(perisDataId , perisWidgetId)
            end
            if radarPanelId == nil and radarContacts > 0 then
                radarPanelId = s.createWidgetPanel(rType)
                radarWidgetId = s.createWidget(radarPanelId, 'radar')
                radarDataId = activeRadar.getWidgetDataId()
                s.addDataToWidget(radarDataId , radarWidgetId)
            end
            peris = 0
        end
    end
    local function UpdateRadarRoutine()
        -- UpdateRadarRoutine Locals
            local function trilaterate (r1, p1, r2, p2, r3, p3, r4, p4 )-- Thanks to Wolfe's DU math library and Eastern Gamer advice
                p1,p2,p3,p4 = vec3(p1),vec3(p2),vec3(p3),vec3(p4)
                local r1s, r2s, r3s = r1*r1, r2*r2, r3*r3
                local v2 = p2 - p1
                local ax = v2:normalize()
                local U = v2:len()
                local v3 = p3 - p1
                local ay = (v3 - v3:project_on(ax)):normalize()
                local v3x, v3y = v3:dot(ax), v3:dot(ay)
                local vs = v3x*v3x + v3y*v3y
                local az = ax:cross(ay)  
                local x = (r1s - r2s + U*U) / (2*U) 
                local y = (r1s - r3s + vs - 2*v3x*x)/(2*v3y)
                local m = r1s - (x^2) - (y^2) 
                local z = msqrt(m)
                local t1 = p1 + ax*x + ay*y + az*z
                local t2 = p1 + ax*x + ay*y - az*z
            
                if mabs((p4 - t1):len() - r4) < mabs((p4 - t2):len() - r4) then
                return t1
                else
                return t2
                end
            end
            
            local function updateVariables(construct, d, wp) -- Thanks to EasternGamer and Dimencia
                local pts = construct.pts
                local index = #pts
                local ref = construct.ref
                if index > 3 then
                    local in1, in2, in3, in4 = pts[index], pts[index-1], pts[index-2], pts[index-3]
                    construct.ref = wp
                    local pos = trilaterate(in1[1], in1[2], in2[1], in2[2], in3[1], in3[2], in4[1], in4[2])
                    local x,y,z = pos.x, pos.y, pos.z
                    if x == x and y == y and z == z then
                        x = x + ref[1]
                        y = y + ref[2]
                        z = z + ref[3]
                        local newPos = vec3(x,y,z)
                        construct.center = newPos
                        if construct.lastPos then
                            if (construct.lastPos - newPos):len() < 2 then
                                local dtt = (newPos - vec3(wp)):len()
                                if mabs(dtt - d) < 10 then
                                    construct.skipCalc = true
                                end
                            end
                        end
                        construct.lastPos = newPos
                    end
                    construct.pts = {}
                else
                    local offset = {wp[1]-ref[1],wp[2]-ref[2],wp[3]-ref[3]}
                    pts[index+1] = {d,offset}
                end
            end

        if radar_1 or radar_2 then RADAR.assignRadar() end
        if (activeRadar) then

            if #radarData > 0 then

                local count, count2 = 0, 0
                local radarDist = velMag * 10
                local nearPlanet = nearPlanet
                static, numKnown = 0, 0
                friendlies = {}
                for _,v in pairs(radarData) do
                    local distance = getDistance(v)
                    if distance > 0.0 then 
                        if hasMatchingTransponder(v) then
                            insert(friendlies,v)
                        end
                        if not notPvPZone and warpdrive and distance < EmergencyWarp and  warpdrive.getStatus() == 15 then 
                            msg ("INITIATING WARP")
                            msgTimer = 7
                            warpdrive.initiate()
                        end
                        local abandoned = AbandonedRadar and isConstructAbandoned(v)
                        if CollisionSystem or abandoned then
                            local size = getSize(v)
                            local sz = sizeMap[size]
                            local cType = getConstructKind(v)
                            if abandoned or (distance < radarDist and (sz > 27 or cType == 4 or cType == 6)) then
                                static = static + 1
                                local wp = {worldPos["x"],worldPos["y"],worldPos["z"]} 
                                local construct = contacts[v]
                                if construct == nil then
                                    sz = sz+coreHalfDiag
                                    contacts[v] = {pts = {}, ref = wp, name = getConstructName(v), i = 0, radius = sz, skipCalc = false}
                                    construct = contacts[v]
                                end
                                if not construct.skipCalc then
                                    if (abandoned or cType == 4 or cType == 6) then
                                        construct.center = vec3(conWorldPos(v))
                                        construct.skipCalc = true
                                    else
                                        updateVariables(construct, distance, wp)
                                        count2 = count2 + 1
                                    end                                        
                                    if abandoned and not construct.abandoned then
                                        local time = s.getArkTime()
                                        if lastPlay+5 < time then 
                                            lastPlay = time
                                            play("abRdr", "RD")
                                        end
                                        s.print("Abandoned Construct: "..construct.name.." ("..size.." ".. cTypeString[cType]..") at ::pos{0,0,"..construct.center.x..","..construct.center.y..","..construct.center.z.."}")
                                        msg ("Abandoned Radar Contact ("..size.." ".. cTypeString[cType]..") detected")
                                        construct.abandoned = true
                                        if AutoWreckChase and not inAtmo and #apRoute == 0 then
                                            if isWreckVisited(construct.center) then
                                                msg ("Wreck Chase: ignoring visited wreck "..construct.name)
                                            elseif distance < 5000 then
                                                markWreckVisited(construct.center) -- already parked at it; count as visited
                                                msg ("Wreck Chase: "..construct.name.." is close by, marking visited (no chase)")
                                            elseif wreckChasePhase == 1 and distance < wreckChaseDist then
                                                wreckChaseTarget, wreckChaseDist = construct.center, distance
                                                msg ("Wreck Chase: retargeting closer contact "..construct.name)
                                            elseif wreckChasePhase == 0 then
                                                wreckChaseTarget, wreckChaseDist = construct.center, distance
                                                wreckChasePhase = 1
                                                AP.ResetAutopilots(true)
                                            end
                                        end
                                    end
                                else
                                    insert(knownContacts, construct) 
                                end
                            end
                            count = count + 1
                            if count > 300 or count2 > 30 then
                                coroutine.yield()
                                count, count2 = 0, 0
                            end
                        end
                    end
                end
                numKnown = #knownContacts
                if numKnown > 0 and (velMag > 20 or BrakeLanding) then 
                    local body, far, near, vect
                    local innerCount = 0
                    local galxRef = galaxyReference:getPlanetarySystem(0)
                    vect = constructVelocity:normalize()
                    while innerCount < numKnown do
                        coroutine.yield()
                        local innerList = { table.unpack(knownContacts, innerCount, math.min(innerCount + 75, numKnown)) }
                        body, far, near = galxRef:castIntersections(worldPos, vect, nil, nil, innerList, true)
                        if body and near then 
                            collisionTarget = {body, far, near} 
                            break 
                        end
                        innerCount = innerCount + 75
                    end
                    if not body then collisionTarget = nil end
                else
                    collisionTarget = nil
                end
                knownContacts = {}
                target = activeRadar.getTargetId()
            end
        end
    end
    local function pickType()
        if activeRadar then
            rType = "Atmo"
            if string.find(activeRadar.getName(),"Space") then 
                rType = "Space" 
            end
        end
    end
    function Radar.pickType()
        pickType()
    end

    function Radar.assignRadar()
        if radar_2 and activeRadarState ~= 1 then
            if activeRadarState == -1 then
                if activeRadar == radar_2 then 
                    activeRadar = radar_1
                else  
                    activeRadar = radar_2 
                end
            end
            radars = {activeRadar}
            hasMatchingTransponder = activeRadar.hasMatchingTransponder
            getConstructKind = activeRadar.getConstructKind
            isConstructAbandoned = activeRadar.isConstructAbandoned
            getConstructName = activeRadar.getConstructName
            getDistance = activeRadar.getConstructDistance
            getSize = activeRadar.getConstructCoreSize
            conWorldPos = activeRadar.getConstructWorldPos
            radarData = activeRadar.getConstructIds()
            pickType()
        else
            radarData = activeRadar.getConstructIds()
        end
        activeRadarState = activeRadar.getOperationalState()
    end

    function Radar.UpdateRadar()
        if wreckChasePhase == 1 then
            if velMag * 3.6 <= WreckChaseSpeed then
                wreckChasePhase = 2
                wreckChaseBraked = false
                RetrogradeIsOn = false
                if wreckChaseBurning then AP.cmdThrottle(0) wreckChaseBurning = false end
                if BrakeIsOn then AP.BrakeToggle() end
                ATLAS.AddNewLocation("0-Temp", wreckChaseTarget, true)
                AP.ToggleAutopilot()
                msg ("Wreck Chase: proceeding to wreck")
            elseif not wreckChaseBraked then
                wreckChaseBraked = true
                if not BrakeIsOn then AP.BrakeToggle() end
                RetrogradeIsOn = true
                msg ("Wreck Chase: braking to "..WreckChaseSpeed.." km/h before turning")
            elseif not BrakeIsOn then
                wreckChasePhase = 0 -- pilot released brakes: cancel, and retro goes with the brakes
                wreckChaseBraked = false
                RetrogradeIsOn = false
                if wreckChaseBurning then AP.cmdThrottle(0) wreckChaseBurning = false end
                msg ("Wreck Chase: cancelled")
            elseif not RetrogradeIsOn then
                wreckChasePhase = 0 -- pilot took over alignment: cancel, leave brakes to them
                wreckChaseBraked = false
                if wreckChaseBurning then AP.cmdThrottle(0) wreckChaseBurning = false end
                msg ("Wreck Chase: cancelled")
            else
                -- Retro burn gating: engines only add braking thrust when the nose is actually
                -- pointed retrograde. Hysteresis so throttle doesn't chatter at the edge.
                local dot = constructForward:dot(-constructVelocity:normalize())
                if wreckChaseBurning then
                    if dot < 0.98 then
                        AP.cmdThrottle(0)
                        wreckChaseBurning = false
                    end
                elseif dot > 0.995 then
                    AP.cmdThrottle(1)
                    wreckChaseBurning = true
                    msg ("Wreck Chase: retro burn")
                end
            end
        elseif wreckChasePhase == 2 then
            if not (Autopilot or VectorToTarget or spaceLaunch or IntoOrbit) then
                if wreckChaseTarget and (worldPos - wreckChaseTarget):len() < 10000 then
                    markWreckVisited(wreckChaseTarget) -- arrived; never auto-chase this one again
                end
                wreckChasePhase = 0 -- arrived or pilot cancelled; new detections may chase again
            end
        end
        local cont = coroutine.status (UpdateRadarCoroutine)
        if cont == "suspended" then 
            local value, done = coroutine.resume(UpdateRadarCoroutine)
            if done then s.print("ERROR UPDATE RADAR: "..done) end
        elseif cont == "dead" then
            UpdateRadarCoroutine = coroutine.create(UpdateRadarRoutine)
            local value, done = coroutine.resume(UpdateRadarCoroutine)
        end
    end

    function Radar.GetRadarHud(friendx, friendy, radarX, radarY)
        local radarMessage, msg
        local num = numKnown or 0 
        radarContacts = #radarData
        if radarContacts > 0 then 
            if CollisionSystem then 
                msg = num.."/"..static.." Known/InRange : "..radarContacts.." Total" 
            else
                msg = "Radar Contacts: "..radarContacts
            end
            radarMessage = svgText(radarX, radarY, msg, "pbright txtbig txtmid")
            if #friendlies > 0 then
                radarMessage = radarMessage..svgText( friendx, friendy, "Friendlies In Range", "pbright txtbig txtmid")
                for k, v in pairs(friendlies) do
                    friendy = friendy + 20
                    radarMessage = radarMessage..svgText(friendx, friendy, activeRadar.getConstructName(v), "pdim txtmid")
                end
            end
            local idNum = #activeRadar.getIdentifiedConstructIds()
            if perisPanelID == nil and idNum > 0 then
                peris = 1
                RADAR.ToggleRadarPanel()
            end
            if perisPanelID ~= nil and idNum == 0 then
                RADAR.ToggleRadarPanel()
            end
            if radarPanelId == nil then
                if showHud then RADAR.ToggleRadarPanel() end
            end
        else
            if activeRadarState ~= 1 then
                    radarMessage = svgText(radarX, radarY, rType.." Radar: "..radarStatus[activeRadarState] , "pbright txtbig txtmid")
            else
                radarMessage = svgText(radarX, radarY, "Radar: No "..rType.." Contacts", "pbright txtbig txtmid")
            end
            if radarPanelId ~= nil then
                peris = 0
                RADAR.ToggleRadarPanel()
            end
        end
        return radarMessage
    end

    function Radar.GetClosestName(name)
        if activeRadar then -- Just match the first one
                local closeName = activeRadar.getConstructName(activeRadar.getConstructIds()[1])
                if closeName then name = name .. " " .. closeName end
        end
        return name
    end

    function Radar.ToggleRadarPanel()
        toggleRadarPanel()
    end

    function Radar.ClearVisitedWrecks()
        wreckVisited = {}
        saveWreckVisited()
        msg ("Wreck Chase: visited list cleared")
    end

    function Radar.ContactTick()
        if not contactTimer then contactTimer = 0 end
        if time > contactTimer+10 then
            msg ("Radar Contact" )
            play("rdrCon","RC")
            contactTimer = time
        end
        u.stopTimer("contact")
    end

    function Radar.onEnter(id)
        if activeRadar and not inAtmo and not notPvPZone then 
            u.setTimer("contact",0.1) 
        end
    end

    function Radar.onLeave(id)
        if activeRadar and CollisionSystem then 
            if #contacts > 650 then 
                id = tostring(id)
                contacts[id] = nil 
            end
        end
    end

    local function setup()
        activeRadar=nil
        if radar_2 and radar_2.getOperationalState() then
            activeRadar = radar_2
        else
            activeRadar = radar_1
        end
        activeRadarState=activeRadar.getOperationalState()
        hasMatchingTransponder = activeRadar.hasMatchingTransponder
        getConstructKind = activeRadar.getConstructKind
        isConstructAbandoned = activeRadar.isConstructAbandoned
        getConstructName = activeRadar.getConstructName
        getDistance = activeRadar.getConstructDistance
        getSize = activeRadar.getConstructCoreSize
        conWorldPos = activeRadar.getConstructWorldPos
        radars = {activeRadar}
        radarData = activeRadar.getConstructIds()
        pickType()
        loadWreckVisited()
        if AutoWreckChase then
            WreckChaseSpeed = WreckChaseSpeed or 1000
            s.print("[WreckChase] Armed - threshold "..WreckChaseSpeed.." km/h, "..#wreckVisited.." visited wreck(s) ignored")
        end
        UpdateRadarCoroutine = coroutine.create(UpdateRadarRoutine)

        if userRadar then 
            for k,v in pairs(userRadar) do Radar[k] = v end 
        end   
    end
    setup()

    return Radar
end