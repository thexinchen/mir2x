"""Verify original costume frame groups and inspect the supplied MIX/MIZ records.

This exports metadata and decoded-byte hashes, not converted textures. Pixel
channel layout, blend behavior and current mir2x equipment correspondence are
deliberately outside the conclusions of this tool.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zlib

from export_mir3_aura_state import extract as extract_aura
from export_mir3_target_history import read_va


EXPECTED_FILES = {
    "1.dat": "95fe9f8091f1c317272726fafee454e3987ac23dee7a7739b32502c316c1cc81",
    "1.MIX": "0e5c82a3bde2081af0d85d7dc255632d1890d18ed0c8a8d0f10054109c2758fd",
    "1.MIZ": "c24ef6b5dce1484630c09a7401ada3dabf348775a0ed0e4b925d166a54ba1b87",
    "300.dat": "80f802fd796d671dcb5455805fcf146c2a0319e961208f5ed2b3c8b3598828da",
    "300.MIX": "775214212f5bab67d1279a06bc6261a586f126b4d168316d0bbcd8693e8df7a0",
    "300.MIZ": "3a352d24b54353f2d3c5579ee48892d365341256be6f412c8dc6c3ab89b6bca0",
}


def inspect_frame(index, images, number):
    count = struct.unpack_from("<I", index, 16)[0]
    if not 0 <= number < count:
        raise ValueError("frame outside MIX index")
    offset = struct.unpack_from("<I", index, 24 + 4 * number)[0]
    if offset == 0:
        return {"image": number, "file_offset": 0, "present": False}
    if offset < 24 or offset + 24 > len(images):
        raise ValueError("invalid MIZ frame offset")
    width, height, x, y, compressed_size = struct.unpack_from("<HHhhI", images, offset)
    pixel_format = images[offset + 12]
    if not (0 < width <= 4096 and 0 < height <= 4096) or pixel_format != 0:
        raise ValueError("unsupported frame dimensions or pixel storage")
    if not 0 < compressed_size <= 1372525 or offset + 16 + compressed_size > len(images):
        raise ValueError("invalid compressed frame size")
    stride = (width * 2 + 3) // 4 * 4
    expected_size = stride * height
    decoder = zlib.decompressobj()
    pixels = decoder.decompress(images[offset + 16:offset + 16 + compressed_size], expected_size + 1)
    if (len(pixels) != expected_size or not decoder.eof
            or decoder.unused_data or decoder.unconsumed_tail):
        raise ValueError("MIZ decoded size or stream boundary mismatch")
    return {"image": number, "file_offset": offset, "present": True,
            "width": width, "height": height, "x_offset": x, "y_offset": y,
            "storage_flag": pixel_format, "compressed_bytes": compressed_size,
            "row_stride": stride, "decoded_bytes": len(pixels),
            "decoded_sha256": hashlib.sha256(pixels).hexdigest()}


def extract(sample_path, registry_path, data_root):
    aura = extract_aura(sample_path, registry_path, data_root / "ActorBuff.dat", data_root / "effects.lst")
    sample = sample_path.read_bytes()
    checks = [
        (0x4F7349, "66833b007676", "group loader requires nonzero first WORD count"),
        (0x4F737C, "0fb703508d4304b9010000008b15ccf44800e8cdf7f0ff", "group loader resizes dynamic array to WORD count"),
        (0x4F7396, "0fb7038bc803c903c903c98b5304", "group loader reads eight bytes per record"),
        (0x6FA323, "8b52048b0cc2894e048b4cc204894e08", "effect lookup copies selected eight-byte group"),
        (0x6E4DCE, "0fb6533680ea08740580ea08751c", "only8/16-direction groups add direction stride"),
        (0x6E4DDC, "0fb650020fb648036603d10fb64b2b660fafd1660310", "direction stride includes visible frames and padding"),
        (0x6E4DF8, "0fb71066895338", "single-direction group uses first image directly"),
        (0x6E4DFF, "0fb64002660343386689433a", "visible frame endpoint excludes padding count"),
        (0x6E4B9A, "8bd02b560c0fb74e343bd17635", "advance only when elapsed ticks exceed group interval"),
        (0x6E4BBC, "0fb74638894608837e18007e13", "wrap to first image; nonpositive repeat count remains live"),
        (0x6FB587, "b9180000008b45f8e86011d1ff", "MIX index reader consumes24-byte header"),
        (0x6FB5A2, "8b45f08947148bf003f603f6", "MIX index count determines four-byte offset table"),
        (0x6FB976, "8b0085c07e54", "frame header reader skips nonpositive file offsets"),
        (0x6FBA0B, "8b0085c00f8ebd00000083c010", "pixel reader skips empty index and seeks16 bytes past frame offset"),
        (0x6FBA27, "8b40088945f4837df4007e68817df46df114007f5f", "positive compressed lengths up to1372525 use inflate branch"),
        (0x6FBA69, "e82270d7ff", "pixel reader invokes original decompression helper"),
        (0x4915E7, "0fbf0003c083c003c1e80203c003c0", "flag0 pixel rows use four-byte-aligned two-byte pixel storage"),
        (0x6E214F, "e818d50100", "human appearance refresh extracts packed costume value"),
        (0x6E2154, "0fb6d04a8b45fce804a5ffff", "costume key uses low byte of extracted word minus one before actor112 setter"),
        (0x6FF66C, "c1e810c3", "packed costume extractor returns high WORD"),
    ]
    evidence = []
    for address, expected, role in checks:
        if read_va(sample, address, len(bytes.fromhex(expected))).hex() != expected:
            raise ValueError(f"unexpected appearance frame instructions at {address:#x}")
        evidence.append({"va": hex(address), "hex": expected, "role": role})
    sources, files = {}, {}
    for filename, expected in EXPECTED_FILES.items():
        raw = (data_root / filename).read_bytes()
        if hashlib.sha256(raw).hexdigest() != expected:
            raise ValueError(f"requires documented resource {filename}")
        sources[filename] = {"sha256": expected, "bytes": len(raw)}
        files[filename] = raw
    libraries = {}
    for library in ["1", "300"]:
        index, images = files[library + ".MIX"], files[library + ".MIZ"]
        if index[:16] != b"\x0f(C) MIR3, MIR3." or index[:24] != images[:24]:
            raise ValueError("MIX/MIZ headers disagree")
        count = struct.unpack_from("<I", index, 16)[0]
        if len(index) != 24 + count * 4:
            raise ValueError("MIX offset table size mismatch")
        groups = files[library + ".dat"]
        group_count = struct.unpack_from("<H", groups)[0]
        if 4 + 8 * group_count > len(groups):
            raise ValueError("truncated group metadata")
        libraries[library] = {"image_count": count, "group_count": group_count,
                              "group_trailing_bytes": len(groups) - 4 - 8 * group_count}
    effects = []
    for row in aura["appearance_effect_config"]["rows"]:
        library, group_index = row["image_library"], row["group_index"]
        if group_index >= libraries[library]["group_count"]:
            raise ValueError("effect outside group metadata")
        first, count, padding, interval, directions, reserved = struct.unpack_from(
            "<HBBHBB", files[library + ".dat"], 4 + 8 * group_index)
        frames = [inspect_frame(files[library + ".MIX"], files[library + ".MIZ"], first + i)
                  for i in range(count)]
        effects.append({**row, "first_image": first, "visible_frames": count,
                        "direction_padding": padding, "interval": interval, "directions": directions,
                        "reserved": reserved, "frames": frames,
                        "present_frames": sum(frame["present"] for frame in frames)})
    tiers = []
    for tier in aura["extra_human_appearance"]["tiers"]:
        library = tier["library"]
        tiers.append({**tier, "frame": inspect_frame(files[library + ".MIX"], files[library + ".MIZ"], tier["first_image"])})
    return {"schema_version": 1, "sample_sha256": aura["sample_sha256"],
            "aura_state_instruction_checks": len(aura["instruction_checks"]),
            "instruction_checks": evidence, "sources": sources, "libraries": libraries,
            "original_costume_key": {"source_actor_offset": 128, "target_actor_offset": 112,
                                     "formula": "((packed_appearance >> 16) & 255) - 1",
                                     "matches": [{"actor112": 186, "packed_byte16_23": 187},
                                                 {"actor112": 216, "packed_byte16_23": 217}]},
            "costume_effects": effects, "extra_human_appearance": tiers,
            "limits": ["Current supplied resource hashes only; zero offset means no local frame record, not that every version lacks it.",
                       "Decoded byte layout and stride are verified; RGB channel conversion, blend mode and orientation are not reproduced here.",
                       "Original packed appearance and current item shapes are distinct inputs; no current equipment correspondence is established.",
                       "This is static resource evidence, not an original server or Godot rendering roundtrip."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--data-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample, args.registry, args.data_root)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"checks": len(result["instruction_checks"]),
                      "effects": [{"id": row["resource_id"], "present": row["present_frames"], "total": row["visible_frames"]}
                                  for row in result["costume_effects"]],
                      "tier_frames_present": sum(row["frame"]["present"] for row in result["extra_human_appearance"])}))


if __name__ == "__main__":
    main()
