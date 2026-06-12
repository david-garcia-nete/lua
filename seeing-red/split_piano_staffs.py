#!/usr/bin/env python3
"""Split fixed-clef piano MusicXML note staff assignments at middle C.

This script keeps a readable grand staff by assigning pitched notes below C4 to
staff 2 and pitched notes C4 or above to staff 1. It does not edit pitch,
rhythm, duration, measure, voice, or playback timing; only note ``<staff>``
values are changed. Rests and non-note elements are preserved.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
GENERATED_DIR = ROOT / "generated"
INPUT_MUSICXML = GENERATED_DIR / "piano_unified_fixed_clefs.musicxml"
OUTPUT_MUSICXML = GENERATED_DIR / "piano_unified_fixed_clefs_staff_split.musicxml"
REPORT_OUTPUT = GENERATED_DIR / "piano_unified_fixed_clefs_staff_split_report.txt"

MUSICXML_DECLARATION_AND_DOCTYPE = """<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">
"""

STEP_TO_SEMITONE = {
    "C": 0,
    "D": 2,
    "E": 4,
    "F": 5,
    "G": 7,
    "A": 9,
    "B": 11,
}
MIDDLE_C_MIDI = 60
ALTER_TO_TEXT = {
    -2: "bb",
    -1: "b",
    0: "",
    1: "#",
    2: "x",
}


@dataclass(frozen=True)
class NoteInfo:
    midi: int
    name: str


@dataclass
class StaffSplitReport:
    moved_treble_to_bass: int = 0
    moved_bass_to_treble: int = 0
    lowest_treble: NoteInfo | None = None
    highest_bass: NoteInfo | None = None
    skipped: list[str] = field(default_factory=list)


def child_text(element: ET.Element, name: str) -> str | None:
    child = element.find(name)
    return child.text.strip() if child is not None and child.text else None


def parse_note_pitch(note: ET.Element, measure_number: str, note_index: int) -> NoteInfo | None:
    pitch = note.find("pitch")
    if pitch is None:
        return None

    step = child_text(pitch, "step")
    octave_text = child_text(pitch, "octave")
    alter_text = child_text(pitch, "alter")

    if step not in STEP_TO_SEMITONE:
        raise ValueError(f"measure {measure_number} note {note_index}: unsupported pitch step {step!r}")
    if octave_text is None:
        raise ValueError(f"measure {measure_number} note {note_index}: pitched note has no octave")

    octave = int(octave_text)
    alter = int(float(alter_text)) if alter_text is not None else 0
    midi = (octave + 1) * 12 + STEP_TO_SEMITONE[step] + alter
    alter_label = ALTER_TO_TEXT.get(alter, f"{alter:+}")
    return NoteInfo(midi=midi, name=f"{step}{alter_label}{octave}")


def update_extreme_notes(report: StaffSplitReport, note_info: NoteInfo, staff_number: str) -> None:
    if staff_number == "1":
        if report.lowest_treble is None or note_info.midi < report.lowest_treble.midi:
            report.lowest_treble = note_info
    elif staff_number == "2":
        if report.highest_bass is None or note_info.midi > report.highest_bass.midi:
            report.highest_bass = note_info


def split_staffs(root: ET.Element) -> StaffSplitReport:
    report = StaffSplitReport()

    for measure in root.findall(".//measure"):
        measure_number = measure.get("number", "unknown")
        for note_index, note in enumerate(measure.findall("note"), start=1):
            if note.find("rest") is not None:
                continue

            try:
                note_info = parse_note_pitch(note, measure_number, note_index)
            except (TypeError, ValueError) as exc:
                report.skipped.append(str(exc))
                continue

            if note_info is None:
                report.skipped.append(f"measure {measure_number} note {note_index}: note has no <pitch> and is not a rest")
                continue

            staff = note.find("staff")
            if staff is None:
                report.skipped.append(f"measure {measure_number} note {note_index} {note_info.name}: missing <staff>")
                continue

            current_staff = staff.text.strip() if staff.text else ""
            target_staff = "2" if note_info.midi < MIDDLE_C_MIDI else "1"

            if current_staff == "1" and target_staff == "2":
                report.moved_treble_to_bass += 1
                staff.text = "2"
            elif current_staff == "2" and target_staff == "1":
                report.moved_bass_to_treble += 1
                staff.text = "1"
            elif current_staff not in {"1", "2"}:
                report.skipped.append(
                    f"measure {measure_number} note {note_index} {note_info.name}: unsupported staff {current_staff!r}"
                )
                continue

            update_extreme_notes(report, note_info, target_staff)

    return report


def write_musicxml(root: ET.Element, path: Path) -> None:
    ET.indent(root, space="  ")
    xml_body = ET.tostring(root, encoding="unicode", short_empty_elements=True)
    path.write_text(MUSICXML_DECLARATION_AND_DOCTYPE + xml_body + "\n", encoding="utf-8")


def format_note(note_info: NoteInfo | None) -> str:
    return note_info.name if note_info is not None else "None"


def write_report(report: StaffSplitReport, path: Path) -> None:
    lines = [
        "Piano fixed-clef staff split report",
        "===================================",
        f"Input MusicXML: {INPUT_MUSICXML}",
        f"Output MusicXML: {OUTPUT_MUSICXML}",
        "Split point: C4 / Middle C (notes below C4 -> staff 2; notes C4 and above -> staff 1)",
        "",
        f"Notes moved from treble to bass: {report.moved_treble_to_bass}",
        f"Notes moved from bass to treble: {report.moved_bass_to_treble}",
        f"Lowest note remaining on treble staff: {format_note(report.lowest_treble)}",
        f"Highest note remaining on bass staff: {format_note(report.highest_bass)}",
        "",
        "Notes skipped and why:",
    ]
    if report.skipped:
        lines.extend(f"- {item}" for item in report.skipped)
    else:
        lines.append("- None")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    root = ET.parse(INPUT_MUSICXML).getroot()
    report = split_staffs(root)
    write_musicxml(root, OUTPUT_MUSICXML)
    write_report(report, REPORT_OUTPUT)

    print(f"Wrote {OUTPUT_MUSICXML}")
    print(f"Wrote {REPORT_OUTPUT}")
    print(f"Notes moved from treble to bass: {report.moved_treble_to_bass}")
    print(f"Notes moved from bass to treble: {report.moved_bass_to_treble}")
    print(f"Lowest note remaining on treble staff: {format_note(report.lowest_treble)}")
    print(f"Highest note remaining on bass staff: {format_note(report.highest_bass)}")
    print(f"Notes skipped: {len(report.skipped)}")


if __name__ == "__main__":
    main()
