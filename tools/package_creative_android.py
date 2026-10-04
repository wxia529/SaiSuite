"""Collect development APKs separately and verify preserved version/signature."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile
import release

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist/development/creative-tools/android'


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--universal',action='store_true')
    parser.add_argument('--split',action='store_true')
    parser.add_argument('--output', type=Path, default=OUT)
    args=parser.parse_args()
    output=args.output.resolve()
    if not output.is_relative_to(ROOT):
        raise ValueError('Distribution must stay inside the project workspace')
    output.mkdir(parents=True,exist_ok=True)
    name,build=release.version()
    for abi in release.VARIANTS:
        if abi == 'universal' and args.universal or abi != 'universal' and args.split:
            source='app-release.apk' if abi == 'universal' else f'app-{abi}-release.apk'
            shutil.copy2(ROOT/'build/app/outputs/flutter-apk'/source,output/f'SaiSuite-{name}-{abi}.apk')
    if not all((output/f'SaiSuite-{name}-{abi}.apk').exists() for abi in release.VARIANTS):
        return
    os.environ.setdefault('ANDROID_HOME','E:/Android/Sdk')
    report=[]
    for abi,offset in release.VARIANTS.items():
        apk=output/f'SaiSuite-{name}-{abi}.apk'
        badging=subprocess.check_output([release.sdk_tool('aapt'),'dump','badging',str(apk)],text=True,encoding='utf-8')
        assert "name='io.github.wxia529.saisuite'" in badging and f"versionCode='{build+offset}'" in badging
        assert f"versionName='{name}'" in badging and "sdkVersion:'24'" in badging and "targetSdkVersion:'36'" in badging
        certs=subprocess.check_output([release.sdk_tool('apksigner'),'verify','--print-certs',str(apk)],text=True,encoding='utf-8')
        assert re.findall(r'certificate SHA-256 digest: ([0-9a-f]+)',certs)==[release.EXPECTED_CERT]
        with zipfile.ZipFile(apk) as z:
            entries=set(z.namelist())
            architectures={p.split('/')[1] for p in entries if p.startswith('lib/') and p.endswith('.so')}
            assert any(p.startswith('assets/mlkit-google-ocr-models/') and '/Hani_ctc/' in p for p in entries), 'Chinese OCR model missing'
            for architecture in architectures:
                assert f'lib/{architecture}/libmlkit_google_ocr_pipeline.so' in entries, 'OCR native library missing'
        assert architectures == (set(release.VARIANTS)-{'universal'} if abi=='universal' else {abi})
        checksum=hashlib.sha256(apk.read_bytes()).hexdigest()
        apk.with_suffix('.apk.sha256').write_text(f'{checksum}  {apk.name}\n',encoding='ascii')
        report.append({'name':apk.name,'bytes':apk.stat().st_size,'sha256':checksum,'version':f'{name}+{build}',
                       'variant':abi,'minSdk':24,'targetSdk':36,'certificate':release.EXPECTED_CERT})
    (output/'inspection.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
    (output/'SHA256SUMS.txt').write_text(''.join(f"{item['sha256']}  {item['name']}\n" for item in report),encoding='ascii')
    print(json.dumps(report,indent=2,ensure_ascii=False))


if __name__=='__main__':
    main()
