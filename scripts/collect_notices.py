# Collect original notices from resolved local packages, including dev dependencies.
import json
import os
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urlparse, unquote
from urllib.request import url2pathname

ROOT = Path(__file__).resolve().parent.parent
metadata = json.loads(subprocess.check_output(['cargo', 'metadata', '--format-version', '1', '--locked'], cwd=ROOT, text=True, encoding='utf-8'))
rows, missing = [], []
flutter_root = Path(os.environ['FLUTTER_ROOT'])

def collect(ecosystem, name, version, directory, license_id):
    directory = Path(directory)
    originals = sorted(p for p in directory.iterdir() if p.is_file() and p.name.lower().startswith(('license', 'licence', 'copying', 'notice')))
    if not originals and (directory / 'AUTHORS').is_file() and 'LICENSE:' in (directory / 'AUTHORS').read_text(encoding='utf-8'):
        originals = [directory / 'AUTHORS']
    if not originals and directory.is_relative_to(flutter_root):
        originals = [flutter_root / 'LICENSE']
    destination = ROOT / 'third_party' / 'licenses' / ecosystem / f'{name}-{version}'
    destination.mkdir(parents=True, exist_ok=True)
    for original in originals:
        shutil.copyfile(original, destination / original.name)
    if not originals:
        missing.append(f'{ecosystem}:{name}@{version}')
    relative = destination.relative_to(ROOT).as_posix()
    rows.append((ecosystem, name, version, license_id or 'See original license', relative, bool(originals)))

for package in metadata['packages']:
    if package['source'] is not None:
        collect('rust', package['name'], package['version'], Path(package['manifest_path']).parent, package.get('license'))

config_file = ROOT / 'apps/mirquova_flutter/.dart_tool/package_config.json'
config = json.loads(config_file.read_text(encoding='utf-8'))
for package in config['packages']:
    if package['name'] == 'mirquova':
        continue
    uri = package['rootUri']
    parsed = urlparse(uri)
    directory = Path(url2pathname(unquote(parsed.path))) if parsed.scheme == 'file' else (config_file.parent / uri).resolve()
    version = 'sdk'
    for line in (directory / 'pubspec.yaml').read_text(encoding='utf-8').splitlines():
        if line.startswith('version:'):
            version = line.split(':', 1)[1].strip().strip("'\"")
            break
    collect('dart', package['name'], version, directory, None)

flutter_root = Path(os.environ['FLUTTER_ROOT'])
collect('sdk', 'flutter', '3.47.8', flutter_root, 'BSD-3-Clause')
font_source = flutter_root / 'bin/cache/artifacts/material_fonts'
font_destination = ROOT / 'third_party/licenses/fonts'
font_destination.mkdir(parents=True, exist_ok=True)
for filename in ['roboto_license.txt', 'materialicons_license.txt']:
    shutil.copyfile(font_source / filename, font_destination / filename)

# Preserve native Flutter engine and client-wrapper notices with binaries.
engine = flutter_root / 'bin/cache/artifacts/engine'
for platform in ['windows-x64-release', 'windows-x64', 'common']:
    directory = engine / platform
    for original in directory.glob('license*.md'):
        destination = ROOT / 'third_party/licenses/native' / platform
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original, destination / original.name)

header = '''# Third-party notices

Generated from resolved Cargo metadata and Flutter package configuration. Includes development dependencies; this inventory is not a legal clearance or final native-runtime redistribution review. Cargo.lock and pubspec.lock record exact resolutions. Original notices are preserved under third_party/licenses.

Flutter-generated platform templates originate from the Flutter SDK (BSD-3-Clause). Material icons and Roboto used by Flutter and visual tests come from Flutter SDK artifacts; original font notices are in third_party/licenses/fonts. No third-party app designs, media, seals, or brand graphics were copied.

Project code licensing and release identifiers remain undecided. Project-local toolchains are excluded from distribution; their original notices remain in .toolchains. Native Flutter engine/client-wrapper notices are also preserved under third_party/licenses/native. Compiler/runtime and complete Android engine redistribution review remains required before a public release.

| Ecosystem | Package | Version | Declared license | Original notices |
| --- | --- | --- | --- | --- |
'''
lines = [f'| {eco} | {name} | {version} | {license_id} | [{"Present" if found else "MISSING"}]({relative}/) |' for eco, name, version, license_id, relative, found in sorted(rows)]
(ROOT / 'THIRD_PARTY_NOTICES.md').write_text(header + '\n'.join(lines) + '\n', encoding='utf-8')
print(f'Collected notice directories for {len(rows)} packages/SDKs.')
if missing:
    raise SystemExit('Missing original notices: ' + ', '.join(missing))