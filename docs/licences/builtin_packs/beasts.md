# Beasts and Farm Animals (built-in token pack): provenance

The seven animal tokens in `builtin_packs/beasts/` are Quaternius's animated Farm Animals, converted
from FBX to GLB by `tools/roster/build_beasts.gd` (Godot's own FBX reader and glTF exporter, no
Blender). Nothing else went in: no repainted colours, no AI-made content. The conversion sets each
animal's real-world height (see "Scale"), renames the clips the token animation tree plays and drops
the rest; the meshes, flat material colours and skeletons are the source's.

Obtained 2026-11-01 (a licence can change after a download, so the date is part of the record).

## Source and licence

The pack page https://quaternius.com/packs/farmanimal.html ("Farm Animal Pack", June 2018, 7 models)
shows `License CC0`, linking https://creativecommons.org/publicdomain/zero/1.0/. The author's own
itch.io page https://quaternius.itch.io/lowpoly-animated-animals ("LowPoly Animated Animals",
"6 Animated Animals with Death, Idle, Jump, Run and Walk animations in FBX, OBJ and Blend format.
CC0 License", license metadata "Creative Commons Zero v1.0 Universal") offers the same animals as
the file "Farm Animals Animated by Quaternius.zip" (6963285 bytes, 2018-11-08), taken through the
page's own download button (name your own price, $0, no login). Neither page names the newer QAL
licence. The zip holds no licence file. Checked on the day of the download, 2026-11-01.

```
SHA-256 B4BC5F209368CAFC21962934E7D676CF1CFB1F746A363086CD9F45C4385DB70E  Farm Animals Animated by Quaternius.zip
0202789CAD8C1DEBB8AE5B4A47D1A5D2E5F93A0875878BC0B05A80E42AE37E8D  FBX/Cow.fbx
6DB270DDC7591E9A013F96EAB445031381FA6D5D68D2FEBA567F964E0FE68D90  FBX/Horse.fbx
3FF44FD03D5793701B228CF88F00E776F89AFEFDB3DE0B226FEE807908AE79C9  FBX/Llama.fbx
BDF5E149A974FFC2431546F30EA568D7C41F916D7BD87187F1532C45778A9A23  FBX/Pig.fbx
C05E127A5B10EDD059478113F542F691717635B47D7A57317D07E7310A764FF0  FBX/Pug.fbx
4A3FC559CC9F37E3E3F216AF1DAB30CB411EC9B268EB98676F1D5C18A430D33E  FBX/Sheep.fbx
ECBFE34A4D1F5F0695D573E04F0287B03F8F37B8E4DDBF37F7EA9737063AE200  FBX/Zebra.fbx
```

## Not yet included: Ultimate Animated Animal Pack

The card for this pack named two sources. The second, "Ultimate Animated Animal Pack"
(https://quaternius.com/packs/ultimateanimatedanimals.html, July 2021, 12 models, glTF available,
page label `License CC0`), is distributed only through a Google Drive folder, and every file there
answered "Quota exceeded" on 2026-11-01 (Quaternius's itch.io shop does not carry it). Its animals
(Alpaca, Bull, Cow, Deer, Donkey, Fox, Horse, Horse_White, Husky, ShibaInu, Stag, Wolf) can be added
later with the same pack folder; the build script reads FBX, so glTF sources would need a short
loader step instead (`GLTFDocument` in place of `FBXDocument`).

## Files in the pack (SHA-256)

```
a068ea719bb8bb90bd5fe19b9b3f4fabd7544639913e7975b5b8a47c91772dfa  models/cow.glb
3c3436edc838fe8e7d18bf8378ed444bf3e88c9c01b6520f586d2a4a00fa0530  models/horse.glb
831fb3e0e5d35a08ea67f2307996c4fc94b9af8e5fb7e77ef8f4ac3e5fad4bf0  models/llama.glb
ee18cf24c043d106e1b534ceba41e1d6c232d67e038f61aaea7add4d9ff9bdaa  models/pig.glb
7fd92a8a94906fc68df6bc97ce23922a5ed1059c1ec2a830888d4962c7c40f07  models/pug.glb
3107e7eb522209a2633a454be03d8861f45a976d9ae2426c1b2c116b6dd0804c  models/sheep.glb
cce03f4f31c62b6399b721b8a29840182bccb54b44bbf633a7db5c956bb35a4b  models/zebra.glb
```

The icons (`icons/<id>.png`, 128 px, transparent, rendered by `tools/roster/render_icons.gd --yaw -50`
from the game camera's angle) are regenerable and are not hashed here. Total 2.0 MB in Git LFS
(7 GLBs 1.77 MB, 7 icons 0.07 MB).

## Scale

tt-sim applies no token scale (`docs/ASSET_PIPELINE.md` sections 2 and 7: 1 unit is 1 metre, a grid
cell is 1.524 m), and the sources are at an arbitrary modeller scale. Each GLB's root node therefore
carries a uniform scale and offset that make the animal stand on y = 0, centred, at a real-world
height (head to hoof, from the skinned rest pose; `tools/roster/beast_recipes.gd`): horse 2.1 m,
llama 1.8 m, cow and zebra 1.5 m, sheep 1.0 m, pig 0.9 m, pug 0.4 m. No manifest field is needed.

## Animation

The tree (`scenes/board_token/board_token_animation_tree.tscn`) plays clips by fixed names. The
build keeps `Idle` as `battlewait01` (the tree loops it at run time: glTF has no loop flag),
`Jump` as `damage01` (a startle when hit) and, for the cow, horse and zebra, `Death` as
`down01_start` and `down01`. The llama, pig, pug and sheep have no death clip, so a token of those
that is reduced to 0 health has no down animation. Walk and run clips were dropped (tt-sim moves
tokens by sliding them).
