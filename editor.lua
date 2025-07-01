Editor = {
    utf8 = require('utf8'),
    buffer = {""},
    cursor = {row = 1, col = 1},
}

local cursor = Editor.cursor
local buffer = Editor.buffer
local utf8 = Editor.utf8

function move(dx, dy)
    cursor.row = App.clamp(cursor.row + dy, 1, App.line_count())
    cursor.col = App.clamp(cursor.col + dx, 1,
                               Editor.utf8.len(Editor.buffer[cursor.row]) + 1)
end
