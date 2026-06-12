#!/usr/bin/env python3
"""Clean MuseScore-inserted clef changes from the unified piano MXL.

The source file is a compressed MusicXML (``.mxl``) export from MuseScore.
This script extracts the score XML, removes all score-time clef changes, and
writes an uncompressed MusicXML file whose piano grand staff starts with a
fixed treble clef on staff 1 and bass clef on staff 2.  It intentionally does
not edit note pitches, note durations, voices, staff assignments, measure
structure, or playback-related events.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from zipfile import ZipFile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
SOURCE_MXL = ROOT / "xml" / "piano-others-seeing-red-clean-version-43631578-2unifiedmscx-davidgarciane.mxl"
GENERATED_DIR = ROOT / "generated"
OUTPUT_MUSICXML = GENERATED_DIR / "piano_unified_fixed_clefs.musicxml"
REPORT_OUTPUT = GENERATED_DIR / "piano_unified_fixed_clefs_report.txt"

MUSICXML_DECLARATION_AND_DOCTYPE = """<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE score-partwise PUBLIC \"-//Recordare//DTD MusicXML 4.0 Partwise//EN\" \"http://www.musicxml.org/dtds/partwise.dtd\">
"""

FIXED_CLEFS = {
    "1": ("G", "2", "treble"),
    "2": ("F", "4", "bass"),
}


@dataclass(frozen=True)
class ClefCleanupReport:
    clefs_found: int
    clefs_removed: int
    staff_1_status: str
    staff_2_status: str
    source_member: str


def read_score_xml_from_mxl(path: Path) -> tuple[bytes, str]:
    """Return the main score XML bytes and the member name from an MXL file."""
    with ZipFile(path) as archive:
        container_name = "META-INF/container.xml"
        if container_name in archive.namelist():
            container = ET.fromstring(archive.read(container_name))
            rootfile = container.find(".//{*}rootfile")
            if rootfile is not None and rootfile.get("full-path"):
                member_name = rootfile.get("full-path")
                return archive.read(member_name), member_name

        xml_members = [name for name in archive.namelist() if name.lower().endswith((".xml", ".musicxml"))]
        if not xml_members:
            raise FileNotFoundError(f"No MusicXML member found inside {path}")
        member_name = xml_members[0]
        return archive.read(member_name), member_name


def child_text(element: ET.Element, name: str) -> str | None:
    child = element.find(name)
    return child.text.strip() if child is not None and child.text else None


def is_desired_clef(clef: ET.Element, staff_number: str) -> bool:
    sign, line, _ = FIXED_CLEFS[staff_number]
    return clef.get("number") == staff_number and child_text(clef, "sign") == sign and child_text(clef, "line") == line


def make_clef(staff_number: str) -> ET.Element:
    sign, line, _ = FIXED_CLEFS[staff_number]
    clef = ET.Element("clef", {"number": staff_number})
    ET.SubElement(clef, "sign").text = sign
    ET.SubElement(clef, "line").text = line
    return clef


def find_insert_index_for_clefs(attributes: ET.Element) -> int:
    """Place clefs in the MusicXML attributes order after staves/instruments."""
    preceding_tags = {"footnote", "level", "divisions", "key", "time", "staves", "part-symbol", "instruments"}
    insert_index = 0
    for index, child in enumerate(list(attributes)):
        if child.tag in preceding_tags:
            insert_index = index + 1
    return insert_index


def ensure_opening_attributes(root: ET.Element) -> ET.Element:
    first_part = root.find("part")
    if first_part is None:
        raise ValueError("MusicXML score has no <part> element")
    first_measure = first_part.find("measure")
    if first_measure is None:
        raise ValueError("MusicXML first part has no <measure> element")
    attributes = first_measure.find("attributes")
    if attributes is None:
        attributes = ET.Element("attributes")
        first_measure.insert(0, attributes)
    return attributes


def remove_existing_clefs(root: ET.Element) -> int:
    """Remove every existing clef element without touching non-clef content."""
    removed = 0
    for attributes in root.findall(".//attributes"):
        for child in list(attributes):
            if child.tag == "clef":
                attributes.remove(child)
                removed += 1
    return removed


def clean_clefs(root: ET.Element, source_member: str) -> ClefCleanupReport:
    all_clefs = root.findall(".//clef")
    clefs_found = len(all_clefs)
    opening_attributes = ensure_opening_attributes(root)

    original_opening_clefs = list(opening_attributes.findall("clef"))
    status_by_staff: dict[str, str] = {}
    for staff_number, (_, _, label) in FIXED_CLEFS.items():
        if any(is_desired_clef(clef, staff_number) for clef in original_opening_clefs):
            status_by_staff[staff_number] = f"preserved as opening staff {staff_number} {label} clef"
        else:
            status_by_staff[staff_number] = f"inserted/replaced as opening staff {staff_number} {label} clef"

    clefs_removed = remove_existing_clefs(root)

    # The fixed grand-staff clefs are notation-only metadata.  Inserting them at
    # the start of the first measure does not change note pitch, duration,
    # voice, staff assignment, measure ordering, or playback.
    insert_index = find_insert_index_for_clefs(opening_attributes)
    for offset, staff_number in enumerate(("1", "2")):
        opening_attributes.insert(insert_index + offset, make_clef(staff_number))

    return ClefCleanupReport(
        clefs_found=clefs_found,
        clefs_removed=clefs_removed,
        staff_1_status=status_by_staff["1"],
        staff_2_status=status_by_staff["2"],
        source_member=source_member,
    )


def write_musicxml(root: ET.Element, path: Path) -> None:
    ET.indent(root, space="  ")
    xml_body = ET.tostring(root, encoding="unicode", short_empty_elements=True)
    path.write_text(MUSICXML_DECLARATION_AND_DOCTYPE + xml_body + "\n", encoding="utf-8")


def write_report(report: ClefCleanupReport, path: Path) -> None:
    assumptions = [
        "The MXL container's rootfile is the score to clean.",
        "The score is a single piano grand-staff part where staff 1 should remain treble and staff 2 should remain bass throughout.",
        "Clef elements are notation metadata here; removing mid-score clefs and inserting fixed opening clefs does not transpose notes or alter playback timing.",
        "All non-clef MusicXML content is left intact, including pitches, durations, voices, staff assignments, measures, directions, and playback-related data.",
    ]
    lines = [
        "Piano unified fixed-clefs report",
        "================================",
        f"Source MXL: {SOURCE_MXL}",
        f"Score XML member read: {report.source_member}",
        f"Output MusicXML: {OUTPUT_MUSICXML}",
        "",
        f"Clef elements found: {report.clefs_found}",
        f"Clef elements removed: {report.clefs_removed}",
        f"Opening treble clef: {report.staff_1_status}.",
        f"Opening bass clef: {report.staff_2_status}.",
        "",
        "Assumptions made:",
    ]
    lines.extend(f"- {assumption}" for assumption in assumptions)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> None:
    GENERATED_DIR.mkdir(parents=True, exist_ok=True)
    score_xml, source_member = read_score_xml_from_mxl(SOURCE_MXL)
    root = ET.fromstring(score_xml)
    report = clean_clefs(root, source_member)
    write_musicxml(root, OUTPUT_MUSICXML)
    write_report(report, REPORT_OUTPUT)
    print(f"Wrote {OUTPUT_MUSICXML}")
    print(f"Wrote {REPORT_OUTPUT}")
    print(f"Clef elements found: {report.clefs_found}")
    print(f"Clef elements removed: {report.clefs_removed}")
    print(f"Opening treble clef: {report.staff_1_status}")
    print(f"Opening bass clef: {report.staff_2_status}")


if __name__ == "__main__":
    main()
