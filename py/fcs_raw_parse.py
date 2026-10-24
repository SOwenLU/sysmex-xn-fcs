#!/usr/bin/env python3
"""Independent byte-level FCS parser (Python stdlib only), used to cross-check flowCore.

Usage:  python3 -I fcs_raw_parse.py <file>

Prints one JSON document to stdout and never writes to disk. TEXT keywords are
emitted verbatim so the caller (R) can redact them before anything is saved.
Event values are reduced to per-parameter aggregates; no individual event is emitted.
"""
import hashlib
import json
import struct
import sys

MAX_DATASETS = 64


def to_int(s):
    s = s.strip()
    try:
        return int(s)
    except ValueError:
        return None


def parse_header(buf, base):
    h = buf[base:base + 58]
    if len(h) < 58:
        raise ValueError("file too short for an FCS HEADER at offset %d" % base)
    version = h[0:6].decode("latin-1")
    spacer = h[6:10].decode("latin-1")
    fields = [h[10 + 8 * i:18 + 8 * i].decode("latin-1") for i in range(6)]
    names = ["text_begin", "text_end", "data_begin", "data_end",
             "analysis_begin", "analysis_end"]
    offsets = {n: to_int(f) for n, f in zip(names, fields)}
    # Optional user-defined OTHER segment offsets sit between byte 58 and TEXT start
    other = []
    tb = offsets["text_begin"]
    if tb is not None and tb > 58:
        extra = buf[base + 58:base + tb].decode("latin-1")
        chunks = [extra[i:i + 8] for i in range(0, len(extra) - len(extra) % 8, 8)]
        other = [c for c in chunks if c.strip()]
    return {"version": version, "spacer_is_spaces": spacer == "    ",
            "offsets": offsets, "raw_fields": fields, "other_segment_fields": other}


def parse_text(raw):
    """Split a TEXT segment into key/value pairs; a doubled delimiter is an escaped literal."""
    delim = raw[0:1]
    tokens, cur, i, n = [], bytearray(), 1, len(raw)
    while i < n:
        c = raw[i:i + 1]
        if c == delim:
            if i + 1 < n and raw[i + 1:i + 2] == delim:
                cur += delim
                i += 2
                continue
            tokens.append(bytes(cur))
            cur = bytearray()
            i += 1
        else:
            cur += c
            i += 1
    trailing_unterminated = len(cur) > 0
    if trailing_unterminated:
        tokens.append(bytes(cur))
    pairs = []
    for k in range(0, len(tokens) - 1, 2):
        pairs.append([tokens[k].decode("latin-1"), tokens[k + 1].decode("latin-1")])
    return {
        "delimiter": delim.decode("latin-1"),
        "delimiter_ord": delim[0] if delim else None,
        "n_tokens": len(tokens),
        "odd_token_count": len(tokens) % 2 == 1,
        "ends_with_delimiter": not trailing_unterminated,
        "pairs": pairs,
    }


def kw_lookup(pairs):
    # FCS keywords are case-insensitive
    return {k.upper(): v for k, v in pairs}


def byteorder_prefix(byteord):
    b = byteord.replace(" ", "")
    if b in ("1,2,3,4", "1,2", "1", "1,2,3,4,5,6,7,8"):
        return "<"
    if b in ("4,3,2,1", "2,1", "8,7,6,5,4,3,2,1"):
        return ">"
    return None


def summarise_data(buf, kw, data_begin, data_end):
    out = {"supported": False}
    npar = to_int(kw.get("$PAR", "")) or 0
    tot = to_int(kw.get("$TOT", ""))
    dtype = kw.get("$DATATYPE", "").strip().upper()
    mode = kw.get("$MODE", "").strip().upper()
    byteord = kw.get("$BYTEORD", "")
    bits = [to_int(kw.get("$P%dB" % (p + 1), "")) for p in range(npar)]
    ranges = [kw.get("$P%dR" % (p + 1), "") for p in range(npar)]
    out.update({"n_par": npar, "tot": tot, "datatype": dtype, "mode": mode,
                "byteord": byteord, "bits": bits})
    if data_begin is None or data_end is None or data_end < data_begin:
        out["reason"] = "no DATA segment"
        return out
    seg = buf[data_begin:data_end + 1]
    out["data_bytes"] = len(seg)
    out["data_sha256"] = hashlib.sha256(seg).hexdigest()
    pref = byteorder_prefix(byteord)
    if mode != "L":
        out["reason"] = "$MODE %s not supported by raw parser" % mode
        return out
    if pref is None:
        out["reason"] = "unrecognised $BYTEORD %r" % byteord
        return out
    if dtype == "I":
        codes = {8: "B", 16: "H", 32: "I", 64: "Q"}
        if any(b not in codes for b in bits):
            out["reason"] = "integer bit widths %s not byte-aligned; raw parser does not unpack them" % bits
            return out
        fmt = pref + "".join(codes[b] for b in bits)
    elif dtype == "F":
        fmt = pref + "f" * npar
    elif dtype == "D":
        fmt = pref + "d" * npar
    else:
        out["reason"] = "$DATATYPE %s not supported by raw parser" % dtype
        return out
    width = struct.calcsize(fmt)
    n_events = len(seg) // width
    out["bytes_per_event"] = width
    out["events_from_data_length"] = n_events
    out["data_length_remainder"] = len(seg) % width
    stats = [{"n": 0, "min": None, "max": None, "sum": 0.0, "sumsq": 0.0,
              "n_zero": 0, "n_eq_range_minus1": 0, "n_ge_range": 0,
              "uniq": set(), "all_integer": True} for _ in range(npar)]
    rng = []
    for r in ranges:
        try:
            rng.append(float(r))
        except ValueError:
            rng.append(None)
    for ev in struct.iter_unpack(fmt, seg[:n_events * width]):
        for p, v in enumerate(ev):
            s = stats[p]
            s["n"] += 1
            s["min"] = v if s["min"] is None or v < s["min"] else s["min"]
            s["max"] = v if s["max"] is None or v > s["max"] else s["max"]
            s["sum"] += v
            s["sumsq"] += float(v) * float(v)
            if v == 0:
                s["n_zero"] += 1
            if rng[p] is not None:
                if v == rng[p] - 1:
                    s["n_eq_range_minus1"] += 1
                if v >= rng[p]:
                    s["n_ge_range"] += 1
            if len(s["uniq"]) <= 1_000_000:
                s["uniq"].add(v)
            if s["all_integer"] and float(v) != int(v):
                s["all_integer"] = False
    for s in stats:
        s["n_unique"] = len(s.pop("uniq"))
        s["mean"] = s["sum"] / s["n"] if s["n"] else None
    out["param_stats"] = stats
    out["supported"] = True
    return out


def parse_dataset(buf, base, index):
    hdr = parse_header(buf, base)
    off = hdr["offsets"]
    ds = {"dataset": index, "base_offset": base, "header": hdr}
    if hdr["version"] not in ("FCS2.0", "FCS3.0", "FCS3.1"):
        ds["error"] = "unexpected version string %r" % hdr["version"]
        return ds, None
    t0, t1 = base + off["text_begin"], base + off["text_end"]
    text = parse_text(buf[t0:t1 + 1])
    ds["text"] = text
    kw = kw_lookup(text["pairs"])

    def resolve(hkey, kkey):
        # HEADER offset, or the TEXT keyword when the HEADER holds 0 (large segments)
        h = off.get(hkey)
        k = to_int(kw.get(kkey, "")) if kkey.upper() in kw else None
        use = h if h not in (None, 0) else k
        return h, k, (base + use) if use not in (None,) else None

    db_h, db_k, db = resolve("data_begin", "$BEGINDATA")
    de_h, de_k, de = resolve("data_end", "$ENDDATA")
    ab_h, ab_k, ab = resolve("analysis_begin", "$BEGINANALYSIS")
    ae_h, ae_k, ae = resolve("analysis_end", "$ENDANALYSIS")
    ds["offsets_resolved"] = {
        "data_begin_header": db_h, "data_begin_keyword": db_k,
        "data_end_header": de_h, "data_end_keyword": de_k,
        "analysis_begin_header": ab_h, "analysis_begin_keyword": ab_k,
        "analysis_end_header": ae_h, "analysis_end_keyword": ae_k,
        "data_begin_abs": db, "data_end_abs": de,
    }
    ds["data_offsets_header_vs_keyword_agree"] = (
        None if db_k is None or db_h in (None, 0) else (db_h == db_k and de_h == de_k))
    has_analysis = ab is not None and ae is not None and (ae - ab) > 0 and (ab - base) > 0
    ds["analysis_segment_present"] = bool(has_analysis)
    ds["analysis_segment_bytes"] = (ae - ab + 1) if has_analysis else 0
    if has_analysis:
        atext = buf[ab:ae + 1]
        if atext[:1] and not atext[:1].isalnum():
            ds["analysis_text"] = parse_text(atext)
    sb, se = to_int(kw.get("$BEGINSTEXT", "")), to_int(kw.get("$ENDSTEXT", ""))
    ds["supplemental_text_present"] = bool(sb and se and se > sb)
    if ds["supplemental_text_present"]:
        ds["supplemental_text"] = parse_text(buf[base + sb:base + se + 1])
    ds["data"] = summarise_data(buf, kw, db, de)
    nxt = to_int(kw.get("$NEXTDATA", "0")) or 0
    ds["nextdata"] = nxt
    ends = [x for x in (t1, de, ae) if x is not None]
    ds["last_byte_used"] = max(ends) if ends else None
    return ds, (base + nxt if nxt else None)


def main(path):
    with open(path, "rb") as fh:
        buf = fh.read()
    res = {"file_size": len(buf), "file_sha256": hashlib.sha256(buf).hexdigest(),
           "magic": buf[:6].decode("latin-1"), "datasets": []}
    base, idx, seen = 0, 1, set()
    while base is not None and idx <= MAX_DATASETS:
        if base in seen or base >= len(buf):
            res["nextdata_error"] = "NEXTDATA points to %d (loop or past EOF)" % base
            break
        seen.add(base)
        ds, base = parse_dataset(buf, base, idx)
        res["datasets"].append(ds)
        if "error" in ds:
            break
        idx += 1
    res["n_datasets"] = len(res["datasets"])
    last = max((d.get("last_byte_used") or 0) for d in res["datasets"]) if res["datasets"] else 0
    trailing = buf[last + 1:]
    res["trailing_bytes"] = len(trailing)
    tstr = trailing.decode("latin-1").strip()
    res["trailing_is_crc_like"] = len(tstr) == 8 and tstr.isdigit()
    res["trailing_preview"] = tstr if res["trailing_is_crc_like"] else None
    json.dump(res, sys.stdout)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: fcs_raw_parse.py <file>")
    main(sys.argv[1])
