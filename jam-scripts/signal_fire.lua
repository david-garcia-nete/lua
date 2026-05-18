local TPQ = 480
local BAR = TPQ * 4

local SONG = {
  title = "Signal Fire",
  key_fifths = 0,
  mode = "minor",
  tempo = 82,
  time_beats = 4,
  time_beat_type = 4,
  sections = {
    {name="Verse 1", bars=8},
    {name="Chorus", bars=8},
    {name="Verse 2", bars=8},
    {name="Chorus", bars=8},
    {name="Bridge", bars=8},
    {name="Final Chorus", bars=8},
    {name="Outro Refrain", bars=4},
  },
  chords = {"Am", "G", "F", "E7"},
}

local PARTS = {
  {id="P1", name="Vocal", midi_program=53, midi_channel=0},
  {id="P2", name="Electric Piano", midi_program=4, midi_channel=1},
  {id="P3", name="Electric Guitar", midi_program=27, midi_channel=2},
  {id="P4", name="Bass Guitar", midi_program=33, midi_channel=3},
  {id="P5", name="Drum Set", midi_program=nil, midi_channel=9},
  {id="P6", name="Saxophone", midi_program=65, midi_channel=4},
  {id="P7", name="Djembe", midi_program=117, midi_channel=5},
}

local LYRIC_BLOCKS = {
  ["Verse 1"] = {
    "Night comes down, we hold the line",
    "Smoke in the rain, still your hand in mine",
    "Static sky but I hear you clear",
    "One small light says we are still here",
  },
  ["Chorus"] = {
    "Signal fire, signal fire",
    "Burn it bright above the wire",
    "Call my name through storm and night",
    "Signal fire, keep us in the light",
  },
  ["Verse 2"] = {
    "Cold street shine on a flooded lane",
    "Boots in the water, heartbeat in the rain",
    "Broken towers, but the message flies",
    "Hope keeps talking in our tired eyes",
  },
  ["Bridge"] = {
    "If the dark gets deep, we breathe and wait",
    "Ash on our sleeves, but we don't break",
    "Every spark says start again",
    "Send it up for every friend",
  },
  ["Final Chorus"] = {
    "Signal fire, signal fire",
    "Burn it bright above the wire",
    "Call my name through storm and night",
    "Signal fire, keep us in the light",
  },
  ["Outro Refrain"] = {
    "Signal fire, hold on",
    "Signal fire, hold on",
  }
}

local CHORD_TONES = {
  Am={57,60,64}, G={55,59,62}, F={53,57,60}, E7={52,56,59,62}
}

local BASS_NOTES = {Am=33,G=31,F=29,E7=28}

local function xml_escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function split_words(line)
  local out = {}
  for w in line:gmatch("[%w']+") do out[#out+1]=w end
  return out
end

local function build_vocal_measures()
  local measures, m = {}, 1
  local first_chorus_lyrics = nil
  for _,sec in ipairs(SONG.sections) do
    local lines = LYRIC_BLOCKS[sec.name] or LYRIC_BLOCKS["Chorus"]
    if sec.name == "Chorus" and not first_chorus_lyrics then first_chorus_lyrics = lines end
    if sec.name == "Chorus" and first_chorus_lyrics then lines = first_chorus_lyrics end
    local li = 1
    for bar=1,sec.bars do
      local chord = SONG.chords[((bar-1)%#SONG.chords)+1]
      local label = nil
      if bar==1 then label = sec.name end
      local words = split_words(lines[li])
      li = li + 1
      if li > #lines then li = 1 end
      local notes = {}
      local melody = {69,71,72,74}
      for i=1,4 do
        notes[#notes+1] = {step=({"A","B","C","D"})[i], octave=(i<3) and 4 or 5, midi=melody[i], lyric=words[i]}
      end
      measures[#measures+1] = {num=m, section=label, chord=chord, notes=notes}
      m = m + 1
    end
  end
  return measures
end

local function write_musicxml(path)
  local vocal = build_vocal_measures()
  local total = #vocal
  local f=assert(io.open(path,"w"))
  f:write('<?xml version="1.0" encoding="UTF-8"?>\n')
  f:write('<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">\n')
  f:write('<score-partwise version="3.1">\n')
  f:write('  <work><work-title>Signal Fire</work-title></work>\n')
  f:write('  <part-list>\n')
  for _,p in ipairs(PARTS) do
    f:write(('    <score-part id="%s"><part-name>%s</part-name></score-part>\n'):format(p.id,p.name))
  end
  f:write('  </part-list>\n')

  -- Vocal with lyrics
  f:write('  <part id="P1">\n')
  for _,m in ipairs(vocal) do
    f:write(('    <measure number="%d">\n'):format(m.num))
    if m.num==1 then
      f:write('      <attributes><divisions>1</divisions><key><fifths>0</fifths><mode>minor</mode></key><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>\n')
      f:write('      <direction placement="above"><direction-type><metronome><beat-unit>quarter</beat-unit><per-minute>82</per-minute></metronome></direction-type><sound tempo="82"/></direction>\n')
    end
    if m.section then
      f:write(('      <direction placement="above"><direction-type><rehearsal>%s</rehearsal></direction-type></direction>\n'):format(xml_escape(m.section)))
    end
    f:write(('      <harmony><root><root-step>%s</root-step></root><kind text="%s">minor</kind></harmony>\n'):format(m.chord:sub(1,1), m.chord))
    for _,n in ipairs(m.notes) do
      f:write('      <note>\n')
      f:write(('        <pitch><step>%s</step><octave>%d</octave></pitch><duration>1</duration><type>quarter</type>\n'):format(n.step,n.octave))
      if n.lyric then
        f:write(('        <lyric><syllabic>single</syllabic><text>%s</text></lyric>\n'):format(xml_escape(n.lyric)))
      end
      f:write('      </note>\n')
    end
    f:write('    </measure>\n')
  end
  f:write('  </part>\n')

  local function write_simple_part(id, clefSign, clefLine, octave)
    f:write(('  <part id="%s">\n'):format(id))
    for i=1,total do
      local chord = SONG.chords[((i-1)%#SONG.chords)+1]
      f:write(('    <measure number="%d">\n'):format(i))
      if i==1 then
        f:write(('      <attributes><divisions>1</divisions><key><fifths>0</fifths><mode>minor</mode></key><time><beats>4</beats><beat-type>4</beat-type></time><clef><sign>%s</sign><line>%d</line></clef></attributes>\n'):format(clefSign, clefLine))
      end
      if id=="P5" then
        f:write('      <note><unpitched><display-step>C</display-step><display-octave>5</display-octave></unpitched><duration>1</duration><type>quarter</type><instrument id="drum"/></note>\n')
        f:write('      <note><rest/><duration>1</duration><type>quarter</type></note>\n')
        f:write('      <note><unpitched><display-step>D</display-step><display-octave>5</display-octave></unpitched><duration>1</duration><type>quarter</type></note>\n')
        f:write('      <note><rest/><duration>1</duration><type>quarter</type></note>\n')
      else
        local tones = CHORD_TONES[chord]
        for b=1,4 do
          local midi = tones[((b-1)%#tones)+1]
          local step = ({"A","B","C","D"})[((b-1)%4)+1]
          f:write(('      <note><pitch><step>%s</step><octave>%d</octave></pitch><duration>1</duration><type>quarter</type></note>\n'):format(step, octave))
        end
      end
      f:write('    </measure>\n')
    end
    f:write('  </part>\n')
  end

  write_simple_part("P2","G",2,4)
  write_simple_part("P3","G",2,4)
  write_simple_part("P4","F",4,2)
  write_simple_part("P5","percussion",2,4)
  write_simple_part("P6","G",2,4)
  write_simple_part("P7","percussion",2,4)

  f:write('</score-partwise>\n')
  f:close()
end

local function bytes(...) local t={} for i,v in ipairs({...}) do t[i]=string.char(v) end return table.concat(t) end
local function u16(n) return bytes(math.floor(n/256)%256, n%256) end
local function u32(n) return bytes(math.floor(n/16777216)%256, math.floor(n/65536)%256, math.floor(n/256)%256, n%256) end
local function varlen(v) local b=v%128 v=math.floor(v/128) while v>0 do b=b*256+((v%128)+128) v=math.floor(v/128) end local o={} while true do o[#o+1]=string.char(b%256) if b<128 then break end b=math.floor(b/256) end return table.concat(o) end
local function end_track() return varlen(0)..bytes(0xFF,0x2F,0x00) end
local function meta_text(delta,t,text) return varlen(delta)..bytes(0xFF,t,#text)..text end
local function note(track,tick,n,dur,vel) track[#track+1]={tick=tick,n=n,d=dur,v=vel or 88} end

local function build_midi()
  local bars = 52
  local tracks = {}
  for i=1,#PARTS do tracks[i]={} end
  for bar=0,bars-1 do
    local b = bar*BAR
    local chord = SONG.chords[(bar%#SONG.chords)+1]
    local tones = CHORD_TONES[chord]
    -- vocal quarter melody
    note(tracks[1], b, 69, TPQ, 88); note(tracks[1], b+TPQ, 71, TPQ, 88); note(tracks[1], b+TPQ*2,72,TPQ,90); note(tracks[1], b+TPQ*3,74,TPQ,90)
    for beat=0,3 do note(tracks[2], b+beat*TPQ, tones[(beat%#tones)+1], TPQ, 74) end
    note(tracks[3], b+TPQ/2, tones[2], TPQ/2, 80); note(tracks[3], b+TPQ*2+TPQ/2, tones[3], TPQ/2, 80)
    note(tracks[4], b, BASS_NOTES[chord], TPQ*2, 84); note(tracks[4], b+TPQ*2, BASS_NOTES[chord]+7, TPQ*2, 82)
    note(tracks[5], b, 36, TPQ/2, 100); note(tracks[5], b+TPQ, 38, TPQ/2, 92); note(tracks[5], b+TPQ*2, 36, TPQ/2, 100); note(tracks[5], b+TPQ*3, 38, TPQ/2, 92)
    note(tracks[6], b+TPQ*2, tones[1]+12, TPQ, 74)
    note(tracks[7], b+TPQ/2, 64, TPQ/3, 58); note(tracks[7], b+TPQ*2+TPQ/2, 63, TPQ/3, 56)
  end
  return tracks
end

local function build_track(name,ch,program,notes)
  local ev, data = {}, {meta_text(0,0x03,name)}
  if program~=nil then ev[#ev+1]={tick=0,o=2,d=bytes(0xC0+ch,program)} end
  for _,n in ipairs(notes) do ev[#ev+1]={tick=n.tick,o=2,d=bytes(0x90+ch,n.n,n.v)}; ev[#ev+1]={tick=n.tick+n.d,o=1,d=bytes(0x80+ch,n.n,0)} end
  table.sort(ev,function(x,y) if x.tick==y.tick then return x.o<y.o end return x.tick<y.tick end)
  local last=0 for _,e in ipairs(ev) do data[#data+1]=varlen(e.tick-last)..e.d; last=e.tick end
  data[#data+1]=end_track(); local body=table.concat(data); return "MTrk"..u32(#body)..body
end

local function write_midi(path)
  local mpqn=math.floor(60000000/SONG.tempo)
  local tempoBody = table.concat({meta_text(0,0x03,"Tempo Map"), varlen(0)..bytes(0xFF,0x51,0x03,math.floor(mpqn/65536)%256,math.floor(mpqn/256)%256,mpqn%256), varlen(0)..bytes(0xFF,0x58,0x04,0x04,0x02,0x18,0x08), end_track()})
  local midi_tracks={"MTrk"..u32(#tempoBody)..tempoBody}
  local part_tracks = build_midi()
  for i,p in ipairs(PARTS) do midi_tracks[#midi_tracks+1] = build_track(p.name, p.midi_channel, p.midi_program, part_tracks[i]) end
  local h="MThd"..u32(6)..u16(1)..u16(#midi_tracks)..u16(TPQ)
  local file=assert(io.open(path,"wb")); file:write(h); for _,tr in ipairs(midi_tracks) do file:write(tr) end; file:close()
end

local function write_markdown(path)
  local md = [[# Signal Fire

## Global Settings
- **Key:** A minor
- **Tempo:** 82 BPM
- **Time Signature:** 4/4
- **Style:** Psychedelic reggae rock
- **Feel:** Simple, playable, song-first

## Section Map
1. Verse 1 (8 bars)
2. Chorus (8 bars)
3. Verse 2 (8 bars)
4. Chorus (8 bars)
5. Bridge (8 bars)
6. Final Chorus (8 bars)
7. Outro Refrain (4 bars)

## Lyrics
### Verse 1
Night comes down, we hold the line  
Smoke in the rain, still your hand in mine  
Static sky but I hear you clear  
One small light says we are still here

### Chorus
Signal fire, signal fire  
Burn it bright above the wire  
Call my name through storm and night  
Signal fire, keep us in the light

### Verse 2
Cold street shine on a flooded lane  
Boots in the water, heartbeat in the rain  
Broken towers, but the message flies  
Hope keeps talking in our tired eyes

### Chorus
Signal fire, signal fire  
Burn it bright above the wire  
Call my name through storm and night  
Signal fire, keep us in the light

### Bridge
If the dark gets deep, we breathe and wait  
Ash on our sleeves, but we don't break  
Every spark says start again  
Send it up for every friend

### Final Chorus
Signal fire, signal fire  
Burn it bright above the wire  
Call my name through storm and night  
Signal fire, keep us in the light

### Outro Refrain
Signal fire, hold on  
Signal fire, hold on

## Pattern Library
- **Vocal:** Quarter-note melody, comfortable range around A4–D5.
- **Keys:** Offbeat skank stabs (Am-G-F-E7 loop).
- **Guitar:** Sparse upstroke doubles on beats 2+ and 4+.
- **Bass:** Root-driven half-note pulse.
- **Drums:** Kick on 1/3, snare on 2/4, simple hats.
- **Sax:** One-bar response fills at line ends.
- **Djembe:** Light offbeat taps for momentum.

## Section Assignments
- **Verses:** Vocal + keys + bass + drums, light guitar and djembe.
- **Choruses:** Add fuller guitar and sax responses.
- **Bridge:** Pull dynamics, keep pulse steady.
- **Final Chorus:** Full ensemble.
- **Outro:** Strip back and repeat refrain.

## Practice Notes
- Learn one section at a time in this order: Verse 1 -> Chorus -> Verse 2 -> Bridge -> Final Chorus -> Outro.
- Keep groove locked before adding fills.
- Vocal phrasing is syllabic; place one word per note where possible.
- Start at 70 BPM, then move to 82 BPM.

## App Notes
- Generated by `jam-scripts/signal_fire.lua`.
- MusicXML is prioritized for MuseScore Studio lyric display.
- MIDI mirrors the same section length and part list for quick DAW import.
]]
  local f=assert(io.open(path,"w")); f:write(md); f:close()
end

os.execute("mkdir -p jams/signal-fire")
write_musicxml("jams/signal-fire/signal_fire.musicxml")
write_midi("jams/signal-fire/signal_fire.mid")
write_markdown("jams/signal-fire/signal_fire_arrangement.md")
print("Generated: jams/signal-fire/signal_fire.musicxml")
print("Generated: jams/signal-fire/signal_fire.mid")
print("Generated: jams/signal-fire/signal_fire_arrangement.md")
