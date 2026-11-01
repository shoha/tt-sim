# Beasts and Farm Animals (built-in token pack): provenance

The 18 animal tokens in `builtin_packs/beasts/` are Quaternius's animated animals, converted to GLB
by `tools/roster/build_beasts.gd` (Godot's own FBX and glTF readers and glTF exporter, no Blender).
Nothing else went in: no repainted colours, no AI-made content. The conversion sets each animal's
real-world height (see "Scale"), renames the clips the token animation tree plays and drops the
rest; the meshes, flat material colours and skeletons are the sources'.

Obtained 2026-11-01 (a licence can change after a download, so the date is part of the record).

## Sources and licence

Both pack pages show `License CC0`, linking https://creativecommons.org/publicdomain/zero/1.0/;
neither names the newer QAL licence. Checked 2026-11-01. Neither download holds a licence file.

| Pack | Page | Download used |
|------|------|---------------|
| Ultimate Animated Animal Pack (12 animals, July 2021) | https://quaternius.com/packs/ultimateanimatedanimals.html | The 12 `.gltf` files of the page's Google Drive folder, downloaded by the project owner in a browser on 2026-11-01 (the scripted download was over Drive's quota): `drive-download-20261101T203057Z-1-001.zip`, 7433831 bytes |
| Farm Animal Pack (7 animals, June 2018) | https://quaternius.com/packs/farmanimal.html (FBX, OBJ, Blend only) | The author's own itch.io page https://quaternius.itch.io/lowpoly-animated-animals ("6 Animated Animals ... CC0 License", metadata "Creative Commons Zero v1.0 Universal"), file "Farm Animals Animated by Quaternius.zip", 6963285 bytes, name-your-own-price $0, no login |

Downloads (SHA-256):

```
87ECD0021F34BC98695DE3AECC61C89AA27C3922F00452B7B5D33C97B4A75CF9  drive-download-20261101T203057Z-1-001.zip
B4BC5F209368CAFC21962934E7D676CF1CFB1F746A363086CD9F45C4385DB70E  Farm Animals Animated by Quaternius.zip
```

Extracted source files (SHA-256):

```
5009BFA756C7B7AF5E02263D47A6D9088CADAADA2240B41B4E87F31327B0E063  Alpaca.gltf
535DA2992EB125D517725159A2EDDEB520B72595BCB3021985FC43D2C84BFF76  Bull.gltf
B04AF067688D9FADF1395B4456DBF3117C2F760FB49E704EE5C8B6391FC8ADB5  Cow.gltf
B8AFD0647E7A74332CE802C8326DFEFE1A2B76DA67AB925A631AADDB5AE9BDD4  Deer.gltf
4CBB2EB7D057789C945B6445D99D0C73B76C0CAF7AC9B37CE88A04CA718BE2FF  Donkey.gltf
2F36E3C9C75ECDDDA85C5F9944E98EE1E88E7C679A546534AFF1CEA8ECDE64C7  Fox.gltf
F137EE67BD565244F7441F35B5594A597588CDA8B60AB109E2041CF13C58E1DD  Horse_White.gltf
3DEB61550DFF1D2786D04B6E8559D63AD3907D6AB606BA28CE0AF074ED96341B  Horse.gltf
0CFD85DDFCC5C07CAF1BDEB296B21017B0DA4C8558A92086DAF4A172E0BF8D97  Husky.gltf
3236979B94A840EB72D9CE091B1361DA327A96F5CE068E666680297480F30F6B  ShibaInu.gltf
170B964909D16D1AB4D428B1D714F25016913D32481ACD9C3D62923192583BE6  Stag.gltf
CC02E9D128B5715F352EE8BEA086F97A35F1D875D240DE99B0F9F2775C37D415  Wolf.gltf
0202789CAD8C1DEBB8AE5B4A47D1A5D2E5F93A0875878BC0B05A80E42AE37E8D  FBX/Cow.fbx
6DB270DDC7591E9A013F96EAB445031381FA6D5D68D2FEBA567F964E0FE68D90  FBX/Horse.fbx (not used, see below)
3FF44FD03D5793701B228CF88F00E776F89AFEFDB3DE0B226FEE807908AE79C9  FBX/Llama.fbx
BDF5E149A974FFC2431546F30EA568D7C41F916D7BD87187F1532C45778A9A23  FBX/Pig.fbx
C05E127A5B10EDD059478113F542F691717635B47D7A57317D07E7310A764FF0  FBX/Pug.fbx
4A3FC559CC9F37E3E3F216AF1DAB30CB411EC9B268EB98676F1D5C18A430D33E  FBX/Sheep.fbx
ECBFE34A4D1F5F0695D573E04F0287B03F8F37B8E4DDBF37F7EA9737063AE200  FBX/Zebra.fbx
```

## What was dropped

Both packs have a Cow and a Horse. For the horse the pack keeps the Animals pack's (richer, about
2000 triangles with eyes and hooves, and the same rig and clip set as the White horse and the
others); the Farm pack's brown horse (about 700 triangles) is not shipped. For the cow the pack
ships both: the Animals pack's brown cow (`cow`, pairs with the Bull) and, at the owner's request
(2026-11-01), the Farm pack's black-and-white Holstein as `cow_holstein`. Clips
dropped from every model: walk, run, gallop, jump variants, attacks, eating and the idle variants
(tt-sim moves tokens by sliding them, and the tree plays only four clips).

## Files in the pack (SHA-256)

```
ba25e037ec86b967e9dedf03f0a8d74f22aa85d869171ba9541afba6dbef58d5  models/alpaca.glb
8529b4b8444f60675c6d137e8afcdc424fde07a53299bcd2db6e7da8babe7f41  models/bull.glb
3b0d6363483fa4fb534bd9caf3140872a5d71c14c116a5c68c9ebdadb9481f69  models/cow.glb
3f5cb047e6142cae89d84b9e25bbde870fc37d34d90ce4457f7db1190a80b6fe  models/deer.glb
ffade5e682689272eeab04c75a17d3ab08f395f68b7f0f64eb1d8abff79ad308  models/donkey.glb
5e5f1b177341a7bbe7319d5b84f340aaed2698cdc031f2fc2bdb567f32bbb68d  models/fox.glb
b11ab7cc71617bc78cc2062209712c9fbc06f8b57ba063a6fd90aca928d829bd  models/cow_holstein.glb
b84ed017dac0bd7e2b6fb4494e2a99b3badc721abc580b0a923d11f0eaa51643  models/horse.glb
7bbcede3c3022ce989fa94a3d80c8c6f297bf1f6ae14d7ebd0e64388eef12415  models/horse_white.glb
45381a370643b0b584352de3a93b0656c9b7ab1d6c7555e1546c3aabaf7d2782  models/husky.glb
831fb3e0e5d35a08ea67f2307996c4fc94b9af8e5fb7e77ef8f4ac3e5fad4bf0  models/llama.glb
ee18cf24c043d106e1b534ceba41e1d6c232d67e038f61aaea7add4d9ff9bdaa  models/pig.glb
7fd92a8a94906fc68df6bc97ce23922a5ed1059c1ec2a830888d4962c7c40f07  models/pug.glb
3107e7eb522209a2633a454be03d8861f45a976d9ae2426c1b2c116b6dd0804c  models/sheep.glb
fab8d2cc3e360f08dbefcfd32b27a71e7a2c42eb3933bdd2de53a739ce5b7f50  models/shiba_inu.glb
705dbfcfc74159699cd95ebd965fa530a3aa3d110325038ba430511b3e6b63a7  models/stag.glb
087785237fa5f1d0d52fd60bc18a4086db2eb693cf633f87181a84935e6e1873  models/wolf.glb
cce03f4f31c62b6399b721b8a29840182bccb54b44bbf633a7db5c956bb35a4b  models/zebra.glb
```

The icons (`icons/<id>.png`, 128 px, transparent, rendered by
`tools/roster/render_icons.gd --yaw -50` from the game camera's angle) are regenerable and not
hashed. Total 7.0 MB in Git LFS (18 GLBs 6.8 MB, 18 icons 0.17 MB).

## Scale

tt-sim applies no token scale (`docs/ASSET_PIPELINE.md` sections 2 and 7: 1 unit is 1 metre, a grid
cell is 1.524 m), and the sources are at an arbitrary modeller scale. Each GLB's root node therefore
carries a uniform scale and offset that make the animal stand on y = 0, centred, at a real-world
height (head, antlers and raised neck included, from the skinned rest pose;
`tools/roster/beast_recipes.gd`): horse and white horse 2.1 m, stag 1.9 m, llama 1.8 m, bull 1.6 m,
cow, Holstein cow, zebra and alpaca 1.5 m, donkey and deer 1.4 m, sheep 1.0 m, pig 0.9 m, wolf 0.85 m,
husky 0.65 m, fox and Shiba Inu 0.5 m, pug 0.4 m. No manifest field is needed.

## Animation

The tree (`scenes/board_token/board_token_animation_tree.tscn`) plays clips by fixed names. The
build keeps `Idle` as `battlewait01` (the tree loops it at run time: glTF has no loop flag),
`Idle_HitReact1` (Animals pack) or `Jump` (Farm pack) as `damage01`, and `Death` as
`down01_start` and `down01`. The Farm pack's llama, pig, pug and sheep have no death clip, so a
token of those reduced to 0 health has no down animation. The idle's playing and looping was
checked in a render job (`tools/render_jobs/probes/rosterbeasts.gd`): the tree's position
advanced and wrapped at the clip length (3.33 s) and the skeleton pose changed between samples.
