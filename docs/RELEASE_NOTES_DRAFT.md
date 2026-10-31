# Release notes (DRAFT)

**DRAFT. Not for publication until the owner approves.** Nothing is tagged, versioned or released;
this page only collects what changed. The version number is not decided (see
`docs/RELEASE_CHECKLIST.md`, "Version decision"). Compiled 2026-10-31 from the history since
the last release, v0.3.0 (2026-10-25): 173 commits in this repository.

Items marked TODO could not be verified from the repositories and need the owner before
publication.

---

## For players

### Build whole villages

Pick the Buildings tool and place houses, cottages, townhouses, barns, towers and halls with a
click or a drag. The palette now holds 100 buildings, in styles from many places and moods:

- Cottages and houses: thatched, turf-roofed, log, half-timber, stone, stucco, adobe and
  pueblo, alpine chalets, porch and veranda cottages.
- Town buildings: canal houses, Dutch stepped and bell gables, mansard townhouses, Tudor
  townhouses with overhanging upper floors, brick terraces.
- Big and grand: castle keeps, gatehouses, bartizan towers, chapels, market halls, pagodas.
- Round and stacked: roundhouses, yurts, tulou, trulli, stilt houses on piles, windmills.
- Courtyard buildings: coaching inn, farmstead, riad and courtyard houses.
- A cheerful toon set (cafe, clinic, gym, lab, lighthouse, hall) and a fantasy set (wizard
  tower, crystal spire, elven hall, treehouse, mushroom cottage, dwarven gatehall, ice lodge).
- Ruins of cottages, chapels, barns and towers.

Click a building to select it, then drag its handles to resize, move it, change its floors or
re-roll its look. Search the palette by name.

### Dress your buildings

A selected building has a Decorate row: ivy, flower boxes, window planters, banners, awnings,
weathervanes, signs, rose windows, towers and buttresses. Press Surprise me for a
combination, or switch each on and off. Ivy and window planters are real plants now, and they
grow around windows and doors without covering them.

### Streets and villages

Draw a street and it fills with a row of varied buildings. There are 11 kinds of street, from
mixed rows and terraces to alpine hamlets, canal rows, Tudor lanes, pueblo villages and
minka villages, and each lot is painted from its street's colour palette. Use Dress this
street to scatter small props along it: barrels, crates, benches, wells, lamp posts, market
stalls, carts, washing lines, haystacks, scarecrows and more (18 props in all).

### A wind that blows through everything

There is now one wind. Grass, trees and ivy sway with it, rain and snow slant with it,
windmills turn their caps into it and spin their sails with it, and banners, awnings and
washing lines flutter in it. The Weather pane has new controls: Calm, Breezy, Windy and
Storm, a compass to pick the direction (or leave it on Auto), and a button for a fresh gust
pattern. If motion bothers you, Settings (Graphics) has a Wind motion slider from 0 to
100 percent.

### Smoother and quicker

Large maps with many buildings load faster, in stages, so the table appears sooner and stays
responsive while buildings finish appearing. Adding a building next to others is cheaper, and
painting buildings and street props is quicker.

### Easier to find your way

Every tool icon on the left rail now has a short tooltip. The Buildings tool shows key hints
and live reasons when a spot will not work (you can bring the hints back from the pane), and
the place-another flow keeps your palette open so you can lay a whole row of buildings.

### Accessibility

Motion follows the system Reduce motion setting: wind streaks, flutter and interface motion
become gentler or hold still.

### Fixes

- Players joining a game now wait for the buildings to stand before the table opens.
- Ivy rows no longer form a visible grid; they vary in size, turn and overlap.
- Buildings no longer have banners and ornaments buried inside their towers.
- Tudor jetties, steep cone roofs and domes read properly (course lines and undersides).
- Several loading and launcher problems with the building tools were fixed.

### Please note

Everyone at the table must run exactly the same game version to join, so each player needs to
update.

---

## For map authors

### The Building tool

Buildings are real library content now: the core library has 100 placeable buildings and 18
props, each with a thumbnail, and the tool lays them on your terrain. A building adapts to its
ground (a yard, a worn path, shrubs, flower beds and stepping stones), keeps scatter away, and
can be saved with your map. Styles are grouped by kind and material in the palette; sizes
respect each style's own limits so a building stays well-formed.

### Streets and settlements

The Street tool offers all 11 street kinds. A street's lots take their palette from the street,
and a street clears a corridor in the scatter. Dress this street adds props to the street's
frontage and the gaps between buildings: props follow the ground slope, merge their surfaces
to stay cheap, and lean slightly with the wind where they are cloth.

### Wind and weather

Wind is part of the level environment: the Weather pane sets strength and direction, and the
Wind motion setting scales how much movement each player sees. Windmill sails and caps, vanes,
banners, awnings and prop cloth all read it.

### The structures editor (structgen)

A separate editor for authoring building styles as a node graph, with a live 3D preview.
Click any piece of a building and the editor selects the node that made it. A style gallery
shows a picture of every building style, and a Decorate row previews the ornaments. One click
on Add to game library places your structure in your own "My structures" collection (it asks
once the first time). TODO: confirm with the owner that structgen is meant to be mentioned
to authors in these notes, since it is a separate tool and not part of the game download.

### Library and licence

The built-in Core library ships with the game and is licensed under Creative Commons
Attribution 4.0 (CC BY 4.0). If you use or redistribute its content (models, textures,
thumbnails, biomes), give credit with this line:

> Core library by Hannah Shore, CC BY 4.0

The licence text is at https://creativecommons.org/licenses/by/4.0/ . The game shows the
licence on the library's detail page in the collections manager. The game itself is not
covered by this licence. TODO: state the game's own terms once the owner decides them (the
repository has no licence file for the game today).

---

## Known issues

- Street props are small at the default (home) camera distance; zoom in to enjoy them.
- The lantern on lamp posts does not glow yet.
- Streets have no painted ground: a street gets no road or paving automatically, so paint it
  by hand for now. Plazas and a ground-paint pass for streets are planned.
- Wind covers plants, weather, windmills, vanes and cloth; effects such as drifting smoke,
  dust and water chop are not built.
- Some wind motion on cloth reads strongly at storm strength when you are very close.
- TODO: downloading a map over Steam (host sending a map with buildings to a Steam client) has
  not been tested end to end this cycle. Do not announce Steam map download until the
  checklist run is done.
- The Core library is still versioned 1.0.0-dev.
