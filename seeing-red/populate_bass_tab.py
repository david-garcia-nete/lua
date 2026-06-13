#!/usr/bin/env python3
"""Populate the empty electric-bass tablature staff in seeing-red-midi.mxl.

The script intentionally leaves the source .mxl untouched and writes an expanded
MusicXML file plus a text report under seeing-red/generated/.
"""
from __future__ import annotations

import copy
import zipfile
from dataclasses import dataclass
from pathlib import Path
import xml.etree.ElementTree as ET

SOURCE = Path("seeing-red/xml/seeing-red-midi.mxl")
OUTPUT = Path("seeing-red/generated/seeing-red-midi-with-bass-tab-fixed.musicxml")
REPORT = Path("seeing-red/generated/seeing-red-midi-with-bass-tab-fixed-report.txt")

STEP_TO_SEMITONE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
SEMITONE_TO_NAME = {
    0: "C",
    1: "C#",
    2: "D",
    3: "Eb",
    4: "E",
    5: "F",
    6: "F#",
    7: "G",
    8: "Ab",
    9: "A",
    10: "Bb",
    11: "B",
}
# MusicXML technical/string numbers use 1 for the highest-pitched string.
# MIDI numbers here are concert/sounding pitches for standard 4-string bass.
BASS_STRINGS = [
    (1, "G2", 43),
    (2, "D2", 38),
    (3, "A1", 33),
    (4, "E1", 28),
]


@dataclass
class ConversionIssue:
    measure: str
    pitch: str
    reason: str


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def child(parent: ET.Element, name: str) -> ET.Element | None:
    for item in parent:
        if local_name(item.tag) == name:
            return item
    return None


def children(parent: ET.Element, name: str) -> list[ET.Element]:
    return [item for item in parent if local_name(item.tag) == name]


def child_text(parent: ET.Element, name: str, default: str | None = None) -> str | None:
    item = child(parent, name)
    return item.text if item is not None else default


def findall_path(parent: ET.Element, *names: str) -> list[ET.Element]:
    current = [parent]
    for name in names:
        nxt: list[ET.Element] = []
        for item in current:
            nxt.extend(children(item, name))
        current = nxt
    return current


def first_path(parent: ET.Element, *names: str) -> ET.Element | None:
    matches = findall_path(parent, *names)
    return matches[0] if matches else None


def pitch_to_midi(pitch: ET.Element) -> int:
    step = child_text(pitch, "step")
    octave = child_text(pitch, "octave")
    if step is None or octave is None:
        raise ValueError("pitch is missing step or octave")
    alter = int(float(child_text(pitch, "alter", "0") or "0"))
    return STEP_TO_SEMITONE[step] + alter + (int(octave) + 1) * 12


def midi_to_name(midi: int) -> str:
    return f"{SEMITONE_TO_NAME[midi % 12]}{midi // 12 - 1}"


def pitch_name(pitch: ET.Element) -> str:
    return midi_to_name(pitch_to_midi(pitch))


def read_mxl_score(path: Path) -> ET.ElementTree:
    with zipfile.ZipFile(path) as archive:
        rootfile = None
        if "META-INF/container.xml" in archive.namelist():
            container = ET.fromstring(archive.read("META-INF/container.xml"))
            for elem in container.iter():
                if local_name(elem.tag) == "rootfile":
                    rootfile = elem.attrib.get("full-path")
                    break
        if rootfile is None:
            xml_files = [name for name in archive.namelist() if name.lower().endswith(".xml")]
            if not xml_files:
                raise RuntimeError(f"No MusicXML payload found in {path}")
            rootfile = xml_files[0]
        return ET.ElementTree(ET.fromstring(archive.read(rootfile)))


def part_names(root: ET.Element) -> dict[str, str]:
    names: dict[str, str] = {}
    part_list = child(root, "part-list")
    if part_list is None:
        return names
    for score_part in children(part_list, "score-part"):
        part_id = score_part.attrib.get("id")
        name = child_text(score_part, "part-name", "") or ""
        if part_id:
            names[part_id] = name.strip()
    return names


def measure_attributes(measure: ET.Element) -> list[ET.Element]:
    return children(measure, "attributes")


def clef_sign(part: ET.Element, staff_number: str) -> str | None:
    for measure in children(part, "measure"):
        for attrs in measure_attributes(measure):
            for clef in children(attrs, "clef"):
                if clef.attrib.get("number", "1") == staff_number:
                    return child_text(clef, "sign")
    return None


def declared_staves(part: ET.Element) -> int:
    for measure in children(part, "measure"):
        for attrs in measure_attributes(measure):
            staves = child_text(attrs, "staves")
            if staves:
                return int(staves)
    return 1


def note_staff(note: ET.Element) -> str:
    return child_text(note, "staff", "1") or "1"


def note_is_rest(note: ET.Element) -> bool:
    return child(note, "rest") is not None


def note_is_chord_continuation(note: ET.Element) -> bool:
    return child(note, "chord") is not None


def identify_bass_part(root: ET.Element) -> tuple[ET.Element | None, list[str]]:
    names = part_names(root)
    candidates: list[tuple[ET.Element, str]] = []
    for part in children(root, "part"):
        pid = part.attrib.get("id", "")
        name = names.get(pid, "")
        if "bass" not in name.lower():
            continue
        if declared_staves(part) < 2:
            continue
        if clef_sign(part, "1") == "F" and clef_sign(part, "2") == "TAB":
            candidates.append((part, name))
    if len(candidates) != 1:
        return None, [
            "Could not safely identify exactly one bass part with staff 1 bass clef and staff 2 TAB clef.",
            f"Candidate count: {len(candidates)}",
        ]
    part, name = candidates[0]
    non_rest_tab_notes = []
    for measure in children(part, "measure"):
        for note in children(measure, "note"):
            if note_staff(note) == "2" and not note_is_rest(note):
                non_rest_tab_notes.append(measure.attrib.get("number", "?"))
    if non_rest_tab_notes:
        return None, [
            "The candidate tab staff is not empty; refusing to overwrite existing tablature.",
            "Measures with non-rest notes on staff 2: " + ", ".join(non_rest_tab_notes[:25]),
        ]
    return part, [f"Identified part {part.attrib.get('id')} ({name}) as the electric bass part."]


def get_octave_change(part: ET.Element) -> int:
    for measure in children(part, "measure"):
        for attrs in measure_attributes(measure):
            transpose = child(attrs, "transpose")
            if transpose is not None:
                octave_change = child_text(transpose, "octave-change")
                if octave_change:
                    return int(octave_change)
    return 0


def best_bass_position(sounding_midi: int) -> tuple[int, int] | None:
    playable: list[tuple[int, int, int, int]] = []
    for string_number, _name, open_midi in BASS_STRINGS:
        fret = sounding_midi - open_midi
        if 0 <= fret <= 24:
            preferred_penalty = 0 if fret <= 12 else 100
            playable.append((preferred_penalty + fret, fret, string_number, open_midi))
    if not playable:
        return None
    _score, fret, string_number, _open = min(playable)
    return string_number, fret


def replace_or_append_text(parent: ET.Element, name: str, text: str) -> None:
    elem = child(parent, name)
    if elem is None:
        elem = ET.Element(name)
        parent.append(elem)
    elem.text = text


def remove_children(parent: ET.Element, name: str) -> None:
    for item in list(parent):
        if local_name(item.tag) == name:
            parent.remove(item)


def set_staff_and_voice(note: ET.Element, staff: str, voice: str) -> None:
    replace_or_append_text(note, "voice", voice)
    replace_or_append_text(note, "staff", staff)


def note_voice(note: ET.Element) -> str:
    return child_text(note, "voice", "1") or "1"


def add_technical(note: ET.Element, string_number: int, fret: int) -> None:
    notations = child(note, "notations")
    if notations is None:
        notations = ET.Element("notations")
        # Keep notations after lyric/time-modification/staff where possible; appending is valid MusicXML.
        note.append(notations)
    technical = child(notations, "technical")
    if technical is None:
        technical = ET.Element("technical")
        notations.append(technical)
    remove_children(technical, "string")
    remove_children(technical, "fret")
    string_elem = ET.Element("string")
    string_elem.text = str(string_number)
    fret_elem = ET.Element("fret")
    fret_elem.text = str(fret)
    technical.append(string_elem)
    technical.append(fret_elem)


def convert_source_item(
    item: ET.Element,
    measure: ET.Element,
    octave_change: int,
    issues: list[ConversionIssue],
    stats: dict[str, object],
    voice_map: dict[str, str],
) -> ET.Element:
    tab_item = copy.deepcopy(item)
    if local_name(tab_item.tag) != "note":
        return tab_item
    source_voice = note_voice(tab_item)
    tab_voice = voice_map.setdefault(source_voice, str(4 + len(voice_map) + 1))
    set_staff_and_voice(tab_item, "2", tab_voice)
    # Remove lyrics from the duplicated tablature notes if any ever appear on the bass staff.
    remove_children(tab_item, "lyric")
    pitch = child(tab_item, "pitch")
    if pitch is not None:
        written_midi = pitch_to_midi(pitch)
        sounding_midi = written_midi + (12 * octave_change)
        pos = best_bass_position(sounding_midi)
        stats["note_count"] = int(stats["note_count"]) + 1
        stats.setdefault("written_midis", []).append(written_midi)  # type: ignore[union-attr]
        stats.setdefault("sounding_midis", []).append(sounding_midi)  # type: ignore[union-attr]
        if pos is None:
            issues.append(
                ConversionIssue(
                    measure.attrib.get("number", "?"),
                    f"written {pitch_name(pitch)} / sounding {midi_to_name(sounding_midi)}",
                    "outside standard 4-string bass range",
                )
            )
        else:
            string_number, fret = pos
            add_technical(tab_item, string_number, fret)
    return tab_item


def staff1_source_items(measure: ET.Element) -> list[ET.Element]:
    """Return the notation-staff musical events to mirror onto the TAB staff.

    In two-voice measures the bass notation staff can contain an internal backup
    between voices, followed by a final backup before the empty TAB staff.  The
    final backup belongs to the existing two-staff layout and must stay in the
    measure before the generated TAB events; internal backups must be copied so
    copied voice-2 notes keep their original rhythmic positions.
    """
    items = list(measure)
    first_tab_index = next(
        (idx for idx, item in enumerate(items) if local_name(item.tag) == "note" and note_staff(item) == "2"),
        len(items),
    )
    final_reset_index = None
    for idx in range(first_tab_index - 1, -1, -1):
        if local_name(items[idx].tag) == "backup":
            final_reset_index = idx
            break
    source_end = final_reset_index if final_reset_index is not None else first_tab_index
    source: list[ET.Element] = []
    for item in items[:source_end]:
        tag = local_name(item.tag)
        if tag == "note" and note_staff(item) == "1":
            source.append(item)
        elif tag in {"backup", "forward"}:
            source.append(item)
    return source


def converted_staff2_items(
    measure: ET.Element,
    octave_change: int,
    issues: list[ConversionIssue],
    stats: dict[str, object],
) -> list[ET.Element]:
    voice_map: dict[str, str] = {}
    return [
        convert_source_item(item, measure, octave_change, issues, stats, voice_map)
        for item in staff1_source_items(measure)
    ]


def populate_tab_staff(part: ET.Element, octave_change: int) -> tuple[int, list[ConversionIssue], dict[str, object]]:
    issues: list[ConversionIssue] = []
    stats: dict[str, object] = {"note_count": 0, "written_midis": [], "sounding_midis": []}
    for measure in children(part, "measure"):
        replacement = converted_staff2_items(measure, octave_change, issues, stats)
        original_children = list(measure)
        new_children: list[ET.Element] = []
        inserted = False
        for item in original_children:
            if local_name(item.tag) == "note" and note_staff(item) == "2":
                if not inserted:
                    new_children.extend(replacement)
                    inserted = True
                continue
            new_children.append(item)
        if not inserted:
            backup_index = None
            for idx, item in enumerate(new_children):
                if local_name(item.tag) == "backup":
                    backup_index = idx
                    break
            insert_at = len(new_children) if backup_index is None else backup_index + 1
            new_children[insert_at:insert_at] = replacement
        measure[:] = new_children
    return int(stats["note_count"]), issues, stats


def note_duration(note: ET.Element) -> int:
    return int(child_text(note, "duration", "0") or "0")


def move_duration(item: ET.Element) -> int:
    return int(child_text(item, "duration", "0") or "0")


def measure_duration_name(duration: int, divisions: int, beat_type: int) -> str:
    if divisions <= 0 or beat_type <= 0:
        return f"{duration} divisions"
    beat_unit = divisions * 4
    numerator = duration * beat_type
    if numerator % beat_unit == 0:
        return f"{numerator // beat_unit}/{beat_type}"
    from math import gcd

    denominator = beat_unit
    divisor = gcd(numerator, denominator)
    return f"{numerator // divisor}/{denominator // divisor}"


def expected_measure_duration(measure: ET.Element, state: dict[str, int]) -> int:
    for attrs in measure_attributes(measure):
        divisions = child_text(attrs, "divisions")
        if divisions:
            state["divisions"] = int(divisions)
        time = child(attrs, "time")
        if time is not None:
            beats = child_text(time, "beats")
            beat_type = child_text(time, "beat-type")
            if beats and beat_type:
                state["beats"] = int(beats)
                state["beat_type"] = int(beat_type)
    return state["divisions"] * state["beats"] * 4 // state["beat_type"]


def validate_tab_staff_durations(part: ET.Element) -> tuple[list[str], list[str]]:
    """Validate that every generated TAB voice fills exactly one measure.

    MusicXML backup/forward elements move the measure cursor, while a <chord>
    note shares the previous note's onset and therefore must not consume extra
    time.  The generated TAB staff uses separate voices when the source notation
    staff uses separate voices, so each TAB voice must independently end at the
    full bar duration and no TAB event may extend beyond the bar.
    """
    state = {"divisions": 1, "beats": 4, "beat_type": 4}
    invalid: list[str] = []
    report_lines: list[str] = []
    for measure in children(part, "measure"):
        expected = expected_measure_duration(measure, state)
        cursor = 0
        voice_ends: dict[str, int] = {}
        overshot = False
        measure_number = measure.attrib.get("number", "?")
        for item in measure:
            tag = local_name(item.tag)
            if tag == "backup":
                cursor -= move_duration(item)
            elif tag == "forward":
                cursor += move_duration(item)
            elif tag == "note":
                if note_staff(item) != "2":
                    if not note_is_chord_continuation(item):
                        cursor += note_duration(item)
                    continue
                voice = note_voice(item)
                duration = note_duration(item)
                event_end = cursor if note_is_chord_continuation(item) else cursor + duration
                voice_ends[voice] = max(voice_ends.get(voice, 0), event_end)
                if event_end > expected:
                    overshot = True
                if not note_is_chord_continuation(item):
                    cursor += duration
        bad_voices = {voice: end for voice, end in voice_ends.items() if end != expected}
        final_duration = measure_duration_name(expected, state["divisions"], state["beat_type"])
        voice_summary = ", ".join(
            f"voice {voice}={measure_duration_name(end, state['divisions'], state['beat_type'])}"
            for voice, end in sorted(voice_ends.items())
        )
        if not voice_summary:
            voice_summary = "no TAB voices"
            bad_voices = {"none": 0}
        report_lines.append(f"- Measure {measure_number}: {final_duration} ({voice_summary})")
        if overshot or bad_voices:
            invalid.append(
                f"measure {measure_number}: expected {final_duration}; "
                + ", ".join(
                    f"voice {voice} found "
                    f"{measure_duration_name(end, state['divisions'], state['beat_type'])}"
                    for voice, end in sorted(bad_voices.items())
                )
            )
    return invalid, report_lines


def write_report(
    messages: list[str],
    part: ET.Element | None,
    note_count: int,
    issues: list[ConversionIssue],
    stats: dict[str, object],
    octave_change: int,
    duration_report: list[str] | None = None,
) -> None:
    lines: list[str] = []
    lines.append("Bass tablature generation report")
    lines.append("=================================")
    lines.append(f"Source: {SOURCE}")
    lines.append(f"Output: {OUTPUT}")
    lines.append("")
    lines.extend(messages)
    lines.append("")
    if part is None:
        lines.append("No score modifications were written because the tab staff could not be safely identified.")
    else:
        lines.append(f"Bass notation staff: part {part.attrib.get('id')} staff 1 (bass clef).")
        lines.append(
            f"Bass tab staff: part {part.attrib.get('id')} staff 2 "
            "(score staff 6, TAB clef; previously full-measure rests only)."
        )
        lines.append(f"Bass notes converted to tab: {note_count}")
        written_midis = stats.get("written_midis", [])
        sounding_midis = stats.get("sounding_midis", [])
        if written_midis:
            lines.append(
                f"Lowest bass note found: written {midi_to_name(min(written_midis))}, "
                f"sounding {midi_to_name(min(sounding_midis))}."
            )
            lines.append(
                f"Highest bass note found: written {midi_to_name(max(written_midis))}, "
                f"sounding {midi_to_name(max(sounding_midis))}."
            )
        lines.append("Notes that could not be converted:")
        if issues:
            for issue in issues:
                lines.append(f"- Measure {issue.measure}: {issue.pitch} ({issue.reason})")
        else:
            lines.append("- None")
        lines.append("Assumptions made:")
        lines.append("- The single part named Electric Bass with staff 1 in bass clef and staff 2 in TAB clef is the target part.")
        lines.append("- Staff 2 was considered empty because it contained only rests before conversion.")
        lines.append(
            f"- Existing bass transposition octave-change={octave_change} was applied when mapping written notes to sounding standard bass tuning."
        )
        lines.append("- MusicXML technical string numbers are 1=G, 2=D, 3=A, 4=E for this 4-string bass.")
        lines.append("- Frets 0-12 were preferred; higher frets up to 24 would be used only if necessary.")
        lines.append("- Rhythm, note durations, ties, rests, voices, and playback pitches were copied from the notation staff to the tab staff.")
        lines.append(
            "- Source notation voices were mapped to distinct TAB voices so MusicXML backup elements reset between voices correctly."
        )
        if duration_report is not None:
            lines.append("")
            lines.append("Corrected staff-6 measure durations:")
            lines.extend(duration_report)
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    tree = read_mxl_score(SOURCE)
    root = tree.getroot()
    part, messages = identify_bass_part(root)
    if part is None:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        write_report(messages, None, 0, [], {}, 0)
        print(f"No MusicXML written; see {REPORT}")
        return 1
    octave_change = get_octave_change(part)
    note_count, issues, stats = populate_tab_staff(part, octave_change)
    invalid_measures, duration_report = validate_tab_staff_durations(part)
    if invalid_measures:
        if OUTPUT.exists():
            OUTPUT.unlink()
        messages.extend(["Staff-6 duration validation failed before writing MusicXML.", *invalid_measures])
        write_report(messages, part, note_count, issues, stats, octave_change, duration_report)
        print("Staff-6 duration validation failed; no MusicXML written.")
        print("Invalid measures:")
        for invalid in invalid_measures:
            print(f"- {invalid}")
        print(f"See {REPORT}")
        return 1
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(tree, space="  ")
    tree.write(OUTPUT, encoding="utf-8", xml_declaration=True)
    write_report(messages, part, note_count, issues, stats, octave_change, duration_report)
    print(f"Wrote {OUTPUT}")
    print(f"Wrote {REPORT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
