"""Verify original aura state messages and the supplied ActorBuff appearance map."""
import argparse
import hashlib
import json
from pathlib import Path
import struct

from export_mir3_target_history import EXPECTED_SAMPLE, read_va

EXPECTED_ACTOR_BUFF = "19f12ea396eca7a0ecf9d6b9dff6237cc920c3002f32124fb8d2bc4d5111a3f2"
EXPECTED_EFFECTS_LIST = "9b4317ea9cf07d6953f431f9df51807ff09c6e4d24b2c86cbda9489c3424457e"
ORDINARY_ACTOR_MESSAGES = (10, 6, 37, 7, 11, 13, 1321, 35, 36, 1316, 56, 801, 807, 808, 9, 33, 27, 5440)


def extract(sample_path, registry_path, actor_buff_path, effects_list_path):
    sample = sample_path.read_bytes()
    if hashlib.sha256(sample).hexdigest() != EXPECTED_SAMPLE:
        raise ValueError("requires documented unpacked sample")
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    if registry["sample_sha256"] != EXPECTED_SAMPLE:
        raise ValueError("registry sample mismatch")
    registrations = []
    specs = [(657, 0x6876DC), (1500, 0x68281C), (41, 0x687460), (1502, 0x682BE0)]
    specs += [(message, 0x683874) for message in ORDINARY_ACTOR_MESSAGES]
    for message, handler in specs:
        rows = [row for row in registry["records"] if row["message"] == message]
        if len(rows) != 1 or rows[0]["handler"] != hex(handler):
            raise ValueError(f"unexpected registration for message{message}")
        call = int(rows[0]["call"], 16)
        context = read_va(sample, call - 24, 29)
        if (context[24] != 0xE8 or b"\x68" + struct.pack("<I", handler) not in context[:24]
                or b"\x66\xba" + struct.pack("<H", message) not in context[:24]
                or b"\x66\xb9\x06\x00" not in context[:24]):
            raise ValueError(f"registration bytes do not support message{message}")
        registrations.append({**rows[0], "context_va": hex(call - 24), "context_hex": context.hex()})
    checks = [
        (0x6876E4, "0fb75a060fb74a080fb7db0fb7c9c1e1100bd98bcb", "combine header words6/8 into actor148 value"),
        (0x6876FB, "8b5d0885db790383c303c1fb0253", "payload byte count divided by4, truncated toward zero"),
        (0x687709, "8b5dfc53510fb74a0a516a006a006a000fb74a048b1287cae8be19ffff", "forward payload, header fields and actor UID to shared dispatch"),
        (0x679219, "8bc383e82974092d680200007417", "dispatch branch41+616 equals message657"),
        (0x679248, "8b45188986940000008b451c8b00898684000000", "actor148 from header value; actor132 from first payload dword"),
        (0x67925C, "8b4d1c8b55208bc6e8c7330600", "copy payload state-vector words to actor"),
        (0x679269, "0fb645148886c6010000", "header word10 low byte becomes actor454; semantics unproven"),
        (0x67928A, "8bc68b10ff5248", "message657 invokes actor VMT+72 reconciliation"),
        (0x6DC63C, "8d433c33c9ba2c000000e88173d2ff", "state vector clears44 bytes at actor60"),
        (0x6DC64F, "8bce03c903c98d533c8bc7e8756dd2ff", "copy4 times supplied word count to actor60"),
        (0x682863, "0fb74606508d5590b9580000008d45f0e820cae0ff", "message1500 reads up to88-byte snapshot using header length"),
        (0x682893, "8b45948983940000008b4598898384000000", "snapshot dwords4/8 become actor148/132"),
        (0x6828AF, "8bc38b10ff5248", "message1500 invokes same reconciliation"),
        (0x48F2B9, "8b7df83bdf7d028bfb", "stream helper chooses minimum of record and field lengths"),
        (0x48F2D3, "8b45fc03c78b55f82bd733c9e8e846f7ff", "short snapshot field is padded with zero"),
        (0x4F70AD, "6880724f006894724f00", "appearance map filename uses ActorBuff plus.dat literals"),
        (0x4F7280, "4163746f724275666600", "ActorBuff filename literal"),
        (0x4F7294, "2e64617400", "dat suffix literal"),
        (0x4F7209, "8943048b45f48b40608bd3e87773f2ff", "store mapping value and append pair to manager96 list"),
        (0x4F6BF9, "8b003b45fc7518", "lookup compares pair key"),
        (0x4F6C0A, "8b40048b55f88902", "lookup returns matched pair value"),
        (0x6E27E9, "8b5770e8db43e1ff", "reconciliation uses actor112 as appearance mapping key"),
        (0x6DC66F, "8b7b70897370", "appearance setter replaces actor112 key"),
        (0x6E27F5, "0fb645e43c2f770783e07f0fab45fa", "mapped byte requests effect index no greater than47"),
        (0x6838CC, "8b450883e80c83f8407c1f", "ordinary actor handler requires payload76 for optional64-byte description"),
        (0x6838E7, "8d430cb940000000e8e0fad7ff", "description copies64 bytes from payload12"),
        (0x68399F, "8b07508b4704508b45fc506a008b470850", "forward shape, state148, description and state132 to shared dispatch"),
        (0x6839B0, "8b0e0fb756048b45f8e82657ffff", "ordinary actor header supplies UID and message to shared dispatch"),
        (0x679131, "8b4518508b4514508b4508500fb74d248b55fc8bc7e88df7ffff", "unknown actor path forwards shape/state fields to creator"),
        (0x67892C, "8bc683e802720f", "shape low byte0/1 selects human branch"),
        (0x678942, "b201a1e0a66d00e85a5c0600", "human actor construction branch"),
        (0x678E37, "8b450c8983940000008b4508898384000000", "creator writes both aura state fields"),
        (0x678E49, "8b45fc8b80f40000008bd3e86317e0ff", "actor insertion occurs after state writes"),
        (0x494E60, "48a84700", "actor-list notification VMT entry"),
        (0x47A848, "c3", "list notification is empty; insertion alone does not prove reconciliation"),
        (0x687467, "837d084c7c2f", "message41 rejects payload shorter than76"),
        (0x687476, "85db7422", "message41 ignores unknown actor UID"),
        (0x68747A, "8bc68b108993800000008d500c8bc3e8ce4f0500", "message41 updates shape and64-byte description"),
        (0x68748E, "8bc38b10ff52448bc38b10ff5248", "message41 refreshes appearance then reconciles auras"),
        (0x682BF7, "85db7459", "message1502 ignores unknown actor UID"),
        (0x682BFB, "0fb7460a89834c0100000fb756068bc3e8c0980500", "message1502 stores actor332 and resizes integer list"),
        (0x682C25, "8b45fc03c78d55f4b904000000e89d07d8ff83c704", "message1502 consumes4-byte list elements"),
        (0x682C3A, "8b4df48b55f88bc3e84d980500", "message1502 writes list element through setter"),
        (0x682C4D, "8bc38b10ff5248", "message1502 reconciles even after an empty list"),
        (0x6DA774, "e0026e00", "human actor VMT+72 override"),
        (0x6E02EB, "e870220000", "human override first calls base aura reconciliation"),
        (0x6DB33F, "8b45d883f81b740e3d2405000074073d290500007512c6437c00c6839c000000008bc38b10ff5248", "actions27/1316/1321 clear death flags and explicitly reconcile before subsequent action fields"),
        (0x6DF803, "bef6ffffff8b83b0000000e89171d2ff85c07e088b83b00000008b30", "extra appearance selector reads first actor176 integer or returns minus10 for empty list"),
        (0x6E03A9, "8b864c01000083c0fe83e8020f83d3000000", "extra appearance branch is restricted to actor332 values2/3"),
        (0x6E03BB, "8bc6e83af4ffff8bd83b9e5c0300000f84be000000899e5c030000", "cache first integer; unchanged value skips rebuilding extra appearance"),
        (0x6E03D6, "83be6003000000740b8d8660030000e80636d3ff", "changed value disposes previous extra appearance before selecting replacement"),
        (0x6E03EA, "bffeffffff83fb0a7c07bf02000000eb1383fb057c07bf01000000eb0783fb037c0233ff85ff7c7c", "signed first integer selects tiers3..4,5..9,10+; lower values create no replacement"),
        (0x6E0419, "8d1c7f8b14dd68847200a1c49d72008b00e8a574fcff", "tier selects six-dword row and resolves its image-library string"),
        (0x6E0438, "8b04dd6c847200508b04dd70847200508b04dd74847200508b4dfcb201a1d4446e00e8e1670000", "extra appearance row supplies start image, frame count and interval to TImagesEffect constructor"),
        (0x6E045F, "8986600300008b8660030000897824", "extra appearance is stored separately at actor864; tier stored at effect36"),
        (0x6E046E, "8b04dd788472008b966003000089421c8b04dd7c8472008b9660030000894220", "row offsets copied to extra image effect28/32"),
        (0x6E6C53, "8948048958088b4d0c03cb4989480c8b4d08894814895810", "TImagesEffect stores image library, first/last frame, interval and current frame"),
        (0x6DA9B6, "84ad6d00", "factory switch effect40 selects714 constructor branch"),
        (0x6DA9D2, "9fad6d00", "factory switch effect47 selects785 constructor branch"),
        (0x6DAD84, "68ca0200006a006a006a008bc8b201a1e02b6e00e8cf980000", "effect40 uses generic constructor6E466C with resource714 and three zero stack arguments"),
        (0x6DAD9F, "68110300006a006a006a008bc8b201a1e02b6e00e8b4980000", "effect47 uses same generic constructor with resource785"),
        (0x6E02C8, "ffffffff010000003100", "extra appearance image library is Delphi string1"),
        (0x728468, "d0026e002e09000001000000e80300000d000000a6ffffffd0026e002f09000001000000e80300000d000000a6ffffffd0026e003009000001000000e80300000d000000a6ffffff", "three extra appearance rows: library1, frames2350/2351/2352, count1, interval1000, offsets13/-90"),
        (0x6E4684, "0fb64510508b450c508b4d1433d28bc7e857030000", "generic effect constructor delegates to6E49F0, distinct from shield constructor6E4964"),
        (0x6E4A11, "897724c64748018b45088947188bc78b10ff5208", "generic parent sets resource36 and direct-effect flag72 before virtual resource initialization"),
        (0x6E4AB4, "807b4800741b", "direct-effect flag selects effects lookup rather than magic indirection"),
        (0x6E4ABD, "a1c49d72008b008b80f40100000fb75324e8b9570100", "direct lookup6FA28C receives manager500 and resource36"),
        (0x6FA949, "b9d4aa6f00e821acd0ff", "resource loader constructs effects.lst path"),
        (0x6FAAD4, "656666656374732e6c737400", "effects.lst filename literal"),
        (0x6FAA20, "baf4aa6f00e85aacd0ff", "loader compares EFFECTS section marker"),
        (0x6FAAF4, "234546464543545300", "EFFECTS section literal"),
    ]
    evidence = []
    for address, expected, role in checks:
        if read_va(sample, address, len(bytes.fromhex(expected))).hex() != expected:
            raise ValueError(f"unexpected aura state instructions at {address:#x}")
        evidence.append({"va": hex(address), "hex": expected, "role": role})
    raw = actor_buff_path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != EXPECTED_ACTOR_BUFF:
        raise ValueError("requires documented ActorBuff.dat configuration")
    mappings = []
    for line in raw.decode("gb18030").splitlines():
        fields = line.split(";", 1)[0].split()
        if not fields:
            continue
        if len(fields) != 2:
            raise ValueError("unexpected ActorBuff row")
        mappings.append({"appr": int(fields[0]), "effect": int(fields[1])})
    if mappings != [{"appr": 186, "effect": 40}, {"appr": 216, "effect": 47}]:
        raise ValueError("unexpected ActorBuff mappings")
    effects_raw = effects_list_path.read_bytes()
    if hashlib.sha256(effects_raw).hexdigest() != EXPECTED_EFFECTS_LIST:
        raise ValueError("requires documented effects.lst configuration")
    effect_rows = []
    section = ""
    for line_number, line in enumerate(effects_raw.decode("gb18030").splitlines(), 1):
        body, _, comment = line.partition("//")
        body = body.split(";", 1)[0].strip()
        if body.startswith("#"):
            section = body
        elif section == "#EFFECTS" and body:
            fields = body.split()
            if fields[0] in ["714", "785"]:
                values = list(map(int, fields))
                if values not in [[714, 300, 19, 0, 0], [785, 300, 25, 0, 0]]:
                    raise ValueError("unexpected appearance effect row")
                effect_rows.append(dict(resource_id=values[0], image_library=str(values[1]),
                                        group_index=values[2], color=values[3], light=values[4],
                                        comment=comment.strip(), line=line_number))
    if [row["resource_id"] for row in effect_rows] != [714, 785]:
        raise ValueError("missing or duplicate appearance effect rows")
    return {
        "schema_version": 1, "sample_sha256": EXPECTED_SAMPLE,
        "registrations": registrations, "instruction_checks": evidence,
        "message657": {"handler": "0x6876dc", "shared_dispatch": "0x6790e4",
                       "actor_uid": "header dword0", "actor148": "header dword6",
                       "actor132": "first payload dword", "state_vector_actor_offset": 60,
                       "actor454": "header word10 low byte; semantics unproven",
                       "state_vector_clear_bytes": 44, "copied_words": "payload byte length divided by4",
                       "reconcile": "actor VMT+72"},
        "message1500": {"handler": "0x68281c", "snapshot_bytes": 88,
                        "actor148_field_offset": 4, "actor132_field_offset": 8,
                        "short_fields": "zero padded when stream has the declared field length",
                        "reconcile": "actor VMT+72"},
        "ordinary_actor_creation": {"handler": "0x683874", "messages": list(ORDINARY_ACTOR_MESSAGES),
                                    "shared_dispatch": "0x6790e4", "creator": "0x6788d8",
                                    "shape_field_offset": 0, "actor148_field_offset": 4, "actor132_field_offset": 8,
                                    "optional_description": {"offset": 12, "bytes": 64, "requires_payload_bytes": 76},
                                    "ordering": "creator writes148/132 before actor-list insertion",
                                    "limit": "list insertion notification is empty; first reconciled frame is not proven here"},
        "message41": {"handler": "0x687460", "requires_known_actor": True, "minimum_payload_bytes": 76,
                      "shape_field_offset": 0, "description_offset": 12, "description_bytes": 64,
                      "order": ["shape", "description", "VMT+68 appearance", "VMT+72 aura reconciliation"]},
        "message1502": {"handler": "0x682be0", "requires_known_actor": True,
                        "actor332": "header word10; semantics unproven", "list_count": "header word6",
                        "element_bytes": 4, "actor_list_offset": 176,
                        "list_semantics": "first integer feeds a separate tiered human appearance selector; business meaning remains unclassified",
                        "then": "VMT+72 aura reconciliation"},
        "extra_human_appearance": {
            "selector": "0x6df7fc", "reconcile": "0x6e02e0", "actor332_values": [2, 3],
            "input": "first actor176 integer, or minus10 when empty", "cached_value_actor_offset": 860,
            "effect_actor_offset": 864, "unchanged_input": "retain existing extra effect",
            "changed_input": "dispose old effect, then resolve selected tier if any",
            "tiers": [dict(tier=i, minimum=minimum, maximum=maximum,
                           library=read_va(sample, library, 1).decode("ascii"), first_image=first,
                           frame_count=count, interval=interval, x_offset=x, y_offset=y)
                      for i, (minimum, maximum) in enumerate([(3, 4), (5, 9), (10, None)])
                      for library, first, count, interval, x, y in
                      [struct.unpack("<IIIIii", read_va(sample, 0x728468 + 24 * i, 24))]],
            "limit": "gate values outside2/3 bypass this branch; do not infer clearing or server gameplay meaning",
        },
        "aura_bits": {"shield": {"actor_offset": 148, "mask": "0x100000", "effect": 1},
                      "ring": {"actor_offset": 132, "mask": "0x80000000", "effect": 2}},
        "appearance_mapping": {"loader": "0x4f7084", "lookup": "0x4f6bcc", "actor_key_setter": "0x6dc664", "actor_key_offset": 112,
                               "filename": "ActorBuff.dat", "sha256": EXPECTED_ACTOR_BUFF, "mappings": mappings,
                               "selects_shield_or_ring": any(row["effect"] in [1, 2] for row in mappings)},
        "appearance_effect_constructors": [
            {"effect": 40, "resource_id": 714, "branch": "0x6dad84", "constructor": "0x6e466c"},
            {"effect": 47, "resource_id": 785, "branch": "0x6dad9f", "constructor": "0x6e466c"},
        ],
        "appearance_effect_config": {"filename": "effects.lst", "sha256": EXPECTED_EFFECTS_LIST,
                                     "section": "#EFFECTS", "loader": "0x6fa91c", "lookup": "0x6fa28c",
                                     "rows": effect_rows,
                                     "limit": "group index is not a first-frame number; MIX/MIZ frame metadata and current asset correspondence remain unverified"},
        "limits": [
            "Static sample and current local configuration evidence; no original server roundtrip was captured.",
            "Message657 vector copies and message1500 snapshots are different original representations, not current mir2x wire structs.",
            "State-driven creation/removal is proven; original server duration and damage absorption remain unknown.",
            "Current ActorBuff mappings do not select1/2; other configurations may map different effects.",
            "Do not infer a fixed44-byte payload limit from a helper which clears44 bytes then copies the supplied word count.",
            "The creator stores flags before insertion, but the list notification is empty; initial reconciled-frame timing is not proven here.",
            "Message1502's first integer selects a separate human appearance tier; its business meaning and actor332 meaning are not identified as current buff IDs.",
            "Original constructor resource714/785 and library1 image2350..2352 are not current mir2x magic IDs or proven matching assets.",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sample", required=True, type=Path)
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--actor-buff", required=True, type=Path)
    parser.add_argument("--effects-list", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    result = extract(args.sample, args.registry, args.actor_buff, args.effects_list)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"checks": len(result["instruction_checks"]), "registrations": len(result["registrations"]),
                      "appearance_mappings": len(result["appearance_mapping"]["mappings"])}))


if __name__ == "__main__":
    main()
