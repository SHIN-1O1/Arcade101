#!/usr/bin/env python3
"""Pre-launch checker: python tools/check_release.py  (exit 1 while blockers remain).
Looks only at files in the repo, so it cannot see your keystore, Play Console or AdMob state."""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
problems, notes = [], []


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def check(ok, blocker, msg):
    if not ok:
        (problems if blocker else notes).append(msg)


policy = read("docs/PRIVACY_POLICY.md")
left = sorted(set(re.findall(r"\[\[[^\]]+\]\]", policy)))
check(not left, True, "docs/PRIVACY_POLICY.md still has placeholders: " + ", ".join(left))

ads = read("core/monetization/ad_config.gd")
check("const USE_TEST_ADS := false" in ads, True, "ad_config.gd: USE_TEST_ADS is still true (set false only for the release build)")
for name in ("REAL_INTERSTITIAL", "REAL_REWARDED", "REAL_BANNER"):
    m = re.search(r"const %s := \"([^\"]*)\"" % name, ads)
    check(bool(m and m.group(1)), name != "REAL_BANNER", "ad_config.gd: %s is empty" % name)
check("const CHILD_DIRECTED := false" in ads, True, "ad_config.gd: CHILD_DIRECTED must stay false (target audience is 13+)")
check("const DEBUG_FORCE_EEA := false" in ads, True, "ad_config.gd: DEBUG_FORCE_EEA must be false in a release")

presets = read("export_presets.cfg")
check(bool(re.search(r'package/unique_name="com\.shin1o1\.arcade101"', presets)), True, "export_presets.cfg: wrong package id")
check(len(re.findall(r"architectures/arm64-v8a=true", presets)) == len(re.findall(r"^platform=", presets, re.M)), True, "export_presets.cfg: arm64-v8a must be on in every preset")
for key in ("keystore/release", "keystore/release_user", "keystore/release_password", "keystore/debug", "keystore/debug_password"):
    for m in re.finditer(r'^%s="([^"]*)"' % re.escape(key), presets, re.M):
        check(not m.group(1), True, "export_presets.cfg: %s holds a value, empty it (secrets stay out of git)" % key)
check("use_gradle_build=true" in presets, True, "export_presets.cfg: Use Gradle Build must be on (ad and billing plugins)")

tracked = subprocess.run(["git", "ls-files"], cwd=ROOT, capture_output=True, text=True).stdout.split()
bad = [f for f in tracked if f.endswith((".keystore", ".jks", ".aab", ".apk"))]
check(not bad, True, "keystore/build files are tracked by git: " + ", ".join(bad))
check(os.path.isdir(os.path.join(ROOT, "android")), False, "android/ build template not installed yet (docs/MONETIZATION.md Part 1)")
check(os.path.isdir(os.path.join(ROOT, "addons", "admob")), False, "addons/admob plugin not installed (ads stay mocked)")
check(os.path.isdir(os.path.join(ROOT, "addons", "GodotGooglePlayBilling")), False, "addons/GodotGooglePlayBilling not installed (No Ads purchase stays mocked)")

proj = read("project.godot")
check(re.search(r'config/version="[^"]+"', proj) is not None, True, "project.godot: application/config/version missing")
code = re.search(r"version/code=(\d+)", presets)
name = re.search(r'version/name="([^"]+)"', presets)
print("Version code %s, name %s (project.godot says %s)" % (code and code.group(1), name and name.group(1), re.search(r'config/version="([^"]+)"', proj).group(1)))

for n in notes:
    print("NOTE   ", n)
for p in problems:
    print("BLOCKER", p)
print("%d blocker(s), %d note(s)" % (len(problems), len(notes)))
sys.exit(1 if problems else 0)
