extends RefCounted

## The Folk pack's roster: one recipe per figure, read by tools/roster/build_folk.gd.
##
## The free "Standard" downloads of Quaternius's Universal Base Characters and Modular Character
## Outfits - Fantasy hold two bodies (a male and a female), two outfits per body (Peasant and
## Ranger, each with extra texture colourways: Peasant 1 and 2, Ranger 1 and 3) and six
## hairstyles. A figure is a body, an outfit with a colourway, optional outfit accessories, a
## hairstyle, and two tints applied as the material's albedo colour: the packs ship one skin tone
## and grey hair cards (their own shader tints them), so skin and hair colour are material tints,
## not repainted textures.
##
## Fields: id (file name), name (shown in the picker), sex ("Male" or "Female"), outfit
## ("Peasant" or "Ranger"), colourway (1 to 3, the outfit texture), hood, pauldron (Ranger
## accessories), hair (a Hair_* style, "" for none), beard (adds the Hair_Beard mesh), skin and
## hair_colour (keys of SKIN_TINTS and HAIR_TINTS).

const SKIN_TINTS := {
	"fair": Color(1.0, 1.0, 1.0),
	"tan": Color(0.86, 0.72, 0.6),
	"brown": Color(0.64, 0.45, 0.34),
	"deep": Color(0.45, 0.3, 0.23),
}

const HAIR_TINTS := {
	"black": Color(0.16, 0.14, 0.14),
	"brown": Color(0.42, 0.27, 0.16),
	"auburn": Color(0.72, 0.33, 0.15),
	"blond": Color(0.95, 0.78, 0.4),
	"grey": Color(0.82, 0.82, 0.84),
}

const RECIPES: Array[Dictionary] = [
	{
		"id": "villager_man",
		"name": "Villager (man)",
		"sex": "Male",
		"outfit": "Peasant",
		"colourway": 1,
		"hair": "Hair_SimpleParted",
		"skin": "fair",
		"hair_colour": "brown",
	},
	{
		"id": "farmhand_man",
		"name": "Farmhand (man)",
		"sex": "Male",
		"outfit": "Peasant",
		"colourway": 2,
		"hair": "Hair_Buzzed",
		"skin": "tan",
		"hair_colour": "black",
	},
	{
		"id": "elder_man",
		"name": "Elder (man)",
		"sex": "Male",
		"outfit": "Peasant",
		"colourway": 1,
		"hair": "Hair_SimpleParted",
		"beard": true,
		"skin": "fair",
		"hair_colour": "grey",
	},
	{
		"id": "labourer_man",
		"name": "Labourer (man)",
		"sex": "Male",
		"outfit": "Peasant",
		"colourway": 2,
		"hair": "Hair_Buzzed",
		"beard": true,
		"skin": "deep",
		"hair_colour": "black",
	},
	{
		"id": "woodsman_man",
		"name": "Woodsman (man)",
		"sex": "Male",
		"outfit": "Ranger",
		"colourway": 1,
		"hair": "Hair_SimpleParted",
		"beard": true,
		"skin": "tan",
		"hair_colour": "auburn",
	},
	{
		"id": "scout_man",
		"name": "Scout (man)",
		"sex": "Male",
		"outfit": "Ranger",
		"colourway": 1,
		"hood": true,
		"pauldron": true,
		"skin": "fair",
		"hair_colour": "brown",
	},
	{
		"id": "hunter_man",
		"name": "Hunter (man)",
		"sex": "Male",
		"outfit": "Ranger",
		"colourway": 3,
		"pauldron": true,
		"hair": "Hair_Long",
		"skin": "brown",
		"hair_colour": "black",
	},
	{
		"id": "wanderer_man",
		"name": "Wanderer (man)",
		"sex": "Male",
		"outfit": "Ranger",
		"colourway": 3,
		"hood": true,
		"skin": "deep",
		"hair_colour": "black",
	},
	{
		"id": "villager_woman",
		"name": "Villager (woman)",
		"sex": "Female",
		"outfit": "Peasant",
		"colourway": 1,
		"hair": "Hair_Buns",
		"skin": "fair",
		"hair_colour": "brown",
	},
	{
		"id": "farmhand_woman",
		"name": "Farmhand (woman)",
		"sex": "Female",
		"outfit": "Peasant",
		"colourway": 2,
		"hair": "Hair_Long",
		"skin": "tan",
		"hair_colour": "blond",
	},
	{
		"id": "matron_woman",
		"name": "Matron (woman)",
		"sex": "Female",
		"outfit": "Peasant",
		"colourway": 1,
		"hair": "Hair_Buns",
		"skin": "brown",
		"hair_colour": "grey",
	},
	{
		"id": "herbalist_woman",
		"name": "Herbalist (woman)",
		"sex": "Female",
		"outfit": "Peasant",
		"colourway": 2,
		"hair": "Hair_BuzzedFemale",
		"skin": "deep",
		"hair_colour": "black",
	},
	{
		"id": "ranger_woman",
		"name": "Ranger (woman)",
		"sex": "Female",
		"outfit": "Ranger",
		"colourway": 1,
		"hair": "Hair_Long",
		"skin": "fair",
		"hair_colour": "auburn",
	},
	{
		"id": "scout_woman",
		"name": "Scout (woman)",
		"sex": "Female",
		"outfit": "Ranger",
		"colourway": 1,
		"hood": true,
		"pauldron": true,
		"skin": "brown",
		"hair_colour": "brown",
	},
	{
		"id": "huntress_woman",
		"name": "Huntress (woman)",
		"sex": "Female",
		"outfit": "Ranger",
		"colourway": 3,
		"pauldron": true,
		"hair": "Hair_Buns",
		"skin": "tan",
		"hair_colour": "blond",
	},
	{
		"id": "wanderer_woman",
		"name": "Wanderer (woman)",
		"sex": "Female",
		"outfit": "Ranger",
		"colourway": 3,
		"hood": true,
		"skin": "deep",
		"hair_colour": "black",
	},
]
