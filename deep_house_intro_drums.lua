-- deep_house_intro_drums.lua
-- Generates a Standard MIDI File (format 0) with a 4-bar deep house intro drum loop.
-- Run: lua deep_house_intro_drums.lua

local output_file = "deep_house_intro_drums.mid"

-- Timing setup ---------------------------------------------------------------
-- We use PPQ (pulses per quarter note) = 480 ticks.
-- In 4/4, one bar = 4 quarter notes = 4 * 480 = 1920 ticks.
-- 8th-note spacing = 480 / 2 = 240 ticks.
local PPQ = 480
local BEAT = PPQ
local EIGHTH = PPQ // 2
local BAR_TICKS = 4 * BEAT
local BARS = 4

-- MIDI channel for drums is channel 10 (1-based), which is 9 in MIDI bytes (0-based).
local DRUM_CH = 9

-- General MIDI drum note numbers
local NOTE_KICK = 36
local NOTE_SNARE = 38
local NOTE_CLAP = 39
local NOTE_HH_CLOSED = 42
local NOTE_HH_OPEN = 46

-- A small helper to append bytes to a table.
local function add_byte(t, b)
  t[#t + 1] = string.char(b)
end

local function add_bytes(t, ...)
  local args = {...}
  for i = 1, #args do
    add_byte(t, args[i])
  end
end

-- Variable-length quantity encoder (for delta times and meta lengths).
local function vlq(n)
  local bytes = { n & 0x7F }
  n = n >> 7
  while n > 0 do
    table.insert(bytes, 1, (n & 0x7F) | 0x80)
    n = n >> 7
  end
  local out = {}
  for i = 1, #bytes do
    out[i] = string.char(bytes[i])
  end
  return table.concat(out)
end

local events = {}

local function add_event(abs_tick, status, data1, data2)
  events[#events + 1] = {
    tick = abs_tick,
    status = status,
    data1 = data1,
    data2 = data2
  }
end

-- Add drum note-on and note-off events.
-- We keep short durations so drums are punchy:
-- kick/snare/clap ~ 120 ticks (a 16th), hats shorter.
local function add_drum_hit(abs_tick, note, velocity, duration)
  add_event(abs_tick, 0x90 | DRUM_CH, note, velocity)       -- note on
  add_event(abs_tick + duration, 0x80 | DRUM_CH, note, 0)   -- note off
end

-- Deterministic velocity variation so playback feels less robotic.
local closed_hat_cycle = {55, 61, 58, 66, 60, 69, 57, 64}
local open_hat_cycle = {78, 82, 80, 84}
local kick_cycle = {103, 107}
local snare_cycle = {93, 97}
local clap_cycle = {73, 77}

for bar = 0, BARS - 1 do
  local bar_start = bar * BAR_TICKS

  -- Beats are 0-based offsets inside bar:
  -- beat 1 -> +0, beat 2 -> +480, beat 3 -> +960, beat 4 -> +1440
  local beat1 = bar_start + 0 * BEAT
  local beat2 = bar_start + 1 * BEAT
  local beat3 = bar_start + 2 * BEAT
  local beat4 = bar_start + 3 * BEAT

  -- Kick on beats 1 and 3
  add_drum_hit(beat1, NOTE_KICK, kick_cycle[(bar % 2) + 1], 120)
  add_drum_hit(beat3, NOTE_KICK, kick_cycle[((bar + 1) % 2) + 1], 120)

  -- Snare + clap layered on beats 2 and 4
  add_drum_hit(beat2, NOTE_SNARE, snare_cycle[(bar % 2) + 1], 120)
  add_drum_hit(beat2, NOTE_CLAP, clap_cycle[(bar % 2) + 1], 110)
  add_drum_hit(beat4, NOTE_SNARE, snare_cycle[((bar + 1) % 2) + 1], 120)
  add_drum_hit(beat4, NOTE_CLAP, clap_cycle[((bar + 1) % 2) + 1], 110)

  -- Closed hi-hat on every 8th note:
  -- positions: 1, &, 2, &, 3, &, 4, & -> every 240 ticks in the bar.
  for i = 0, 7 do
    local t = bar_start + i * EIGHTH
    local vel = closed_hat_cycle[(i % #closed_hat_cycle) + 1]
    add_drum_hit(t, NOTE_HH_CLOSED, vel, 90)
  end

  -- Open hi-hat on each "and" of the beat: 1&, 2&, 3&, 4&
  -- These are at beat + 240 ticks.
  for b = 0, 3 do
    local t = bar_start + b * BEAT + EIGHTH
    local vel = open_hat_cycle[(b % #open_hat_cycle) + 1]
    add_drum_hit(t, NOTE_HH_OPEN, vel, 140)
  end
end

-- Sort events by time; if same tick, note-off first so repeated notes are clean.
table.sort(events, function(a, b)
  if a.tick ~= b.tick then return a.tick < b.tick end
  local a_on = (a.status & 0xF0) == 0x90 and a.data2 > 0
  local b_on = (b.status & 0xF0) == 0x90 and b.data2 > 0
  if a_on ~= b_on then return not a_on end
  return a.data1 < b.data1
end)

-- Build track data chunk.
local track = {}

-- Tempo meta event: 120 BPM -> 500000 microseconds per quarter note.
track[#track + 1] = vlq(0)
add_bytes(track, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20)

-- Time signature meta event: 4/4
track[#track + 1] = vlq(0)
add_bytes(track, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08)

local last_tick = 0
for i = 1, #events do
  local ev = events[i]
  local delta = ev.tick - last_tick
  track[#track + 1] = vlq(delta)
  add_bytes(track, ev.status, ev.data1, ev.data2)
  last_tick = ev.tick
end

-- End-of-track meta event.
track[#track + 1] = vlq(0)
add_bytes(track, 0xFF, 0x2F, 0x00)

local track_data = table.concat(track)
local track_len = #track_data

-- Build MIDI header (MThd): format 0, 1 track, division PPQ.
local header = {
  "MThd",
  string.char(0x00, 0x00, 0x00, 0x06),
  string.char(0x00, 0x00), -- format 0
  string.char(0x00, 0x01), -- one track
  string.char((PPQ >> 8) & 0xFF, PPQ & 0xFF)
}

-- Build track chunk header (MTrk + 4-byte length big-endian).
local trk_header = {
  "MTrk",
  string.char((track_len >> 24) & 0xFF,
              (track_len >> 16) & 0xFF,
              (track_len >> 8) & 0xFF,
              track_len & 0xFF)
}

local midi_blob = table.concat(header) .. table.concat(trk_header) .. track_data

local f, err = io.open(output_file, "wb")
if not f then
  error("Could not open output file: " .. tostring(err))
end
f:write(midi_blob)
f:close()

print("Created MIDI file: " .. output_file)
