function move(dx, dy)
    App.cursor.row = App.clamp(App.cursor.row + dy, 1, App.line_count())
    App.cursor.col = App.clamp(App.cursor.col + dx, 1,
                               App.utf8.len(App.buffer[App.cursor.row]) + 1)
end
