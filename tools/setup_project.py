#!/usr/bin/env python3
"""Creates the Flutter project (mirrornuke_app/) and applies pinned dependencies,
all MirrorNuke sources, unit tests, and Android patches.
Run from the MirrorNuke root folder:  python tools/setup_project.py [--org com.yourname]"""
import os, re, shutil, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, 'mirrornuke_app')
TEMPLATES = os.path.join(ROOT, 'tools', 'templates')
ORG = 'com.mirrornuke'
if '--org' in sys.argv:
    ORG = sys.argv[sys.argv.index('--org') + 1]
PKG = f'{ORG}.mirrornuke_app'
IS_WIN = os.name == 'nt'

def run(cmd, cwd=None):
    print('>', ' '.join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True, shell=IS_WIN)

def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write(text)

def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()

# 1. Create Flutter project once and apply pinned pubspec.yaml + analysis_options.yaml
if not os.path.isdir(APP):
    run([
        'flutter', 'create',
        '--platforms=android,windows',
        '--org', ORG,
        '--project-name', 'mirrornuke_app',
        'mirrornuke_app'
    ], cwd=ROOT)

shutil.copy(os.path.join(TEMPLATES, 'pubspec.yaml'), os.path.join(APP, 'pubspec.yaml'))
shutil.copy(os.path.join(TEMPLATES, 'analysis_options.yaml'), os.path.join(APP, 'analysis_options.yaml'))
run(['flutter', 'pub', 'get'], cwd=APP)

# 2. Copy Dart sources & unit tests
lib = os.path.join(APP, 'lib')
for f in os.listdir(os.path.join(ROOT, 'app', 'lib')):
    if f.endswith('.dart'):
        shutil.copy(os.path.join(ROOT, 'app', 'lib', f), os.path.join(lib, f))

test_dir = os.path.join(APP, 'test')
os.makedirs(test_dir, exist_ok=True)
stale_test = os.path.join(test_dir, 'widget_test.dart')
if os.path.exists(stale_test):
    os.remove(stale_test)
for f in ('security_test.dart', 'audio_test.dart'):
    shutil.copy(os.path.join(TEMPLATES, f), os.path.join(test_dir, f))

# 3. Copy Kotlin sources & XML resources
kt_dir = os.path.join(APP, 'android', 'app', 'src', 'main', 'kotlin', *PKG.split('.'))
os.makedirs(kt_dir, exist_ok=True)
for f in ('MainActivity.kt', 'RemoteControlService.kt', 'CaptureService.kt'):
    src = read(os.path.join(ROOT, 'android', f)).replace('package com.mirrornuke.mirrornuke_app', f'package {PKG}')
    write(os.path.join(kt_dir, f), src)

for dp, _, files_in_dir in os.walk(os.path.join(APP, 'android', 'app', 'src', 'main', 'kotlin')):
    if 'MainActivity.kt' in files_in_dir and os.path.abspath(dp) != os.path.abspath(kt_dir):
        os.remove(os.path.join(dp, 'MainActivity.kt'))

res = os.path.join(APP, 'android', 'app', 'src', 'main', 'res')
os.makedirs(os.path.join(res, 'xml'), exist_ok=True)
os.makedirs(os.path.join(res, 'values'), exist_ok=True)
shutil.copy(
    os.path.join(ROOT, 'android', 'accessibility_service_config.xml'),
    os.path.join(res, 'xml', 'accessibility_service_config.xml')
)
shutil.copy(
    os.path.join(ROOT, 'android', 'strings.xml'),
    os.path.join(res, 'values', 'strings.xml')
)

# 4. ProGuard keep rules for WebRTC
proguard_path = os.path.join(APP, 'android', 'app', 'proguard-rules.pro')
write(proguard_path, """-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }
-dontwarn org.webrtc.**
""")

# 5. Patch AndroidManifest.xml
mf = os.path.join(APP, 'android', 'app', 'src', 'main', 'AndroidManifest.xml')
s = read(mf)
if 'mirrornuke-patched' not in s:
    perms = """    <!-- mirrornuke-patched -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>
    <uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
    <uses-permission android:name="android.permission.RECORD_AUDIO"/>
    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PROJECTION"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-feature android:name="android.software.leanback" android:required="false"/>
    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>
"""
    s = s.replace('<application', perms + '    <application', 1)
    if 'usesCleartextTraffic' not in s:
        s = s.replace('<application', '<application\n        android:usesCleartextTraffic="true"', 1)
    s = re.sub(
        r'(<category android:name="android.intent.category.LAUNCHER"\s*/>)',
        r'\1\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
        s,
        count=1
    )
    services = """
        <service
            android:name=".CaptureService"
            android:exported="false"
            android:foregroundServiceType="mediaProjection"/>
        <service
            android:name=".RemoteControlService"
            android:exported="true"
            android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE">
            <intent-filter>
                <action android:name="android.accessibilityservice.AccessibilityService"/>
            </intent-filter>
            <meta-data
                android:name="android.accessibilityservice"
                android:resource="@xml/accessibility_service_config"/>
        </service>
"""
    s = s.replace('</application>', services + '    </application>', 1)
    write(mf, s)

# 6. Ensure minSdk 24 in app build.gradle(.kts)
for name in ('build.gradle.kts', 'build.gradle'):
    p = os.path.join(APP, 'android', 'app', name)
    if os.path.exists(p):
        g = read(p)
        g = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 24', g)
        g = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 24', g)
        write(p, g)


print('\nMirrorNuke project setup complete.')
print('Next steps:')
print('  cd mirrornuke_app')
print('  flutter analyze --no-fatal-infos')
print('  flutter test')
print('  flutter build windows --release')
print('  flutter build apk --release')
