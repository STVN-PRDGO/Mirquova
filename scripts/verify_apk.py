from pathlib import Path
import os,subprocess,zipfile
root=Path(__file__).resolve().parent.parent
sdk=Path(os.environ['ANDROID_HOME'])
apk=root/'apps/mirquova_flutter/build/app/outputs/flutter-apk/app-debug.apk'
with zipfile.ZipFile(apk) as archive:
    names=archive.namelist()
    required=['lib/arm64-v8a/libmirquova_core.so','lib/arm64-v8a/libflutter.so','AndroidManifest.xml','classes.dex']
    for name in required:
        if name not in names:raise SystemExit(f'Missing APK entry: {name}')
    abis=sorted({name.split('/')[1] for name in names if name.startswith('lib/') and name.endswith('.so')})
    if abis!=['arm64-v8a']:raise SystemExit(f'Unexpected ABI package set: {abis}')
print('PASS APK contains Flutter engine, Rust core, manifest and DEX; ARM64 only.')
for command in [[str(sdk/'build-tools/36.0.0/apksigner.bat'),'verify','--verbose',str(apk)],
                [str(sdk/'build-tools/36.0.0/zipalign.exe'),'-c','-P','16','4',str(apk)]]:
    result=subprocess.run(command,text=True,capture_output=True)
    if result.returncode:raise SystemExit(result.stdout+result.stderr)
    if 'apksigner' in command[0]:print(result.stdout)
    else:print('PASS APK ZIP alignment verification (16 KiB native pages).')