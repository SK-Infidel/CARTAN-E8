# tools/build_gemma_vocab_scripts.py
# Compiles a compact 262,144-byte script table for Gemma 4 vocabulary.
# Byte v in [0..262143] indicates the script category of token v:
#   0: Universal (digits, punctuation, spaces, math symbols - always active)
#   1: Latin (English, French, German, Spanish, etc.)
#   2: Cyrillic (Russian, Ukrainian, etc.)
#   3: CJK (Chinese, Japanese Kanji/Kana)
#   4: Arabic (Arabic, Persian, Urdu)
#   5: Devanagari (Hindi, Sanskrit, Marathi)
#   6: Hangul (Korean)
#   7: Other scripts
# 255: Control tokens (never active in generation)

import json
import os
import struct
import sys
import unicodedata

def build_vocab_scripts(
    tok_path="cache_google_gemma-4-E4B-it_tokenizer.json",
    out_path="Projects/geomind/trainingdata/Checkpoints/geomind_vocab_scripts.bin"
):
    if not os.path.exists(tok_path):
        print(f"Error: Tokenizer file not found: {tok_path}")
        sys.exit(1)

    print(f"[build_vocab_scripts] Loading {tok_path}...")
    with open(tok_path, "r", encoding="utf-8") as f:
        d = json.load(f)

    vocab = d.get("model", {}).get("vocab", {})
    vocab_size = 262144
    scripts_table = bytearray(vocab_size)

    # Reserved control tokens
    control_ids = {0, 1, 2, 3, 105, 106, 2364, 4368}

    counts = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0, 255: 0}

    ALLOWED_PUNCT = set(' \t\n\r .,!?:;"\'-()/%$#@&*+=[]{}<>~`^_|\\•…–—\'‘“”«»$€£¥₹§°±²³µ')

    for s, idx in vocab.items():
        if idx >= vocab_size:
            continue
        is_control = (
            idx <= 106
            or s.startswith("<unused")
            or s.startswith("<|")
            or s.endswith("|>")
            or s.startswith("<tool")
            or s.startswith("<turn")
            or s.startswith("<channel")
            or idx in control_ids
        )
        if is_control:
            scripts_table[idx] = 255
            counts[255] += 1
            continue
        # Raw byte fallback tokens (<0x00> .. <0xFF>)
        if 238 <= idx <= 493:
            scripts_table[idx] = 7
            counts[7] += 1
            continue

        s_clean = s.replace("\u2581", " ")
        has_cjk = False
        has_cyrillic = False
        has_arabic = False
        has_devanagari = False
        has_hangul = False
        has_latin = False
        has_other = False
        has_alnum = False

        for ch in s_clean:
            if ch.isalnum():
                has_alnum = True
                try:
                    name = unicodedata.name(ch).split()[0]
                    if name in ("CJK", "HIRAGANA", "KATAKANA"):
                        has_cjk = True
                    elif name == "CYRILLIC":
                        has_cyrillic = True
                    elif name == "ARABIC":
                        has_arabic = True
                    elif name == "DEVANAGARI":
                        has_devanagari = True
                    elif name == "HANGUL":
                        has_hangul = True
                    elif name == "LATIN":
                        has_latin = True
                    else:
                        has_other = True
                except Exception:
                    has_other = True

        is_emoji = any(
            (0x1F300 <= ord(ch) <= 0x1FAFF)
            or (0x2600 <= ord(ch) <= 0x27BF)
            or (0xFE00 <= ord(ch) <= 0xFE0F)
            for ch in s_clean
        )
        if is_emoji:
            cat = 0 # Universal (emojis unmasked and active)
        elif not has_alnum:
            # Strictly confine Universal category 0 to authentic standard punctuation
            if all(ch in ALLOWED_PUNCT for ch in s_clean):
                cat = 0 # Universal standard punctuation
            else:
                cat = 7 # Other (rare symbols, kaomojis, combining marks)
        elif has_cjk:
            cat = 3 # CJK
        elif has_cyrillic:
            cat = 2 # Cyrillic
        elif has_arabic:
            cat = 4 # Arabic
        elif has_devanagari:
            cat = 5 # Devanagari
        elif has_hangul:
            cat = 6 # Hangul
        elif has_latin:
            cat = 1 # Latin
        else:
            cat = 7 # Other

        scripts_table[idx] = cat
        counts[cat] += 1

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "wb") as f:
        f.write(scripts_table)

    names = {
        0: "Universal (digits/punct/spaces)",
        1: "Latin (English/European)",
        2: "Cyrillic (Russian/Ukrainian)",
        3: "CJK (Chinese/Japanese)",
        4: "Arabic (Arabic/Persian/Urdu)",
        5: "Devanagari (Hindi/Sanskrit)",
        6: "Hangul (Korean)",
        7: "Other scripts",
        255: "Control tokens"
    }

    print(f"[build_vocab_scripts] Exported {len(scripts_table)} bytes to {out_path}.")
    print("[build_vocab_scripts] Distribution:")
    for cat, cnt in sorted(counts.items()):
        print(f"  [{cat:3d}] {names.get(cat, 'Unknown'):<32}: {cnt} tokens")

if __name__ == "__main__":
    build_vocab_scripts()
