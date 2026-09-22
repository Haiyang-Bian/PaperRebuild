"""Index a local DOCX for bounded reading; XML block IDs are not page numbers.

Uses the Python standard library. The local cache is not a verified transcript:
equations, tables, reading order and page references need the original scan.
"""

import argparse
import hashlib
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
NS = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
      "m": "http://schemas.openxmlformats.org/officeDocument/2006/math"}
TEXT_TAGS = {f"{{{NS['w']}}}t", f"{{{NS['m']}}}t"}


def text_of(element):
    return "".join(node.text or "" for node in element.iter() if node.tag in TEXT_TAGS)


def build_index(args):
    source = args.source.resolve()
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    with ZipFile(source) as archive:
        document = ET.fromstring(archive.read("word/document.xml"))
    records = []
    for number, element in enumerate(document.find("w:body", NS), 1):
        kind = element.tag.split("}")[-1]
        if kind == "sectPr":
            continue
        style = element.find("w:pPr/w:pStyle", NS)
        text = text_of(element)
        if kind == "tbl":
            text = "\n".join(" | ".join(text_of(cell) for cell in row.findall("w:tc", NS))
                             for row in element.findall("w:tr", NS))
        records.append({"block": number, "kind": kind,
                        "style": style.get(f"{{{NS['w']}}}val") if style is not None else None,
                        "math_objects": len(element.findall(".//m:oMath", NS)),
                        "text": text})
    args.cache.mkdir(parents=True, exist_ok=True)
    (args.cache / "blocks.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False) + "\n" for row in records), encoding="utf-8")
    metadata = {"source_name": source.name, "sha256": digest, "blocks": len(records),
                "characters": sum(len(row["text"]) for row in records),
                "warning": "Unverified conversion text. Block IDs are not PDF or printed pages."}
    (args.cache / "metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(metadata, ensure_ascii=False))


def read_index(args):
    records = (json.loads(line) for line in (args.cache / "blocks.jsonl").read_text(encoding="utf-8").splitlines())
    pattern = re.compile(args.pattern) if args.command == "find" else None
    count = 0
    for row in records:
        selected = bool(pattern.search(row["text"])) if pattern else args.start <= row["block"] <= args.end
        if selected and row["text"]:
            print(f"[B{row['block']:04d}; {row['kind']}; math={row['math_objects']}] {row['text']}")
            count += 1
            if count >= args.limit:
                print("[bounded output limit reached; continue with another range]")
                break


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache", type=Path, default=ROOT / "tmp" / "docx-thesis")
    commands = parser.add_subparsers(dest="command", required=True)
    index = commands.add_parser("index")
    index.add_argument("--source", type=Path, default=ROOT / "docs" / "摘要.docx")
    index.set_defaults(action=build_index)
    show = commands.add_parser("show")
    show.add_argument("--start", type=int, required=True)
    show.add_argument("--end", type=int, required=True)
    find = commands.add_parser("find")
    find.add_argument("pattern")
    for command in (show, find):
        command.add_argument("--limit", type=int, default=40)
        command.set_defaults(action=read_index)
    args = parser.parse_args()
    if args.command != "index" and not 1 <= args.limit <= 80:
        parser.error("limit must be within 1..80")
    if args.command == "show" and not 1 <= args.start <= args.end < args.start + 80:
        parser.error("read 1..80 XML blocks per call")
    args.action(args)


if __name__ == "__main__":
    main()
