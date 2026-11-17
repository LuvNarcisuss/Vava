# Media and artwork credits

## Short recordings

All four short sources are real table tennis footage. The two organized matches lead the catalog, followed by two informal games. The H.264/AAC transcodes preserve the selected source timing and aspect ratio. Their extracted frames retain the source license. See Assets/Content/catalog.json for the title, author, original link, license and asset mapping. See Assets/Content/media-manifest.json for the bundled bytes and SHA-256 digests.

| Clip | Original work | App adaptation |
| --- | --- | --- |
| Ravne league final | Televizija Uršlja, Wikimedia Commons, CC BY 3.0 | 508–546 seconds, H.264 MP4 and a still from the excerpt |
| Netherlands vs China | Netherlands Institute for Sound & Vision, Open Beelden, CC BY-SA 3.0 NL | 29–86 seconds, H.264 MP4 and a still from the excerpt, shared under the same license |
| A game between brothers | Anumodu favour Amarachi, Wikimedia Commons, CC BY-SA 4.0 | Complete clip, resized and converted to H.264 MP4, shared under the same license |
| Table tennis outdoors | Evworo, Wikimedia Commons, CC BY-SA 3.0 | Complete clip, resized and converted to H.264 MP4, shared under the same license |

## Official replays and lessons

Watch uses locally stored thumbnails associated with World Table Tennis publisher pages. The sources are listed in Assets/Content/replay-cover-sources.json. The full videos remain on the publisher's site. Academy offers original drill cards and progress checklists informed by public material from Tom Lodziak (United Kingdom), Table Tennis England and Butterfly North America (United States). The publisher links are accessible from each course regardless of purchase status.

## App artwork and type

Assets/Design/Artwork.json maps generated artwork and owner-provided branding to their asset catalog entries, sources and hashes; generated entries also retain their exact English prompts. Assets/Design/Sources contains the individual outputs. Assets/Design/Review contains icon scale checks and representative video frames. Kalam Bold and Comic Neue Regular are bundled under their SIL Open Font Licenses in Assets/Fonts.

The current screen background is a portrait illustration generated with built-in ImageGen. `Assets/Design/Sources/table-tennis-background.png` retains the generated PNG. The asset catalog and local H5 archive use identical image bytes. The previous table-texture source remains in the artwork provenance. The illustration is used across the login, main tabs and detail screens, with the Shorts player using its own media surface.

## Current Vava logo

On November 17, 2026, the owner supplied `/Users/apple/Downloads/247/logo.png` for Vava branding. `Assets/Design/Sources/brand-logo.png` preserves those original bytes. The application icon uses the same 1024 x 1024 pixels in opaque RGB PNG packaging. `brand-logo.imageset` and the local H5 `art/brand-logo.png` retain the supplied PNG unchanged. The welcome/login page displays the entire square with contain sizing; native-shell and H5 loading/error surfaces use the same mark. The web page icon also points to it. Colors, lettering and composition are preserved.

The previous generated launcher source and welcome illustration remain available for provenance; the current login page no longer uses that illustration. This update does not replace profile portraits or navigation glyphs.
