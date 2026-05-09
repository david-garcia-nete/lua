-- first_jam_midi.lua
-- Generates a 56-bar arrangement in A minor and exports MIDI.

local TPQ = 480
local BAR = TPQ * 4
local TOTAL_BARS = 56

local song = {
    title = "First Jam Arrangement",
    tempo = 80,
    time_signature = {4, 4},
    key = "A minor",
    total_bars = TOTAL_BARS,
    progression_core = {"Am", "F", "C", "G"},
    progression_bridge = {"F", "G", "Am", "Am"},
    tracks = {
        drums = {},
        bass = {},
        chords = {},
        melody = {},
    }
}

local chord_notes = {
    Am = {57, 60, 64},
    F = {53, 57, 60},
    C = {60, 64, 67},
    G = {55, 59, 62},
}

local bass_roots = { Am = 33, F = 29, C = 36, G = 31 }
local bass_fifths = { Am = 40, F = 36, C = 43, G = 38 }

local melody_phrase = {
    {69, 72}, -- A4, C5
    {67, 69}, -- G4, A4
    {64, 67}, -- E4, G4
    {62, 64}, -- D4, E4
}

local function bytes(...)
    local out = {}
    for i, v in ipairs({...}) do
        out[i] = string.char(v)
    end
    return table.concat(out)
end

local function u16(n)
    return bytes(math.floor(n / 256) % 256, n % 256)
end

local function u32(n)
    return bytes(
        math.floor(n / 16777216) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 256) % 256,
        n % 256
    )
end

local function varlen(value)
    local buffer = value % 128
    value = math.floor(value / 128)
    while value > 0 do
        buffer = buffer * 256 + ((value % 128) + 128)
        value = math.floor(value / 128)
    end

    local out = {}
    while true do
        table.insert(out, string.char(buffer % 256))
        if buffer < 128 then break end
        buffer = math.floor(buffer / 256)
    end
    return table.concat(out)
end


local function addNote(track, tick, note, duration, velocity)
    table.insert(track, {
        tick = tick,
        note = note,
        duration = duration,
        velocity = velocity or 90,
    })
end

function addDrumPattern(bar_start, bars, level, fill_end)
    for b = 0, bars - 1 do
        local bar_index = bar_start + b
        local base = (bar_index - 1) * BAR

        local hat_velocity = ({light = 45, medium = 58, full = 70})[level] or 58
        local kick_velocity = ({light = 80, medium = 95, full = 108})[level] or 95
        local snare_velocity = ({light = 72, medium = 90, full = 100})[level] or 90

        for i = 0, 7 do
            addNote(song.tracks.drums, base + i * (TPQ / 2), 42, TPQ / 4, hat_velocity)
        end

        addNote(song.tracks.drums, base + 0 * TPQ, 36, TPQ / 2, kick_velocity)
        addNote(song.tracks.drums, base + 2 * TPQ, 36, TPQ / 2, kick_velocity)

        if level ~= "light" then
            addNote(song.tracks.drums, base + 1.5 * TPQ, 36, TPQ / 4, kick_velocity - 10)
        end

        addNote(song.tracks.drums, base + 1 * TPQ, 38, TPQ / 2, snare_velocity)
        addNote(song.tracks.drums, base + 3 * TPQ, 38, TPQ / 2, snare_velocity)

        if fill_end and b == bars - 1 then
            addNote(song.tracks.drums, base + 3 * TPQ, 38, TPQ / 4, 100)
            addNote(song.tracks.drums, base + 3.25 * TPQ, 42, TPQ / 8, 90)
            addNote(song.tracks.drums, base + 3.5 * TPQ, 46, TPQ / 8, 95)
            addNote(song.tracks.drums, base + 3.75 * TPQ, 38, TPQ / 8, 110)
        end
    end
end

function addBassPattern(bar_start, bars, progression, style)
    for b = 0, bars - 1 do
        local chord = progression[(b % #progression) + 1]
        local base = (bar_start + b - 1) * BAR
        local root = bass_roots[chord]
        local fifth = bass_fifths[chord]

        if style == "sparse" then
            addNote(song.tracks.bass, base, root, TPQ * 2, 86)
            addNote(song.tracks.bass, base + TPQ * 2, fifth, TPQ * 2, 78)
        elseif style == "active" then
            addNote(song.tracks.bass, base, root, TPQ, 90)
            addNote(song.tracks.bass, base + TPQ, fifth, TPQ, 82)
            addNote(song.tracks.bass, base + TPQ * 2, root + 12, TPQ, 84)
            addNote(song.tracks.bass, base + TPQ * 3, fifth, TPQ, 80)
        else
            addNote(song.tracks.bass, base, root, TPQ * 2, 92)
            addNote(song.tracks.bass, base + TPQ * 2, fifth, TPQ, 86)
            addNote(song.tracks.bass, base + TPQ * 3, root + 12, TPQ, 84)
        end
    end
end

function addChordPattern(bar_start, bars, progression, style)
    for b = 0, bars - 1 do
        local chord = progression[(b % #progression) + 1]
        local base = (bar_start + b - 1) * BAR
        local notes = chord_notes[chord]
        local shift = (style == "high") and 12 or 0
        local velocity = ({soft = 55, normal = 70, strong = 82})[style] or 70

        for _, note in ipairs(notes) do
            addNote(song.tracks.chords, base, note + shift, BAR, velocity)
        end
    end
end

function addMelodyPattern(bar_start, bars, doubled)
    for b = 0, bars - 1 do
        local phrase = melody_phrase[(b % 4) + 1]
        local base = (bar_start + b - 1) * BAR

        addNote(song.tracks.melody, base, phrase[1], TPQ, 90)
        addNote(song.tracks.melody, base + TPQ * 2, phrase[2], TPQ, 90)

        if doubled then
            addNote(song.tracks.melody, base, phrase[1] + 12, TPQ, 72)
            addNote(song.tracks.melody, base + TPQ * 2, phrase[2] + 12, TPQ, 72)
        end
    end
end

local function buildArrangement()
    addDrumPattern(1, 4, "light", false)

    addDrumPattern(5, 8, "medium", false)
    addBassPattern(5, 8, song.progression_core, "sparse")
    addChordPattern(9, 4, song.progression_core, "soft")

    addDrumPattern(13, 8, "full", false)
    addBassPattern(13, 8, song.progression_core, "normal")
    addChordPattern(13, 8, song.progression_core, "normal")
    addMelodyPattern(13, 8, false)

    addDrumPattern(21, 8, "medium", false)
    addBassPattern(21, 8, song.progression_core, "active")
    addChordPattern(21, 8, song.progression_core, "soft")

    addDrumPattern(29, 4, "full", true)
    addDrumPattern(33, 4, "full", true)
    addBassPattern(29, 8, song.progression_core, "active")
    addChordPattern(29, 8, song.progression_core, "high")
    addMelodyPattern(29, 8, true)

    addDrumPattern(37, 8, "light", false)
    addBassPattern(37, 8, song.progression_bridge, "sparse")
    addChordPattern(37, 8, song.progression_bridge, "soft")

    addDrumPattern(45, 4, "full", false)
    addDrumPattern(49, 4, "full", true)
    addBassPattern(45, 8, song.progression_core, "active")
    addChordPattern(45, 8, song.progression_core, "strong")
    addMelodyPattern(45, 8, true)

    addDrumPattern(53, 4, "light", false)
    addBassPattern(53, 4, {"Am", "Am", "Am", "Am"}, "sparse")
    addChordPattern(53, 4, {"Am", "Am", "Am", "Am"}, "soft")
end

local function meta_text(delta, meta_type, text)
    return varlen(delta) .. bytes(0xFF, meta_type, #text) .. text
end

local function end_track(delta)
    return varlen(delta) .. bytes(0xFF, 0x2F, 0x00)
end

local function build_track(name, channel, program, notes)
    local events = {}
    local data = {meta_text(0, 0x03, name)}

    if program ~= nil then
        table.insert(events, {tick = 0, order = 0, data = bytes(0xC0 + channel, program)})
    end

    for _, n in ipairs(notes) do
        table.insert(events, {tick = n.tick, order = 2, data = bytes(0x90 + channel, n.note, n.velocity)})
        table.insert(events, {tick = n.tick + n.duration, order = 1, data = bytes(0x80 + channel, n.note, 0)})
    end

    table.sort(events, function(a, b)
        if a.tick == b.tick then return a.order < b.order end
        return a.tick < b.tick
    end)

    local last_tick = 0
    for _, e in ipairs(events) do
        table.insert(data, varlen(e.tick - last_tick) .. e.data)
        last_tick = e.tick
    end

    table.insert(data, end_track(0))
    local body = table.concat(data)
    return "MTrk" .. u32(#body) .. body
end

function exportMidi(path)
    local tempo_track = {}
    table.insert(tempo_track, meta_text(0, 0x03, "Tempo Map"))
    table.insert(tempo_track, varlen(0) .. bytes(0xFF, 0x51, 0x03, 0x0B, 0x71, 0xB0))
    table.insert(tempo_track, varlen(0) .. bytes(0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08))
    table.insert(tempo_track, varlen(0) .. bytes(0xFF, 0x59, 0x02, 0x00, 0x00))
    table.insert(tempo_track, end_track(0))
    local tempo_body = table.concat(tempo_track)

    local tracks = {
        "MTrk" .. u32(#tempo_body) .. tempo_body,
        build_track("Drums", 9, nil, song.tracks.drums),
        build_track("Bass", 0, 38, song.tracks.bass),
        build_track("Chords", 1, 0, song.tracks.chords),
        build_track("Melody", 2, 80, song.tracks.melody),
    }

    local header = "MThd" .. u32(6) .. u16(1) .. u16(#tracks) .. u16(TPQ)
    local f = assert(io.open(path, "wb"))
    f:write(header)
    for _, t in ipairs(tracks) do f:write(t) end
    f:close()
end

buildArrangement()
exportMidi("first_jam.mid")
print("Success: generated first_jam.mid")
