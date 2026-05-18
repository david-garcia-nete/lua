local TPQ=480
local BAR=TPQ*4
local tempo=128
local tracks={drums={},bass={},rhythm={},lead={},vocal={},piano={}}
local function b(...) local t={} for i,v in ipairs({...}) do t[i]=string.char(v) end return table.concat(t) end
local function u16(n) return b(math.floor(n/256)%256,n%256) end
local function u32(n) return b(math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256) end
local function var(v) local r=v%128 v=math.floor(v/128) while v>0 do r=r*256+((v%128)+128) v=math.floor(v/128) end local o={} while true do o[#o+1]=string.char(r%256) if r<128 then break end r=math.floor(r/256) end return table.concat(o) end
local function note(t,tick,p,d,v) t[#t+1]={tick=tick,p=p,d=d,v=v or 90} end
local function bt(bar) return (bar-1)*BAR end
for bar=1,32 do
  local t=bt(bar)
  note(tracks.drums,t,36,TPQ/2,108); note(tracks.drums,t+TPQ,38,TPQ/2,102); note(tracks.drums,t+2*TPQ,36,TPQ/2,110); note(tracks.drums,t+3*TPQ,38,TPQ/2,106)
  local roots={38,36,34,36}
  for i=0,3 do note(tracks.bass,t+i*TPQ,roots[i+1],TPQ*3/4,88+i*2) end
  local riff={50,50,48,46}
  if (bar>=11 and bar<=14) or (bar>=21 and bar<=24) or (bar>=29 and bar<=31) then riff={46,41,48,50} end
  for i=0,3 do note(tracks.rhythm,t+i*TPQ,riff[i+1],TPQ*3/4,96) end
  if bar%2==1 then note(tracks.lead,t+TPQ,65,TPQ/2,94); note(tracks.lead,t+2*TPQ,67,TPQ/2,90) end
  if (bar>=5 and bar<=10) or (bar>=15 and bar<=20) then note(tracks.vocal,t+TPQ,69,TPQ/2,86); note(tracks.vocal,t+2*TPQ,67,TPQ/2,84); note(tracks.vocal,t+3*TPQ,65,TPQ/2,88) end
  if (bar>=11 and bar<=14) or (bar>=21 and bar<=24) or (bar>=29 and bar<=31) then note(tracks.vocal,t,74,TPQ/2,96); note(tracks.vocal,t+TPQ,77,TPQ/2,100); note(tracks.vocal,t+2*TPQ,76,TPQ/2,94) end
  note(tracks.piano,t,62,TPQ,74); note(tracks.piano,t+TPQ,65,TPQ,72); note(tracks.piano,t+2*TPQ,69,TPQ,70); note(tracks.piano,t+3*TPQ,72,TPQ,74)
end
local function eot() return var(0)..b(0xFF,0x2F,0) end
local function meta(d,t,s) return var(d)..b(0xFF,t,#s)..s end
local function tr(name,ch,prog,notes)
  local ev={{tick=0,o=0,d=meta(0,0x03,name)}}
  if prog then ev[#ev+1]={tick=0,o=1,d=b(0xC0+ch,prog)} end
  for _,n in ipairs(notes) do ev[#ev+1]={tick=n.tick,o=2,d=b(0x90+ch,n.p,n.v)} ev[#ev+1]={tick=n.tick+n.d,o=3,d=b(0x80+ch,n.p,0)} end
  table.sort(ev,function(a,b) if a.tick==b.tick then return a.o<b.o end return a.tick<b.tick end)
  local out,last={},0
  for _,x in ipairs(ev) do out[#out+1]=var(x.tick-last)..x.d last=x.tick end
  out[#out+1]=eot(); local body=table.concat(out)
  return 'MTrk'..u32(#body)..body
end
local mpqn=math.floor(60000000/tempo)
local tempoTrack='MTrk'..u32(35)..meta(0,0x03,'Tempo')..var(0)..b(0xFF,0x51,0x03,math.floor(mpqn/65536)%256,math.floor(mpqn/256)%256,mpqn%256)..var(0)..b(0xFF,0x58,0x04,0x04,0x02,0x18,0x08)..eot()
local out={tempoTrack,tr('Drums',9,nil,tracks.drums),tr('Bass',0,33,tracks.bass),tr('Rhythm',1,30,tracks.rhythm),tr('Lead',2,29,tracks.lead),tr('Vocal',3,54,tracks.vocal),tr('Piano',4,0,tracks.piano)}
os.execute('mkdir -p jams/breakout-drive')
local f=assert(io.open('jams/breakout-drive/breakout_drive.mid','wb'))
f:write('MThd'..u32(6)..u16(1)..u16(#out)..u16(TPQ)); for _,t in ipairs(out) do f:write(t) end; f:close()
print('generated jams/breakout-drive/breakout_drive.mid')
