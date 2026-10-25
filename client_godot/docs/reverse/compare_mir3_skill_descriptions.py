"""Compare local Mir3 descriptions with exported Godot metadata; never infer original IDs."""
import argparse
import ast
import base64
import csv
import hashlib
import json
from pathlib import Path
import re
import struct


def header(data, versions):
    magic, version, count = struct.unpack_from('<4sII', data)
    if magic != b'M2SP' or version not in versions:
        raise ValueError('unsupported metadata header')
    return version, count


def export(description_path, sprites, main_path, legacy_csv=None, identity_path=None):
    raw = description_path.read_bytes()
    text = base64.b64decode(b''.join(raw.split()), validate=True).decode('gbk')
    entries = {}
    for line_number, line in enumerate(text.splitlines(), 1):
        if not line.strip() or line.startswith(';'):
            continue
        name, separator, description = line.partition('=')
        if not separator:
            raise ValueError(f'unrecognized description line {line_number}')
        entries.setdefault(name, []).append({'line': line_number, 'text': description})

    names_raw = (sprites / 'magic_name.m2xmeta').read_bytes()
    _, count = header(names_raw, [1])
    names = {}
    offset = 12
    for _ in range(count):
        magic_id, length = struct.unpack_from('<IH', names_raw, offset)
        offset += 6
        names[magic_id] = names_raw[offset:offset + length].decode('utf-8')
        offset += length
    if offset != len(names_raw) or len(names) != count:
        raise ValueError('incomplete or duplicate magic name metadata')

    skills_raw = (sprites / 'skill.m2xmeta').read_bytes()
    version, count = header(skills_raw, [1, 2])
    skills = {}
    offset = 12
    for _ in range(count):
        fmt = '<IIIBBBB' if version == 2 else '<IIBBBB'
        row = struct.unpack_from(fmt, skills_raw, offset)
        offset += struct.calcsize(fmt)
        skills[row[0]] = {'flags': row[-1]}
    if offset != len(skills_raw) or len(skills) != count:
        raise ValueError('incomplete or duplicate skill metadata')

    identity_path = identity_path or Path(__file__).with_name('mir3-skill-identity.json')
    identities, identity_hash = {}, None
    if identity_path.exists():
        identity_raw = identity_path.read_bytes()
        identity = json.loads(identity_raw)
        if identity['source_sha256']['current_names'] != hashlib.sha256(names_raw).hexdigest() or identity['source_sha256']['current_skills'] != hashlib.sha256(skills_raw).hexdigest():
            raise ValueError('original identity evidence does not match current metadata')
        for row in identity['skills']:
            if names.get(row['current_id']) != row['current_name'] or row['current_id'] in identities:
                raise ValueError('invalid original identity correspondence')
            identities[row['current_id']] = row
        identity_hash = hashlib.sha256(identity_raw).hexdigest()

    legacy_by_name = {}
    legacy_hash = None
    if legacy_csv is not None:
        legacy_raw = legacy_csv.read_bytes()
        legacy_hash = hashlib.sha256(legacy_raw).hexdigest()
        legacy_ids = set()
        for row in csv.DictReader(legacy_raw.decode('utf-8-sig').splitlines()):
            legacy_id = int(row['MagID'])
            name = row['MagName']
            if legacy_id in legacy_ids:
                raise ValueError(f'duplicate legacy reference ID: {legacy_id}')
            legacy_ids.add(legacy_id)
            if name in legacy_by_name:
                raise ValueError(f'duplicate legacy reference name: {name}')
            legacy_by_name[name] = {
                'id': legacy_id,
                'provenance': 'repository King_Magic.csv; version match to analyzed binary unproven',
                'fields': row,
            }

    main = main_path.read_text(encoding='utf-8')
    policies = {}
    for policy in ['SWING', 'TARGET', 'GROUND', 'SELF']:
        match = re.search(r'const ' + policy + r'_MAGIC_NAMES := (\[.*?\])', main, re.S)
        for name in ast.literal_eval(match[1]):
            policies[name] = policy.lower()
    policies['空拳刀法'] = 'spinkick'
    rows = []
    for magic_id, skill in sorted(skills.items()):
        name = names[magic_id]
        identity = identities.get(magic_id, {})
        original_name = identity.get('original_resource_name') or name
        rows.append({'current_id': magic_id, 'name': name,
                     'current_policy': 'passive' if skill['flags'] & 1 else policies.get(name, 'unsupported'),
                     'original_id': identity.get('original_resource_id'),
                     'original_name': original_name if identity else None,
                     'identity_match': identity.get('match'),
                     'explicit_lock_allowed': identity.get('explicit_lock_allowed'),
                     'history_known_positive': identity.get('history_known_positive'),
                     'legacy_reference': legacy_by_name.get(name),
                     'original_descriptions': entries.get(original_name, [])})
    return {'schema_version': 3,
            'scope': 'Current IDs remain separate from original resource IDs. Original identity uses the source-checked resource join and one explicit spelling alias; server target-mode/delay values remain unproven.',
            'original_identity_sha256': identity_hash,
            'legacy_reference_sha256': legacy_hash,
            'source_sha256': hashlib.sha256(raw).hexdigest(),
            'name_metadata_sha256': hashlib.sha256(names_raw).hexdigest(),
            'skill_metadata_sha256': hashlib.sha256(skills_raw).hexdigest(),
            'main_sha256': hashlib.sha256(main_path.read_bytes()).hexdigest(),
            'description_key_count': len(entries),
            'description_entry_count': sum(map(len, entries.values())),
            'duplicate_keys': {name: [entry['line'] for entry in values] for name, values in entries.items() if len(values) > 1},
            'skills': rows}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--descriptions', required=True, type=Path)
    parser.add_argument('--sprites', required=True, type=Path)
    parser.add_argument('--main', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--legacy-csv', type=Path, help='Optional reference table, never proof of original binary IDs')
    parser.add_argument('--identity', type=Path, help='Source-checked original resource correspondence; defaults to sibling mir3-skill-identity.json when present')
    args = parser.parse_args()
    result = export(args.descriptions, args.sprites, args.main, args.legacy_csv, args.identity)
    args.output.write_bytes((json.dumps(result, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))
    rows = result['skills']
    print(json.dumps({'description_keys': result['description_key_count'], 'description_entries': result['description_entry_count'], 'verified_original_ids': sum(row['original_id'] is not None for row in rows),
                      'current_skills': len(rows), 'legacy_reference_matches': sum(row['legacy_reference'] is not None for row in rows), 'exact_matches': sum(bool(row['original_descriptions']) for row in rows),
                      'unsupported': [row['name'] for row in rows if row['current_policy'] == 'unsupported']}, ensure_ascii=True))
