_G._OSNAME = "miniOS"
_G._OSVER = "0.5.9.8"
_G._OSVERSION = _OSNAME .. " " .. _OSVER

--component code
function component_code()
local adding = {}
local removing = {}
local primaries = {}

-------------------------------------------------------------------------------

-- This allows writing component.modem.open(123) instead of writing
-- component.getPrimary("modem").open(123), which may be nicer to read.
setmetatable(component, { __index = function(_, key)
                                      return component.getPrimary(key)
                                    end })

function component.get(address, componentType)
  checkArg(1, address, "string")
  checkArg(2, componentType, "string", "nil")
  for c in component.list(componentType, true) do
    if c:sub(1, address:len()) == address then
      return c
    end
  end
  return nil, "no such component"
end

function component.isAvailable(componentType)
  checkArg(1, componentType, "string")
  if not primaries[componentType] then
    -- This is mostly to avoid out of memory errors preventing proxy
    -- creation cause confusion by trying to create the proxy again,
    -- causing the oom error to be thrown again.
    component.setPrimary(componentType, component.list(componentType, true)())
  end
  return primaries[componentType] ~= nil
end

function component.isPrimary(address)
  local componentType = component.type(address)
  if componentType then
    if component.isAvailable(componentType) then
      return primaries[componentType].address == address
    end
  end
  return false
end

function component.getPrimary(componentType)
  checkArg(1, componentType, "string")
  assert(component.isAvailable(componentType),
    "no primary '" .. componentType .. "' available")
  return primaries[componentType]
end

function component.setPrimary(componentType, address)
  checkArg(1, componentType, "string")
  checkArg(2, address, "string", "nil")
  if address ~= nil then
    address = component.get(address, componentType)
    assert(address, "no such component")
  end

  local wasAvailable = primaries[componentType]
  if wasAvailable and address == wasAvailable.address then
    return
  end
  local wasAdding = adding[componentType]
  if wasAdding and address == wasAdding.address then
    return
  end
  if wasAdding then
    event.cancel(wasAdding.timer)
  end
  primaries[componentType] = nil
  adding[componentType] = nil

  local primary = address and component.proxy(address) or nil
  if wasAvailable then
    computer.pushSignal("component_unavailable", componentType)
  end
  if primary then
    if wasAvailable or wasAdding then
      adding[componentType] = {
        address=address,
        timer=event.timer(0.1, function()
          adding[componentType] = nil
          primaries[componentType] = primary
          computer.pushSignal("component_available", componentType)
        end)
      }
    else
      primaries[componentType] = primary
      computer.pushSignal("component_available", componentType)
    end
  end
end

-------------------------------------------------------------------------------

local function onComponentAdded(_, address, componentType)
  if not (primaries[componentType] or adding[componentType]) then
    component.setPrimary(componentType, address)
  end
end

local function onComponentRemoved(_, address, componentType)
  if primaries[componentType] and primaries[componentType].address == address or
     adding[componentType] and adding[componentType].address == address
  then
    component.setPrimary(componentType, component.list(componentType, true)())
  end
end

event.listen("component_added", onComponentAdded)
event.listen("component_removed", onComponentRemoved)
end
--text libary
function text_code()
  local text = {}
  
  function text.detab(value, tabWidth)
    checkArg(1, value, "string")
    checkArg(2, tabWidth, "number", "nil")
    tabWidth = tabWidth or 8
    local function rep(match)
      local spaces = tabWidth - match:len() % tabWidth
      return match .. string.rep(" ", spaces)
    end
    local result = value:gsub("([^\n]-)\t", rep) -- truncate results
    return result
  end
  
  function text.padRight(value, length)
    checkArg(1, value, "string", "nil")
    checkArg(2, length, "number")
    if not value or unicode.len(value) == 0 then
      return string.rep(" ", length)
    else
      return value .. string.rep(" ", length - unicode.len(value))
    end
  end
  
  function text.padLeft(value, length)
    checkArg(1, value, "string", "nil")
    checkArg(2, length, "number")
    if not value or unicode.len(value) == 0 then
      return string.rep(" ", length)
    else
      return string.rep(" ", length - unicode.len(value)) .. value
    end
  end
  
  function text.trim(value) -- from http://lua-users.org/wiki/StringTrim
    local from = string.match(value, "^%s*()")
    return from > #value and "" or string.match(value, ".*%S", from)
  end
  
  function text.wrap(value, width, maxWidth)
    checkArg(1, value, "string")
    checkArg(2, width, "number")
    checkArg(3, maxWidth, "number")
    local line, nl = value:match("([^\r\n]*)(\r?\n?)") -- read until newline
    if unicode.len(line) > width then -- do we even need to wrap?
      local partial = unicode.sub(line, 1, width)
      local wrapped = partial:match("(.*[^a-zA-Z0-9._()'`=])")
      if wrapped or unicode.len(line) > maxWidth then
        partial = wrapped or partial
        return partial, unicode.sub(value, unicode.len(partial) + 1), true
      else
        return "", value, true -- write in new line.
      end
    end
    local start = unicode.len(line) + unicode.len(nl) + 1
    return line, start <= unicode.len(value) and unicode.sub(value, start) or nil, unicode.len(nl) > 0
  end
  
  function text.wrappedLines(value, width, maxWidth)
    local line, nl
    return function()
      if value then
        line, value, nl = text.wrap(value, width, maxWidth)
        return line
      end
    end
  end
  
  -------------------------------------------------------------------------------
  
  function text.tokenize(value)
    checkArg(1, value, "string")
    local tokens, token = {}, ""
    local escaped, quoted, start = false, false, -1
    for i = 1, unicode.len(value) do
      local char = unicode.sub(value, i, i)
      if escaped then -- escaped character
        escaped = false
        token = token .. char
      elseif char == "\\" and quoted ~= "'" then -- escape character?
        escaped = true
        token = token .. char
      elseif char == quoted then -- end of quoted string
        quoted = false
        token = token .. char
      elseif (char == "'" or char == '"') and not quoted then
        quoted = char
        start = i
        token = token .. char
      elseif string.find(char, "%s") and not quoted then -- delimiter
        if token ~= "" then
          table.insert(tokens, token)
          token = ""
        end
      else -- normal char
        token = token .. char
      end
    end
    if quoted then
      return nil, "unclosed quote at index " .. start
    end
    if token ~= "" then
      table.insert(tokens, token)
    end
    return tokens
  end
  
  -------------------------------------------------------------------------------
  
  function text.endswith(s, send)
    return #s >= #send and s:find(send, #s-#send+1, true) and true or false
  end
  
  return text
end
--event code
function event_code()
  local event, listeners, timers = {}, {}, {}
  local lastInterrupt = -math.huge
  
  local function matches(signal, name, filter)
    if name and not (type(signal[1]) == "string" and signal[1]:match(name))
    then
      return false
    end
    for i = 1, filter.n do
      if filter[i] ~= nil and filter[i] ~= signal[i + 1] then
        return false
      end
    end
    return true
  end
  
  local function call(callback, ...)
    local result, message = pcall(callback, ...)
    if not result and type(event.onError) == "function" then
      pcall(event.onError, message)
      return
    end
    return message
  end
  
  local function dispatch(signal, ...)
    if listeners[signal] then
      local function callbacks()
        local list = {}
        for index, listener in ipairs(listeners[signal]) do
          list[index] = listener
        end
        return list
      end
      for _, callback in ipairs(callbacks()) do
        if call(callback, signal, ...) == false then
          event.ignore(signal, callback) -- alternative method of removing a listener
        end
      end
    end
  end
  
  local function tick()
    local function elapsed()
      local list = {}
      for id, timer in pairs(timers) do
        if timer.after <= computer.uptime() then
          table.insert(list, timer.callback)
          timer.times = timer.times - 1
          if timer.times <= 0 then
            timers[id] = nil
          else
            timer.after = computer.uptime() + timer.interval
          end
        end
      end
      return list
    end
    for _, callback in ipairs(elapsed()) do
      call(callback)
    end
  end
  
  -------------------------------------------------------------------------------
  
  function event.cancel(timerId)
    checkArg(1, timerId, "number")
    if timers[timerId] then
      timers[timerId] = nil
      return true
    end
    return false
  end
  
  function event.ignore(name, callback)
    checkArg(1, name, "string")
    checkArg(2, callback, "function")
    if listeners[name] then
      for i = 1, #listeners[name] do
        if listeners[name][i] == callback then
          table.remove(listeners[name], i)
          if #listeners[name] == 0 then
            listeners[name] = nil
          end
          return true
        end
      end
    end
    return false
  end
  
  function event.listen(name, callback)
    checkArg(1, name, "string")
    checkArg(2, callback, "function")
    if listeners[name] then
      for i = 1, #listeners[name] do
        if listeners[name][i] == callback then
          return false
        end
      end
    else
      listeners[name] = {}
    end
    table.insert(listeners[name], callback)
    return true
  end
  
  function event.onError(message)
    local log = io.open("/tmp/event.log", "a")
    if log then
      log:write(message .. "\n")
      log:close()
    end
  end
  
  function event.pull(...)
    local args = table.pack(...)
    local seconds, name, filter
    if type(args[1]) == "string" then
      name = args[1]
      filter = table.pack(table.unpack(args, 2, args.n))
    else
      checkArg(1, args[1], "number", "nil")
      checkArg(2, args[2], "string", "nil")
      seconds = args[1]
      name = args[2]
      filter = table.pack(table.unpack(args, 3, args.n))
    end
  
    local hasFilter = name ~= nil
    if not hasFilter then
      for i = 1, filter.n do
        hasFilter = hasFilter or filter[i] ~= nil
      end
    end
  
    local deadline = seconds and
                     (computer.uptime() + seconds) or
                     (hasFilter and math.huge or 0)
    repeat
      local closest = seconds and deadline or math.huge
      for _, timer in pairs(timers) do
        closest = math.min(closest, timer.after)
      end
      local signal = table.pack(computer.pullSignal(closest - computer.uptime()))
      if signal.n > 0 then
        dispatch(table.unpack(signal, 1, signal.n))
      end
      tick()
      if event.shouldInterrupt() then
        lastInterrupt = computer.uptime()
        error("interrupted", 0)
      end
      if not (seconds or hasFilter) or matches(signal, name, filter) then
        return table.unpack(signal, 1, signal.n)
      end
    until computer.uptime() >= deadline
  end
  
  function event.shouldInterrupt()
    return computer.uptime() - lastInterrupt > 1 and
           keyboard.isControlDown() and
           keyboard.isAltDown() and
           keyboard.isKeyDown(keyboard.keys.c)
  end
  
  function event.timer(interval, callback, times)
    checkArg(1, interval, "number")
    checkArg(2, callback, "function")
    checkArg(3, times, "number", "nil")
    local id
    repeat
      id = math.floor(math.random(1, 0x7FFFFFFF))
    until not timers[id]
    timers[id] = {
      interval = interval,
      after = computer.uptime() + interval,
      callback = callback,
      times = times or 1
    }
    return id
  end
  
  -------------------------------------------------------------------------------
  
  return event
end
--os lib code
function os_lib_code()
local os = {}
	local env = {
	PATH=".",
	TMPDIR="" --what would be a good default value?
	}
	function os.getenv(varname)
	if varname == '#' then
		return #env
	elseif varname ~= nil then
		return env[varname]
	else
		return env
	end
	end

	function os.setenv(varname, value)
		checkArg(1, varname, "string", "number")
		if value == nil then
			env[varname] = nil
		else
			local success, val = pcall(tostring, value)
			if success then
				env[varname] = val
				return env[varname]
			else
				return nil, val
			end
		end
	end

return os
end
--filesystem code
function fs_code()
  local fileStream = {}
  function fileStream:close()
    if self.handle then
      self.fs.close(self.handle)
      self.handle = nil
    end
  end
  function fileStream:read(n)
    if not self.handle then
      return nil, "file is closed"
    end
    return self.fs.read(self.handle, n or math.huge)
  end
  function fileStream:seek(whence, offset)
    if not self.handle then
      return nil, "file is closed"
    end
    return self.fs.seek(self.handle, whence, offset)
  end
  function fileStream:write(str)
    if not self.handle then
      return nil, "file is closed"
    end
    return self.fs.write(self.handle, str)
  end
  local fs = {}
  fs.drive = {}
  --drive mapping table, initialized later
  fs.drive._map = {}
  --converts a drive letter into a proxy
  function fs.drive.letterToProxy(letter)
	return fs.drive._map[letter]
  end
  --finds the proxy associated with the letter
  function fs.drive.proxyToLetter(proxy)
    for l,p in pairs(fs.drive._map) do
	  if p == proxy then return l end
	end
	return nil
  end
  --maps a proxy to a letter
  function fs.drive.mapProxy(letter, proxy)
    fs.drive._map[letter] = proxy
  end
  --finds the address of a drive letter.
  function fs.drive.toAddress(letter)
    return fs.drive._map[letter].address
  end
  --finds the drive letter mapped to an address
  function fs.drive.toLetter(address)
	for l,p in pairs(fs.drive._map) do
	  if p.address == address then return l end
	end
	return nil
  end
  function fs.drive.mapAddress(letter, address)
	--print("mapAddress")
    fs.drive._map[letter] = fs.proxy(address)
  end
  function fs.drive.autoMap(address) --returns the letter if mapped OR already mapped, false if not.
	--print("autoMap")
	--we get the address and see if it already is mapped...
	local l = fs.drive.toLetter(address)
	if l then return l end
	--then we take the address and attempt to map it
	--start at A:	
	l = "A"
	while true do
		--see if it is mapped and then go to the next letter...
		if fs.drive._map[l] then l = ('ABCDEFGHIJKLMNOPQRSTUVWXYZ_'):match(l..'(.)') else fs.drive.mapAddress(l, address) return l end
		--if we got to the end, fail
		if l == "_" then return false end
	end
  end
  function fs.drive.listProxy()
    local t = fs.drive._map
    local p = {}
	for n in pairs(t) do table.insert(p, n) end
    table.sort(p, f)
    local i = 0      -- iterator variable
    local iter = function ()   -- iterator function
      i = i + 1
      if p[i] == nil then return nil
      else return p[i], t[p[i]]
      end
    end
    return iter
  end
  function fs.drive.list()
    local i = 0      -- iterator variable
	local proxyIter = fs.drive.listProxy()
    local iter = function ()   -- iterator function
	  l, p = proxyIter()
	  if not l then return nil end
      return l, p.address
    end
	return iter
  end
  fs.drive._current = "A" --as the boot drive is A:
  function fs.drive.setcurrent(letter)
	letter = letter:upper()
    if not fs.drive._map[letter] then error("Invalid Drive", 2) end
    fs.drive._current = letter
	end
  function fs.drive.getcurrent() return fs.drive._current end
  --Splits a string into drive and path.
  function fs.drive.drivePath(fullPath)
  	checkArg(1, fullPath, "string")
  	local drive
  	local path
  	if fullPath:sub(2, 2) == ":" then
  	  drive = fullPath:sub(1,1):upper()
  	  path = fullPath:sub(3)
  	  if not drive:match("^%a+$") then error("bad argument #1 (invalid drive given)") end
      if path:sub(1,1) ~= "/" then path = "/" .. path end
  	else
  	  path = fullPath
  	  if path:sub(1,1) ~= "/" then path = "/" .. path end
  	end
  	return drive, path
  end
  function fs.findDrive(fullPath)
    local l, p = fs.drive.drivePath(fullPath)
	return l or fs.drive._current, p
  end
  function fs.drive.invoke(drive, method, ...) return fs.drive._map[drive][method](...) end
  function fs.invoke(...) printErr("Warning! fs.invoke is now depreciated!") return fs.drive.invoke(fs.drive._current, ...) end
  function fs.proxy(filter)
    checkArg(1, filter, "string")
    local address
    for c in component.list("filesystem") do
      if component.invoke(c, "getLabel") == filter then
        address = c
        break
      end
	  if filter:sub(2,2) == ":" then
	    if fs.drive.toAddress(filter:sub(1,1)) == c then address = c break end
      end
	  if c:sub(1, filter:len()) == filter then
        address = c
        break
      end
    end
    if not address then
      return nil, "no such file system"
    end
    return component.proxy(address)
  end
  function fs.open(path, mode)
    checkArg(1, path, "string")
    mode = tostring(mode or "r")
    checkArg(2, mode, "string")
    assert(({r=true, rb=true, w=true, wb=true, a=true, ab=true})[mode],
      "bad argument #2 (r[b], w[b] or a[b] expected, got " .. mode .. ")")
	
	local drive, rest = fs.drive.drivePath(path)
	drive = drive or fs.drive.getcurrent()
	if not (fs.exists(path) and not fs.isDirectory(path)) then
		return nil, "file not found" end
  
    local handle, reason = fs.drive.invoke(drive, "open", rest, mode)
    if not handle then
      return nil, reason
    end
  
    local stream = {letter = drive, fs = fs.drive.letterToProxy(drive), handle = handle}
  
    local function cleanup(self)
      if not self.handle then return end
      if fs.drive._map[self.letter] then pcall(proxy.close, self.handle) end
    end
    local metatable = {__index = fileStream,
                       __gc = cleanup,
                       __metatable = "filestream",
					   __tostring = function(self) return self.handle end
					   }
    return setmetatable(stream, metatable)
  end
  function fs.write(handle, ...) return handle:write(...) end
  function fs.read(handle, ...) return handle:read(...) end
  function fs.seek(handle, ...) return handle:seek(...) end
  function fs.close(handle, ...) return handle:close(...) end
  function fs.isDirectory(path) local l, path = fs.findDrive(path) return fs.drive.invoke(l, "isDirectory", path) end
  function fs.exists(path) local l, path = fs.findDrive(path) return fs.drive.invoke(l, "exists", path) end
  function fs.remove(path) local l, path = fs.findDrive(path) return fs.drive.invoke(l, path) end
  function fs.copy(fromPath, toPath)
    if fs.isDirectory(fromPath) then
      return nil, "cannot copy folders" --make able to copy folders later?
    end
    local input, reason = fs.open(fromPath, "rb")
    if not input then
      return nil, reason
    end
    local output, reason = fs.open(toPath, "wb")
    if not output then
      input:close()
    return nil, reason
    end
    repeat
      local buffer, reason = input:read()
      if not buffer and reason then
        return nil, reason
      elseif buffer then
        local result, reason = output:write(buffer)
        if not result then
          input:close()
          output:close()
          return nil, reason
          end
        end
    until not buffer
    input:close()
    output:close()
    return true
  end
  function fs.rename(from, to)
    checkArg(1, from, "string")
	checkArg(2, to, "string")
    local lf, fp = fs.findDrive(from)
    local lt, tp = fs.findDrive(to)
	if lf == lt then return fs.drive.invoke(lf, "rename", fp, tp) end
	local result, reason = fs.copy(from, to)
    if result then
      return fs.remove(from)
    else
      return nil, reason
    end
  end
  function fs.makeDirectory(path) l, path = fs.findDrive(path) return fs.drive.invoke(l,"makeDirectory", path) end
  function fs.list(path)
	local l, path = fs.findDrive(path)
    local i = 0
    local t = fs.drive.invoke(l, "list", path)
	local n = #t
    return function()
      i = i + 1
	  if i <= n then return t[i] end
	  return nil
	end
  end
  function fs.name(path)
    local parts = segments(path)
    return parts[#parts]
  end
  function fs.segments(path)
    path = path:gsub("\\", "/")
    repeat local n; path, n = path:gsub("//", "/") until n == 0
    local parts = {}
    for part in path:gmatch("[^/]+") do
      table.insert(parts, part)
    end
    local i = 1
    while i <= #parts do
      if parts[i] == "." then
        table.remove(parts, i)
      elseif parts[i] == ".." then
        table.remove(parts, i)
        i = i - 1
        if i > 0 then
          table.remove(parts, i)
      else
        i = 1
        end
      else
        i = i + 1
      end
    end
    return parts
  end
  function fs.canonical(path)
    local result = table.concat(fs.segments(path), "/")
    if unicode.sub(path, 1, 1) == "/" then
      return "/" .. result
    else
      return result
    end
  end
  function fs.concat(pathA, pathB, ...)
    checkArg(1, pathA, "string")
    local function concat(n, a, b, ...)
      if not b then
        return a
      end
      checkArg(n, b, "string")
      return concat(n + 1, a .. "/" .. b, ...)
    end
    return fs.canonical(concat(2, pathA, pathB, ...))
end
  function fs.resolve(path, ext)
    if ext then
      checkArg(2, ext, "string")
      local where = miniOS.findFile(path, ext)
      if where then
        return where
      else
        return nil, "file not found"
      end
    else
      -- if unicode.sub(path, 1, 1) == "/" then
        -- return fs.canonical(path)
      -- else
        -- return fs.concat(fs.getWorkingDirectory(), path)
      -- end
	  letter, path = fs.findDrive(path)
	  return letter .. ":" .. fs.canonical(path)
    end
  end
  function fs.getWorkingDirectory() return os.getenv("PWD") or fs.drive.getcurrent() .. ":/" end
  function fs.setWorkingDirectory(dir)
    checkArg(1, dir, "string")
    dir = fs.canonical(dir) .. "/"
    if dir == "//" then dir = "/" end
    if fs.isDirectory(dir) then
      os.setenv("PWD", dir)
      return true
    else
      return nil, "not a directory"
    end
  end
  function fs.findFile(name, ext)
    checkArg(1, name, "string")
    local function findIn(dir)
      if dir:sub(1, 1) ~= "/" then
        dir = shell.resolve(dir)
      end
      dir = fs.concat(fs.concat(dir, name), "..")
      local name = fs.name(name)
      local list = fs.list(dir)
      if list then
        local files = {}
        for file in list do
          files[file] = true
        end
        if ext and unicode.sub(name, -(1 + unicode.len(ext))) == "." .. ext then
          -- Name already contains extension, prioritize.
          if files[name] then
            return true, fs.concat(dir, name)
          end
        elseif files[name] then
          -- Check exact name.
          return true, fs.concat(dir, name)
        elseif ext then
          -- Check name with automatially added extension.
          local name = name .. "." .. ext
          if files[name] then
            return true, fs.concat(dir, name)
          end
        end
      end
      return false
    end
    if unicode.sub(name, 1, 1) == "/" then
      local found, where = findIn("/")
      if found then return where end
    elseif unicode.sub(name, 1, 2) == "./" then
      local found, where = findIn(shell.getWorkingDirectory())
      if found then return where end
    else
      for path in string.gmatch(shell.getPath(), "[^:]+") do
        local found, where = findIn(path)
        if found then return where end
      end
    end
    return false
  end

  
  --handle inserted and removed filesystems
  local function onComponentAdded(_, address, componentType)
    if componentType == "filesystem" then
        fs.drive.autoMap(address)
    end
  end
  local function onComponentRemoved(_, address, componentType)
    if componentType == "filesystem" then
      fs.drive.mapAddress(fs.drive.toLetter(address), nil)
    end
  end
  event.listen("component_added", onComponentAdded)
  event.listen("component_removed", onComponentRemoved)
  local function driveInit()
    local boot = fs.proxy(computer.getBootAddress())
    local temp = fs.proxy(computer.tmpAddress())
    fs.drive._map = { ["A"]=boot, ["X"]=temp } 
  end
  driveInit()
  --return the API
  return fs
end
--terminal code
function terminal_code()
  local term = {}
  local cursorX, cursorY = 1, 1
  local cursorBlink = nil
  
  local function toggleBlink()
    if term.isAvailable() then
      cursorBlink.state = not cursorBlink.state
      if cursorBlink.state then
        cursorBlink.alt = component.gpu.get(cursorX, cursorY)
        component.gpu.set(cursorX, cursorY, "_")
      else
        component.gpu.set(cursorX, cursorY, cursorBlink.alt)
      end
    end
  end
  
  -------------------------------------------------------------------------------
  
  function term.clear()
    if term.isAvailable() then
      local w, h = component.gpu.getResolution()
      component.gpu.fill(1, 1, w, h, " ")
    end
    cursorX, cursorY = 1, 1
  end
  
  function term.clearLine()
    if term.isAvailable() then
      local w = component.gpu.getResolution()
      component.gpu.fill(1, cursorY, w, 1, " ")
    end
    cursorX = 1
  end
  
  function term.getCursor()
    return cursorX, cursorY
  end
  
  function term.setCursor(col, row)
    checkArg(1, col, "number")
    checkArg(2, row, "number")
    if cursorBlink and cursorBlink.state then
      toggleBlink()
    end
    cursorX = math.floor(col)
    cursorY = math.floor(row)
  end
  
  function term.getCursorBlink()
    return cursorBlink ~= nil
  end
  
  function term.setCursorBlink(enabled)
    checkArg(1, enabled, "boolean")
    if enabled then
      if not cursorBlink then
        cursorBlink = {}
        cursorBlink.id = event.timer(0.5, toggleBlink, math.huge)
        cursorBlink.state = false
      elseif not cursorBlink.state then
        toggleBlink()
      end
    elseif cursorBlink then
      event.cancel(cursorBlink.id)
      if cursorBlink.state then
        toggleBlink()
      end
      cursorBlink = nil
    end
  end
  
  function term.isAvailable()
    return component.isAvailable("gpu") and component.isAvailable("screen")
  end
  
  function term.readKey(echo)
    local blink = term.getCursorBlink()
	term.setCursorBlink(true)
	local ok, name, address, charOrValue, code = pcall(event.pull, "key_down")
      if not ok then
        term.setCursorBlink(blink)
        error("interrupted", 0)
    end
	if name == "key_down" then
	  if echo then term.write(charOrValue) end
      term.setCursorBlink(blink)
	end
  end
  
  function term.read(history, dobreak)
    checkArg(1, history, "table", "nil")
    history = history or {}
    table.insert(history, "")
    local offset = term.getCursor() - 1
    local scrollX, scrollY = 0, #history - 1
  
    local function getCursor()
      local cx, cy = term.getCursor()
      return cx - offset + scrollX, 1 + scrollY
    end
  
    local function line()
      local cbx, cby = getCursor()
      return history[cby]
    end
  
    local function setCursor(nbx, nby)
      local w, h = component.gpu.getResolution()
      local cx, cy = term.getCursor()
  
      scrollY = nby - 1
  
      nbx = math.max(1, math.min(unicode.len(history[nby]) + 1, nbx))
      local ncx = nbx + offset - scrollX
      if ncx > w then
        local sx = nbx - (w - offset)
        local dx = math.abs(scrollX - sx)
        scrollX = sx
        component.gpu.copy(1 + offset + dx, cy, w - offset - dx, 1, -dx, 0)
        local str = unicode.sub(history[nby], nbx - (dx - 1), nbx)
        str = text.padRight(str, dx)
        component.gpu.set(1 + math.max(offset, w - dx), cy, unicode.sub(str, 1 + math.max(0, dx - (w - offset))))
      elseif ncx < 1 + offset then
        local sx = nbx - 1
        local dx = math.abs(scrollX - sx)
        scrollX = sx
        component.gpu.copy(1 + offset, cy, w - offset - dx, 1, dx, 0)
        local str = unicode.sub(history[nby], nbx, nbx + dx)
        --str = text.padRight(str, dx)
        component.gpu.set(1 + offset, cy, str)
      end
  
      term.setCursor(nbx - scrollX + offset, cy)
    end
  
    local function copyIfNecessary()
      local cbx, cby = getCursor()
      if cby ~= #history then
        history[#history] = line()
        setCursor(cbx, #history)
      end
    end
  
    local function redraw()
      local cx, cy = term.getCursor()
      local bx, by = 1 + scrollX, 1 + scrollY
      local w, h = component.gpu.getResolution()
      local l = w - offset
      local str = unicode.sub(history[by], bx, bx + l)
      str = text.padRight(str, l)
      component.gpu.set(1 + offset, cy, str)
    end
  
    local function home()
      local cbx, cby = getCursor()
      setCursor(1, cby)
    end
  
    local function ende()
      local cbx, cby = getCursor()
      setCursor(unicode.len(line()) + 1, cby)
    end
  
    local function left()
      local cbx, cby = getCursor()
      if cbx > 1 then
        setCursor(cbx - 1, cby)
        return true -- for backspace
      end
    end
  
    local function right(n)
      n = n or 1
      local cbx, cby = getCursor()
      local be = unicode.len(line()) + 1
      if cbx < be then
        setCursor(math.min(be, cbx + n), cby)
      end
    end
  
    local function up()
      local cbx, cby = getCursor()
      if cby > 1 then
        setCursor(1, cby - 1)
        redraw()
        ende()
      end
    end
  
    local function down()
      local cbx, cby = getCursor()
      if cby < #history then
        setCursor(1, cby + 1)
        redraw()
        ende()
      end
    end
  
    local function delete()
      copyIfNecessary()
      local cbx, cby = getCursor()
      if cbx <= unicode.len(line()) then
        history[cby] = unicode.sub(line(), 1, cbx - 1) ..
                       unicode.sub(line(), cbx + 1)
        local cx, cy = term.getCursor()
        local w, h = component.gpu.getResolution()
        component.gpu.copy(cx + 1, cy, w - cx, 1, -1, 0)
        local br = cbx + (w - cx)
        local char = unicode.sub(line(), br, br)
        if not char or unicode.len(char) == 0 then
          char = " "
        end
        component.gpu.set(w, cy, char)
      end
    end
  
    local function insert(value)
      copyIfNecessary()
      local cx, cy = term.getCursor()
      local cbx, cby = getCursor()
      local w, h = component.gpu.getResolution()
      history[cby] = unicode.sub(line(), 1, cbx - 1) ..
                     value ..
                     unicode.sub(line(), cbx)
      local len = unicode.len(value)
      local n = w - (cx - 1) - len
      if n > 0 then
        component.gpu.copy(cx, cy, n, 1, len, 0)
      end
      component.gpu.set(cx, cy, value)
      right(len)
    end
  
    local function onKeyDown(char, code)
      term.setCursorBlink(false)
      if code == keyboard.keys.back then
        if left() then delete() end
      elseif code == keyboard.keys.delete then
        delete()
      elseif code == keyboard.keys.left then
        left()
      elseif code == keyboard.keys.right then
        right()
      elseif code == keyboard.keys.home then
        home()
      elseif code == keyboard.keys["end"] then
        ende()
      elseif code == keyboard.keys.up then
        up()
      elseif code == keyboard.keys.down then
        down()
      elseif code == keyboard.keys.enter then
        local cbx, cby = getCursor()
        if cby ~= #history then -- bring entry to front
          history[#history] = line()
          table.remove(history, cby)
        end
        return true, history[#history] .. "\n"
      elseif keyboard.isControlDown() and code == keyboard.keys.d then
        if line() == "" then
          history[#history] = ""
          return true, nil
        end
      elseif keyboard.isControlDown() and code == keyboard.keys.c then
        history[#history] = ""
        return true, nil
      elseif not keyboard.isControl(char) then
        insert(unicode.char(char))
      end
      term.setCursorBlink(true)
      term.setCursorBlink(true) -- force toggle to caret
    end
  
    local function onClipboard(value)
      copyIfNecessary()
      term.setCursorBlink(false)
      local cbx, cby = getCursor()
      local l = value:find("\n", 1, true)
      if l then
        history[cby] = unicode.sub(line(), 1, cbx - 1)
        redraw()
        insert(unicode.sub(value, 1, l - 1))
        return true, line() .. "\n"
      else
        insert(value)
        term.setCursorBlink(true)
        term.setCursorBlink(true) -- force toggle to caret
      end
    end
  
    local function cleanup()
      if history[#history] == "" then
        table.remove(history)
      end
      term.setCursorBlink(false)
      if term.getCursor() > 1 and dobreak ~= false then
        print()
      end
    end
  
    term.setCursorBlink(true)
    while term.isAvailable() do
      local ocx, ocy = getCursor()
      local ok, name, address, charOrValue, code = pcall(event.pull)
      if not ok then
        cleanup()
        error("interrupted", 0)
      end
      local ncx, ncy = getCursor()
      if ocx ~= ncx or ocy ~= ncy then
        cleanup()
        return "" -- soft fail the read if someone messes with the term
      end
      if term.isAvailable() and -- may have changed since pull
         type(address) == "string" and
         component.isPrimary(address)
      then
        local done, result
        if name == "key_down" then
          done, result = onKeyDown(charOrValue, code)
        elseif name == "clipboard" then
          done, result = onClipboard(charOrValue)
        end
        if done then
          cleanup()
          return result
        end
      end
    end
    cleanup()
    return nil -- fail the read if term becomes unavailable
  end
  
  function term.write(value, wrap)
    if not term.isAvailable() then
      return
    end
    value = tostring(value)
    if unicode.len(value) == 0 then
      return
    end
    do
      local noBell = value:gsub("\a", "")
      if #noBell ~= #value then
        value = noBell
        computer.beep()
      end
    end
    value = text.detab(value)
    local w, h = component.gpu.getResolution()
    if not w then
      return -- gpu lost its screen but the signal wasn't processed yet.
    end
    local blink = term.getCursorBlink()
    term.setCursorBlink(false)
    local line, nl
    repeat
      local wrapAfter, margin = math.huge, math.huge
      if wrap then
        wrapAfter, margin = w - (cursorX - 1), w
      end
      line, value, nl = text.wrap(value, wrapAfter, margin)
      component.gpu.set(cursorX, cursorY, line)
      cursorX = cursorX + unicode.len(line)
      if nl or (cursorX > w and wrap) then
        cursorX = 1
        cursorY = cursorY + 1
      end
      if cursorY > h then
        component.gpu.copy(1, 1, w, h, 0, -1)
        component.gpu.fill(1, h, w, 1, " ")
        cursorY = h
      end
    until not value
    term.setCursorBlink(blink)
  end
  
  -------------------------------------------------------------------------------
  
  return term
end
local function printProcess(...)
  local args = table.pack(...)
  local argstr = ""
  for i = 1, args.n do
    local arg = tostring(args[i])
    if i > 1 then
      arg = "\t" .. arg
    end
    argstr = argstr .. arg
  end
  return argstr
end
function print(...)
  term.write(printProcess(...) .. "\n", true)
end
function printErr(...)
		local c = component.gpu.getForeground()
		component.gpu.setForeground(0xFF0000)
		print(...)
		component.gpu.setForeground(c)
end
function printPaged(...)
  argstr = printProcess(...) .. "\n"
  local i = 0
  local p = 0
  function readline()
    i = string.find(argstr, "\n", i+1)    -- find 'next' newline
    if i == nil then return nil end
	local out = argstr:sub(p,i)
	p = i + 1
    return out
  end
  local function readlines(file, line, num)
    local w, h = component.gpu.getResolution()
    num = num or (h - 1)
	--num = num or (h)
    term.setCursorBlink(false)
    for _ = 1, num do
      if not line then
        line = readline()
        if not line then -- eof
          return nil
        end
      end
      local wrapped
      wrapped, line = text.wrap(text.detab(line), w, w)
      term.write(wrapped .. "\n")
    end
    term.setCursor(1, h)
    term.write("Press enter or space to continue:")
    term.setCursorBlink(true)
    return true
  end

  local line = nil
  while true do
    if not readlines(file, line) then
      return
    end
    while true do
      local event, address, char, code = event.pull("key_down")
      if component.isPrimary(address) then
        if code == keyboard.keys.q then
          term.setCursorBlink(false)
          term.clearLine()
          return
        elseif code == keyboard.keys.space or code == keyboard.keys.pageDown then
		  term.clearLine()
          break
        elseif code == keyboard.keys.enter or code == keyboard.keys.down then
          term.clearLine()
          if not readlines(file, line, 1) then
            return
          end
        end
      end
    end
  end

end
--load programs
function loadfile(file, mode, env)
  local handle, reason = filesystem.open(file)
  if not handle then
    error(reason, 2)
  end
  local buffer = ""
  repeat
    local data, reason = filesystem.read(handle)
    if not data and reason then
      error(reason)
    end
    buffer = buffer .. (data or "")
  until not data
  filesystem.close(handle)
  if mode == nil then mode = "bt" end
  if env == nil then env = _G end
  return load(buffer, "=" .. file)
end

function dofile(file)
  local program, reason = loadfile(file)
  if program then
    local result = table.pack(pcall(program))
    if result[1] then
      return table.unpack(result, 2, result.n)
    else
      error(result[2])
    end
  else
    error(reason)
  end
end

--set up libs
event = event_code()
component_code()
text = text_code()
os = os_lib_code()
filesystem = fs_code()
fs = filesystem
keyboard = dofile("keyboard.lua")
term = terminal_code()
--set up terminal
if term.isAvailable() then
  component.gpu.bind(component.screen.address)
  component.gpu.setResolution(component.gpu.getResolution())
  component.gpu.setBackground(0x000000)
  component.gpu.setForeground(0xFFFFFF)
  term.setCursorBlink(true)
  term.clear()
end

print("Starting " .. _OSNAME .. "...\n")

--clean up libs
event_code, component_code, text_code, fs_code, terminal_code = nil, nil, nil, nil, nil

--map the drives
for address, componentType in component.list() do 
  if componentType == "filesystem" then filesystem.drive.autoMap(address) end
end

miniOS = {}
local function interrupt(data)
  if data[2] == "RUN" then miniOS.runfile(data[3], table.unpack(data[4])) end
end
local function runfile(file, ...)
  local program, reason = loadfile(file)
  if program then
    local result = table.pack(pcall(program, ...))
    if result[1] then
      return table.unpack(result, 2, result.n)
    else
	  if type(result[2]) == "table" then if result[2][1] then if result[2][1] == "INTERRUPT" then interrupt(result[2]) return end end end
      error(result[2], 3)
    end
  else
    error(reason, 3)
  end
end
local function kernelError()
  printErr("\nPress any key to try again.")
  term.readKey()
end
function miniOS.runfile(...)
  local _, err = pcall(runfile, ...)
  if not _ then
	printErr(err)
	--printErr("\n" .. debug.traceback())
  end
  return _
end
function require(lib)
	return _G[lib] or _G[string.lower(lib)]
end

miniOS.freeMem = computer.freeMemory()

--start command and keep it running.
local command_drive = fs.drive.getcurrent()
if filesystem.exists("autoexec.bat") then miniOS.runfile("command.lua", "autoexec.bat") else miniOS.runfile("command.lua") end
while true do
	miniOS.freeMem = computer.freeMemory()
	print()
	fs.drive.setcurrent(command_drive)
	if not miniOS.runfile("command.lua", "-c") then kernelError() end
end