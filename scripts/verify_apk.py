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
build_tools=sdk/'build-tools'/os.environ.get('MIRQUOVA_ANDROID_BUILD_TOOLS', '36.0.0')
windows=os.name=='nt'
for command in [[str(build_tools/('apksigner.bat' if windows else 'apksigner')),'verify','--verbose',str(apk)],
                [str(build_tools/('zipalign.exe' if windows else 'zipalign')),'-c','-P','16','4',str(apk)]]:
    result=subprocess.run(command,text=True,capture_output=True)
    if result.returncode:raise SystemExit(result.stdout+result.stderr)
    if 'apksigner' in command[0]:print(result.stdout)
    else:print('PASS APK ZIP alignment verification (16 KiB native pages).')
