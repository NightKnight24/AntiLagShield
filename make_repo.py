#!/usr/bin/env python3
import os, hashlib, gzip, tarfile, io, shutil

REPO_DIR = os.path.join(os.path.dirname(__file__), "repo")
DEBS_DIR = os.path.join(REPO_DIR, "debs")
DIST_DIR = os.path.join(os.path.dirname(__file__), "dist")

os.makedirs(DEBS_DIR, exist_ok=True)

# Copy latest debs and tipa
for item in os.listdir(DIST_DIR):
    src = os.path.join(DIST_DIR, item)
    if item.endswith(".deb"):
        shutil.copy2(src, os.path.join(DEBS_DIR, item))
    elif item.endswith(".tipa"):
        shutil.copy2(src, os.path.join(REPO_DIR, item))

def extract_control_from_deb(deb_path):
    with open(deb_path, "rb") as f:
        # Deb is AR format
        header = f.read(8)
        assert header == b"!<arch>\n", "Not a valid ar archive"
        while True:
            file_header = f.read(60)
            if not file_header or len(file_header) < 60:
                break
            fname = file_header[:16].strip().decode(errors="ignore")
            size = int(file_header[48:58].strip())
            file_data = f.read(size)
            if size % 2 != 0:
                f.read(1) # padding byte
            if fname.startswith("control.tar"):
                # Untar control.tar
                with tarfile.open(fileobj=io.BytesIO(file_data), mode="r:*") as tar:
                    for member in tar.getmembers():
                        if member.name.endswith("control") and not member.isdir():
                            c_f = tar.extractfile(member)
                            return c_f.read().decode("utf-8")
    return ""

packages_entries = []

for deb_fname in sorted(os.listdir(DEBS_DIR)):
    if not deb_fname.endswith(".deb"):
        continue
    deb_path = os.path.join(DEBS_DIR, deb_fname)
    ctrl = extract_control_from_deb(deb_path)
    
    with open(deb_path, "rb") as df:
        content = df.read()
        size = len(content)
        md5 = hashlib.md5(content).hexdigest()
        sha1 = hashlib.sha1(content).hexdigest()
        sha256 = hashlib.sha256(content).hexdigest()
    
    entry = ctrl.strip()
    entry += f"\nFilename: debs/{deb_fname}"
    entry += f"\nSize: {size}"
    entry += f"\nMD5sum: {md5}"
    entry += f"\nSHA1: {sha1}"
    entry += f"\nSHA256: {sha256}\n"
    packages_entries.append(entry)

packages_content = "\n".join(packages_entries) + "\n"
packages_path = os.path.join(REPO_DIR, "Packages")
with open(packages_path, "w", encoding="utf-8") as pf:
    pf.write(packages_content)

packages_gz_path = os.path.join(REPO_DIR, "Packages.gz")
with gzip.open(packages_gz_path, "wb") as gzf:
    gzf.write(packages_content.encode("utf-8"))

# Generate Release file
def get_file_info(rel_path):
    full_p = os.path.join(REPO_DIR, rel_path)
    if not os.path.exists(full_p):
        return ""
    with open(full_p, "rb") as f:
        data = f.read()
    sz = len(data)
    md5 = hashlib.md5(data).hexdigest()
    sha256 = hashlib.sha256(data).hexdigest()
    return sz, md5, sha256

pkg_sz, pkg_md5, pkg_sha = get_file_info("Packages")
gz_sz, gz_md5, gz_sha = get_file_info("Packages.gz")

release_content = f"""Origin: NightKnight Repo
Label: NightKnight24
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm iphoneos-arm64
Components: main
Description: Official repository for Anti-Lag Shield Pro & NightKnight Projects.
MD5Sum:
 {pkg_md5} {pkg_sz} Packages
 {gz_md5} {gz_sz} Packages.gz
SHA256:
 {pkg_sha} {pkg_sz} Packages
 {gz_sha} {gz_sz} Packages.gz
"""

with open(os.path.join(REPO_DIR, "Release"), "w", encoding="utf-8") as rf:
    rf.write(release_content)

# Generate HTML Landing Page
html_content = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NightKnight Repo — Anti-Lag Shield Pro</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: #0b0e14;
            color: #ffffff;
            margin: 0;
            padding: 24px;
            display: flex;
            flex-direction: column;
            align-items: center;
        }
        .container {
            max-width: 600px;
            width: 100%;
        }
        .header {
            text-align: center;
            margin-bottom: 24px;
        }
        .card {
            background: #141a24;
            border: 1px solid #222d3d;
            border-radius: 16px;
            padding: 20px;
            margin-bottom: 20px;
        }
        .btn {
            display: block;
            width: 100%;
            box-sizing: border-box;
            text-align: center;
            background: #00d2f5;
            color: #000;
            font-weight: bold;
            padding: 14px;
            border-radius: 12px;
            text-decoration: none;
            margin-bottom: 12px;
            font-size: 16px;
        }
        .btn-zebra { background: #33b5e5; color: #fff; }
        .btn-cydia { background: #96613d; color: #fff; }
        .btn-troll { background: #30d158; color: #000; }
        .badge {
            display: inline-block;
            background: #19382b;
            color: #30d158;
            padding: 4px 10px;
            border-radius: 8px;
            font-size: 12px;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1 style="font-size: 40px; margin-bottom: 4px;">🛡️</h1>
            <h2 style="margin: 0;">NightKnight Jailbreak Repo</h2>
            <p style="color: #00d2f5; font-size: 14px;">Official Source for Anti-Lag Shield Pro & Utilities</p>
        </div>

        <div class="card">
            <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px;">
                <h3 style="margin: 0;">Anti-Lag Shield Pro</h3>
                <span class="badge">v3.8 • UNIVERSAL</span>
            </div>
            <p style="color: #a0aec0; font-size: 14px; line-height: 1.5;">
                Universal Network Sentinel, Device Revival & Low-Latency Acceleration Suite for all 64-bit iOS & iPadOS devices (iOS 12.0 – 18.x).
            </p>
            <p style="color: #718096; font-size: 12px;">
                • Turbo UI Mode (0ms touch, GPU blur bypass)<br>
                • Deep Flash Storage & Cache Cleaner<br>
                • Zero-Trust Hardware Gateway Lock & Anti-Spoof Sentinel<br>
                • Bluetooth Gamepad VIP Scheduling (Xbox, PS5, Switch)
            </p>
        </div>

        <div class="card">
            <h4 style="margin-top: 0; color: #a0aec0;">INSTALL ON YOUR DEVICE:</h4>
            <a class="btn" href="sileo://source/https://nightknight24.github.io/repo/">⚡ Add to Sileo</a>
            <a class="btn btn-zebra" href="zbra://sources/add/https://nightknight24.github.io/repo/">🦓 Add to Zebra</a>
            <a class="btn btn-cydia" href="cydia://url/https://cydia.saurik.com/api/share#?source=https://nightknight24.github.io/repo/">📦 Add to Cydia</a>
            <a class="btn btn-troll" href="AntiLagShield_v3.8.tipa">📱 Download TrollStore (.tipa)</a>
        </div>

        <div style="text-align: center; color: #718096; font-size: 13px;">
            <p>Repo URL: <code>https://nightknight24.github.io/repo/</code></p>
            <p style="margin-top: 6px;">
                <a href="privacy.html" style="color: #00d2f5; margin-right: 14px;">Privacy Policy</a> • 
                <a href="license.html" style="color: #00d2f5; margin-left: 14px; margin-right: 14px;">License Agreement</a> • 
                <a href="https://github.com/NightKnight24/AntiLagShield" style="color: #00d2f5; margin-left: 14px;">GitHub Source</a>
            </p>
            <p style="margin-top: 8px;">Maintained by <a href="https://github.com/NightKnight24" style="color: #00d2f5;">NightKnight24</a></p>
        </div>
    </div>
</body>
</html>
"""

with open(os.path.join(REPO_DIR, "index.html"), "w", encoding="utf-8") as hf:
    hf.write(html_content)

print("==> Successfully generated complete APT repository in repo/!")