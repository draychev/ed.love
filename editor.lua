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

function insert_char(character)
    local ch = Editor.lookup[character] or character -- fallback
    local line = current_line()
    local bytepos = Editor.utf8.offset(line, Editor.cursor.col)
    buffer[Editor.cursor.row] = line:sub(1, bytepos - 1) .. ch ..
                                    line:sub(bytepos)
    move(1, 0)
end

function backspace()
    if cursor.col > 1 then
        local line = current_line()
        print("DEBUG(app.backspace): line=" .. line .. ", cursor.col=" ..
                  cursor.col)
        local b1 = Editor.utf8.offset(line, cursor.col)
        local b0 = Editor.utf8.offset(line, cursor.col - 1)
        print("DEBUG(app.backspace): b0=" .. b0 .. ", b1=" .. b1)
        buffer[cursor.row] = line:sub(1, b0 - 1) .. line:sub(b1)
        move(-1, 0)
    elseif cursor.row > 1 then
        local prev_len = Editor.utf8.len(buffer[cursor.row - 1])
        buffer[cursor.row - 1] = buffer[cursor.row - 1] .. buffer[cursor.row]
        table.remove(buffer, cursor.row)
        cursor.row = cursor.row - 1
        cursor.col = prev_len + 1
    end
end
