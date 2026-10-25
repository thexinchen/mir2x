"""Run export_registry(output_path) inside IDA with the Mir3 unpacked IDB open.

Example through IDA py_eval:
    exec(open(SCRIPT_PATH, encoding="utf-8").read())
    export_registry(OUTPUT_PATH)
"""


def export_registry(output_path):
    import json
    from pathlib import Path
    import ida_funcs
    import ida_nalt
    import idautils
    import idc

    expected_hash = "eef5bc3ce72b8db3449389f21c367f9795dacbf919480c606717a49b052d7021"
    actual_hash = ida_nalt.retrieve_input_file_sha256().hex()
    if actual_hash != expected_hash:
        raise ValueError("This extractor is specific to the documented Mir3 unpacked sample")

    rows = []
    for call in idautils.CodeRefsTo(0x6CD104, False):
        message = mode = handler = None
        ea = call
        for _ in range(12):
            ea = idc.prev_head(ea)
            mnemonic = idc.print_insn_mnem(ea)
            register = idc.print_operand(ea, 0)
            if mnemonic == "mov" and idc.get_operand_type(ea, 1) == idc.o_imm:
                if register in ("dx", "edx") and message is None:
                    message = idc.get_operand_value(ea, 1)
                if register in ("cx", "ecx") and mode is None:
                    mode = idc.get_operand_value(ea, 1)
            if mnemonic == "push" and handler is None and idc.get_operand_type(ea, 0) == idc.o_imm:
                target = idc.get_operand_value(ea, 0)
                function = ida_funcs.get_func(target)
                if function and function.start_ea == target:
                    handler = target
            if message is not None and mode is not None and handler is not None:
                break
        owner = ida_funcs.get_func(call)
        rows.append({
            "call": hex(call),
            "register_function": hex(owner.start_ea) if owner else None,
            "message": message,
            "registration_ecx": mode,
            "handler": hex(handler) if handler else None,
        })

    rows.sort(key=lambda row: int(row["call"], 16))
    result = {"schema_version": 1, "sample_sha256": actual_hash,
              "registration_function": "0x6cd104", "records": rows}
    Path(output_path).write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return {"records": len(rows), "output": str(output_path)}
