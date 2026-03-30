import json
import sys

def get_metrics(filename, label):
    try:
        with open(filename, 'r') as f:
            data = json.load(f)
        stats = data['stages']['basic_stats']
        dup = data['stages']['duplication']
        return {
            'label': label,
            'reads': stats['total_reads'],
            'bases': stats['total_bases'],
            'dup': dup['duplication_ratio']
        }
    except Exception as e:
        return {'label': label, 'reads': f"ERR: {e}", 'bases': 0, 'dup': 0}

files = [
    ('res_plain_exact.json', 'Plain (Exact)'),
    ('res_libdeflate.json', 'GZ (LibDeflate)'),
    ('res_qwd_native.json', 'GZ (NativeQwD)')
]

print(f"{'Format/Mode':<16} | {'Total Reads':>11} | {'Total Bases':>11} | {'Dup Ratio'}")
print("-" * 60)
for f, l in files:
    m = get_metrics(f, l)
    print(f"{m['label']:<16} | {m['reads']:>11} | {m['bases']:>11} | {m['dup']}")
