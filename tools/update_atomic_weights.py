"""Generate the offline table from primary scientific sources (Python stdlib)."""
import html
import json
import re
from pathlib import Path
from urllib.request import urlopen

PUBCHEM = 'https://pubchem.ncbi.nlm.nih.gov/rest/pug/periodictable/JSON'
CIAAW = 'https://ciaaw.org/abridged-atomic-weights.htm'
with urlopen(PUBCHEM, timeout=60) as response:
    rows = json.load(response)['Table']['Row']
weights = {row['Cell'][1]: float(row['Cell'][3]) for row in rows}
with urlopen(CIAAW, timeout=60) as response:
    page = response.read().decode('utf-8')
uncertainties = {}
for row in re.findall(r'<tr[^>]*>(.*?)</tr>', page, re.S):
    cells = [html.unescape(re.sub(r'<[^>]+>', '', c)).strip()
             for c in re.findall(r'<td[^>]*>(.*?)</td>', row, re.S)]
    if len(cells) < 4 or not cells[0].isdigit():
        continue
    match = re.fullmatch(r'([\d.]+)\s*±\s*([\d.]+)', cells[3])
    if match:
        weights[cells[1]] = float(match[1])
        uncertainties[cells[1]] = float(match[2])
assert len(weights) == 118 and len(uncertainties) == 84
assert weights['Li'] == 6.94 and weights['Fe'] == 55.845
result = ('// CIAAW Abridged Standard Atomic Weights 2024; retrieved 2026-10-04.\n'
          f'// {CIAAW}\n// PubChem reference isotope mass numbers for other elements:\n'
          f'// {PUBCHEM}\nconst atomicWeights = <String, double>{{\n')
result += ''.join(f"  '{symbol}': {value},\n" for symbol, value in weights.items()) + '};\n'
result += 'const atomicWeightUncertainties = <String, double>{\n'
result += ''.join(f"  '{symbol}': {value},\n" for symbol, value in uncertainties.items()) + '};\n'
result += 'const referenceMassSymbols = <String>{\n'
result += ''.join(f"  '{symbol}',\n" for symbol in weights if symbol not in uncertainties) + '};\n'
Path(__file__).resolve().parents[1].joinpath('lib/core/atomic_weights.dart').write_text(result, encoding='utf-8')
print('Generated 118 elements: 84 standard atomic weights and 34 reference mass numbers.')
