"""Package individually generated image-model sources without changing their composition."""

from hashlib import sha256
import json
from pathlib import Path
import shutil
import sys

from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
assets = root / "Assets/Assets.xcassets"
input_manifest = Path(sys.argv[1]) if len(sys.argv) > 1 else root / "Assets/Design/Artwork.json"
records = json.loads(input_manifest.read_text())
assets.mkdir(parents=True, exist_ok=True)
(assets / "Contents.json").write_text('{"info":{"version":1,"author":"xcode"}}\n')
review = Image.new("RGB", (6 * 180, 4 * 135), "#17312c")
labels = ImageDraw.Draw(review)
manifest = []
icon_index = 0
for item in records:
    if "path" in item:
        original = Path(item["path"])
        identifier = item["id"]
        transparent = item["transparent"]
    else:
        original = root / item["source"]
        identifier = original.stem
        transparent = item["name"].startswith("icon-")
    source = root / "Assets/Design/Sources" / f"{identifier}.png"
    source.parent.mkdir(exist_ok=True)
    if not source.exists():
        shutil.copyfile(original, source)
    with Image.open(source) as picture:
        picture.load()
        if transparent:
            assert "A" in picture.getbands()
            alpha = picture.getchannel("A")
            assert alpha.getextrema() == (0, 255), source
            name = "icon-" + identifier
            picture.thumbnail((192, 192), Image.Resampling.LANCZOS)
            x, y = (icon_index % 6) * 180, (icon_index // 6) * 135
            for dimension, offset in [(92, 12), (36, 120)]:
                preview = picture.copy()
                preview.thumbnail((dimension, dimension), Image.Resampling.LANCZOS)
                review.paste(preview, (x + offset, y + 8), preview)
            labels.text((x + 12, y + 104), identifier, fill="#fff0d4")
            icon_index += 1
        else:
            name = identifier
        if name == "launcher":
            name = "AppIcon"
            assert picture.width == picture.height
            picture = picture.convert("RGB").resize((1024, 1024), Image.Resampling.LANCZOS)
            folder = assets / (name + ".appiconset")
            image_spec = {"idiom": "universal", "platform": "ios", "size": "1024x1024", "filename": "image.png"}
        else:
            folder = assets / (name + ".imageset")
            image_spec = {"idiom": "universal", "filename": "image.png"}
            if not transparent:
                picture.thumbnail((1200, 1800), Image.Resampling.LANCZOS)
        folder.mkdir(exist_ok=True)
        output = folder / "image.png"
        picture.save(output, optimize=True)
        (folder / "Contents.json").write_text(json.dumps({
            "images": [image_spec], "info": {"version": 1, "author": "xcode"}
        }, indent=2) + "\n")
        manifest.append({
            "name": name, "prompt": item["prompt"], "tool": "built-in ImageGen",
            "source": str(source.relative_to(root)), "sourceSHA256": sha256(source.read_bytes()).hexdigest(),
            "asset": str(output.relative_to(root)), "assetSHA256": sha256(output.read_bytes()).hexdigest()
        })
review.save(root / "Assets/Design/Review/icons.jpg", quality=92)
(root / "Assets/Design/Artwork.json").write_text(json.dumps(manifest, indent=2) + "\n")
