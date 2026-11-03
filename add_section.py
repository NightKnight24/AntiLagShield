import plistlib, os, copy

bb_path = "/var/mobile/Library/BulletinBoard/VersionedSectionInfo.plist"
with open(bb_path, "rb") as f:
    d = plistlib.load(f)

sec_bytes = d["sectionInfo"]["com.google.ios.youtube"]
sec_dict = plistlib.loads(sec_bytes)

# Clone for Anti-Lag Shield
new_dict = copy.deepcopy(sec_dict)
objs = new_dict["$objects"]
objs[2] = "com.jordan.antilagshield"
objs[5] = "Anti-Lag Shield"

new_bytes = plistlib.dumps(new_dict, fmt=plistlib.FMT_BINARY)
d["sectionInfo"]["com.jordan.antilagshield"] = new_bytes

# Backup
os.system(f"cp {bb_path} {bb_path}.bak")
with open(bb_path, "wb") as f:
    plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)

print("Added com.jordan.antilagshield to VersionedSectionInfo.plist!")

# Also ensure the UserNotifications directory exists
notif_dir = "/var/mobile/Library/UserNotifications/E749A762-7697-4E44-98B5-2FAB699F05C7"
os.makedirs(notif_dir, exist_ok=True)
empty_archive = {'$version': 100000, '$archiver': 'NSKeyedArchiver', '$top': {'root': plistlib.UID(0)}, '$objects': ['$null']}
with open(os.path.join(notif_dir, "DeliveredNotifications.plist"), "wb") as f:
    plistlib.dump(empty_archive, f, fmt=plistlib.FMT_BINARY)

os.system(f"chown -R mobile:mobile {notif_dir} /var/mobile/Library/BulletinBoard")
print("UserNotifications directory and permissions set successfully!")
