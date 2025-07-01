-- A general architecture for free-wheeling, live programs:
--  on startup:
--    scan both the app directory and the save directory for files with numeric prefixes
--    load files in order
--
--  then start drawing frames on screen and reacting to events
--
--  events from keyboard and mouse are handled as the app desires
--
--  on incoming messages to a specific file, the app must:
--    determine the definition name from the first word
--    execute the value, returning any errors
--    look up the filename for the definition or define a new filename for it
--    save the message's value to the filename
--
--  if a game encounters a run-time error, send it to the driver and await
--  further instructions. The app will go unresponsive in the meantime, that
--  is expected. To shut it down cleanly, type C-q in the driver.
-- We try to save new definitions in the source directory, but this is not
-- possible if the app lives in a .love file. In that case new definitions
-- go in the save dir.
-- namespace for these functions
live = {}
-- state for these functions
Live = {}

-- a namespace of frameworky callbacks
-- these will be modified live
on = {}

-- === on startup, load all files with numeric prefix

function live.load()
    if Live.frozen_definitions == nil then -- a second run due to initialization errors will contain definitions we don't want to freeze
        live.freeze_all_existing_definitions()
    end

    -- version control
    Live.filenames_to_load = {} -- filenames in order of numeric prefix
    Live.filename = {} -- map from definition name to filename (including numeric prefix)
    Live.final_prefix = 0
    live.load_files_so_far()

    -- some hysteresis
    Live.previous_read = 0
end

function live.load_files_so_far()
    for _, filename in ipairs(love.filesystem.getDirectoryItems('')) do
        local numeric_prefix, root = filename:match('^(%d+)-(.+)')
        if numeric_prefix and tonumber(numeric_prefix) > 0 then -- skip 0000
            Live.filename[root] = filename
            table.insert(Live.filenames_to_load, filename)
            Live.final_prefix = math.max(Live.final_prefix,
                                         tonumber(numeric_prefix))
        end
    end
    table.sort(Live.filenames_to_load)
    -- load files from save dir
    for _, filename in ipairs(Live.filenames_to_load) do
        -- ?     print('loading', filename)
        local buf = love.filesystem.read(filename)
        assert(buf and buf ~= '')
        local _, definition_name = filename:match('^(%d+)-(.+)')
        local status, err = live.eval(buf, definition_name)
        if not status then error(err) end
    end
end

APP = 'fw_app'

-- === on each frame, check for messages and alter the app as needed

function live.update(dt)
    if Current_time - Live.previous_read > 0.1 then
        local buf = live.receive_from_driver()
        if buf then
            local possibly_mutated = live.run(buf)
            if possibly_mutated then
                if on.code_change then on.code_change() end
            end
        end
        Live.previous_read = Current_time
    end
end

-- look for a message from outside, and return nil if there's nothing
function live.receive_from_driver()
    local f = io.open(love.filesystem.getAppdataDirectory() ..
                          '/_love_akkartik_driver_app')
    if f == nil then return nil end
    local result = f:read('*a')
    f:close()
    if result == '' then return nil end -- empty file == no message
    print('<=' .. color_escape( --[[bold]] 1, --[[blue]] 4))
    print(result)
    print(reset_terminal())
    os.remove(love.filesystem.getAppdataDirectory() ..
                  '/_love_akkartik_driver_app')
    return result
end

function live.send_to_driver(msg)
    local f = io.open(love.filesystem.getAppdataDirectory() ..
                          '/_love_akkartik_app_driver', 'w')
    if f == nil then return end
    f:write(msg)
    f:close()
    print('=>' .. color_escape(0, --[[green]] 2))
    print(msg)
    print(reset_terminal())
end

function live.send_run_time_error_to_driver(msg)
    local f = io.open(love.filesystem.getAppdataDirectory() ..
                          '/_love_akkartik_app_driver_run_time_error', 'w')
    if f == nil then return end
    f:write(msg)
    f:close()
    print('=>' .. color_escape(0, --[[red]] 1))
    print(msg)
    print(reset_terminal())
end

-- args:
--   format: 0 for normal, 1 for bold
--   color: 0-15
function color_escape(format, color)
    return ('\027[%d;%dm'):format(format, 30 + color)
end

function reset_terminal() return '\027[m' end

-- returns true if we might have mutated the app, by either creating or deleting a definition
function live.run(buf)
    local cmd = live.get_cmd_from_buffer(buf)
    assert(cmd)
    if cmd == 'QUIT' then
        love.event.quit(1)
    elseif cmd == 'RESTART' then
        restart()
    elseif cmd == 'MANIFEST' then
        Live.filename[APP] = love.filesystem.getIdentity()
        live.send_to_driver(json.encode(Live.filename))
    elseif cmd == 'DELETE' then
        local definition_name = buf:match('^%s*%S+%s+(%S+)')
        if Live.frozen_definitions[definition_name] then
            live.send_to_driver('ERROR definition ' .. definition_name ..
                                    ' is part of Freewheeling infrastructure and cannot be deleted.')
            return
        end
        if Live.filename[definition_name] then
            local index = table.find(Live.filenames_to_load,
                                     Live.filename[definition_name])
            table.remove(Live.filenames_to_load, index)
            live.eval(definition_name .. ' = nil', 'driver') -- ignore errors which will likely be from keywords like `function = nil`
            -- try to remove the file from both source_dir and save_dir
            -- this won't work for files inside .love files
            App.remove(App.source_dir .. Live.filename[definition_name])
            love.filesystem.remove(Live.filename[definition_name])
            Live.filename[definition_name] = nil
        end
        live.send_to_driver('{}')
        return true
    elseif cmd == 'GET' then
        local definition_name = buf:match('^%s*%S+%s+(%S+)')
        local val, _ = live.get_binding(definition_name)
        if val then
            live.send_to_driver(val)
        else
            live.send_to_driver('ERROR no such value')
        end
    elseif cmd == 'GET*' then
        -- batch version of GET
        local result = {}
        for definition_name in buf:gmatch('%s+(%S+)') do
            print(definition_name)
            local val, _ = live.get_binding(definition_name)
            if val then table.insert(result, val) end
        end
        local delimiter = '\n==fw: definition boundary==\n'
        live.send_to_driver(table.concat(result, delimiter) .. delimiter) -- send a final delimiter to simplify the driver's task
    elseif cmd == 'DEFAULT_MAP' then
        local contents = love.filesystem.read('default_map')
        if contents == nil then contents = '{}' end
        live.send_to_driver(contents)
        -- other commands go here
    else
        local definition_name = live.get_definition_name_from_buffer(buf)
        if definition_name == nil then
            -- contents are all Lua comments; we don't currently have a plan for them
            live.send_to_driver('ERROR empty definition')
            return
        end
        print('definition name is ' .. definition_name)
        if Live.frozen_definitions[definition_name] then
            live.send_to_driver('ERROR definition ' .. definition_name ..
                                    ' is part of Freewheeling infrastructure and cannot be safely edited live.')
            return
        end
        local status, err = live.eval(buf, definition_name)
        if not status then
            -- throw an error
            live.send_to_driver('ERROR ' .. cleaned_up_frame(tostring(err)))
            return
        end
        -- eval succeeded without errors; persist the definition
        local filename = Live.filename[definition_name]
        if filename == nil then
            Live.final_prefix = Live.final_prefix + 1
            filename = ('%04d-%s'):format(Live.final_prefix, definition_name)
            table.insert(Live.filenames_to_load, filename)
            Live.filename[definition_name] = filename
        end
        -- try to write to source dir
        local status, err = App.write_file(App.source_dir .. filename, buf)
        if err then
            -- not possible; perhaps it's a .love file
            -- try to write to save dir
            local status, err2 = love.filesystem.write(filename, buf)
            if err2 then
                -- throw an error
                live.send_to_driver('ERROR ' .. tostring(err .. '\n\n' .. err2))
                return true
            end
        end
        return true
    end
end

function live.get_cmd_from_buffer(buf)
    -- return the first word
    return buf:match('^%s*(%S+)')
end

function live.get_definition_name_from_buffer(buf)
    return first_noncomment_word(buf)
end

-- return the first word (separated by whitespace) that's not in a Lua comment
-- or empty string if there's nothing
-- ignore strings; we don't expect them to be the first word in a program
function first_noncomment_word(str)
    local pos = 1
    while pos <= #str do -- not Unicode-aware; hopefully it doesn't need to be
        if str:sub(pos, pos) == '-' then
            -- skip any comments
            if str:sub(pos + 1, pos + 1) == '-' then
                -- definitely start of a comment
                local long_comment_header = str:match('^%[=*%[', pos + 2)
                if long_comment_header then
                    -- long comment
                    local long_comment_trailer =
                        long_comment_header:gsub('%[', ']')
                    pos = str:find(long_comment_trailer, pos, --[[plain]] true)
                    if pos == nil then return '' end -- incomplete comment; no first word
                    pos = pos + #long_comment_trailer
                else
                    -- line comment
                    pos = str:find('\n', pos)
                    if pos == nil then return '' end -- incomplete comment; no first word
                end
            end
        end
        -- any non-whitespace that's not a comment is the first word
        if str:sub(pos, pos):match('%s') then
            pos = pos + 1
        else
            return str:match('^%S*', pos)
        end
    end
    return ''
end

function live.get_binding(name)
    if Live.filename[name] then
        return love.filesystem.read(Live.filename[name])
    end
end

function table.find(h, x) for k, v in pairs(h) do if v == x then return k end end end

-- Wrapper for Lua's weird evaluation model.
-- Lua is persnickety about expressions vs statements, so we need to do some
-- extra work to get the result of an evaluation.
-- filename will show up in call stacks for any error messages
-- return values:
--  all well -> true, ...
--  load failed -> nil, error message
--  run (pcall) failed -> false, error message
function live.eval(buf, filename)
    -- We assume a program is either correct with 'return' prefixed xor not.
    -- Is this correct? Who knows! But the Lua REPL does this as well.
    local f = load('return ' .. buf, filename or 'REPL')
    if f then return pcall(f) end
    local f, err = load(buf, filename or 'REPL')
    if f then
        return pcall(f)
    else
        return nil, err
    end
end

-- === infrastructure for performing safety checks on any new definition

-- Everything that exists before we start loading the live files is frozen and
-- can't be edited live.
function live.freeze_all_existing_definitions()
    Live.frozen_definitions = {on = true} -- special case for version 1
    local done = {}
    done[Live.frozen_definitions] = true
    live.freeze_all_existing_definitions_in(_G, {}, done)
end

function live.freeze_all_existing_definitions_in(tab, scopes, done)
    -- track duplicates to avoid cycles like _G._G, _G._G._G, etc.
    if done[tab] then return end
    done[tab] = true
    for name, binding in pairs(tab) do
        local full_name = live.full_name(scopes, name)
        -- ?     print(full_name)
        Live.frozen_definitions[full_name] = true
        if type(binding) == 'table' and full_name ~= 'package' then -- var 'package' contains copies of all modules, but not the best name; rely on people to not modify package.loaded.io.open, etc.
            table.insert(scopes, name)
            live.freeze_all_existing_definitions_in(binding, scopes, done)
            table.remove(scopes)
        end
    end
end

function live.full_name(scopes, name)
    local ns = table.concat(scopes, '.')
    if #ns == 0 then return name end
    return ns .. '.' .. name
end

-- === on error, pause the app and wait for messages

local main_run_frame = App.run_frame

-- one iteration of the event loop when showing an error
-- return nil to continue the event loop, non-nil to quit
-- We don't run this within handle_error because a second error in
-- handle_error will crash.
local error_frame_keys_down = {}
function error_run_frame()
    if love.event then
        love.event.pump()
        for name, a, b, c, d, e, f in love.event.poll() do
            if name == 'quit' then
                return a or 0
            elseif name == 'keypressed' then
                error_frame_keys_down[a] = true
                -- C-c
                if a == 'c' and
                    (error_frame_keys_down.lctrl or error_frame_keys_down.rctrl) then
                    love.system.setClipboardText(Error_message)
                end
            elseif name == 'keyreleased' then
                if not Disallow_error_recovery_on_key_release then
                    error_frame_keys_down[a] = nil
                    App.run_frame = main_run_frame
                end
            end
        end
    end

    local dt = love.timer.step()
    Current_time = Current_time + dt
    if Current_time - Live.previous_read > 0.1 then
        local buf = live.receive_from_driver()
        if buf then
            local maybe_modified = live.run(buf)
            if maybe_modified then
                -- retry
                App.run_frame = main_run_frame
                return
            end
        end
        Live.previous_read = Current_time
    end

    love.graphics.origin()
    love.graphics.clear(0, 0, 1)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(Error_message, 40, 40, 600)
    love.graphics.present()

    love.timer.sleep(0.001)

    -- returning nil continues the loop
end

-- return nil to continue the event loop, non-nil to quit
function live.handle_error(err)
    local cleaned_up_error = err
    if not err:match('stack overflow') then
        local callstack = debug.traceback('', --[[stack frame]] 2)
        cleaned_up_error =
            'Error: ' .. cleaned_up_frame(tostring(err)) .. '\n' ..
                cleaned_up_callstack(callstack)
    else
        -- call only primitive functions when we're out of stack space
    end
    live.send_run_time_error_to_driver(cleaned_up_error)
    love.graphics.setFont(love.graphics.newFont(20))
    Error_message = 'Something is wrong. Sorry!\n\n' .. cleaned_up_error ..
                        '\n\n' .. 'Options:\n' ..
                        '- press "ctrl+c" (without the quotes) to copy this message to your clipboard to send to me: ak@akkartik.com\n' ..
                        '- press any other key to retry, see if things start working again\n' ..
                        '- run driver.love to try to fix it yourself. As you do, feel free to ask me questions: ak@akkartik.com\n'
    Error_count = Error_count + 1
    if Error_count > 1 then
        Error_message = Error_message ..
                            ('\n\nThis is error #%d in this session; things will probably not improve in this session. Please copy the message and send it to me: ak@akkartik.com.'):format(
                                Error_count)
    end
    print(Error_message)
    error_frame_keys_down = {}
    App.run_frame = error_run_frame
end

-- one iteration of the event loop when showing an error
-- return nil to continue the event loop, non-nil to quit
-- We don't run this within handle_error because a second error in
-- handle_error will crash.
function initialization_error_run_frame()
    if love.event then
        love.event.pump()
        for name, a, b, c, d, e, f in love.event.poll() do
            if name == 'quit' then
                return a or 0
            elseif name == 'keypressed' then
                error_frame_keys_down[a] = true
                -- C-c
                if a == 'c' and
                    (error_frame_keys_down.lctrl or error_frame_keys_down.rctrl) then
                    love.system.setClipboardText(Error_message)
                end
            elseif name == 'keyreleased' then
                -- don't try to recover from initialization errors
                error_frame_keys_down[a] = nil
            end
        end
    end

    local dt = love.timer.step()
    Current_time = Current_time + dt
    if Current_time - Live.previous_read > 0.1 then
        local buf = live.receive_from_driver()
        if buf then
            local maybe_modified = live.run(buf)
            if maybe_modified then
                -- retry
                local success = xpcall(function()
                    App.initialize(love.arg.parseGameArguments(arg), arg)
                end, live.handle_initialization_error)
                if success then
                    App.run_frame = main_run_frame
                    return
                end
            end
        end
        Live.previous_read = Current_time
    end

    love.graphics.origin()
    love.graphics.clear(0, 0, 1)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(Error_message, 40, 40, 600)
    love.graphics.present()

    love.timer.sleep(0.001)

    -- returning nil continues the loop
end

function live.handle_initialization_error(err)
    local cleaned_up_error = err
    if not err:match('stack overflow') then
        local callstack = debug.traceback('', --[[stack frame]] 2)
        cleaned_up_error =
            'Error: ' .. cleaned_up_frame(tostring(err)) .. '\n' ..
                cleaned_up_callstack(callstack)
    else
        -- call only primitive functions when we're out of stack space
    end
    live.send_run_time_error_to_driver(cleaned_up_error)
    love.graphics.setFont(love.graphics.newFont(20))
    Error_message = 'Something is wrong. Sorry!\n\n' .. cleaned_up_error ..
                        '\n\n' .. 'Options:\n' ..
                        '- press "ctrl+c" (without the quotes) to copy this message to your clipboard to send to me: ak@akkartik.com\n' ..
                        '- run driver.love to try to fix it yourself. As you do, feel free to ask me questions: ak@akkartik.com\n'
    Error_count = Error_count + 1
    if Error_count > 1 then
        Error_message = Error_message ..
                            ('\n\nThis is error #%d in this session; things will probably not improve in this session. Please copy the message and send it to me: ak@akkartik.com.'):format(
                                Error_count)
    end
    print(Error_message)
    error_frame_keys_down = {}
    App.run_frame = initialization_error_run_frame
end

-- I tend to read code from files myself (say using love.filesystem calls)
-- rather than offload that to load().
-- Functions compiled in this manner have ugly filenames of the form [string "filename"]
-- This function cleans out this cruft from error callstacks.
-- It also strips out the numeric prefixes we introduce in filenames.
function cleaned_up_callstack(callstack)
    local frames = {}
    for frame in string.gmatch(callstack, '[^\n]+\n*') do
        table.insert(frames, cleaned_up_frame(frame))
    end
    -- the initial "stack traceback:" line was unindented and remains so
    return table.concat(frames, '\n\t')
end

function cleaned_up_frame(frame)
    local line = frame:gsub('^%s*(.-)\n?$', '%1')
    local filename, rest = line:match('([^:]*):(.*)')
    if filename then
        return cleaned_up_filename(filename) .. ':' .. rest
    else
        return line
    end
end

function cleaned_up_filename(filename)
    -- pass through frames that don't match this format
    -- this includes the initial line "stack traceback:"
    local core_filename = filename:match('^%[string "(.*)"%]$')
    if core_filename == nil then return filename end
    -- strip out the numeric prefixes we introduce in filenames
    local _, core_filename2 = core_filename:match('^(%d+)-(.+)')
    return core_filename2 or core_filename
end
