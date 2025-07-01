Editor = {
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

local cursor = Editor.cursor
local buffer = Editor.buffer
local utf8 = Editor.utf8

function move(dx, dy)
    cursor.row = clamp(cursor.row + dy, 1, line_count())
    cursor.col = clamp(cursor.col + dx, 1,
                               Editor.utf8.len(Editor.buffer[cursor.row]) + 1)
end

function line_count() return #Editor.buffer end
function current_line() return Editor.buffer[Editor.cursor.row] end
function clamp(val, min, max)
    if val < min then
        return min
    elseif val > max then
        return max
    else
        return val
    end
end
