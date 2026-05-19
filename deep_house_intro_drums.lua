-- deep_house_intro_drums.lua
-- Generates a Standard MIDI File (format 1) with a 4-bar deep house intro jam:
-- track 1 = drums, track 2 = bass.
-- Run: lua deep_house_intro_drums.lua

local output_file = "second_jam_deep_house_intro.mid"

-- Timing setup ---------------------------------------------------------------
-- PPQ (pulses per quarter note) = 480 ticks.
-- In 4/4, one bar = 4 quarter notes = 4 * 480 = 1920 ticks.
-- 8th-note spacing = 480 / 2 = 240 ticks.
local PPQ = 480
local BEAT = PPQ
local EIGHTH = PPQ // 2
local BAR_TICKS = 4 * BEAT
local BARS = 4

-- MIDI channels are 0-based in status bytes:
-- channel 10 drums => 9, channel 1 bass => 0.
local DRUM_CH = 9
local BASS_CH = 0

-- General MIDI drum note numbers
local NOTE_KICK = 36
local NOTE_SNARE = 38
local NOTE_CLAP = 39
local NOTE_HH_CLOSED = 42
local NOTE_HH_OPEN = 46

-- Bass note numbers (requested)
local NOTE_A2 = 45
local NOTE_D3 = 50
local NOTE_E3 = 52
local NOTE_FS3 = 54

-- Helper to append bytes to a table.
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

local drum_events = {}
local bass_events = {}

local function add_event(event_list, abs_tick, status, data1, data2)
  event_list[#event_list + 1] = {
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
  add_event(drum_events, abs_tick, 0x90 | DRUM_CH, note, velocity)      -- note on
  add_event(drum_events, abs_tick + duration, 0x80 | DRUM_CH, note, 0)  -- note off
end

-- Add bass notes with slightly shortened 8th-note duration for groove.
local function add_bass_note(abs_tick, note, velocity, duration)
  add_event(bass_events, abs_tick, 0x90 | BASS_CH, note, velocity)       -- note on
  add_event(bass_events, abs_tick + duration, 0x80 | BASS_CH, note, 0)   -- note off
end

-- Deterministic velocity variation so playback feels less robotic.
local closed_hat_cycle = {55, 61, 58, 66, 60, 69, 57, 64}
local open_hat_cycle = {78, 82, 80, 84}
local kick_cycle = {103, 107}
local snare_cycle = {93, 97}
local clap_cycle = {73, 77}

-- Bass velocities:
-- Root A notes are stronger (85-95), passing notes are softer (70-85).
local bass_root_cycle = {88, 92, 90, 95}
local bass_pass_cycle = {74, 81, 78}

-- One-bar bass pattern in A minor feel, then repeated for all 4 bars.
-- Count: 1   &   2   &   3   &   4
-- Notes: A   E   A   F#  A   D   A
-- Tick offsets in one bar:
-- 1  -> 0
-- &1 -> 240
-- 2  -> 480
-- &2 -> 720
-- 3  -> 960
-- &3 -> 1200
-- 4  -> 1440
local bass_pattern = {
  {offset = 0 * EIGHTH, note = NOTE_A2,  is_root = true},
  {offset = 1 * EIGHTH, note = NOTE_E3,  is_root = false},
  {offset = 2 * EIGHTH, note = NOTE_A2,  is_root = true},
  {offset = 3 * EIGHTH, note = NOTE_FS3, is_root = false},
  {offset = 4 * EIGHTH, note = NOTE_A2,  is_root = true},
  {offset = 5 * EIGHTH, note = NOTE_D3,  is_root = false},
  {offset = 6 * EIGHTH, note = NOTE_A2,  is_root = true}
}

-- 8th note = 240 ticks, so 85% is 204 ticks.
-- This leaves a small gap before the next note to keep the groove clean.
local BASS_NOTE_DUR = math.floor(EIGHTH * 0.85)

for bar = 0, BARS - 1 do
  local bar_start = bar * BAR_TICKS

  -- Beats are 0-based offsets inside bar:
  -- beat 1 -> +0, beat 2 -> +480, beat 3 -> +960, beat 4 -> +1440
  local beat1 = bar_start + 0 * BEAT
  local beat2 = bar_start + 1 * BEAT
  local beat3 = bar_start + 2 * BEAT
  local beat4 = bar_start + 3 * BEAT

  -- Keep existing drum groove unchanged.
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

  -- Bass: repeat the same one-bar syncopated pattern each bar.
  local root_index = 1
  local pass_index = 1
  for i = 1, #bass_pattern do
    local step = bass_pattern[i]
    local velocity
    if step.is_root then
      velocity = bass_root_cycle[root_index]
      root_index = (root_index % #bass_root_cycle) + 1
    else
      velocity = bass_pass_cycle[pass_index]
      pass_index = (pass_index % #bass_pass_cycle) + 1
    end
    add_bass_note(bar_start + step.offset, step.note, velocity, BASS_NOTE_DUR)
  end
end

local function sort_events(events)
  table.sort(events, function(a, b)
    if a.tick ~= b.tick then return a.tick < b.tick end
    local a_on = (a.status & 0xF0) == 0x90 and a.data2 > 0
    local b_on = (b.status & 0xF0) == 0x90 and b.data2 > 0
    if a_on ~= b_on then return not a_on end
    return a.data1 < b.data1
  end)
end

local function make_track_chunk(event_list, include_song_meta, optional_prefix_events)
  local track = {}

  if include_song_meta then
    -- Tempo meta event: 120 BPM -> 500000 microseconds per quarter note.
    track[#track + 1] = vlq(0)
    add_bytes(track, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20)

    -- Time signature meta event: 4/4
    track[#track + 1] = vlq(0)
    add_bytes(track, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08)
  end

  -- Optional setup events (for example, instrument program change).
  if optional_prefix_events then
    for i = 1, #optional_prefix_events do
      local p = optional_prefix_events[i]
      track[#track + 1] = vlq(p.delta)
      add_bytes(track, p.status, p.data1)
    end
  end

  local last_tick = 0
  for i = 1, #event_list do
    local ev = event_list[i]
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

  local trk_header = {
    "MTrk",
    string.char((track_len >> 24) & 0xFF,
                (track_len >> 16) & 0xFF,
                (track_len >> 8) & 0xFF,
                track_len & 0xFF)
  }

  return table.concat(trk_header) .. track_data
end

sort_events(drum_events)
sort_events(bass_events)

-- Build MIDI header (MThd): format 1, 2 tracks, division PPQ.
local header = {
  "MThd",
  string.char(0x00, 0x00, 0x00, 0x06),
  string.char(0x00, 0x01), -- format 1 (multiple simultaneous tracks)
  string.char(0x00, 0x02), -- two tracks
  string.char((PPQ >> 8) & 0xFF, PPQ & 0xFF)
}

local drum_track_blob = make_track_chunk(drum_events, true, nil)

-- Program change for bass track on channel 1:
-- 33 (1-based GM index) => 32 in MIDI byte value (Electric Bass finger).
local bass_program_change = {
  {delta = 0, status = 0xC0 | BASS_CH, data1 = 32}
}
local bass_track_blob = make_track_chunk(bass_events, false, bass_program_change)

local midi_blob = table.concat(header) .. drum_track_blob .. bass_track_blob

local f, err = io.open(output_file, "wb")
if not f then
  error("Could not open output file: " .. tostring(err))
end
f:write(midi_blob)
f:close()

print("Created MIDI file with drums + bass: " .. output_file)
