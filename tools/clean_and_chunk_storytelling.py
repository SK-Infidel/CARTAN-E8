"""
Clean and chunk Projects/geomind/trainingdata/storytelling_corpus.txt into pure 7-bit ASCII,
paragraph-unwrapped, curriculum-ordered digestible chunks for CARTAN-E8 byte-latent training.
Strictly zero regex used (deterministic string and character state-machine parsing).
"""

import os
import glob
import json

UTF8_REPLACEMENTS = [
    ("\u2018", "'"),
    ("\u2019", "'"),
    ("\u201c", '"'),
    ("\u201d", '"'),
    ("\u2014", " - "),
    ("\u2013", " - "),
    ("--", " - "),
    ("\u2026", "..."),
    ("\u00e6", "ae"),
    ("\u00c6", "Ae"),
    ("\u0153", "oe"),
    ("\u0152", "Oe"),
    ("\u00e9", "e"),
    ("\u00e8", "e"),
    ("\u00ea", "e"),
    ("\u00eb", "e"),
    ("\u00e0", "a"),
    ("\u00e1", "a"),
    ("\u00e2", "a"),
    ("\u00e4", "a"),
    ("\u00ef", "i"),
    ("\u00ee", "i"),
    ("\u00ed", "i"),
    ("\u00f4", "o"),
    ("\u00f6", "o"),
    ("\u00f3", "o"),
    ("\u00f9", "u"),
    ("\u00fb", "u"),
    ("\u00fc", "u"),
    ("\u00fa", "u"),
    ("\u00e7", "c"),
    ("\u00f1", "n"),
    ("\u00a3", "pounds "),
    ("\u00bd", "1/2"),
    ("\u00a0", " "),
]

BOOK_BOUNDARIES = {
    "Alice In Wonderland": (
        "Alice was beginning to get very tired",
        "remembering her own child-life, and the happy summer",
        False,
        2,
    ),
    "Anthem": (
        "It is a sin to write this.",
        "The sacred word:",
        True,
        2,
    ),
    "Sherlock Holmes": (
        "To Sherlock Holmes she is always",
        "where I believe that she has met with considerable success.",
        True,
        3,
    ),
    "Frankenstein": (
        "You will rejoice to hear that no disaster",
        "lost in darkness and distance.",
        False,
        3,
    ),
    "Pride And Prejudice": (
        "It is a truth universally acknowledged",
        "uniting them.",
        False,
        4,
    ),
    "Dracula": (
        "_3 May. Bistritz._",
        "already knows Ring and all that belongs to him.",
        True,
        4,
    ),
    "Great Expectations": (
        "My father\u2019s family name being Pirrip",
        "I saw no shadow of another parting",
        True,
        4,
    ),
    "Tom Sawyer": (
        "\u201cTOM!\u201d",
        "part of their lives at present.",
        False,
        4,
    ),
    "Moby Dick": (
        "Call me Ishmael.",
        "only found another orphan.",
        False,
        5,
    ),
    "Huckleberry Finn": (
        "You don\u2019t know about me without you have read",
        "I been there before.",
        False,
        6,
    ),
}


def is_separator_line(s: str) -> bool:
    stripped = s.replace("-", "").replace("=", "").replace("*", "").replace(" ", "").strip()
    return len(stripped) == 0


def normalize_ascii_line(text: str) -> str:
    if is_separator_line(text):
        return ""
    for src, dst in UTF8_REPLACEMENTS:
        if src in text:
            text = text.replace(src, dst)
    if "_" in text:
        text = text.replace("_", "")
    out_chars = []
    prev_space = False
    for ch in text:
        code = ord(ch)
        if code == 9 or code == 32:
            if not prev_space:
                out_chars.append(" ")
                prev_space = True
        elif 33 <= code <= 126:
            out_chars.append(ch)
            prev_space = False
    res = "".join(out_chars).strip()
    if is_separator_line(res):
        return ""
    return res


def is_chapter_or_metadata_header(line: str) -> bool:
    if not line or is_separator_line(line):
        return True
    up = line.upper()
    prefixes = (
        "CHAPTER ",
        "PART ONE",
        "PART TWO",
        "PART THREE",
        "PART FOUR",
        "PART FIVE",
        "PART SIX",
        "PART SEVEN",
        "PART EIGHT",
        "PART NINE",
        "PART TEN",
        "PART ELEVEN",
        "PART TWELVE",
        "LETTER 1",
        "LETTER 2",
        "LETTER 3",
        "LETTER 4",
        "BOOK TITLE:",
        "GENRE:",
        "### CHAPTER",
        "--- BOOK:",
        "===",
        "THE END",
        "CONCLUSION",
        "[ILLUSTRATION",
        "[_COPYRIGHT",
    )
    for p in prefixes:
        if up.startswith(p):
            return True
    roman_prefixes = (
        "I. ", "II. ", "III. ", "IV. ", "V. ", "VI. ",
        "VII. ", "VIII. ", "IX. ", "X. ", "XI. ", "XII. ",
    )
    for rp in roman_prefixes:
        if line.startswith(rp) and line.isupper():
            return True
    if len(line) < 55 and line.isupper() and any(c.isalpha() for c in line):
        if not line.endswith(".") and not line.endswith("!") and not line.endswith("?") and not line.endswith('"'):
            return True
    return False


def stitch_broken_sentences(paragraphs: list) -> list:
    """
    Stitches paragraphs that were broken mid-sentence by page-break illustrations
    (e.g., when paragraph i does not end with terminal punctuation or paragraph i+1 starts lowercase).
    """
    if not paragraphs:
        return []
    merged = [paragraphs[0]]
    terminal_chars = '.!?"\'):;'
    for p in paragraphs[1:]:
        if not p:
            continue
        prev = merged[-1]
        first_alpha = ""
        for ch in p:
            if ch.isalpha():
                first_alpha = ch
                break
        starts_lower = (first_alpha != "" and first_alpha.islower())
        ends_incomplete = (prev[-1] not in terminal_chars)
        if starts_lower or ends_incomplete:
            merged[-1] = normalize_ascii_line(prev + " " + p)
        else:
            merged.append(p)
    return merged


def unwrap_paragraphs(raw_lines: list, double_spaced: bool) -> list:
    """
    Unwraps 70-column hard-wrapped lines into clean full-sentence paragraphs.
    Handles nested [Illustration: ... [_Copyright ...]] blocks without splitting sentences.
    """
    paragraphs = []
    cur_lines = []
    blank_run = 0
    bracket_depth = 0

    para_blank_threshold = 2 if double_spaced else 1

    for raw in raw_lines:
        s = raw.strip()
        if bracket_depth > 0:
            bracket_depth += s.count("[") - s.count("]")
            if bracket_depth < 0:
                bracket_depth = 0
            continue
        if s.startswith("[Illustration") or s.startswith("[_Copyright"):
            bracket_depth = s.count("[") - s.count("]")
            if bracket_depth < 0:
                bracket_depth = 0
            continue

        if not s or is_separator_line(s):
            blank_run += 1
            if blank_run >= para_blank_threshold and cur_lines:
                joined = normalize_ascii_line(" ".join(cur_lines))
                if joined and len(joined) >= 20:
                    paragraphs.append(joined)
                cur_lines = []
            continue

        blank_run = 0
        cleaned = normalize_ascii_line(s)
        if not cleaned or is_chapter_or_metadata_header(cleaned):
            if cur_lines:
                joined = normalize_ascii_line(" ".join(cur_lines))
                if joined and len(joined) >= 20:
                    paragraphs.append(joined)
                cur_lines = []
            continue

        cur_lines.append(cleaned)

    if cur_lines:
        joined = normalize_ascii_line(" ".join(cur_lines))
        if joined and len(joined) >= 20:
            paragraphs.append(joined)

    return stitch_broken_sentences(paragraphs)


def extract_modern_opening_section(pre_book_text: str) -> list:
    """
    Extracts the clean modern narrative stories and Speaker A/B dialogues from the top of
    storytelling_corpus.txt, stopping before CLASSICAL LITERARY DIALOGUES.
    """
    cutoff = pre_book_text.find("CLASSICAL LITERARY DIALOGUES")
    if cutoff != -1:
        pre_book_text = pre_book_text[:cutoff]

    paragraphs = []
    pending_speaker_a = ""
    for raw_line in pre_book_text.splitlines():
        s = raw_line.strip()
        if not s or is_separator_line(s):
            continue
        if is_chapter_or_metadata_header(s):
            continue
        if s.startswith("CONVERSATIONAL DIALOGUES") or s.startswith("GEOMIND MULTI-GENRE"):
            continue
        cleaned = normalize_ascii_line(s)
        if len(cleaned) < 15:
            continue
        if cleaned.startswith("Speaker A:"):
            pending_speaker_a = cleaned
        elif cleaned.startswith("Speaker B:") and pending_speaker_a:
            paragraphs.append(pending_speaker_a + "\n" + cleaned)
            pending_speaker_a = ""
        else:
            if pending_speaker_a:
                paragraphs.append(pending_speaker_a)
                pending_speaker_a = ""
            paragraphs.append(cleaned)
    return paragraphs


def extract_clean_tinystories(ts_path: str) -> list:
    if not os.path.exists(ts_path):
        return []
    with open(ts_path, "r", encoding="utf-8", errors="replace") as f:
        lines = f.readlines()
    paragraphs = []
    cur = []
    for raw in lines:
        s = raw.strip()
        if not s or is_separator_line(s):
            if cur:
                joined = normalize_ascii_line(" ".join(cur))
                if len(joined) >= 25:
                    paragraphs.append(joined)
                cur = []
            continue
        if s.startswith("Story ") or s.startswith("Theme:") or s.startswith("==="):
            continue
        cur.append(s)
    if cur:
        joined = normalize_ascii_line(" ".join(cur))
        if len(joined) >= 25:
            paragraphs.append(joined)
    return stitch_broken_sentences(paragraphs)


def slice_book_lines(lines: list, start_marker: str, end_marker: str) -> list:
    start_idx = 0
    for i, l in enumerate(lines):
        if start_marker in l:
            start_idx = i
            break
    end_idx = len(lines)
    for i in range(len(lines) - 1, start_idx, -1):
        if end_marker in lines[i]:
            end_idx = i + 4
            break
    return lines[start_idx:min(end_idx, len(lines))]


def pack_paragraphs_into_chunks(paragraphs: list, source_name: str, tier: int, target_bytes: int = 12000) -> list:
    chunks = []
    cur_paras = []
    cur_len = 0
    for p in paragraphs:
        p_len = len(p) + 1
        if cur_len + p_len > target_bytes and cur_paras:
            chunks.append({
                "source": source_name,
                "tier": tier,
                "text": "\n".join(cur_paras) + "\n",
                "bytes": cur_len,
                "paragraphs": len(cur_paras),
            })
            cur_paras = [p]
            cur_len = p_len
        else:
            cur_paras.append(p)
            cur_len += p_len
    if cur_paras:
        chunks.append({
            "source": source_name,
            "tier": tier,
            "text": "\n".join(cur_paras) + "\n",
            "bytes": cur_len,
            "paragraphs": len(cur_paras),
        })
    return chunks


def main():
    corpus_path = "Projects/geomind/trainingdata/storytelling_corpus.txt"
    tinystories_path = "Projects/geomind/trainingdata/hf_roneneldan_TinyStories.txt"
    out_dir = "Projects/geomind/trainingdata/storytelling_chunks"
    clean_master_path = "Projects/geomind/trainingdata/storytelling_corpus_clean.txt"

    os.makedirs(out_dir, exist_ok=True)
    for old_f in glob.glob(os.path.join(out_dir, "chunk_*.txt")):
        os.remove(old_f)

    with open(corpus_path, "r", encoding="utf-8", errors="replace") as f:
        full_text = f.read()

    parts = full_text.split("--- BOOK:")
    modern_paras = extract_modern_opening_section(parts[0])
    tiny_paras = extract_clean_tinystories(tinystories_path)

    all_sources = []
    if tiny_paras:
        all_sources.append(("TinyStories_Curated", 1, tiny_paras))
    if modern_paras:
        all_sources.append(("GeoMind_Modern_Narratives", 1, modern_paras))

    book_map = {}
    for p in parts[1:]:
        lines = p.splitlines()
        title = lines[0].replace("---", "").strip()
        book_map[title] = lines[1:]

    ordered_books = sorted(BOOK_BOUNDARIES.keys(), key=lambda k: BOOK_BOUNDARIES[k][3])
    for title in ordered_books:
        if title not in book_map:
            continue
        start_m, end_m, is_double, tier = BOOK_BOUNDARIES[title]
        if tier >= 6:
            continue
        sliced = slice_book_lines(book_map[title], start_m, end_m)
        paras = unwrap_paragraphs(sliced, is_double)
        safe_title = title.replace(" ", "_")
        all_sources.append((safe_title, tier, paras))

    all_chunks = []
    master_paragraphs = []
    for src_name, tier, paras in all_sources:
        master_paragraphs.extend(paras)
        chunks = pack_paragraphs_into_chunks(paras, src_name, tier, target_bytes=12000)
        all_chunks.extend(chunks)
        total_b = sum(c["bytes"] for c in chunks)
        print(f"  [Tier {tier}] {src_name:28s}: {len(paras):5d} paragraphs -> {len(chunks):3d} chunks ({total_b:8d} bytes)")

    manifest = []
    for idx, ch in enumerate(all_chunks):
        chunk_id = idx + 1
        fname = f"chunk_{chunk_id:03d}_t{ch['tier']}_{ch['source']}.txt"
        fpath = os.path.join(out_dir, fname).replace("\\", "/")
        with open(fpath, "w", encoding="ascii", errors="ignore") as cf:
            cf.write(ch["text"])
        manifest.append({
            "chunk_id": chunk_id,
            "file": fpath,
            "source": ch["source"],
            "tier": ch["tier"],
            "bytes": ch["bytes"],
            "paragraphs": ch["paragraphs"],
        })

    with open(clean_master_path, "w", encoding="ascii", errors="ignore") as mf:
        for p in master_paragraphs:
            mf.write(p + "\n")

    manifest_path = os.path.join(out_dir, "manifest.json").replace("\\", "/")
    with open(manifest_path, "w", encoding="utf-8") as jf:
        json.dump({
            "total_chunks": len(manifest),
            "total_bytes": sum(m["bytes"] for m in manifest),
            "total_paragraphs": len(master_paragraphs),
            "chunks": manifest,
        }, jf, indent=2)

    print("--------------------------------------------------------------------------------")
    print(f"Total Clean Chunks : {len(manifest)}")
    print(f"Total Clean Bytes  : {sum(m['bytes'] for m in manifest):,d} bytes")
    print(f"Clean Master Saved : {clean_master_path}")
    print(f"Chunk Directory    : {out_dir}")


if __name__ == "__main__":
    main()
