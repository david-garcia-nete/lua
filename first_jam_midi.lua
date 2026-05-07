-- first_jam_midi.lua
-- Generates a simple 16-bar MIDI song:
-- Drums + Bass + Chords in A minor
-- Tempo: 80 BPM
-- Progression: Am - F - C - G

local TPQ = 480 -- ticks per quarter note
local BAR = TPQ * 4

local function bytes(...)
    local t = {...}
    local s = {}
    for i, v in ipairs(t) do
        s[i] = string.char(v)
    end
    return table.concat(s)
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

local function meta_text(delta, meta_type, text)
    return varlen(delta) .. bytes(0xFF, meta_type, #text) .. text
end

local function end_track(delta)
    return varlen(delta) .. bytes(0xFF, 0x2F, 0x00)
end

local function midi_event(delta, status, data1, data2)
    if data2 == nil then
        return varlen(delta) .. bytes(status, data1)
    end
    return varlen(delta) .. bytes(status, data1, data2)
end

local function note_events(events, start_tick, channel, note, duration, velocity)
    table.insert(events, {
        tick = start_tick,
        order = 2,
        data = bytes(0x90 + channel, note, velocity)
    })

    table.insert(events, {
        tick = start_tick + duration,
        order = 1,
        data = bytes(0x80 + channel, note, 0)
    })
end

local function build_track(name, channel, program, notes)
    local events = {}

    local data = {}
    table.insert(data, meta_text(0, 0x03, name))

    if program ~= nil then
        table.insert(events, {
            tick = 0,
            order = 0,
            data = bytes(0xC0 + channel, program)
        })
    end

    for _, n in ipairs(notes) do
        note_events(events, n.tick, channel, n.note, n.duration, n.velocity or 90)
    end

    table.sort(events, function(a, b)
        if a.tick == b.tick then
            return a.order < b.order
        end
        return a.tick < b.tick
    end)

    local last_tick = 0
    for _, e in ipairs(events) do
        local delta = e.tick - last_tick
        table.insert(data, varlen(delta) .. e.data)
        last_tick = e.tick
    end

    table.insert(data, end_track(0))

    local body = table.concat(data)
    return "MTrk" .. u32(#body) .. body
end

local function build_tempo_track()
    local data = {}

    table.insert(data, meta_text(0, 0x03, "Tempo Map"))

    -- 80 BPM = 750,000 microseconds per quarter note
    table.insert(data, varlen(0) .. bytes(0xFF, 0x51, 0x03, 0x0B, 0x71, 0xB0))

    -- 4/4 time signature
    table.insert(data, varlen(0) .. bytes(0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08))

    table.insert(data, end_track(0))

    local body = table.concat(data)
    return "MTrk" .. u32(#body) .. body
end

local drums = {}
local bass = {}
local chords = {}
local melody = {}

-- MIDI note numbers:
-- Drums, General MIDI: Kick 36, Snare 38, Closed Hat 42
-- Bass: A1 33, F1 29, C2 36, G1 31, E2 40, G2 43, D2 38
-- Chords: A3 57, C4 60, E4 64, F3 53, G3 55, B3 59, D4 62, G4 67

for bar = 0, 15 do
    local base = bar * BAR

    -- Hi-hat every eighth note
    for i = 0, 7 do
        table.insert(drums, {
            tick = base + i * (TPQ / 2),
            note = 42,
            duration = TPQ / 4,
            velocity = 60
        })
    end

    -- Kick on beats 1 and 3
    table.insert(drums, { tick = base + 0 * TPQ, note = 36, duration = TPQ / 2, velocity = 100 })
    table.insert(drums, { tick = base + 2 * TPQ, note = 36, duration = TPQ / 2, velocity = 100 })

    -- Snare on beats 2 and 4
    table.insert(drums, { tick = base + 1 * TPQ, note = 38, duration = TPQ / 2, velocity = 95 })
    table.insert(drums, { tick = base + 3 * TPQ, note = 38, duration = TPQ / 2, velocity = 95 })

    -- Small variation every fourth bar
    if (bar + 1) % 4 == 0 then
        table.insert(drums, { tick = base + 2.5 * TPQ, note = 36, duration = TPQ / 2, velocity = 90 })
    end
end

local bass_pattern = {
    { root = 33, fifth = 40 }, -- Am: A1, E2
    { root = 29, fifth = 36 }, -- F: F1, C2
    { root = 36, fifth = 43 }, -- C: C2, G2
    { root = 31, fifth = 38 }, -- G: G1, D2
}

for bar = 4, 15 do
    local p = bass_pattern[(bar % 4) + 1]
    local base = bar * BAR

    table.insert(bass, { tick = base, note = p.root, duration = TPQ * 2, velocity = 90 })
    table.insert(bass, { tick = base + TPQ * 2, note = p.fifth, duration = TPQ * 2, velocity = 80 })
end

local chord_pattern = {
    {57, 60, 64}, -- Am: A3 C4 E4
    {53, 57, 60}, -- F: F3 A3 C4
    {60, 64, 67}, -- C: C4 E4 G4
    {55, 59, 62}, -- G: G3 B3 D4
}

for bar = 8, 15 do
    local notes = chord_pattern[(bar % 4) + 1]
    local base = bar * BAR

    for _, note in ipairs(notes) do
        table.insert(chords, {
            tick = base,
            note = note,
            duration = BAR,
            velocity = 70
        })
    end
end

-- Simple melody enters in bars 13-16
local melody_pattern = {
    {69, 72}, -- A4, C5
    {67, 69}, -- G4, A4
    {64, 67}, -- E4, G4
    {62, 64}, -- D4, E4
}

for bar = 12, 15 do
    local notes = melody_pattern[(bar % 4) + 1]
    local base = bar * BAR

    table.insert(melody, { tick = base, note = notes[1], duration = TPQ, velocity = 85 })
    table.insert(melody, { tick = base + TPQ * 2, note = notes[2], duration = TPQ, velocity = 85 })
end

local tracks = {
    build_tempo_track(),
    build_track("Drums", 9, nil, drums),       -- Channel 10 in MIDI terms
    build_track("Bass", 0, 38, bass),         -- Synth bass
    build_track("Chords", 1, 0, chords),      -- Piano
    build_track("Melody", 2, 80, melody),     -- Lead synth
}

local header = "MThd" .. u32(6) .. u16(1) .. u16(#tracks) .. u16(TPQ)

local file = assert(io.open("first_jam.mid", "wb"))
file:write(header)
for _, track in ipairs(tracks) do
    file:write(track)
end
file:close()

print("Created first_jam.mid")
