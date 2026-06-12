#!/usr/bin/env python3
"""Generate experimental combined scores for the Seeing Red source files.

Implementation plan
-------------------
1. Treat the four MIDI files as one timing source and build a new MusicXML
   score with one part per source file.  A small in-script MIDI parser is used
   so the script can run even when optional MIDI libraries such as music21,
   mido, or pretty_midi are unavailable in the execution environment.
2. Treat the four existing MusicXML files as a second timing source.  Copy one
   source part per file into a new score without changing rhythms; append rest
   measures to shorter parts so every part reaches the longest source duration.
3. Write both experimental scores and a plain-text audit report to
   ``seeing-red/generated/``.  The source files in ``seeing-red/midi/`` and
   ``seeing-red/xml/`` are read-only inputs.

Notes
-----
The user requested music21 where possible.  This repository environment does
not provide music21, and package installation may be blocked by network policy.
The MIDI score therefore uses a dependency-free parser/converter rather than
failing.  If richer notation is needed later, mido or pretty_midi could replace
only ``parse_midi_file`` while keeping the rest of this workflow.
"""
from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass
from fractions import Fraction
from math import gcd
from pathlib import Path
import copy
import html
import struct
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
MIDI_DIR = ROOT / "midi"
XML_DIR = ROOT / "xml"
GENERATED_DIR = ROOT / "generated"
MIDI_OUTPUT = GENERATED_DIR / "combined_from_midi.musicxml"
XML_OUTPUT = GENERATED_DIR / "combined_from_xml.musicxml"
REPORT_OUTPUT = GENERATED_DIR / "combined_report.txt"

PART_SPECS = [
    ("Bass", "Bass-Seeing Red Clean Version-43631578.mid", "Bass-Seeing Red Clean Version-43631578.musicxml"),
    ("Drums", "Drums-Seeing Red Clean Version-43631578.mid", "Drums-Seeing Red Clean Version-43631578.musicxml"),
    ("Piano/Others", "Piano-Others-Seeing Red Clean Version-43631578 (1).mid", "Piano-Others-Seeing Red Clean Version-43631578.musicxml"),
    ("Vocal", "Vocal-Seeing Red Clean Version-43631578 (1).mid", "Vocal-Seeing Red Clean Version-43631578 (1).musicxml"),
]

MIDI_DIVISIONS = 15_360  # lcm(960, 1024) for exact MIDI tick-to-quarter conversion.
MEASURE_QUARTERS = 4


@dataclass(frozen=True)
class MidiNote:
    start_tick: int
    end_tick: int
    pitch: int
    channel: int
    velocity: int


@dataclass
class MidiPartInfo:
    name: str
    path: Path
    ppq: int
    max_tick: int
    notes: list[MidiNote]

    @property
    def quarter_length(self) -> Fraction:
        return Fraction(self.max_tick, self.ppq)

    @property
    def duration_seconds_at_120_bpm(self) -> Fraction:
        return self.quarter_length * Fraction(1, 2)

    @property
    def end_divisions(self) -> int:
        return int(self.quarter_length * MIDI_DIVISIONS)


@dataclass
class XmlPartInfo:
    name: str
    path: Path
    measures: int
    quarter_length: Fraction
    divisions: int
    padding_quarters: Fraction = Fraction(0, 1)
    padding_measures: int = 0


class GenerationError(RuntimeError):
    """Raised for clear, user-facing generation failures."""


def lcm(values: list[int]) -> int:
    result = 1
    for value in values:
        result = result * value // gcd(result, value)
    return result


def require_inputs() -> None:
    missing: list[Path] = []
    for _, midi_name, xml_name in PART_SPECS:
        for path in (MIDI_DIR / midi_name, XML_DIR / xml_name):
            if not path.exists():
                missing.append(path)
    if missing:
        joined = "\n".join(f"  - {path}" for path in missing)
        raise GenerationError(f"Missing required source files:\n{joined}")


def read_varlen(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    while True:
        if offset >= len(data):
            raise GenerationError("Unexpected end of MIDI data while reading variable-length quantity")
        byte = data[offset]
        offset += 1
        value = (value << 7) | (byte & 0x7F)
        if not byte & 0x80:
            return value, offset


def parse_midi_file(path: Path, name: str) -> MidiPartInfo:
    """Parse MIDI notes and timing with no third-party dependency.

    The parser handles Standard MIDI Files with running status, meta events,
    SysEx events, note-on, and note-off messages.  Tempo is intentionally not
    used for MusicXML placement; tick positions and PPQ are the timing source.
    """
    data = path.read_bytes()
    offset = 0
    if data[offset:offset + 4] != b"MThd":
        raise GenerationError(f"{path} is not a Standard MIDI File")
    offset += 4
    header_len = struct.unpack(">I", data[offset:offset + 4])[0]
    offset += 4
    if header_len < 6:
        raise GenerationError(f"{path} has an invalid MIDI header length")
    midi_format, track_count, division = struct.unpack(">HHH", data[offset:offset + 6])
    offset += header_len
    if division & 0x8000:
        raise GenerationError(f"{path} uses SMPTE time division; PPQ MIDI is required")
    ppq = division
    notes: list[MidiNote] = []
    max_tick = 0

    for track_index in range(track_count):
        if data[offset:offset + 4] != b"MTrk":
            raise GenerationError(f"{path} track {track_index + 1} is missing an MTrk header")
        offset += 4
        track_len = struct.unpack(">I", data[offset:offset + 4])[0]
        offset += 4
        track_end = offset + track_len
        tick = 0
        running_status: int | None = None
        active: dict[tuple[int, int], list[tuple[int, int]]] = defaultdict(list)

        while offset < track_end:
            delta, offset = read_varlen(data, offset)
            tick += delta
            max_tick = max(max_tick, tick)
            status = data[offset]
            if status < 0x80:
                if running_status is None:
                    raise GenerationError(f"{path} has MIDI running status without prior status")
                status = running_status
            else:
                offset += 1
                if status < 0xF0:
                    running_status = status

            if status == 0xFF:  # meta event
                if offset >= len(data):
                    raise GenerationError(f"{path} has truncated MIDI meta event")
                offset += 1  # meta type
                length, offset = read_varlen(data, offset)
                offset += length
                continue
            if status in (0xF0, 0xF7):  # SysEx
                length, offset = read_varlen(data, offset)
                offset += length
                continue

            event_type = status >> 4
            channel = status & 0x0F
            if event_type in (0x8, 0x9, 0xA, 0xB, 0xE):
                pitch_or_controller = data[offset]
                value = data[offset + 1]
                offset += 2
                if event_type == 0x9 and value > 0:
                    active[(channel, pitch_or_controller)].append((tick, value))
                elif event_type == 0x8 or (event_type == 0x9 and value == 0):
                    starts = active.get((channel, pitch_or_controller))
                    if starts:
                        start_tick, velocity = starts.pop(0)
                        if tick > start_tick:
                            notes.append(MidiNote(start_tick, tick, pitch_or_controller, channel, velocity))
                            max_tick = max(max_tick, tick)
            elif event_type in (0xC, 0xD):
                offset += 1
            else:
                raise GenerationError(f"{path} contains unsupported MIDI event status 0x{status:02X}")

        # Close any unterminated notes at the track end so badly terminated MIDI
        # still produces a score and a visible duration in the report.
        for (channel, pitch), starts in active.items():
            for start_tick, velocity in starts:
                if tick > start_tick:
                    notes.append(MidiNote(start_tick, tick, pitch, channel, velocity))
        offset = track_end

    return MidiPartInfo(name=name, path=path, ppq=ppq, max_tick=max_tick, notes=notes)


def pitch_to_xml(pitch: int) -> tuple[str, int, int]:
    names = ["C", "C", "D", "D", "E", "F", "F", "G", "G", "A", "A", "B"]
    alters = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]
    pc = pitch % 12
    return names[pc], alters[pc], pitch // 12 - 1


def xml_escape(text: str) -> str:
    return html.escape(text, quote=True)


def add_pitched_note(lines: list[str], pitch: int, duration: int, chord: bool = False) -> None:
    step, alter, octave = pitch_to_xml(pitch)
    lines.append("      <note>")
    if chord:
        lines.append("        <chord/>")
    lines.append("        <pitch>")
    lines.append(f"          <step>{step}</step>")
    if alter:
        lines.append(f"          <alter>{alter}</alter>")
    lines.append(f"          <octave>{octave}</octave>")
    lines.append("        </pitch>")
    lines.append(f"        <duration>{duration}</duration>")
    lines.append("      </note>")


def add_rest(lines: list[str], duration: int) -> None:
    lines.append("      <note>")
    lines.append("        <rest/>")
    lines.append(f"        <duration>{duration}</duration>")
    lines.append("      </note>")


def midi_part_to_musicxml_lines(part: MidiPartInfo, part_id: str, global_end_divisions: int) -> list[str]:
    """Convert one parsed MIDI file to a measured MusicXML part.

    The conversion uses exact division positions derived from MIDI ticks.  Notes
    are represented as time slices: when several pitches sound at the same time,
    one note plus MusicXML chord notes are emitted for that slice.  This keeps
    onset and release timing exact, although it is intended as cleanup material
    rather than polished notation.
    """
    multiplier = Fraction(MIDI_DIVISIONS, part.ppq)
    intervals = [
        (int(note.start_tick * multiplier), int(note.end_tick * multiplier), note.pitch)
        for note in part.notes
        if note.end_tick > note.start_tick
    ]
    boundaries = {0, global_end_divisions}
    measure_divisions = MIDI_DIVISIONS * MEASURE_QUARTERS
    for measure_boundary in range(0, global_end_divisions + measure_divisions, measure_divisions):
        boundaries.add(measure_boundary)
    for start, end, _ in intervals:
        boundaries.add(start)
        boundaries.add(end)
    points = sorted(point for point in boundaries if 0 <= point <= global_end_divisions)

    lines = [f'  <part id="{part_id}">']
    measure_number = 1
    current_measure_end = measure_divisions
    lines.append(f'    <measure number="{measure_number}">')
    lines.append("      <attributes>")
    lines.append(f"        <divisions>{MIDI_DIVISIONS}</divisions>")
    lines.append("        <key><fifths>0</fifths></key>")
    lines.append("        <time><beats>4</beats><beat-type>4</beat-type></time>")
    lines.append("        <clef><sign>G</sign><line>2</line></clef>")
    lines.append("      </attributes>")

    for start, end in zip(points, points[1:]):
        if end <= start:
            continue
        while start >= current_measure_end:
            lines.append("    </measure>")
            measure_number += 1
            current_measure_end += measure_divisions
            lines.append(f'    <measure number="{measure_number}">')
        duration = end - start
        active_pitches = sorted({pitch for note_start, note_end, pitch in intervals if note_start < end and note_end > start})
        if active_pitches:
            add_pitched_note(lines, active_pitches[0], duration, chord=False)
            for pitch in active_pitches[1:]:
                add_pitched_note(lines, pitch, duration, chord=True)
        else:
            add_rest(lines, duration)

    lines.append("    </measure>")
    lines.append("  </part>")
    return lines


def write_midi_based_score(midi_infos: list[MidiPartInfo]) -> None:
    global_end_divisions = max(info.end_divisions for info in midi_infos)
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 3.1 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">',
        '<score-partwise version="3.1">',
        '  <work><work-title>Seeing Red - Combined from MIDI</work-title></work>',
        '  <identification>',
        '    <encoding><software>seeing-red/generate_combined_scores.py</software></encoding>',
        '  </identification>',
        '  <part-list>',
    ]
    for index, info in enumerate(midi_infos, start=1):
        lines.extend([
            f'    <score-part id="P{index}">',
            f'      <part-name>{xml_escape(info.name)}</part-name>',
            '    </score-part>',
        ])
    lines.append('  </part-list>')
    for index, info in enumerate(midi_infos, start=1):
        lines.extend(midi_part_to_musicxml_lines(info, f"P{index}", global_end_divisions))
    lines.append('</score-partwise>')
    MIDI_OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")


def measure_length_quarters(measure: ET.Element, current_divisions: int) -> tuple[Fraction, int]:
    divisions = current_divisions
    cursor = 0
    max_cursor = 0
    for child in list(measure):
        if child.tag == "attributes":
            divisions_text = child.findtext("divisions")
            if divisions_text:
                divisions = int(divisions_text)
        elif child.tag == "note":
            duration_text = child.findtext("duration")
            if duration_text and child.find("chord") is None:
                cursor += int(duration_text)
                max_cursor = max(max_cursor, cursor)
        elif child.tag == "forward":
            cursor += int(child.findtext("duration", "0"))
            max_cursor = max(max_cursor, cursor)
        elif child.tag == "backup":
            cursor -= int(child.findtext("duration", "0"))
    return Fraction(max_cursor, divisions), divisions


def read_xml_part_info(path: Path, name: str) -> XmlPartInfo:
    root = ET.parse(path).getroot()
    part = root.find("part")
    if part is None:
        raise GenerationError(f"{path} does not contain a MusicXML <part>")
    divisions = 1
    total = Fraction(0, 1)
    measures = part.findall("measure")
    for measure in measures:
        measure_quarters, divisions = measure_length_quarters(measure, divisions)
        total += measure_quarters
    return XmlPartInfo(name=name, path=path, measures=len(measures), quarter_length=total, divisions=divisions)


def renumber_part(part: ET.Element, part_id: str) -> ET.Element:
    copied = copy.deepcopy(part)
    copied.set("id", part_id)
    return copied


def make_padding_measure(number: int, divisions: int, duration_quarters: Fraction) -> ET.Element:
    measure = ET.Element("measure", {"number": str(number)})
    # Padding is measure-aligned for the current source set, but this guard keeps
    # the function safe if future inputs need a shorter final rest.
    duration = duration_quarters * divisions
    if duration.denominator != 1:
        raise GenerationError(f"Cannot create exact XML padding duration {duration_quarters} with divisions={divisions}")
    note = ET.SubElement(measure, "note")
    ET.SubElement(note, "rest")
    ET.SubElement(note, "duration").text = str(duration.numerator)
    return measure


def write_xml_based_score(xml_infos: list[XmlPartInfo]) -> None:
    max_quarters = max(info.quarter_length for info in xml_infos)
    output_root = ET.Element("score-partwise", {"version": "3.1"})
    work = ET.SubElement(output_root, "work")
    ET.SubElement(work, "work-title").text = "Seeing Red - Combined from XML"
    identification = ET.SubElement(output_root, "identification")
    encoding = ET.SubElement(identification, "encoding")
    ET.SubElement(encoding, "software").text = "seeing-red/generate_combined_scores.py"
    part_list = ET.SubElement(output_root, "part-list")

    source_roots: list[ET.Element] = []
    source_parts: list[ET.Element] = []
    for index, info in enumerate(xml_infos, start=1):
        source_root = ET.parse(info.path).getroot()
        source_part = source_root.find("part")
        if source_part is None:
            raise GenerationError(f"{info.path} does not contain a MusicXML <part>")
        source_roots.append(source_root)
        source_parts.append(source_part)
        score_part = ET.SubElement(part_list, "score-part", {"id": f"P{index}"})
        ET.SubElement(score_part, "part-name").text = info.name

    for index, (info, source_part) in enumerate(zip(xml_infos, source_parts), start=1):
        new_part = renumber_part(source_part, f"P{index}")
        padding = max_quarters - info.quarter_length
        info.padding_quarters = padding
        if padding:
            if padding.denominator != 1 or padding.numerator % MEASURE_QUARTERS != 0:
                raise GenerationError(f"{info.path} needs non-measure-aligned padding of {padding} quarter notes")
            pad_measures = padding.numerator // MEASURE_QUARTERS
            info.padding_measures = pad_measures
            next_number = info.measures + 1
            for extra in range(pad_measures):
                new_part.append(make_padding_measure(next_number + extra, info.divisions, Fraction(MEASURE_QUARTERS, 1)))
        output_root.append(new_part)

    tree = ET.ElementTree(output_root)
    ET.indent(tree, space="  ")
    tree.write(XML_OUTPUT, encoding="utf-8", xml_declaration=True)


def decimal(value: Fraction, digits: int = 9) -> str:
    return f"{float(value):.{digits}f}"


def write_report(midi_infos: list[MidiPartInfo], xml_infos: list[XmlPartInfo]) -> None:
    midi_max = max(info.quarter_length for info in midi_infos)
    xml_max = max(info.quarter_length for info in xml_infos)
    lines = [
        "Seeing Red combined-score generation report",
        "============================================",
        "",
        "Implementation plan executed:",
        "1. Read source files from seeing-red/midi/ and seeing-red/xml/ without modifying them.",
        "2. Generated one experimental combined score from MIDI timing.",
        "3. Generated one experimental combined score from MusicXML timing without vocal scaling.",
        "4. Padded shorter XML parts with rests to match the longest XML part.",
        "",
        "Generated files:",
        f"- {MIDI_OUTPUT.relative_to(ROOT)}",
        f"- {XML_OUTPUT.relative_to(ROOT)}",
        f"- {REPORT_OUTPUT.relative_to(ROOT)}",
        "",
        "Source files used:",
    ]
    for name, midi_name, xml_name in PART_SPECS:
        lines.append(f"- {name}: midi/{midi_name}; xml/{xml_name}")

    lines.extend(["", "MIDI timing source durations:"])
    for info in midi_infos:
        pad = midi_max - info.quarter_length
        lines.append(
            f"- {info.name}: {info.max_tick} ticks at PPQ {info.ppq}; "
            f"{decimal(info.quarter_length)} quarter notes; "
            f"{decimal(info.duration_seconds_at_120_bpm)} seconds at 120 BPM; "
            f"{len(info.notes)} parsed notes; MIDI-score rest padding to longest part: {decimal(pad)} quarter notes."
        )

    lines.extend(["", "MusicXML timing source durations and padding:"])
    for info in xml_infos:
        lines.append(
            f"- {info.name}: {info.measures} source measures; "
            f"{decimal(info.quarter_length)} quarter notes; "
            f"padding added: {info.padding_measures} measures / {decimal(info.padding_quarters)} quarter notes."
        )

    lines.extend([
        "",
        "Alignment risks:",
        "- The MIDI-derived score preserves tick timing with exact integer MusicXML divisions, but it is an experimental cleanup score: overlapping material is converted into time slices/chords and may need re-notation in MuseScore.",
        "- The MIDI files do not all end at the same time. Bass, Drums, and Vocal are close, while Piano/Others is much longer; shorter MIDI parts therefore receive trailing rests in the generated score.",
        "- The XML-derived score intentionally does not scale the vocal part. It preserves each source part's notation and appends rests, so endings align but internal musical sections may still not correspond if the source files came from different exports or arrangements.",
        "- The XML source files have different measure counts and durations before padding, so a combined score produced from them should be treated as a layout/cleanup starting point rather than proof of musical alignment.",
        "",
        "Recommendation for MuseScore cleanup:",
        "- The MIDI-based combined score is likely the better starting point if playback/timing alignment is the priority, because it uses the MIDI files as a shared tick-based timing source.",
        "- The XML-based combined score is likely the better starting point if preserving existing notation is the priority, but it carries higher alignment risk because the source XML durations differ substantially and padding only fixes the final barline alignment.",
        "- No vocal-duration scaling was applied or recommended by this generation step.",
        "",
        "Dependency note:",
        "- music21 was preferred, but it was not available in this environment. The script uses a dependency-free MIDI parser instead. If future MIDI import requires more expressive quantization or percussion mapping, replacing the parser with mido or pretty_midi would be the most direct alternative.",
    ])
    REPORT_OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    try:
        require_inputs()
        GENERATED_DIR.mkdir(parents=True, exist_ok=True)
        midi_infos = [parse_midi_file(MIDI_DIR / midi_name, name) for name, midi_name, _ in PART_SPECS]
        write_midi_based_score(midi_infos)
        xml_infos = [read_xml_part_info(XML_DIR / xml_name, name) for name, _, xml_name in PART_SPECS]
        write_xml_based_score(xml_infos)
        write_report(midi_infos, xml_infos)
    except GenerationError as exc:
        print(f"ERROR: {exc}")
        return 1
    print(f"Wrote {MIDI_OUTPUT}")
    print(f"Wrote {XML_OUTPUT}")
    print(f"Wrote {REPORT_OUTPUT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
