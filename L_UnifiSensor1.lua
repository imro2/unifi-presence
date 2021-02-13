-- -----------------------------------------------------------------------------
-- L_UnifiSensor1.lua
-- This file is available under GPL 3.0. See LICENSE in documentation for info.
--
-- Based on UnifiSensor pluggin by LiveHouse Automation 
-- https://www.livehouseautomation.com.au/
-- https://github.com/peterv-vera/unifi-sensor
-- 
-- Significant portions of code used from  VirtualSensor pluggin by Patrick H. Rigney
-- http://www.toggledbits.com/
-- https://github.com/toggledbits/VirtualSensor
-- -----------------------------------------------------------------------------

--module("L_UnifiSensor1", package.seeall)

local _PLUGIN_NAME = "UnifiSensor"
local _PLUGIN_VERSION = "0.1"
local _PLUGIN_URL = "http://"

local isOpenLuup
local isALTUI

local https = require('ssl.https')
https.TIMEOUT= 10
local ltn12 = require("ltn12")

local UNIFI_SID = "urn:peterv-vera:serviceId:UnifiSensor1"
local UNIFI_TYPE = "urn:schemas-peterv-vera:device:UnifiSensor:1"
local SECURITY_SID = "urn:micasaverde-com:serviceId:SecuritySensor1"
local HADEVICE_SID = "urn:micasaverde-com:serviceId:HaDevice1"
local GATEWAY_SID = "urn:micasaverde-com:serviceId:HomeAutomationGateway1"

local DEBUG_MODE = true
local DEFAULT_PERIOD = 30

local PARENT_DEVICE

local json = require("dkjson")

local cookie = nil

--[[   D E B U G   F U N C T I O N S   ]]

local function dump(t)
	if t == nil then return "nil" end
	local sep = ""
	local str = "{ "
	for k,v in pairs(t) do
		local val
		if type(v) == "table" then
			val = dump(v)
		elseif type(v) == "function" then
			val = "(function)"
		elseif type(v) == "string" then
			val = string.format("%q", v)
		elseif type(v) == "number" then
			local d = v - os.time()
			if d < 0 then d = -d end
			if d <= 86400 then
				val = string.format("%d (%s)", v, os.date("%X", v))
			else
				val = tostring(v)
			end
		else
			val = tostring(v)
		end
		str = str .. sep .. k .. "=" .. val
		sep = ", "
	end
	str = str .. " }"
	return str
end

local function log(msg, ...) -- luacheck: ignore 212
	local str
  local args = {...}
	local level = 50
	if type(msg) == "table" then
		str = tostring(msg.prefix or _PLUGIN_NAME) .. ": " .. tostring(msg.msg or msg[1])
		level = msg.level or level
	else
		str = _PLUGIN_NAME .. ": " .. tostring(msg)
	end
	str = string.gsub(str, "%%(%d+)", function( n )
			n = tonumber(n, 10)
			if n < 1 or n > #args then return "nil" end
			local val = args[n]
			if type(val) == "table" then
				return dump(val)
			elseif type(val) == "string" then
				return string.format("%q", val)
			elseif type(val) == "number" then
				local d = val - os.time()
				if d < 0 then d = -d end
				if d <= 86400 then
					val = string.format("%d (time %s)", val, os.date("%X", val))
				end
			end
			return tostring(val)
		end
	)
	luup.log(str, level)
end

local function debug(msg, ...)
	if DEBUG_MODE then
		log({msg=msg,prefix=_PLUGIN_NAME.."(debug)::"}, ... )
	end
end


--[[   U T I L I T Y   F U N C T I O N S   ]]

-- Get numeric variable, or return default value if not set or blank
local function getVarNumeric( name, dflt, dev, serviceId )
	assert((name or "") ~= "") -- cannot be blank or nil
	dev = dev or PARENT_DEVICE
	if serviceId == nil then serviceId = UNIFI_SID end
	local s = luup.variable_get(serviceId, name, dev) or ""
	if s == "" then return dflt end
	s = tonumber(s, 10)
	if (s == nil) then return dflt end
	return s
end

local function getVar( name, dflt, dev, serviceId )
	local s = luup.variable_get(serviceId or UNIFI_SID, name, dev or PARENT_DEVICE) or ""
	return ( not string.match( s, "^%s*$" ) ) and s or dflt -- this specific test allows nil dflt return
end

local function initVar( sid, name, dflt, dev )
	dev = dev or PARENT_DEVICE
	sid = sid or UNIFI_SID
	local currVal = luup.variable_get( sid, name, dev )
  --log("sid %1, name %2, dflt %3, dev %4, currVal %5", sid, name, dflt, dev, currVal)
	if currVal == nil then
		luup.variable_set( sid, name, tostring(dflt), dev )
		return dflt
	end
	return currVal
end

-- Set last seen
local function setLastSeen( val, dev )
  local currentLastSeen = getVarNumeric("LastSeen", 0, dev, UNIFI_SID)
  debug("Dev %1, Current last_seen: %2, new last_seen %3", dev, currentLastSeen, val)
  if currentLastSeen < (val or 0) then
    luup.variable_set( UNIFI_SID, "LastSeen", val, dev )
  end
end

local function isEnabled( dev )
	return getVarNumeric( "Enabled", 1, dev, UNIFI_SID ) ~= 0
end

local function isLoggedIn( dev ) 
  return getVarNumeric("LoggedIn", 0, dev, UNIFI_SID) ~= 0
end

local function setLoggedIn( val, dev ) 
  local flag = val and 1 or 0
  if getVarNumeric("LoggedIn", 0, dev, UNIFI_SID) ~= flag then
    luup.variable_set( UNIFI_SID, "LoggedIn", flag , dev )
  end
end

-- Set or reset the current tripped state
local function trip( flag, pdev )
	debug("trip(%1,%2)", flag, pdev)
	local val = flag and 1 or 0
  --if device was seen within timout interval, do not untrip
  debug("Timout treshold: %1, Last seen: %2", os.time() - getVarNumeric("DeviceTimeout", 300, pdev, UNIFI_SID), getVarNumeric( "LastSeen", 0, pdev, UNIFI_SID))
  if val == 0 and os.time() - getVarNumeric("Timeout", 300, pdev, UNIFI_SID) < getVarNumeric( "LastSeen", 0, pdev, UNIFI_SID) then
    val = 1
  end
	local currTrip = getVarNumeric( "Tripped", 0, pdev, SECURITY_SID )
  debug ("val: %1 currTrip: %2", val, currTrip)
	if currTrip ~= val then
    luup.variable_set( SECURITY_SID, "Tripped", val, pdev )
    -- We don't need to worry about LastTrip or ArmedTripped, as Luup manages them.
    -- Note, the semantics of ArmedTripped are such that it changes only when Armed=1
    -- AND there's an edge (change) to Tripped. If Armed is changed from 0 to 1,
    -- ArmedTripped is not changed, even if Tripped=1 at that moment; it will change
    -- only when Tripped is explicitly set.
	end
end

local function setOffset( s )
  local p="%a+, (%d+) (%a+) (%d+) (%d+):(%d+):(%d+) GMT"
  local day,month,year,hour,min,sec=s:match(p)
  local MON={Jan=1,Feb=2,Mar=3,Apr=4,May=5,Jun=6,Jul=7,Aug=8,Sep=9,Oct=10,Nov=11,Dec=12}
  local month=MON[month]
  local serverTime = os.time({day=day,month=month,year=year,hour=hour,min=min,sec=sec})
  local offset=serverTime-os.time(os.date("!*t"))
  debug("Server time: %1, Local time: %2, Offset: %3", serverTime + offset, os.time(), offset)
  if math.abs(offset) > 5 and getVarNumeric("ContrTimeOffset", 0) then
    luup.variable_set(UNIFI_SID, "ContrTimeOffset", offset, PARENT_DEVICE) 
  end
end

local function getChildDevices( typ, parent, filter )
	assert(parent ~= nil)
	local res = {}
	for k,v in pairs(luup.devices) do
		if v.device_num_parent == parent and ( typ == nil or v.device_type == typ ) and ( filter==nil or filter(k, v) ) then
			table.insert( res, k )
		end
	end
	return res
end

local function prepForNewChildren( existingChildren, dev )
	debug("prepForNewChildren(%1)", existingChildren)
	if existingChildren == nil then
		existingChildren = {}
		for k,v in pairs( luup.devices ) do
			if v.device_num_parent == dev then
				table.insert( existingChildren, k )
			end
		end
	end
	local ptr = luup.chdev.start( dev )
	for _,k in ipairs( existingChildren ) do
		local v = luup.devices[k]
		assert(v)
		assert(v.device_num_parent == dev)
		debug("prepForNewChildren() appending existing child %1 (%2/%3)", v.description, k, v.id)
		luup.chdev.append( dev, ptr, v.id, v.description, "",	"D_MotionSensor1.xml", "", "", false )
	end
	return ptr, existingChildren
end

--[[   A C T I O N   H A N D L E R S   ]]

function actionAddChild( dev )
	-- Find max ID in use.
	local mx = 0
	local c = getChildDevices( nil, dev )
	for _,d in ipairs( c or {} ) do
		local v = tonumber(luup.devices[d].id)
		if v and v > mx then mx = v end
	end

	-- Generate default description
	local desc = "Virtual Unifi Device Sensor"

	log("Add new child type %1 id %2 desc %3", "urn:schemas-micasaverde-com:device:MotionSensor:1", mx+1, desc)

	local ptr = prepForNewChildren( nil, dev )
	luup.chdev.append( dev, ptr, tostring(mx+1), desc, "", "D_MotionSensor1.xml", "", "", false )
	luup.chdev.sync( dev, ptr )
	return 4,0
end

function actionSetDebug( dev, newDebug )
	debug("actionSetDebug(%1, %2)", dev, newDebug)
	luup.variable_set( UNIFI_SID, "DebugMode", newDebug, dev )
end

function actionTrip( dev )
	debug("actionTrip(%1)", dev)
	trip( true, dev );
end

function actionReset( dev )
	debug("actionReset(%1)", dev)
	trip( false, dev );
end


--[[HTTP request handling]]
local function http_request(path, payload, method)
  
  local url = base_url..path
  local request_headers = {}
  local request_source = nil
  local debugMsg = ""
  local cookie = getVar("Cookie") 
  
  if payload then
    request_headers["Content-Type"] = "application/json;charset=UTF-8" --application/x-www-form-urlencoded"
    request_headers["Content-Length"] = payload:len()
    request_source = ltn12.source.string(payload)
    method = (method or "POST")
  end
  
  if cookie then
    request_headers["cookie"] = cookie
  end
  
  if DEBUG_MODE then 
    debugMsg = "Method: " .. (method or "GET") .. "\n"
    debugMsg = debugMsg .. "Url:" .. url .. "\n"
    debugMsg = debugMsg .. "Request headers:\n"
    if type(request_headers) == "table" then
      for k, v in pairs(request_headers) do
        debugMsg = debugMsg .. "\t" .. k .. ":" .. v .. "\n"        
      end
    end
    debugMsg = debugMsg .. "Request payload: " .. (payload or "")
    debug(debugMsg)
  end
  
  local response = {}

  local body, code, headers = https.request{
                                method = method,
                                url = url,
                                headers = request_headers,
                                source = request_source,        
                                sink = ltn12.sink.table(response)
                                 }   
  
  code = tonumber(code) or 500  

  if DEBUG_MODE then 
    debugMsg = "Status:" .. (body and "OK" or "FAILED") .. "\n"
    debugMsg = debugMsg .. "HTTP code:" .. code .. "\n"
    debugMsg = debugMsg .. "Response headers:\n"
    if type(headers) == "table" then
      for k, v in pairs(headers) do
        debugMsg = debugMsg .. "\t" .. k .. ":" .. v .. "\n"        
      end
    end
    debugMsg = debugMsg .. "Response payload: " .. table.concat(response or {})
    debug(debugMsg)
  end
  
  if code>=200 and code < 400 then 
    if type(headers) == "table" then
      for k, v in pairs(headers) do
        if k == "set-cookie" then
          cookie = string.match(v, "(unifises=[^;]*;)")
          luup.variable_set(UNIFI_SID, "Cookie", cookie, lul_device)
        --elseif k == "date" and not isLoggedIn() then 
          --setOffset(v)
        end
      end
    end
  else
    log("Connection failed: HTTP code: %1 URL: %2", code, url)
  end
  
  return body, code, table.concat(response)
  
end

local function getUnifiError(resp)
  if resp == nil then
    return "Emtpy repsonse"
  end
  
  local respTab, pos, err = json.decode(resp)
  if err then
    return "Could not parse the response: " .. resp
  else
    local respMeta = respTab.meta or {}
    return respMeta.msg or "No error message"
  end
end

local function login()

  if isLoggedIn(PARENT_DEVICE) then
    return true
  end
  
  local username = getVar("UnifiUser", "username")
  local password = getVar("UnifiPassword", "password")
  local body, code, response = http_request('/api/login', '{"username":"'..username..'", "password":"'..password..'"}')
 
  if body and code>=200 and code < 400 then 
    setLoggedIn(true, PARENT_DEVICE)
    luup.set_failure(false, PARENT_DEVICE)
    return true 
  end

  log("Failed to log in: %1 - %2", code, getUnifiError(response))
  setLoggedIn(false, PARENT_DEVICE)
  luup.set_failure(true, PARENT_DEVICE)
  return false

end

local function request(path, payload, retries)
  
  local num_retries = retries or getVarNumeric("LoginRetries", 1)
  
  if not isLoggedIn(PARENT_DEVICE) then
    if not login() then
      return nil, {}
    end
  end
  
  local body, code, response = http_request(path, payload)  
  
  local errorMsg = ""
  if code ~= 200 then
    errorMsg = getUnifiError(response)
    log("Response: %1 - %2", code, errorMsg)
  end
 
  if code == 401 and errorMsg == "api.err.LoginRequired" then
    --most likely expired session 
    log("Logging in")
    setLoggedIn(false, PARENT_DEVICE)
    login()
    num_retries = num_retries - 1
    
    if isLoggedIn(PARENT_DEVICE) and num_retries >= 0 then 
      return request(path,payload,num_retries)
    end
    
    return nil, {}
  end
  
  if (not body) or code < 200 or code >= 400 then
    setLoggedIn(false, PARENT_DEVICE)
    luup.set_failure(true, PARENT_DEVICE)
  end
  
  return code, response
  
end

function get_list()
  local site = getVar("UnifiSite", "default")
  local code, resp = request("/api/s/"..site.."/stat/sta")
  return code, resp
end

function get_device_status(mac)
  local site = getVar("UnifiSite", "default")
  mac = string.lower(mac)
  local code, resp = request("/api/s/"..site.."/stat/sta", '{"macs":['..mac..']}')
  return code, resp
end

function get_user_device_status(mac)
  local site = getVar("UnifiSite", "default")
  mac = string.lower(mac)
  local code, resp = request("/api/s/"..site.."/stat/user/"..mac)
  return code, resp
end



-- Query the Unifi Controller 
local function executeUnifiQuery(dev)
  
  base_url = getVar("UnifiURL", "https://0.0.0.0", dev, UNIFI_SID) 
  site = getVar("UnifiSite", "default", dev, UNIFI_SID)
  
  local c = getChildDevices( nil, dev )
	for _,d in ipairs( c or {} ) do
    local mac = getVar("MACAddress", "", d, UNIFI_SID)
		if mac ~= "" then
      log ("Cheking MAC: %1", mac)
      local code, resp = get_user_device_status(mac)
      if code == 200 then
          local respTab, pos, err = json.decode(resp)
          if err then
            log ("Error parsing JSON response: %1", err)
          end
          local respData = respTab.data or {}
          local lastSeen = respData[1].last_seen or 0
          if lastSeen ~= 0 then lastSeen = lastSeen + getVarNumeric("ContrTimeOffset", 0) end
          setLastSeen( lastSeen, d)
          if respData[1].uptime ~= nil then
            log ("MAC %1 active for %2 seconds", mac, respData[1].uptime)
            trip(true,d)
          else
            log ("MAC %1 inactive since %2", mac, lastSeen)
            trip(false,d)
          end
      elseif code == 400 then
        --mac is not configured (has not been seen by the controller)
        log("Device with MAC %1 has not been seen by the controller", mac)
        trip(false,d)
      else
        trip(false,d)
      end
    end
	end
  
end


function unifiPoll()

  local dev = luup.device

  local period = getVarNumeric("Period", 60, dev, UNIFI_SID)
  luup.call_delay("unifiPoll", tostring(period), "")

  --
  -- To avoid having to be able to "cancel" a running timer, esp after repeated
  -- enable/disable calls, we simply "do nothing" in this code if the timer is
  -- disabled.  The actual timer itself is never stopped, we simply don't respond
  -- if we're disabled.
  --
  if isEnabled(dev) then
    -- Query the address, write result, inverted if necessary.
    executeUnifiQuery(dev)
    debug("Unifi Query Enabled, executed")
  else
    debug("Unifi Query Disabled, not executed " .. (enable or "No value"))
  end
end

--
-- Initializes variables if not found in config
--
local function initSettings( dev )

  initVar(UNIFI_SID, "Period", "60", dev)
  initVar(UNIFI_SID, "DebugMode", "0", dev)
  initVar(UNIFI_SID, "Enabled", "0", dev)
  initVar(UNIFI_SID, "UnifiURL", "https://0.0.0.0:8443", dev)
  initVar(UNIFI_SID, "UnifiUser", "username", dev)
  initVar(UNIFI_SID, "UnifiPassword", "password", dev)
  initVar(UNIFI_SID, "UnifiSite", "default", dev)
  initVar(HADEVICE_SID, "Configured", "0", dev)
  initVar(UNIFI_SID, "ContrTimeOffset", 0, dev)
  initVar(UNIFI_SID, "DeviceTimeout", 300, dev)

end


function unifi_init(dev)

  PARENT_DEVICE = dev
  
  debug("plugin_init(%1)", dev)
	log("starting version %1 for device %2", _PLUGIN_VERSION, dev )

	if getVarNumeric("DebugMode",0,dev,UNIFI_SID) ~= 0 then
		DEBUG_MODE = true
		debug("plugin_init(): Debug enabled by DebugMode state variable")
    else
        DEBUG_MODE = false
	end

	-- Check for ALTUI and OpenLuup. ??? need quicker, cleaner check
	for k,v in pairs(luup.devices) do
		if v.device_type == "urn:schemas-upnp-org:device:altui:1" and v.device_num_parent == 0 then
			debug("plugin_init() detected ALTUI at %1", k)
			isALTUI = true
		elseif v.device_type == "openLuup" then
			debug("plugin_init() detected openLuup")
			isOpenLuup = true
		end
	end

  initSettings( dev )

  -- Register request handler
  luup.register_handler("requestHandler", "UnifiSensor")


  --
  -- Do this deferred to avoid slowing down startup processes.
  --
  luup.call_delay("unifiPoll", "1", "")
  return true
end

local function getDevice( dev, pdev, v ) -- luacheck: ignore 212
	if v == nil then v = luup.devices[dev] end
	local json = require("json")
	if json == nil then json = require("dkjson") end
	local devinfo = {
		  devNum=dev
		, ['type']=v.device_type
		, description=v.description or ""
		, room=v.room_num or 0
		, udn=v.udn or ""
		, id=v.id
		, ['device_json'] = luup.attr_get( "device_json", dev )
		, ['impl_file'] = luup.attr_get( "impl_file", dev )
		, ['device_file'] = luup.attr_get( "device_file", dev )
		, manufacturer = luup.attr_get( "manufacturer", dev ) or ""
		, model = luup.attr_get( "model", dev ) or ""
	}
	local rc,t,httpStatus,uri
	if isOpenLuup then
		uri = "http://localhost:3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json"
	else
		uri = "http://localhost/port_3480/data_request?id=status&DeviceNum=" .. dev .. "&output_format=json"
	end
	rc,t,httpStatus = luup.inet.wget(uri, 15)
	if httpStatus ~= 200 or rc ~= 0 then
		devinfo['_comment'] = string.format( 'State info could not be retrieved, rc=%s, http=%s', tostring(rc), tostring(httpStatus) )
		return devinfo
	end
	local d = json.decode(t)
	local key = "Device_Num_" .. dev
	if d ~= nil and d[key] ~= nil and d[key].states ~= nil then d = d[key].states else d = nil end
	devinfo.states = d or {}
	return devinfo
end

function requestHandler( lul_request, lul_parameters, lul_outputformat )
  debug("request(%1,%2,%3) luup.device=%4", lul_request, lul_parameters, lul_outputformat, luup.device)
	local action = lul_parameters['action'] or lul_parameters['command'] or ""
	local deviceNum = tonumber( lul_parameters['device'], 10 ) or luup.device
  
	if action == "debug" then
		local err,msg,job,args = luup.call_action( UNIFI_SID, "SetDebug", { debug=1 }, deviceNum )
		return string.format("Device #%s result: %s, %s, %s, %s", tostring(deviceNum), tostring(err), tostring(msg), tostring(job), dump(args)), "text/plain"
	end

	if action == "alive" then
		return '{"alive":true}', "application/json"
    
	elseif action == "status" then
		local json = require("dkjson")
		if json == nil then json = require("dkjson") end
		local st = {
			name=_PLUGIN_NAME,
			version=_PLUGIN_VERSION,
			--configversion=_CONFIGVERSION,
			url=_PLUGIN_URL,
			['type']=UNIFI_TYPE,
			responder=luup.device,
			timestamp=os.time(),
			system = {
				version=luup.version,
				isOpenLuup=isOpenLuup,
				isALTUI=isALTUI,
				units=luup.attr_get( "TemperatureFormat", 0 ),
			},
			devices={}
		}
		for k,v in pairs( luup.devices ) do
			if v.device_type == UNIFI_TYPE then
				local devinfo = getDevice( k, luup.device, v ) or {}
				table.insert( st.devices, devinfo )
			end
		end
		return json.encode( st ), "application/json"

	elseif string.find("trip reset arm disarm setvalue", action) then
		local alias = lul_parameters['alias'] or ""
		local parm = {}
		local devAction
		local sid = UNIFI_SID
		if action == "trip" then
			devAction = "Trip"
		elseif action == "arm" then
			devAction = "SetArmed"
			parm.newArmedValue = 1
			sid = SECURITY_SID
		elseif action == "disarm" then
			devAction = "SetArmed"
			parm.newArmedValue = 0
			sid = SECURITY_SID
		elseif action == "setvalue" then
			devAction = "SetValue"
			parm.newValue = lul_parameters['value']
		else
			devAction = "Reset"
		end
		local nDev = 0
		for k,v in pairs( luup.devices ) do
			if v.device_type == UNIFI_TYPE then
				local da = luup.variable_get(UNIFI_SID, "Alias", k) or ""
				if da ~= "" and ( alias == "*" or alias == da ) then
					luup.call_action( sid, devAction, parm, k)
					nDev = nDev + 1
				end
			end
		end
		return string.format("Done with %q for %d devices matching alias %q", action, nDev, alias), "text/plain"

	elseif action == "restart" then

		if luup.devices[deviceNum] and luup.devices[deviceNum].device_num_parent == PARENT_DEVICE then
			startChild( deviceNum )
			doChildUpdate( true, deviceNum )
			return '{"status":true}', "application/json"
		end
		return "ERROR invalid device", "text/plain"

	else
		return string.format("Action %q not implemented", action), "text/plain"
	end
end

