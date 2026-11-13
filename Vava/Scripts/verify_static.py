"""Verify source, artwork, media, and generated project metadata without compiling the app."""

import hashlib
import json
import plistlib
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image

root = Path(__file__).resolve().parents[1]
checks = 0


def check(condition, label):
    global checks
    if not condition:
        raise AssertionError(label)
    checks += 1


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads((root / path).read_text())


plist = plistlib.loads((root / "App/Info.plist").read_bytes())
project = (root / "Vava.xcodeproj/project.pbxproj").read_text()
app = "\n".join(path.read_text() for path in (root / "App").rglob("*.swift"))
check(plist["CFBundleDisplayName"] == "Vava", "Vava display name")
check(plist["CFBundleName"] == "$(PRODUCT_NAME)" and "PRODUCT_NAME = Vava;" in project, "Vava product name")
check(project.count("PRODUCT_BUNDLE_IDENTIFIER = com.vava.pingpong;") == 2, "Vava Bundle ID in Debug and Release")
check(not re.search(r"SecItem|kSecAttr|TableTennis\.Auth", app), "No Keychain access")
check(".atomic, .completeFileProtectionUntilFirstUserAuthentication" in app, "Protected local library persistence")
check("2026-11-13.2" in app, "Current agreement revision")
check(not (root / "TableTennis.xcodeproj").exists(), "Retired project removed")
check(plist["UISupportedInterfaceOrientations"] == ["UIInterfaceOrientationPortrait"], "Portrait orientation")
check("TARGETED_DEVICE_FAMILY = 1;" in project, "iPhone target")
for key in ("SUPPORTS_MACCATALYST", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD", "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD"):
    check(f"{key} = NO;" in project, key)
for name in plist["UIAppFonts"] + ["terms.pdf", "privacy.pdf", "catalog.json", "Media", "coin-products.json", "Assets.xcassets"]:
    check(f"{name} in Resources" in project, f"Bundled resource {name}")
check("systemName:" not in app and ".systemFont(" not in app, "Custom pictograms and typography")
for name in plist["UIAppFonts"]:
    path = root / "Assets/Fonts" / name
    check(path.exists() and path.stat().st_size > 0, f"Font file {name}")
for name in ["terms", "privacy"]:
    check((root / "Assets/Agreements" / (name + ".pdf")).read_bytes().startswith(b"%PDF-"), f"{name} PDF")
    check((root / "Assets/AgreementSources" / (name + ".md")).exists(), f"{name} editable text")
scheme = ET.parse(root / "Vava.xcodeproj/xcshareddata/xcschemes/Vava.xcscheme")
references = scheme.findall(".//BuildableReference")
check(bool(references) and all(
    ref.get("BuildableName") == "Vava.app" and ref.get("BlueprintName") == "Vava"
    and ref.get("ReferencedContainer") == "container:Vava.xcodeproj" for ref in references
), "Vava scheme references")
check([path.name for path in (root / "Vava.xcodeproj/xcshareddata/xcschemes").glob("*.xcscheme")]
      == ["Vava.xcscheme"], "Single Vava scheme")
check(scheme.find(".//LaunchAction").get("buildConfiguration") == "Debug", "Debug run")
check(scheme.find(".//ArchiveAction").get("buildConfiguration") == "Release", "Release archive")
check(scheme.find(".//StoreKitConfigurationFileReference") is None, "Apple catalog by default")
roots = re.findall(r'\("([A-Za-z]+)", "[a-z]+", [A-Za-z]+Screen\(context\)\)', app)
check(roots == ["Shorts", "Academy", "Watch", "Chats", "Me"], "Five independent roots")
packs = read_json("Configuration/coin-products.json")
check(len(packs) == 6 and all(pack["productID"] == "" and pack["coins"] > 0 for pack in packs), "Unconfigured packs")
check(not (root / "Configuration/backend.json").exists(), "Retired backend configuration removed")
check("backend.json" not in project and "storage/v1" not in app and "rest/v1" not in app, "No active backend routes")
check('url(forResource: path, withExtension: nil, subdirectory: "Media")' in app, "Bundle media lookup")
check("lastKnownFileType = folder; name = Media; path = Assets/Content/Media;" in project, "Media folder reference")
check('Bundle.main.decode("catalog")' in app and "URLSession" not in app, "On-device catalog and media")
art = read_json("Assets/Design/Artwork.json")
check(len(art) == 25, "25 individually generated artwork files")
for item in art:
    source, asset = root / item["source"], root / item["asset"]
    check(digest(source) == item["sourceSHA256"], f"Source hash {item['name']}")
    check(digest(asset) == item["assetSHA256"], f"Asset hash {item['name']}")
    with Image.open(asset) as image:
        if item["name"].startswith("icon-"):
            check(image.mode == "RGBA" and image.getchannel("A").getextrema() == (0, 255), f"Alpha {item['name']}")
        if item["name"] == "AppIcon":
            check(image.mode == "RGB" and image.size == (1024, 1024), "Opaque launcher icon")
catalog = read_json("Assets/Content/catalog.json")
check([len(catalog[k]) for k in ("shorts", "courses", "replays")] == [4, 6, 6], "Catalog sizes")
ids = [item["id"] for items in catalog.values() for item in items]
check(len(ids) == len(set(ids)), "Stable distinct catalog IDs")
check(all(course.get("steps") for course in catalog["courses"]), "Bundled lesson steps")
replay_sources = read_json("Assets/Content/replay-cover-sources.json")
check(set(replay_sources) == {item["cover"] for item in catalog["replays"]}, "Replay cover provenance")
check(sum(course["price"] == 0 for course in catalog["courses"]) == 1, "One introductory course")
media = read_json("Assets/Content/media-manifest.json")
check(set(media) == ({item[k] for item in catalog["shorts"] for k in ("media", "cover")} | {item["cover"] for item in catalog["replays"]}), "Media object mapping")
for name, item in media.items():
    path = root / "Assets/Content/Media" / name
    check(path.stat().st_size == item["bytes"] and digest(path) == item["sha256"], f"Media hash {name}")
    if path.suffix == ".mp4":
        output = subprocess.check_output(
            ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
             "stream=codec_name", "-of", "csv=p=0", str(path)], text=True
        )
        check(output.strip() == "h264", f"H.264 video {name}")
    else:
        with Image.open(path) as image:
            check(image.format == "JPEG" and image.width > 250, f"Photo cover {name}")
print(f"{checks} static source and resource checks passed.")
