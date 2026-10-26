# Package only locally verified preview build outputs. Does not publish anything.
from pathlib import Path
import argparse,ctypes,hashlib,json,os,re,shutil,subprocess,zipfile
ROOT=Path(__file__).resolve().parent.parent
windows=ROOT/'apps/mirquova_flutter/build/windows/x64/runner/Release'
apk=ROOT/'apps/mirquova_flutter/build/app/outputs/flutter-apk/app-debug.apk'
required=[windows/'mirquova.exe',windows/'mirquova_core.dll',windows/'flutter_windows.dll',apk]
for path in required:
    if not path.is_file():raise SystemExit(f'Missing build output: {path}')
core=ctypes.CDLL(str(windows/'mirquova_core.dll'))
core.mq_abi_version.restype=ctypes.c_uint32
if core.mq_abi_version()!=2:raise SystemExit('Windows core ABI does not match this preview')
with zipfile.ZipFile(apk) as archive:
    if 'lib/arm64-v8a/libmirquova_core.so' not in archive.namelist():raise SystemExit('APK is missing the native ARM64 core')
    packaged_core=hashlib.sha256(archive.read('lib/arm64-v8a/libmirquova_core.so')).hexdigest()
    native_core=ROOT/'apps/mirquova_flutter/android/app/src/main/jniLibs/arm64-v8a/libmirquova_core.so'
    # AGP removes symbols from JNI libraries before packaging. Compare the same
    # standard stripped form, preserving the original build output.
    ndk=Path(os.environ.get('ANDROID_NDK_HOME',str(ROOT/'.toolchains/android-sdk/ndk/28.2.13676358')))
    strip_tool=ndk/'toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe'
    check_dir=ROOT/'.toolchains/package-check'
    check_dir.mkdir(parents=True,exist_ok=True)
    stripped=check_dir/'libmirquova_core.so'
    subprocess.run([str(strip_tool),'--strip-unneeded','-o',str(stripped),str(native_core)],check=True)
    with stripped.open('rb') as source:built_core=hashlib.file_digest(source,'sha256').hexdigest()
    if packaged_core!=built_core:raise SystemExit('APK contains a stale native core')
parser=argparse.ArgumentParser()
parser.add_argument('--iteration', default='iteration-03')
args=parser.parse_args()
if not re.fullmatch(r'iteration-[0-9]{2}',args.iteration):raise SystemExit('Invalid iteration folder')
destination=ROOT/'artifacts'/args.iteration
if destination.exists():raise SystemExit('Refusing to overwrite existing preview artifacts')
destination.mkdir(parents=True)
readme='''Mirquova preview 0.2.0 - foundation and discovery only.

Windows: extract the complete Windows ZIP into one folder, then run mirquova.exe.
Keep data and both DLLs beside the executable. This is an unsigned development preview.
Android: ARM64 debug-signed phone APK, Android 7/API 24 or later. No TV validation.

Pairing, transfers, casting, playback and online subtitles are not implemented.
Scan nearby browses for six seconds. Make discoverable shares a chosen name for up to two minutes.
Hide now or hiding/closing the app stops visibility. No transport endpoint is offered.
Use this updated preview on both devices; the earlier discovery contract is incompatible.
Manual addresses are session-only candidates and are not contacted or trusted.

Source and repeatable build/test instructions are in D:/Mirquova.
Original dependency/native engine notices accompany these previews.
No institutional affiliation, code licensing choice or store release is implied.
'''
archive_path=destination/'Mirquova-preview-windows-x64.zip'
with zipfile.ZipFile(archive_path,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as archive:
    for path in sorted(windows.rglob('*')):
        if path.is_file():archive.write(path,path.relative_to(windows).as_posix())
    archive.write(ROOT/'THIRD_PARTY_NOTICES.md','THIRD_PARTY_NOTICES.md')
    for path in sorted((ROOT/'third_party').rglob('*')):
        if path.is_file():archive.write(path,path.relative_to(ROOT).as_posix())
    archive.writestr('PREVIEW_README.txt',readme)
shutil.copyfile(apk,destination/'Mirquova-preview-android-arm64-debug.apk')
shutil.copyfile(ROOT/'THIRD_PARTY_NOTICES.md',destination/'THIRD_PARTY_NOTICES.md')
shutil.copytree(ROOT/'third_party',destination/'third_party')
(destination/'README.txt').write_text(readme,encoding='utf-8')
manifest=[]
for path in [archive_path,destination/'Mirquova-preview-android-arm64-debug.apk']:
    with path.open('rb') as source:digest=hashlib.file_digest(source,'sha256').hexdigest()
    manifest.append({'file':path.name,'bytes':path.stat().st_size,'sha256':digest})
(destination/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
print(json.dumps(manifest,indent=2))