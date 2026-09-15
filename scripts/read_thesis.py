"""Inspect a thesis PDF or render a bounded selection of its physical pages.

Python is used only for document handling; research models belong in Julia.
Dependencies: pypdf (inspect), pypdfium2 and Pillow (render).
"""

import argparse
import hashlib
import json
import sys
from importlib.metadata import version
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PDF = ROOT / "docs" / "摘要.pdf"


def select_pages(value, count):
    """Parse 1-based PDF page numbers, keeping the user's order."""
    selected = []
    for part in value.split(","):
        ends = part.strip().split("-")
        if len(ends) == 1:
            start = stop = int(ends[0])
        elif len(ends) == 2:
            start, stop = map(int, ends)
        else:
            raise ValueError(f"Invalid page range: {part}")
        if not 1 <= start <= stop <= count:
            raise ValueError(f"Page range must be within 1..{count}: {part}")
        for page in range(start, stop + 1):
            if page not in selected:
                selected.append(page)
    return selected


def inspect_pdf(args):
    from pypdf import PdfReader

    digest = hashlib.sha256()
    with args.pdf.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    reader = PdfReader(args.pdf)
    pages = []
    for number, page in enumerate(reader.pages, 1):
        record = {
            "pdf_page": number,
            "width_pt": float(page.mediabox.width),
            "height_pt": float(page.mediabox.height),
            "declared_rotation_degrees": page.rotation,
        }
        try:
            record["extracted_nonwhitespace_characters"] = len(
                "".join((page.extract_text() or "").split())
            )
        except Exception as exc:
            record["extracted_nonwhitespace_characters"] = None
            record["extraction_error"] = f"{type(exc).__name__}: {exc}"
        pages.append(record)
    try:
        source = args.pdf.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        source = str(args.pdf.resolve())
    data = {
        "source": source,
        "sha256": digest.hexdigest(),
        "size_bytes": args.pdf.stat().st_size,
        "pdf_page_count": len(pages),
        "inspection_tool": {"script": "scripts/read_thesis.py", "pypdf_version": version("pypdf")},
        "metadata": {str(k): str(v) for k, v in (reader.metadata or {}).items()},
        "pages_without_extractable_text": sum(
            p["extracted_nonwhitespace_characters"] == 0 for p in pages
        ),
        "pages_with_extraction_errors": sum("extraction_error" in p for p in pages),
        "note": "Physical PDF page numbers are 1-based. This is a text-layer check, not OCR or a reading-completion record. Printed page labels and content orientation require visual verification.",
        "pages": pages,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in data.items() if k not in ("pages", "metadata")}, ensure_ascii=False))
    print(f"Saved: {args.output}")


def render_pdf(args):
    import pypdfium2 as pdfium

    if not 36 <= args.dpi <= 600:
        raise ValueError("DPI must be between 36 and 600")
    with pdfium.PdfDocument(str(args.pdf)) as document:
        pages = select_pages(args.pages, len(document))
        if len(pages) > 12:
            raise ValueError("Render at most 12 physical pages per call; split reading into bounded batches")
        args.output.mkdir(parents=True, exist_ok=True)
        for number in pages:
            page = document[number - 1]
            try:
                bitmap = page.render(scale=args.dpi / 72, rotation=args.rotation)
                try:
                    image = bitmap.to_pil()
                    try:
                        path = args.output / f"pdf-{number:03d}-r{args.rotation}-{args.dpi}dpi.png"
                        image.save(path)
                        print(path)
                    finally:
                        image.close()
                finally:
                    bitmap.close()
            finally:
                page.close()


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pdf", type=Path, default=DEFAULT_PDF)
    commands = parser.add_subparsers(dest="command", required=True)
    inspect = commands.add_parser("inspect", help="Hash source and check each page's text layer")
    inspect.add_argument("--output", type=Path, default=ROOT / "docs" / "reading" / "source_manifest.json")
    inspect.set_defaults(action=inspect_pdf)
    render = commands.add_parser("render", help="Render selected physical pages without changing the PDF")
    render.add_argument("--pages", required=True, help="1-based physical pages, e.g. 6-9,30")
    render.add_argument("--rotation", type=int, choices=(0, 90, 180, 270), default=0, help="Clockwise rotation of the rendered page; verify per batch")
    render.add_argument("--dpi", type=int, default=130)
    render.add_argument("--output", type=Path, default=ROOT / "tmp" / "pdfs" / "reading")
    render.set_defaults(action=render_pdf)
    args = parser.parse_args()
    args.action(args)


if __name__ == "__main__":
    main()
