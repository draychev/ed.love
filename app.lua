App = {
    utf8 = require('utf8'),
    buffer = {""},
    cursor = {row = 1, col = 1},
    filename = nil,
    minibuffer = "",
    mode = "edit", -- "edit" or "mini"
    pendingX = false,
    ttf = "fonts/BerkeleyMonoVariable-Regular.ttf",
    -- ttf        = "fonts/lucida-grande.ttf",
    font_size = 18,
    lookup = {escape = "\27", tab = "\t", space = " "}
}

local anisotropy = 1 -- 0 is sharpest; 1 less so
love.graphics.setDefaultFilter("linear", "linear", anisotropy)
-- font = love.graphics.newFont(
App.font = love.graphics.newFont(App.ttf, App.font_size)
App.font:setFilter("linear", "linear", anisotropy)
love.graphics.setFont(App.font)
App.lh = App.font:getHeight()

function App.line_count() return #App.buffer end
function App.current_line() return App.buffer[App.cursor.row] end
function App.clamp(val, min, max)
    if val < min then
        return min
    elseif val > max then
        return max
    else
        return val
    end
end

-- one iteration of the event loop
-- return nil to continue the event loop, non-nil to quit
function App.run_frame()
    if love.event then
        love.event.pump()
        for name, a, b, c, d, e, f in love.event.poll() do
            if name == "quit" then
                if not love.quit or not love.quit() then
                    return a or 0
                end
            end
            love.handlers[name](a, b, c, d, e, f)
        end
    end

    local dt = love.timer.step()

    App.update(dt)

    love.graphics.origin()
    love.graphics.clear(love.graphics.getBackgroundColor())
    App.draw(utf8, buffer, lh, cursor)
    love.graphics.present()

    love.timer.sleep(0.001)

    -- returning nil continues the loop
end

-- The rest of this file wraps around various LÖVE primitives to support
-- automated tests. Often tests will run with a fake version of a primitive
-- that redirects to the real love.* version once we're done with tests.
--
-- Not everything is so wrapped yet. Sometimes you still have to use love.*
-- primitives directly.

function App.love_version()
    local major_version, minor_version = love.getVersion()
    local version = major_version .. '.' .. minor_version
    return version, major_version
end

function App.undo_initialize() love.graphics.setFont(Love_snapshot.initial_font) end

function App.run_tests(record_error_fn)
    local sorted_names = {}
    for name, binding in pairs(_G) do
        if name:find('test_') == 1 then table.insert(sorted_names, name) end
    end
    table.sort(sorted_names)
    local globals = App.shallow_copy_all_globals()
    App = App_for_tests
    local saved_font = love.graphics.getFont()
    love.graphics.setFont(Love_snapshot.initial_font)
    -- ?   App.initialize_for_test() -- debug: run a single test at a time like these 2 lines
    -- ?   test_search()
    for _, name in ipairs(sorted_names) do
        App.initialize_for_test()
        -- ?     print('=== '..name)
        xpcall(_G[name], function(err) record_error_fn(name, err) end)
    end
    love.graphics.setFont(saved_font)
    -- restore all global state except Test_errors
    local test_errors = Test_errors
    App.restore_all_globals(globals)
    Test_errors = test_errors
end

function App.run_test(test, record_error_fn)
    local globals = App.shallow_copy_all_globals()
    App = App_for_tests
    local saved_font = love.graphics.getFont()
    love.graphics.setFont(Love_snapshot.initial_font)
    App.initialize_for_test()
    xpcall(test, function(err) record_error_fn('', err) end)
    love.graphics.setFont(saved_font)
    -- restore all global state except Test_errors
    local test_errors = Test_errors
    App.restore_all_globals(globals)
    Test_errors = test_errors
end

function App.initialize_for_test()
    App.screen.init {width = 100, height = 50}
    App.screen.contents = {} -- clear screen
    App.filesystem = {}
    App.source_dir = ''
    App.current_dir = ''
    App.save_dir = ''
    App.fake_keys_pressed = {}
    App.fake_mouse_state = {x = -1, y = -1}
    App.initialize_globals()
end

-- App.screen.resize and App.screen.move seem like better names than
-- love.window.setMode and love.window.setPosition respectively. They'll
-- be side-effect-free during tests, and they'll save their results in
-- attributes of App.screen for easy access.

App.screen = {}

-- Use App.screen.init in tests to initialize the fake screen.
function App.screen.init(dims)
    App.screen.width = dims.width
    App.screen.height = dims.height
end

function App.screen.resize(width, height, flags)
    App.screen.width = width
    App.screen.height = height
    App.screen.flags = flags
end

function App.screen.size()
    return App.screen.width, App.screen.height, App.screen.flags
end

function App.screen.move(x, y, displayindex)
    App.screen.x = x
    App.screen.y = y
    App.screen.displayindex = displayindex
end

function App.screen.position()
    return App.screen.x, App.screen.y, App.screen.displayindex
end

-- If you use App.screen.print instead of love.graphics.print,
-- tests will be able to check what was printed using App.screen.check below.
--
-- One drawback of this approach: the y coordinate used depends on font size,
-- which feels brittle.

function App.screen.print(msg, x, y)
    local screen_row = 'y' .. tostring(y)
    -- ?   print('drawing "'..msg..'" at y '..tostring(y))
    local screen = App.screen
    if screen.contents[screen_row] == nil then
        screen.contents[screen_row] = {}
        for i = 0, screen.width - 1 do
            screen.contents[screen_row][i] = ''
        end
    end
    if x < screen.width then screen.contents[screen_row][x] = msg end
end

function App.screen.check(y, expected_contents, msg)
    -- ?   print('checking for "'..expected_contents..'" at y '..tostring(y))
    local screen_row = 'y' .. tostring(y)
    local contents = ''
    if App.screen.contents[screen_row] == nil then
        error('no text at y ' .. tostring(y))
    end
    for i, s in ipairs(App.screen.contents[screen_row]) do
        contents = contents .. s
    end
end

-- If you access the time using App.get_time instead of love.timer.getTime,
-- tests will be able to move the time back and forwards as needed using
-- App.wait_fake_time below.

App.time = 1
function App.get_time() return App.time end
function App.wait_fake_time(t) App.time = App.time + t end

function App.width(text) return love.graphics.getFont():getWidth(text) end

-- If you access the clipboard using App.get_clipboard and App.set_clipboard
-- instead of love.system.getClipboardText and love.system.setClipboardText
-- respectively, tests will be able to manipulate the clipboard by
-- reading/writing App.clipboard.

App.clipboard = ''
function App.get_clipboard() return App.clipboard end
function App.set_clipboard(s) App.clipboard = s end

-- In tests I mostly send chords all at once to the keyboard handlers.
-- However, you'll occasionally need to check if a key is down outside a handler.
-- If you use App.key_down instead of love.keyboard.isDown, tests will be able to
-- simulate keypresses using App.fake_key_press and App.fake_key_release
-- below. This isn't very realistic, though, and it's up to tests to
-- orchestrate key presses that correspond to the handlers they invoke.

App.fake_keys_pressed = {}
function App.key_down(key) return App.fake_keys_pressed[key] end

function App.fake_key_press(key) App.fake_keys_pressed[key] = true end
function App.fake_key_release(key) App.fake_keys_pressed[key] = nil end

-- Tests mostly will invoke mouse handlers directly. However, you'll
-- occasionally need to check if a mouse button is down outside a handler.
-- If you use App.mouse_down instead of love.mouse.isDown, tests will be able to
-- simulate mouse clicks using App.fake_mouse_press and App.fake_mouse_release
-- below. This isn't very realistic, though, and it's up to tests to
-- orchestrate presses that correspond to the handlers they invoke.

App.fake_mouse_state = {x = -1, y = -1} -- x,y always set

function App.mouse_move(x, y)
    App.fake_mouse_state.x = x
    App.fake_mouse_state.y = y
end
function App.mouse_down(mouse_button) return App.fake_mouse_state[mouse_button] end
function App.mouse_x() return App.fake_mouse_state.x end
function App.mouse_y() return App.fake_mouse_state.y end

function App.fake_mouse_press(x, y, mouse_button)
    App.fake_mouse_state.x = x
    App.fake_mouse_state.y = y
    App.fake_mouse_state[mouse_button] = true
end
function App.fake_mouse_release(x, y, mouse_button)
    App.fake_mouse_state.x = x
    App.fake_mouse_state.y = y
    App.fake_mouse_state[mouse_button] = nil
end

-- If you use App.open_for_reading and App.open_for_writing instead of other
-- various Lua and LÖVE helpers, tests will be able to check the results of
-- file operations inside the App.filesystem table.

function App.open_for_reading(filename)
    if App.filesystem[filename] then
        return {
            lines = function(self)
                return App.filesystem[filename]:gmatch('[^\n]+')
            end,
            read = function(self) return App.filesystem[filename] end,
            close = function(self) end
        }
    end
end

function App.read_file(filename) return App.filesystem[filename] end

function App.open_for_writing(filename)
    App.filesystem[filename] = ''
    return {
        write = function(self, s)
            App.filesystem[filename] = App.filesystem[filename] .. s
        end,
        close = function(self) end
    }
end

function App.write_file(filename, contents)
    App.filesystem[filename] = contents
    return --[[status]] true
end

function App.mkdir(dirname)
    -- nothing in test mode
end

function App.remove(filename) App.filesystem[filename] = nil end

-- Some helpers to trigger an event and then refresh the screen. Akin to one
-- iteration of the event loop.

-- all textinput events are also keypresses
-- TODO: handle chords of multiple keys
function App.run_after_textinput(t)
    App.keypressed(t)
    App.textinput(t)
    App.keyreleased(t)
    App.screen.contents = {}
    App.draw(utf8, buffer, lh, cursor)
end

-- not all keys are textinput
-- TODO: handle chords of multiple keys
function App.run_after_keychord(chord, key)
    App.keychord_press(chord, key)
    App.keyreleased(key)
    App.screen.contents = {}
    App.draw(utf8, buffer, lh, cursor)
end

function App.run_after_mouse_click(x, y, mouse_button)
    App.fake_mouse_press(x, y, mouse_button)
    App.mousepressed(x, y, mouse_button)
    App.fake_mouse_release(x, y, mouse_button)
    App.mousereleased(x, y, mouse_button)
    App.screen.contents = {}
    App.draw(utf8, buffer, lh, cursor)
end

function App.run_after_mouse_press(x, y, mouse_button)
    App.fake_mouse_press(x, y, mouse_button)
    App.mousepressed(x, y, mouse_button)
    App.screen.contents = {}
    App.draw(utf8, buffer, lh, cursor)
end

function App.run_after_mouse_release(x, y, mouse_button)
    App.fake_mouse_release(x, y, mouse_button)
    App.mousereleased(x, y, mouse_button)
    App.screen.contents = {}
    App.draw(utf8, buffer, lh, cursor)
end

-- miscellaneous internal helpers

function App.color(color)
    love.graphics.setColor(color.r, color.g, color.b, color.a)
end

function App.shallow_copy_all_globals()
    local result = {}
    for k, v in pairs(_G) do result[k] = v end
    return result
end

function App.restore_all_globals(x)
    -- delete extra bindings
    for k, v in pairs(_G) do if x[k] == nil then _G[k] = nil end end
    -- restore previous bindings
    for k, v in pairs(x) do _G[k] = v end
end

-- Test_errors will be an array
function record_error(test_name, err)
    local err_without_line_number = err:gsub('^[^:]*:[^:]*: ', '')
    table.insert(Test_errors, test_name .. ' -- ' .. err_without_line_number)
end

-- Test_errors will be a table by test name
function record_error_by_test(test_name, err)
    local err_without_line_number = err:gsub('^[^:]*:[^:]*: ', '')
    Test_errors[test_name] = err_without_line_number
    -- ?   Test_errors[test_name] = debug.traceback(err_without_line_number)
end

function App.insert_char(character)
    local ch = App.lookup[character] or character -- fallback
    local line = App.current_line()
    local bytepos = App.utf8.offset(line, App.cursor.col)
    App.buffer[App.cursor.row] = line:sub(1, bytepos - 1) .. ch ..
                                     line:sub(bytepos)
    App.move(1, 0)
end

function App.move(dx, dy)
    App.cursor.row = App.clamp(App.cursor.row + dy, 1, App.line_count())
    App.cursor.col = App.clamp(App.cursor.col + dx, 1,
                               App.utf8.len(App.buffer[App.cursor.row]) + 1)
end

function App.backspace()
    local cursor = App.cursor
    local buffer = App.buffer
    if cursor.col > 1 then
        local line = App.current_line()
        print("DEBUG(app.App.backspace): line=" .. line .. ", cursor.col=" ..
                  cursor.col)
        local b1 = App.utf8.offset(line, cursor.col)
        local b0 = App.utf8.offset(line, cursor.col - 1)
        print("DEBUG(app.App.backspace): b0=" .. b0 .. ", b1=" .. b1)
        buffer[cursor.row] = line:sub(1, b0 - 1) .. line:sub(b1)
        App.move(-1, 0)
    elseif cursor.row > 1 then
        local prev_len = App.utf8.len(buffer[cursor.row - 1])
        buffer[cursor.row - 1] = buffer[cursor.row - 1] .. buffer[cursor.row]
        table.remove(buffer, cursor.row)
        cursor.row = cursor.row - 1
        cursor.col = prev_len + 1
    end
end

function App.resize(w, h)
    -- ?   print(("Window resized to width: %d and height: %d."):format(w, h))
    App.screen.width, App.screen.height = w, h
    -- some hysteresis while resizing
    if Current_time < Last_resize_time + 0.1 then return end
    Last_resize_time = Current_time
    if on.resize then on.resize(w, h) end
end

function App.filedropped(file) if on.file_drop then on.file_drop(file) end end

function App.draw(utf8, buffer, lh, cursor) if on.draw then on.draw(App) end end

function App.update(dt)
    Current_time = Current_time + dt
    -- some hysteresis while resizing
    if Current_time < Last_resize_time + 0.1 then return end
    Cursor_time = Cursor_time + dt
    live.update(dt)
    if on.update then on.update(dt) end
end

function App.mousepressed(x, y, mouse_button, is_touch, presses)
    Cursor_time = 0 -- ensure cursor is visible immediately after it moves
    love.keyboard.setTextInput(true) -- bring up keyboard on touch screen
    if on.mouse_press then
        on.mouse_press(x, y, mouse_button, is_touch, presses)
    end
end

function App.mousereleased(x, y, mouse_button, is_touch, presses)
    Cursor_time = 0 -- ensure cursor is visible immediately after it moves
    if on.mouse_release then
        on.mouse_release(x, y, mouse_button, is_touch, presses)
    end
end

function App.mousemoved(x, y, dx, dy, istouch)
    if on.mouse_move then on.mouse_move(x, y, dx, dy, istouch) end
end

function App.wheelmoved(dx, dy)
    Cursor_time = 0 -- ensure cursor is visible immediately after it moves
    if on.mouse_wheel_move then on.mouse_wheel_move(dx, dy) end
end

function App.mousefocus(in_focus)
    Cursor_time = 0 -- ensure cursor is visible immediately after it moves
    if on.mouse_focus then on.mouse_focus(in_focus) end
end

function App.focus(in_focus)
    if in_focus then Last_focus_time = Current_time end
    if in_focus then
        love.graphics.setBackgroundColor(1, 1, 1)
    else
        love.graphics.setBackgroundColor(0.8, 0.8, 0.8)
    end
    if on.focus then on.focus(in_focus) end
end

-- App.keypressed is defined in keychord.lua

function App.keychord_press(chord, key, scancode, is_repeat)
    -- ignore events for some time after window in focus (mostly alt-tab)
    if Current_time < Last_focus_time + 0.01 then return end
    Cursor_time = 0 -- ensure cursor is visible immediately after it moves
    if on.keychord_press then
        on.keychord_press(chord, key, scancode, is_repeat, App) -- TODO: find a better way - why pass App?
    end
end

function App.textinput(t)
    -- ignore events for some time after window in focus (mostly alt-tab)
    if Current_time < Last_focus_time + 0.01 then return end
    Cursor_time = 0 -- ensure cursor is visible immediately after it moves
    if on.text_input then on.text_input(t, App) end
end

function App.keyreleased(key, scancode)
    -- ignore events for some time after window in focus (mostly alt-tab)
    if Current_time < Last_focus_time + 0.01 then return end
    Cursor_time = 0 -- ensure cursor is visible immediately after it moves
    if on.key_release then on.key_release(key, scancode) end
end

function App.initialize(arg, unfiltered_arg)
    Arg, Unfiltered_arg = arg, unfiltered_arg
    love.keyboard.setKeyRepeat(true)

    Editor_state = nil -- not used outside editor tests

    love.graphics.setBackgroundColor(1, 1, 1)

    if love.filesystem.getInfo('config') then
        load_settings()
    else
        initialize_default_settings()
    end

    -- app-specific stuff
    -- keep a few blank lines around: https://merveilles.town/@akkartik/110084833821965708
    love.window.setTitle('broadsheet.love')

    if on.initialize then on.initialize(arg, unfiltered_arg) end

    if rawget(_G, 'jit') then
        jit.off()
        jit.flush()
    end
end

-- called both in tests and real run
function App.initialize_globals()
    Supported_versions = {
        '11.5', '11.4', '11.3', '11.2', '11.1', '11.0', '12.0'
    } -- put the recommended version first
    Error_message = ''
    Error_count = 0

    -- tests currently mostly clear their own state

    -- blinking cursor
    Cursor_time = 0

    -- for hysteresis in a few places
    Current_time = 0
    Last_focus_time = 0 -- https://love2d.org/forums/viewtopic.php?p=249700
    Last_resize_time = 0
end

-- *** *** ***
local function load_file(path)
    buffer = {""}
    local f = io.open(path, "r")
    if f then
        buffer = {}
        for line in f:lines() do table.insert(buffer, line) end
        f:close()
        filename = path
    else
        buffer = {""}
        filename = path
    end
    cursor.row, cursor.col = 1, 1
end

local function save_file(path)
    local f = io.open(path, "w")
    if not f then return end
    for _, line in ipairs(buffer) do f:write(line, "\n") end
    f:close()
    filename = path
end

local function delete_char()
    local line = App.current_line()
    local b0 = App.utf8.offset(line, cursor.col)
    if b0 and b0 <= #line then
        local b1 = App.utf8.offset(line, cursor.col + 1) or (#line + 1)
        buffer[cursor.row] = line:sub(1, b0 - 1) .. line:sub(b1)
    elseif cursor.row < App.line_count() then
        buffer[cursor.row] = line .. buffer[cursor.row + 1]
        table.remove(buffer, cursor.row + 1)
    end
end

local function kill_to_eol()
    buffer[cursor.row] = App.current_line():sub(1, utf8.offset(current_line(),
                                                               cursor.col) - 1)
end

--- stuff from akkartik --------------------
-- called only for real run

function initialize_default_settings()
    local font_height = 20
    love.graphics.setFont(love.graphics.newFont(font_height))
    initialize_window_geometry()
end

function initialize_window_geometry()
    -- Initialize window width/height and make window resizable.
    --
    -- I get tempted to have opinions about window dimensions here, but they're
    -- non-portable:
    --  - maximizing doesn't work on mobile and messes things up
    --  - maximizing keeps the title bar on screen in Linux, but off screen on
    --    Windows. And there's no way to get the height of the title bar.
    -- It seems more robust to just follow LÖVE's default window size until
    -- someone overrides it.
    App.screen.width, App.screen.height, App.screen.flags = App.screen.size()
    App.screen.flags.resizable = true
    App.screen.resize(App.screen.width, App.screen.height, App.screen.flags)
end

-- plumb all other handlers through to on.*
for handler_name in pairs(love.handlers) do
    if App[handler_name] == nil then
        App[handler_name] = function(...)
            if on[handler_name] then on[handler_name](...) end
        end
    end
end
