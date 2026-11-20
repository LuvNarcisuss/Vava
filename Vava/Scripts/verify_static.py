"""Verify source, artwork, media, and generated project metadata without compiling the app."""

import hashlib
import json
import plistlib
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET
from uuid import UUID
from zipfile import ZipFile

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
native_sources = list((root / "App/Core").glob("*.swift")) + list((root / "App/ReactNative").glob("*.swift"))
app = "\n".join(path.read_text() for path in native_sources if path.name != "Theme.swift")
react = "\n".join(path.read_text() for path in (root / "ReactNative").glob("*.tsx"))
check(plist["CFBundleDisplayName"] == "Vava", "Vava display name")
check(plist["CFBundleName"] == "$(PRODUCT_NAME)" and "PRODUCT_NAME = Vava;" in project, "Vava product name")
check(plist["CFBundleIdentifier"] == "$(PRODUCT_BUNDLE_IDENTIFIER)", "Bundle ID follows build configuration")
identities = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);[^}]*}\s*;\s*name = (Debug|Release);", project)
check(dict((name, bundle_id) for bundle_id, name in identities) == {
    "Debug": "im.seex.sao2", "Release": "com.vava.pingpong",
} and len(identities) == 2, "Debug and Release Bundle IDs")
check(project.count("DEVELOPMENT_TEAM = JPTS6M4T5B;") == 2, "Yu Sun signing team")
check(not re.search(r"SecItem|kSecAttr|TableTennis\.Auth", app), "No Keychain access")
check(".atomic, .completeFileProtectionUntilFirstUserAuthentication" in app, "Protected local library persistence")
check("2026-11-13.2" in app, "Preserved consent revision")
check("https://docs.google.com/document/d/1HKDBNvyA7Vha5_sVVoc4P4Z8e-udZkrMlfdbTgVvdOs" in app, "Terms document URL")
check("https://docs.google.com/document/d/1_ldTUi2Y1bfT5x9BphLfDo3AwM7ZBpNxUnHFmwI2GFo" in app, "Privacy document URL")
check("SFSafariViewController" in app and "snapshot.agreements" in react, "Shared native agreement reader")
check("terms.pdf in Resources" not in project and "privacy.pdf in Resources" not in project, "Historical PDFs stay outside the app bundle")
check(not (root / "TableTennis.xcodeproj").exists(), "Retired project removed")
check(plist["UISupportedInterfaceOrientations"] == ["UIInterfaceOrientationPortrait"], "Portrait orientation")
check(set(plist["NSBonjourServices"]) == {"_vava-chat._tcp", "_vava-chat._udp"}
      and all(plist.get(key) for key in ("NSLocalNetworkUsageDescription", "NSMicrophoneUsageDescription",
                                       "NSCameraUsageDescription")), "Nearby chat discovery and call permissions")
for name in ("ChatModels", "ChatService", "ChatTransport", "ChatMedia"):
    check(f"{name}.swift in Sources" in project, f"{name} is in the iPhone target")
check("mailto" not in app.lower(), "Chats does not substitute email for private messages")
check("TARGETED_DEVICE_FAMILY = 1;" in project, "iPhone target")
check(set(re.findall(r"TARGETED_DEVICE_FAMILY = ([^;]+);", project)) == {"1"}, "All configurations are iPhone-only")
for key in ("SUPPORTS_MACCATALYST", "SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD", "SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD"):
    check(f"{key} = NO;" in project, key)
for name in plist["UIAppFonts"] + ["catalog.json", "Media", "coin-products.json", "Assets.xcassets"]:
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
launch = scheme.find("./LaunchAction")
storekit_path = "Configuration/VavaCoins.storekit"
storekit_reference = launch.find("StoreKitConfigurationFileReference")
check(storekit_reference is not None and storekit_reference.get("identifier") == f"../{storekit_path}"
      and (root / "Vava.xcworkspace" / storekit_reference.get("identifier")).resolve().is_file(),
      "Vava Debug Run selects the local StoreKit catalog")
local_mode = "VAVA_LOCAL_STOREKIT"
launch_flag = launch.find(f"EnvironmentVariables/EnvironmentVariable[@key='{local_mode}']")
check(launch_flag is not None and launch_flag.get("value") == "1" and launch_flag.get("isEnabled") == "YES",
      "Vava Debug Run opts into the isolated wallet")
check(scheme.find(f"./ArchiveAction//EnvironmentVariable[@key='{local_mode}']") is None
      and scheme.find("./ArchiveAction//StoreKitConfigurationFileReference") is None,
      "Archive has no local StoreKit settings")
check("VavaCoins.storekit in Resources" not in project, "Local catalog stays outside the app bundle")
spec = (root / "project.yml").read_text()
check(f"storeKitConfiguration: {storekit_path}" in spec and f'{local_mode}: "1"' in spec
      and 'schemePathPrefix: "../"' in spec,
      "XcodeGen preserves the local StoreKit configuration")
package = read_json("package.json")
lock = read_json("package-lock.json")
check(package["dependencies"]["react-native"] == lock["packages"]["node_modules/react-native"]["version"], "Locked React Native version")
check(package["dependencies"]["react"] == lock["packages"]["node_modules/react"]["version"], "Locked React version")
check("withModuleName: \"Vava\"" in app and "AppRegistry.registerComponent('Vava'" in (root / "index.js").read_text(), "Matching React Native entrypoint")
check("react-native-xcode.sh" in project and "react-native-xcode.sh" in spec, "Release JavaScript bundling phase")
for name in ("VavaNative.swift", "VavaNativeBridge.m", "NativeVideo.swift", "NativeMediaActions.swift"):
    check(f"{name} in Sources" in project, f"Native bridge source {name}")
for name in [path.name for path in (root / "App/Features").glob("*.swift")] + ["Theme.swift"]:
    check(f"{name} in Sources" not in project, f"UIKit screen excluded {name}")
react_entry = (root / "ReactNative/WebApp.tsx").read_text()
root_declaration = re.search(r"const tabs = \[(.*?)\]", react_entry, re.S)
check(root_declaration is not None and re.findall(r'[\"\']([A-Za-z]+)[\"\']', root_declaration.group(1))
      == ["Academy", "Watch", "Shorts", "Chats", "Me"], "Five local H5 navigation roots in order")
check("previous.revision" in react_entry and "snapshotRevision" in app, "Snapshot ordering protection")
check("PrivacyInfo.xcprivacy in Resources" in project and "PrivacyInfo.xcprivacy" in spec, "Privacy manifest retained by generator")
check((root / "Vava.xcworkspace/contents.xcworkspacedata").exists(), "CocoaPods workspace exists")
check((root / "Podfile.lock").exists(), "Native dependency lockfile exists")
# The shipped archive must correspond to the current presentation source.
with ZipFile(root / "Assets/LocalWeb/vava.zip") as archive:
    members = archive.namelist()
    check(all(not name.startswith("/") and ".." not in Path(name).parts for name in members), "Local H5 archive paths")
    for name in ["index.html", "app.js", "app.css", "manifest.json", "art/icon-academy.png", "art/icon-me.png", "fonts/Kalam-Bold.ttf", "fonts/ComicNeue-Regular.ttf"]:
        check(name in members, f"Local H5 resource {name}")
    manifest = json.loads(archive.read("manifest.json"))
    for name, expected in manifest["sources"].items():
        check(digest(root / name) == expected, f"Local H5 archive matches {name}")
    for directory in ["ReactNative", "Web"]:
        check(all(str(path.relative_to(root)) in manifest["sources"] for path in (root / directory).iterdir() if path.is_file()), f"Local H5 manifest covers {directory}")
    for name in ["index.html", "app.css"]:
        check(archive.read(name) == (root / "Web" / name).read_bytes(), f"Local H5 packaged {name}")
    check(archive.read("art/background.png") == (root / "Assets/Assets.xcassets/background.imageset/image.png").read_bytes(),
          "Local H5 packaged the current screen background")
    check(b"connect-src 'none'" in archive.read("index.html"), "Local H5 denies web network requests")
check("vava.zip in Resources" in project and "Assets/LocalWeb/vava.zip" in spec, "Bundled H5 archive in generated project")
check("LocalWebView.swift in Sources" in project, "Native local WebView included")
page_host = (root / "App/ReactNative/LocalWebView.swift").read_text()
check("allowingReadAccessTo: root" in page_host and "websiteDataStore = .nonPersistent()" in page_host, "Restricted local WebView storage")
check("message.frameInfo.isMainFrame" in page_host and "entry.type != .symlink" in page_host, "Local bridge and archive validation")
check("commands.has(message.command)" in (root / "ReactNative/App.tsx").read_text(), "H5 command allowlist")
packs = read_json("Configuration/coin-products.json")
check(len(packs) == 9, "Nine StoreKit consumables for the wallet grid")
expected_packs = [
    ("0.99", 400, "ampqtftkneoumheh"),
    ("1.99", 800, "xtvhwdsgjloktbwl"),
    ("4.99", 2450, "ofodmhntljhmyqmu"),
    ("9.99", 5150, "kngnkmkillhkjekc"),
    ("19.99", 10800, "wmiafabmsrgzdnfy"),
    ("29.99", 16800, "oeryktujrjycpirn"),
    ("49.99", 29400, "abnkqxwpzttscctn"),
    ("69.99", 42600, "tocftlpnavpjddox"),
    ("99.99", 63700, "bxmlhefhtmbillwb"),
]
check([(pack["referenceUSD"], pack["coins"], pack["productID"]) for pack in packs] == expected_packs,
      "Reference USD, coin quantities, and StoreKit IDs in wallet display order")
product_ids = {pack["productID"] for pack in packs}
check(len(product_ids) == len(packs) and all(re.fullmatch(r"[a-z]{16}", item) for item in product_ids),
      "Unique 16-letter product IDs")
fixture = read_json(storekit_path)
check([(offer["displayPrice"], offer["productID"], offer["type"], offer["referenceName"])
       for offer in fixture["products"]]
      == [(pack["referenceUSD"], pack["productID"], "Consumable", f"{pack['coins']:,} Coins") for pack in packs],
      "Local StoreKit consumables match the wallet catalog")
wallet = (root / "App/Core/Wallet.swift").read_text()
check(all(api in wallet for api in ["SKProductsRequest", "SKPaymentQueue", "SKMutablePayment", "SKReceiptRefreshRequest"])
      and not any(api in wallet for api in ["Product.products", "Transaction.updates", "Transaction.unfinished", "VerificationResult<Transaction>"]),
      "Wallet uses StoreKit 1 exclusively")
check("case .valid = await receipt.validate()" in wallet
      and "transactionIdentifier == transactionID" in wallet, "Receipt validation precedes transaction credit")

check(re.search(r"#if DEBUG\s+.*?" + local_mode + r".*?#else\s+localStoreKit = false\s+#endif", wallet, re.S),
      "Local wallet opt-in is compiled out of Release")
check('localStoreKit ? localFile : appleFile' in wallet and '"LocalStoreKitWallets"' in wallet,
      "Local StoreKit uses a separate wallet file")
check(re.search(r"localStoreKit\s*\? environment == \.xcode\s*: environment == \.sandbox \|\| environment == \.productionSandbox \|\| environment == \.production", wallet),
      "Purchase delivery requires the wallet's StoreKit environment")
check(not (root / "Configuration/backend.json").exists(), "Retired backend configuration removed")
check("backend.json" not in project and "storage/v1" not in app and "rest/v1" not in app, "No active backend routes")
check('url(forResource: path, withExtension: nil, subdirectory: "Media")' in app, "Bundle media lookup")
check("lastKnownFileType = folder; name = Media; path = Assets/Content/Media;" in project, "Media folder reference")
check('Bundle.main.decode("catalog")' in app and "URLSession" not in app, "On-device catalog and media")
art = read_json("Assets/Design/Artwork.json")
check(len(art) == 33, "33 artwork entries with generated and owner-provided provenance")
reaction_states = {
    "icon-like-outline": False, "icon-save-outline": False,
    "icon-like-selected": True, "icon-save-selected": True,
}
art_by_name = {item["name"]: item for item in art}
for name, filled in reaction_states.items():
    check(name in art_by_name, f"Independent artwork for {name}")
    with Image.open(root / art_by_name[name]["asset"]) as image:
        center = image.getchannel("A").getpixel((image.width // 2, image.height // 2))
        check(center >= 240 if filled else center <= 15, f"Visible fill state for {name}")
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
engagement_fields = {"likes", "saves", "shares"}
editorial_counts = {"ravne": 26, "netherlands-china": 30, "club-rally": 22, "open-rally": 24}
publisher_names = {}
editorial_ids = set()
editorial_bodies = set()
for clip in catalog["shorts"]:
    publisher = clip["publisherID"]
    check(bool(re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", publisher)), f"Stable publisher ID for {clip['id']}")
    check(publisher_names.setdefault(publisher, clip["publisher"]) == clip["publisher"], "Consistent publisher attribution")
    counts = clip["engagement"]
    check(counts.keys() == engagement_fields, f"Only estimated engagement fields for {clip['id']}")
    check(all(type(value) is int and 20 <= value <= 50 for value in counts.values()), f"Estimate range for {clip['id']}")
    notes = clip["editorialComments"]
    check(len(notes) == editorial_counts[clip["id"]], f"Editorial comment rows for {clip['id']}")
    for note in notes:
        check(set(note) == {"id", "body"}, "Editorial content contains only a stable ID and note text")
        identifier = UUID(note["id"])
        check(identifier.version == 5 and identifier not in editorial_ids, "Stable unique editorial comment ID")
        editorial_ids.add(identifier)
        body = note["body"].strip()
        check(1 <= len(body) <= 200 and body not in editorial_bodies, "Distinct readable editorial comment")
        editorial_bodies.add(body)
check(all(course.get("steps") for course in catalog["courses"]), "Bundled lesson steps")
photo_sources = read_json("Assets/Content/publisher-photo-sources.json")
authors = {}
for course in catalog["courses"]:
    author = course["author"]
    check(author == authors.setdefault(author["id"], author), "Consistent coaching source identity")
    check(course["referenceName"].startswith(author["name"] + " · "), "Coaching reference attribution")
    check(author["website"].startswith("https://"), "Public coaching source website")
check(set(photo_sources) == {author["avatar"] for author in authors.values()}, "Coaching photo provenance")
for name, source in photo_sources.items():
    image_path = root / "Assets/Content/Media" / name
    check(source["source"].startswith("https://") and bool(source["credit"]), "Photo source and credit")
    check(digest(image_path) == source["sha256"], f"Coaching photo hash {name}")
    with Image.open(image_path) as image:
        check(image.format == "JPEG" and image.size == (256, 256) and not image.getexif(), f"Coaching photo format {name}")
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
