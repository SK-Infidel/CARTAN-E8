#!/usr/bin/env python3
"""
tools/document_reader.py
CARTAN / GeoMind Document Extraction Engine
Extracts structured Markdown text from Microsoft Word (.docx), Excel (.xlsx), and Adobe PDF (.pdf) files.
"""

import sys
import os
import re
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.getLogger("pypdf").setLevel(logging.ERROR)

W_NS = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
S_NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
R_NS = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"

def read_docx(path: str) -> str:
    """Extracts structured Markdown text and tables from a Word (.docx) file."""
    try:
        with zipfile.ZipFile(path, 'r') as z:
            if 'word/document.xml' not in z.namelist():
                return f"Error: Invalid .docx container; missing word/document.xml."
            xml_data = z.read('word/document.xml')
    except Exception as e:
        return f"Error reading .docx archive: {e}"

    try:
        root = ET.fromstring(xml_data)
    except Exception as e:
        return f"Error parsing document XML: {e}"

    body = root.find(f"{W_NS}body")
    if body is None:
        return "(Document body is empty)"

    output_lines = []

    for elem in body:
        # Paragraphs
        if elem.tag == f"{W_NS}p":
            p_style = ""
            p_pr = elem.find(f"{W_NS}pPr")
            is_bullet = False
            if p_pr is not None:
                style_elem = p_pr.find(f"{W_NS}pStyle")
                if style_elem is not None:
                    p_style = style_elem.attrib.get(f"{W_NS}val", "")
                num_pr = p_pr.find(f"{W_NS}numPr")
                if num_pr is not None:
                    is_bullet = True

            runs_text = []
            for child in elem.iter():
                if child.tag == f"{W_NS}t" and child.text:
                    runs_text.append(child.text)
                elif child.tag == f"{W_NS}tab":
                    runs_text.append("\t")

            p_text = "".join(runs_text).strip()
            if not p_text:
                continue

            # Map heading styles to Markdown
            low_style = p_style.lower()
            if "heading1" in low_style or "heading 1" in low_style:
                output_lines.append(f"\n# {p_text}\n")
            elif "heading2" in low_style or "heading 2" in low_style:
                output_lines.append(f"\n## {p_text}\n")
            elif "heading3" in low_style or "heading 3" in low_style:
                output_lines.append(f"\n### {p_text}\n")
            elif "heading4" in low_style or "heading 4" in low_style:
                output_lines.append(f"\n#### {p_text}\n")
            elif is_bullet or "bullet" in low_style or "list" in low_style:
                output_lines.append(f"* {p_text}")
            else:
                output_lines.append(p_text)

        # Tables
        elif elem.tag == f"{W_NS}tbl":
            table_rows = []
            max_cols = 0
            for tr in elem.findall(f"{W_NS}tr"):
                row_cells = []
                for tc in tr.findall(f"{W_NS}tc"):
                    cell_text_parts = []
                    for t_elem in tc.iter(f"{W_NS}t"):
                        if t_elem.text:
                            cell_text_parts.append(t_elem.text.strip())
                    cell_str = " ".join(cell_text_parts).replace("|", "\\|")
                    row_cells.append(cell_str)
                if row_cells:
                    table_rows.append(row_cells)
                    if len(row_cells) > max_cols:
                        max_cols = len(row_cells)

            if table_rows and max_cols > 0:
                output_lines.append("")
                # Header row
                header = table_rows[0] + [""] * (max_cols - len(table_rows[0]))
                output_lines.append("| " + " | ".join(header) + " |")
                output_lines.append("| " + " | ".join(["---"] * max_cols) + " |")
                # Data rows
                for r in table_rows[1:]:
                    padded_r = r + [""] * (max_cols - len(r))
                    output_lines.append("| " + " | ".join(padded_r) + " |")
                output_lines.append("")

    return "\n".join(output_lines)


def _col_str_to_idx(col_str: str) -> int:
    """Converts Excel column string (e.g. 'A', 'B', 'AA') to 0-based column index."""
    idx = 0
    for char in col_str.upper():
        if 'A' <= char <= 'Z':
            idx = idx * 26 + (ord(char) - ord('A') + 1)
    return idx - 1


def read_xlsx(path: str) -> str:
    """Extracts structured Markdown tables from an Excel (.xlsx) file."""
    try:
        with zipfile.ZipFile(path, 'r') as z:
            namelist = z.namelist()

            # 1. Parse shared strings table if present
            shared_strings = []
            if 'xl/sharedStrings.xml' in namelist:
                ss_root = ET.fromstring(z.read('xl/sharedStrings.xml'))
                for si in ss_root.findall(f"{S_NS}si"):
                    parts = []
                    for t_elem in si.iter(f"{S_NS}t"):
                        if t_elem.text:
                            parts.append(t_elem.text)
                    shared_strings.append("".join(parts))

            # 2. Parse workbook sheet names
            sheets = []
            if 'xl/workbook.xml' in namelist:
                wb_root = ET.fromstring(z.read('xl/workbook.xml'))
                sheets_elem = wb_root.find(f"{S_NS}sheets")
                if sheets_elem is not None:
                    for idx, sheet_elem in enumerate(sheets_elem.findall(f"{S_NS}sheet")):
                        s_name = sheet_elem.attrib.get("name", f"Sheet{idx+1}")
                        s_id = sheet_elem.attrib.get("sheetId", str(idx+1))
                        # Default path format
                        sheet_path = f"xl/worksheets/sheet{s_id}.xml"
                        if sheet_path not in namelist:
                            sheet_path = f"xl/worksheets/sheet{idx+1}.xml"
                        sheets.append((s_name, sheet_path))

            if not sheets:
                # Fallback to finding all sheet XMLs
                sheet_files = [f for f in namelist if f.startswith("xl/worksheets/sheet") and f.endswith(".xml")]
                sheet_files.sort()
                for idx, sf in enumerate(sheet_files):
                    sheets.append((f"Sheet{idx+1}", sf))

            if not sheets:
                return "(Workbook contains no worksheets)"

            output_blocks = []
            coord_pattern = re.compile(r"([A-Za-z]+)([0-9]+)")

            for sheet_name, sheet_path in sheets:
                if sheet_path not in namelist:
                    continue
                try:
                    s_root = ET.fromstring(z.read(sheet_path))
                except Exception:
                    continue

                sheet_data = s_root.find(f"{S_NS}sheetData")
                if sheet_data is None:
                    continue

                # Map (row_idx, col_idx) -> value
                grid = {}
                max_r = 0
                max_c = 0

                for row_elem in sheet_data.findall(f"{S_NS}row"):
                    row_num_str = row_elem.attrib.get("r")
                    default_r = int(row_num_str) - 1 if row_num_str and row_num_str.isdigit() else max_r

                    for c_elem in row_elem.findall(f"{S_NS}c"):
                        cell_ref = c_elem.attrib.get("r", "")
                        match = coord_pattern.match(cell_ref)
                        if match:
                            c_str, r_str = match.groups()
                            col_idx = _col_str_to_idx(c_str)
                            row_idx = int(r_str) - 1
                        else:
                            row_idx = default_r
                            col_idx = max_c

                        val_type = c_elem.attrib.get("t", "")
                        v_elem = c_elem.find(f"{S_NS}v")
                        cell_val = ""

                        if val_type == "s" and v_elem is not None and v_elem.text:
                            # Shared string lookup
                            try:
                                ss_idx = int(v_elem.text)
                                if 0 <= ss_idx < len(shared_strings):
                                    cell_val = shared_strings[ss_idx]
                            except ValueError:
                                cell_val = v_elem.text
                        elif val_type == "inlineStr":
                            is_elem = c_elem.find(f"{S_NS}is")
                            if is_elem is not None:
                                t_parts = [t.text for t in is_elem.iter(f"{S_NS}t") if t.text]
                                cell_val = "".join(t_parts)
                        elif val_type == "b" and v_elem is not None and v_elem.text:
                            cell_val = "TRUE" if v_elem.text == "1" else "FALSE"
                        elif v_elem is not None and v_elem.text:
                            cell_val = v_elem.text

                        if cell_val:
                            grid[(row_idx, col_idx)] = cell_val.strip().replace("|", "\\|")
                            if row_idx > max_r: max_r = row_idx
                            if col_idx > max_c: max_c = col_idx

                if not grid:
                    output_blocks.append(f"### Sheet: {sheet_name}\n*(Sheet is empty)*\n")
                    continue

                # Format grid as Markdown Table (limit to first 100 rows, 25 cols)
                rows_limit = min(max_r + 1, 100)
                cols_limit = min(max_c + 1, 25)

                lines = [f"### Sheet: {sheet_name}\n"]
                header_row = [grid.get((0, c), f"Col_{c+1}") for c in range(cols_limit)]
                lines.append("| " + " | ".join(header_row) + " |")
                lines.append("| " + " | ".join(["---"] * cols_limit) + " |")

                for r in range(1, rows_limit):
                    row_vals = [grid.get((r, c), "") for c in range(cols_limit)]
                    # Skip completely empty rows
                    if any(row_vals):
                        lines.append("| " + " | ".join(row_vals) + " |")

                if max_r >= 100 or max_c >= 25:
                    lines.append(f"\n*(Display truncated to {rows_limit} rows and {cols_limit} columns; total size: {max_r+1}x{max_c+1})*")

                output_blocks.append("\n".join(lines))

            return "\n\n".join(output_blocks)

    except Exception as e:
        return f"Error reading .xlsx archive: {e}"


def read_pdf(path: str) -> str:
    """Extracts structured text from a PDF (.pdf) file using pypdf."""
    try:
        import pypdf
    except ImportError:
        return "Error: pypdf library is not installed."

    try:
        reader = pypdf.PdfReader(path)
        total_pages = len(reader.pages)
        if total_pages == 0:
            return "(PDF document has 0 pages)"

        output_lines = [f"# PDF Document: {os.path.basename(path)} ({total_pages} pages)\n"]

        # Extract metadata if available
        if reader.metadata:
            meta_items = []
            if reader.metadata.title: meta_items.append(f"Title: {reader.metadata.title}")
            if reader.metadata.author: meta_items.append(f"Author: {reader.metadata.author}")
            if reader.metadata.subject: meta_items.append(f"Subject: {reader.metadata.subject}")
            if meta_items:
                output_lines.append("**Metadata**: " + " | ".join(meta_items) + "\n")

        for idx, page in enumerate(reader.pages):
            p_num = idx + 1
            text = page.extract_text() or ""
            text = text.strip()

            if text:
                output_lines.append(f"--- Page {p_num} ---")
                output_lines.append(text)
                output_lines.append("")
            else:
                has_images = len(page.images) > 0 if hasattr(page, 'images') else False
                if has_images:
                    output_lines.append(f"--- Page {p_num} ---")
                    output_lines.append("*(Scanned / Image-only page - no extractable text stream)*\n")

            # Limit preview to first 30 pages to prevent token context explosion
            if p_num >= 30 and total_pages > 30:
                output_lines.append(f"\n[... Document truncated at Page 30 of {total_pages} ...]")
                break

        return "\n".join(output_lines)

    except Exception as e:
        return f"Error reading PDF file: {e}"


def main():
    if len(sys.argv) < 2:
        print("Usage: python document_reader.py <file_path>")
        sys.exit(1)

    target_path = sys.argv[1]
    if not os.path.isfile(target_path):
        print(f"Error: File not found: {target_path}")
        sys.exit(1)

    ext = os.path.splitext(target_path)[1].lower()

    if ext == ".docx":
        res = read_docx(target_path)
    elif ext == ".xlsx":
        res = read_xlsx(target_path)
    elif ext == ".pdf":
        res = read_pdf(target_path)
    else:
        # Fallback raw text read
        try:
            with open(target_path, 'r', encoding='utf-8', errors='replace') as f:
                res = f.read()
        except Exception as e:
            res = f"Error reading file: {e}"

    # Print to stdout with UTF-8 encoding
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    print(res)


if __name__ == "__main__":
    main()
