# Owner-supplied memory artwork — 10 October 2026

Source: `/Users/popcorn/Downloads/DODDY-Numbered-Video-Assets-v01.zip`.
The owner explicitly selected this numbered ZIP, then approved the memory-journey
mockups for implementation. No new generated characters, downloaded fonts or outside
art were added. Existing candidate image sets and archived packs remain unchanged.
This records provenance, not an independent commercial-rights determination.

All five native `UploadedDoddy_*.imageset/art.png` files are byte-identical to these
ZIP entries. Prefix for every entry below:

`DODDY-Numbered-Video-Assets-v01/doddy-extra-poses-expressions-v02/doddy-extra-poses-expressions-v02/01-transparent-poses/`

| Native image set | ZIP filename | SHA-256 |
| --- | --- | --- |
| UploadedDoddy_Sitting | doddy_crosslegged_v02.png | f9496932f6944096c626301c00cc49070ea4fc71cbbf6516d27807c12ca58db6 |
| UploadedDoddy_Listening | doddy_listening_v02.png | 96375303e59d4b5f272805abb896a14ba3fcec37e8420a2dd04ec8b66823bc41 |
| UploadedDoddy_Inspect | doddy_kneeling_inspect_v02.png | c9a6d37b6e0ae53f321b6d93961f32688e2819ef3d9d84b8c30e51acf8bf380d |
| UploadedDoddy_Kept | doddy_fistpump_v02.png | c7a1fd158652d6420c67ce51d2e60e6b4808392fc131c108c7e348acf80a0561 |
| UploadedDoddy_Privacy | doddy_shush_v02.png | 69fa189d4e81c86b3387ee4172709a16af2c4b8aca00dd86e28382f20e57140f |

Verified directly by `unzip -p` of each exact ZIP entry piped to `shasum -a 256`,
compared with `shasum -a 256` of the corresponding native PNG; all five pairs match.
Dark appearance adds a light paper backing around the unchanged image. Artwork is
decorative, can be hidden in Settings, and has no invented animation/state behaviour.
The existing development app icon is not replaced or represented as final branding.

## Widget copies (Live Activity, 10 October 2026)

`DoddyWidgets/Assets.xcassets/UploadedDoddy_{Listening,Kept,Sitting}.imageset` hold `art@2x.png`
(107×160 px) and `art@3x.png` (160×240 px): Lanczos downscales of the three files above, with no
crop, recolour or other edit. Live Activity images must stay small; the app keeps the
byte-identical originals. Regenerate from the originals if the ZIP files change.
