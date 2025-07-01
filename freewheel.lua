-- save/restore framework globals on very first load
freewheel = {}

function freewheel.snapshot_love()
    if Love_snapshot then return end
    Love_snapshot = {}
    -- save the entire initial font; it doesn't seem reliably recreated using newFont
    Love_snapshot.initial_font = love.graphics.getFont()
end
