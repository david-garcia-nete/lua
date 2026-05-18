# Jam Notebook

## Repo organization
- `jam-scripts/` contains Lua generators for each jam.
- `jams/` contains generated jam outputs (MusicXML + MIDI + Markdown arrangement sheets).

Current layout:
- `jam-scripts/first_jam_midi.lua`
- `jam-scripts/signal_fire.lua`
- `jams/first-jam/first_jam.mid`
- `jams/first-jam/first_jam_arrangement.md`
- `jams/signal-fire/signal_fire.musicxml`
- `jams/signal-fire/signal_fire.mid`
- `jams/signal-fire/signal_fire_arrangement.md`

## Generate Signal Fire
Run from repo root:

```bash
lua jam-scripts/signal_fire.lua
```

Expected outputs:
- `jams/signal-fire/signal_fire.musicxml`
- `jams/signal-fire/signal_fire.mid`
- `jams/signal-fire/signal_fire_arrangement.md`
