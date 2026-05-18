local TPQ = 480
local BAR = TPQ * 4

local SONG = {
  title = "Signal Fire",
  key = "A minor",
  tempo = 82,
  time_signature = "4/4",
  total_bars = 56,
  progression_core = {"Am", "G", "F", "E7"},
  progression_bridge = {"F", "G", "Am", "Am"},
  progression_outro = {"Am", "Am", "Am", "Am"},
  sections = {
    {"Intro / Dub Pulse", 1, 4}, {"Verse A", 5, 12}, {"Chorus 1 / Signal Hook", 13, 20},
    {"Verse B / Grit Build", 21, 28}, {"Psychedelic Break", 29, 36}, {"Bridge / Drop to Smoke", 37, 44},
    {"Final Chorus / Full Fire", 45, 52}, {"Outro / Echo Fade", 53, 56},
  },
  tracks = {drums={}, bass={}, keys={}, guitar={}, lead={}, sax={}, djembe={}}
}

local CHORDS = { Am={57,60,64}, G={55,59,62}, F={53,57,60}, E7={52,56,59,62} }
local BASS = { Am={33,40,43,44}, G={31,38,41,42}, F={29,36,40,41}, E7={28,35,39,40} }

local function bytes(...) local t={} for i,v in ipairs({...}) do t[i]=string.char(v) end return table.concat(t) end
local function u16(n) return bytes(math.floor(n/256)%256, n%256) end
local function u32(n) return bytes(math.floor(n/16777216)%256, math.floor(n/65536)%256, math.floor(n/256)%256, n%256) end
local function varlen(v) local b=v%128 v=math.floor(v/128) while v>0 do b=b*256+((v%128)+128) v=math.floor(v/128) end local o={} while true do o[#o+1]=string.char(b%256) if b<128 then break end b=math.floor(b/256) end return table.concat(o) end
local function note(track,tick,n,dur,vel) track[#track+1]={tick=tick,n=n,d=dur,v=vel or 90} end
local function bar_tick(bar) return (bar-1)*BAR end

local function add_drum_bar(bar,mode,fill)
  local t=SONG.tracks.drums local b=bar_tick(bar)
  local hv=(mode=="full") and 72 or ((mode=="light") and 52 or 62)
  local kv=(mode=="full") and 112 or 98
  local sv=(mode=="full") and 104 or 92
  for i=0,7 do note(t,b+i*TPQ/2,42,TPQ/4,hv) end
  note(t,b,36,TPQ/3,kv); note(t,b+2*TPQ,36,TPQ/3,kv-6); note(t,b+3*TPQ+TPQ/2,36,TPQ/4,kv-12)
  note(t,b+TPQ,38,TPQ/3,sv); note(t,b+3*TPQ,38,TPQ/3,sv)
  if fill then note(t,b+3*TPQ,45,TPQ/6,95); note(t,b+3*TPQ+TPQ/4,47,TPQ/6,98); note(t,b+3*TPQ+TPQ/2,50,TPQ/6,104) end
end

local function add_bass_bar(bar,chord,strong)
  local t=SONG.tracks.bass local b=bar_tick(bar) local p=BASS[chord]
  note(t,b,p[1],TPQ*3/4,strong and 100 or 92); note(t,b+TPQ,p[2],TPQ/2,84)
  note(t,b+2*TPQ,p[3],TPQ*3/4,strong and 96 or 88); note(t,b+3*TPQ+TPQ/2,p[4],TPQ/3,82)
end

local function add_skank_bar(bar,chord,mode)
  local t=SONG.tracks.keys local g=SONG.tracks.guitar local b=bar_tick(bar) local ns=CHORDS[chord]
  if mode=="pad" then for _,n in ipairs(ns) do note(t,b,n+12,BAR,60) end; if chord=="Am" then note(g,b,69,BAR,66) end; return end
  for beat=0,3 do local off=b+beat*TPQ+TPQ/2; for _,n in ipairs(ns) do note(t,off,n+12,TPQ/3,74) end end
  local gv=(mode=="strong") and 84 or 72
  note(g,b+TPQ/2,ns[2]+12,TPQ/4,gv); note(g,b+TPQ*2+TPQ/2,ns[3]+12,TPQ/4,gv)
  if mode=="strong" then note(g,b+TPQ*3+TPQ/2,ns[1]+24,TPQ/2,78) end
end

local function add_lead_hook(bar,final)
  local t=SONG.tracks.lead local b=bar_tick(bar) local v=final and 104 or 90
  note(t,b+TPQ,69,TPQ/2,v); note(t,b+TPQ+TPQ/2,72,TPQ/2,v); note(t,b+TPQ*3,76,TPQ/2,v)
  if final then note(t,b+TPQ,81,TPQ/2,82); note(t,b+TPQ*3,88,TPQ/2,76) end
end

local function add_sax_response(bar)
  local t=SONG.tracks.sax local b=bar_tick(bar)
  note(t,b+TPQ*2,74,TPQ/2,78); note(t,b+TPQ*3,72,TPQ/2,76)
end

local function add_djembe_bar(bar,dense)
  local t=SONG.tracks.djembe local b=bar_tick(bar)
  note(t,b+TPQ/2,64,TPQ/6,58); note(t,b+TPQ+TPQ/2,63,TPQ/6,54); note(t,b+TPQ*2+TPQ/2,64,TPQ/6,60)
  if dense then note(t,b+TPQ*3,63,TPQ/6,56); note(t,b+TPQ*3+TPQ/2,64,TPQ/6,62) end
end

local function write_section(a,b,prog,opts)
  for bar=a,b do local chord=prog[((bar-a)%#prog)+1]
    add_drum_bar(bar,opts.drums,opts.fill and bar==b)
    if opts.bass then add_bass_bar(bar,chord,opts.strong_bass) end
    if opts.keys then add_skank_bar(bar,chord,opts.keys_mode or "skank") end
    if opts.lead and (bar-a)%2==0 then add_lead_hook(bar,opts.final_lead) end
    if opts.sax and (bar-a)%2==1 then add_sax_response(bar) end
    if opts.djembe then add_djembe_bar(bar,opts.dense_djembe) end
  end
end

local function meta_text(delta,t,text) return varlen(delta)..bytes(0xFF,t,#text)..text end
local function end_track() return varlen(0)..bytes(0xFF,0x2F,0x00) end
local function build_track(name,ch,program,notes)
local ev, data = {}, {meta_text(0,0x03,name)}
  if program~=nil then ev[#ev+1]={tick=0,o=0,d=bytes(0xC0+ch,program)} end
  for _,n in ipairs(notes) do ev[#ev+1]={tick=n.tick,o=2,d=bytes(0x90+ch,n.n,n.v)}; ev[#ev+1]={tick=n.tick+n.d,o=1,d=bytes(0x80+ch,n.n,0)} end
  table.sort(ev,function(x,y) if x.tick==y.tick then return x.o<y.o end return x.tick<y.tick end)
  local last=0 for _,e in ipairs(ev) do data[#data+1]=varlen(e.tick-last)..e.d; last=e.tick end
  data[#data+1]=end_track(); local body=table.concat(data); return "MTrk"..u32(#body)..body
end

local function exportMidi(path)
  local mpqn=math.floor(60000000/SONG.tempo)
  local t={meta_text(0,0x03,"Tempo Map"), varlen(0)..bytes(0xFF,0x51,0x03,math.floor(mpqn/65536)%256,math.floor(mpqn/256)%256,mpqn%256), varlen(0)..bytes(0xFF,0x58,0x04,0x04,0x02,0x18,0x08), varlen(0)..bytes(0xFF,0x59,0x02,0x00,0x00), end_track()}
  local tb=table.concat(t)
  local tracks={"MTrk"..u32(#tb)..tb, build_track("Drums",9,nil,SONG.tracks.drums), build_track("Bass",0,33,SONG.tracks.bass), build_track("Electric Piano",1,4,SONG.tracks.keys), build_track("Guitar",2,27,SONG.tracks.guitar), build_track("Lead",3,80,SONG.tracks.lead), build_track("Sax",4,65,SONG.tracks.sax), build_track("Djembe",5,117,SONG.tracks.djembe)}
  local h="MThd"..u32(6)..u16(1)..u16(#tracks)..u16(TPQ)
  local f=assert(io.open(path,"wb")); f:write(h); for _,tr in ipairs(tracks) do f:write(tr) end; f:close()
end

local function exportMarkdown(path)
  local md = [[# Signal Fire

## Global Settings
- **Style:** Psychedelic reggae rock
- **Key:** A minor
- **Tempo:** 82 BPM
- **Time Signature:** 4/4
- **Total Length:** 56 bars

## Section Map
| Section | Bars | Energy |
|---|---:|---|
| Intro / Dub Pulse | 1–4 | Smoky, restrained |
| Verse A | 5–12 | Groove-first, vocal space |
| Chorus 1 / Signal Hook | 13–20 | Attitude hook enters |
| Verse B / Grit Build | 21–28 | Bass-forward push |
| Psychedelic Break | 29–36 | Dub/space texture |
| Bridge / Drop to Smoke | 37–44 | Pad-heavy drop |
| Final Chorus / Full Fire | 45–52 | Bigger, still playable |
| Outro / Echo Fade | 53–56 | Am pedal and fade |

## Pattern Library
### Drum patterns
- **D1 Dub Groove:** kick weight on 1 and 3, snare on 2/4, closed hat eighths.
- **D2 Lifted Chorus:** same backbone with louder hats/kick.
- **D3 Fill Tag:** tom/snare fill in bar 4 before key section changes.

### Bass patterns
- **B1 Root-5 engine:** root and 5th with syncopated tail.
- **B2 Flat-7 color:** include b7 movement for minor attitude.
- **B3 E7 lead-in:** chromatic approach into E7 resolution.

### Chord/skank patterns
- **K1 Offbeat skank:** short stabs on every “&” beat.
- **K2 Bridge pad:** sustained voicings for smoke/drop sections.

### Guitar texture patterns
- **G1 Muted stabs:** sparse skank doubles.
- **G2 Chorus stabs:** stronger accents and occasional high sustain.

### Melody patterns
- **M1 Signal hook:** compact 2–3 note singable phrase.
- **M2 Final hook double:** octave support in final chorus.

### Sax patterns
- **S1 Response line:** call-and-response in empty vocal pockets.

### Djembe/percussion patterns
- **P1 Light pulse:** gentle offbeat hand percussion.
- **P2 Dense pulse:** extra strikes in final chorus for lift.

## Section Assignments
| Section | Drums | Bass | Keys | Guitar | Lead | Sax | Djembe |
|---|---|---|---|---|---|---|---|
| Intro | D1 | B1 | K1 | G1 | - | - | - |
| Verse A | D1 | B1/B2 | K1 | G1 | - | sparse | - |
| Chorus 1 | D2 | B1/B3 | K1 | G2 | M1 | S1 | light |
| Verse B | D1 | B2/B3 | K1 | G1 | - | sparse | - |
| Psychedelic Break | D2+D3 | B2 | K1 | G2 sustain | M1 | S1 | P1 |
| Bridge | D1 | B1 | K2 | sustain | - | sparse | P1 |
| Final Chorus | D2+D3 | B1/B3 strong | K1 | G2 strong | M2 | S1 | P2 |
| Outro | D1 | B1 (Am pedal) | K2 | sustain | motif tails | - | light |

## Practice Notes
- **Piano/Electric piano:** keep skanks short; bridge/outro switch to sustained pads.
- **Guitar:** think muted upstroke punctuation, then open up in final chorus.
- **Bass:** this is the attitude engine; lock kick/snare and drive transitions into E7.
- **Drums:** keep 2/4 authoritative; use fills only at section edges.
- **Sax:** answer vocal/hook space; avoid continuous playing.
- **Recording/production:** dub delays on skank and sax tails, widen final chorus by velocity and layering.

## App Notes
- Sections reference reusable pattern names so the groove can be iterated quickly.
- MIDI and Markdown are generated from the same Lua source to keep arrangement and notes in sync.
- Jam Notebook flow: capture idea -> rehearse by section -> export to DAW -> refine notation/arrangement.
]]
  local f=assert(io.open(path,"w")); f:write(md); f:close()
end

os.execute("mkdir -p jams/signal-fire")
write_section(1,4,SONG.progression_core,{drums="light",bass=true,keys=true,keys_mode="skank"})
write_section(5,12,SONG.progression_core,{drums="medium",bass=true,keys=true,keys_mode="skank",sax=true})
write_section(13,20,SONG.progression_core,{drums="full",bass=true,keys=true,keys_mode="strong",lead=true,sax=true,djembe=true,strong_bass=true})
write_section(21,28,SONG.progression_core,{drums="medium",bass=true,keys=true,keys_mode="skank",sax=true})
write_section(29,36,SONG.progression_core,{drums="full",fill=true,bass=true,keys=true,keys_mode="strong",lead=true,sax=true,djembe=true})
write_section(37,44,SONG.progression_bridge,{drums="light",bass=true,keys=true,keys_mode="pad",sax=true,djembe=true})
write_section(45,52,SONG.progression_core,{drums="full",fill=true,bass=true,keys=true,keys_mode="strong",lead=true,final_lead=true,sax=true,djembe=true,dense_djembe=true,strong_bass=true})
write_section(53,56,SONG.progression_outro,{drums="light",bass=true,keys=true,keys_mode="pad",lead=true})

exportMidi("jams/signal-fire/signal_fire.mid")
exportMarkdown("jams/signal-fire/signal_fire_arrangement.md")
print("Success: generated jams/signal-fire/signal_fire.mid")
print("Success: generated jams/signal-fire/signal_fire_arrangement.md")
