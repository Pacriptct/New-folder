-- ReplicatedStorage.Packages.CharacterCreator.Config
--
-- Drives the character creator. Asset lists themselves are NOT defined
-- here — they're discovered at runtime from
-- ReplicatedStorage.CharacterAssets so dropping a new hair / eye /
-- brow into the folder makes it selectable without a config edit.
--
-- This config holds:
--   * height / weight ranges + scaling math
--   * fixed colour palettes
--   * birthplaces and which horse each grants
--   * Robux developer product IDs for paid rerolls

local CharacterCreatorConfig = {}

------------------------------------------------------------
-- Height / weight rolling
------------------------------------------------------------

CharacterCreatorConfig.Height = {
	Min = 58,
	Max = 76,
}

CharacterCreatorConfig.Weight = {
	Min = 100,
	Max = 220,
}

CharacterCreatorConfig.Scaling = {
	HeightBase = 0.9,
	HeightSpread = 0.25,
	WidthBase = 0.9,
	WidthSpread = 0.25,
	HeadBase = 1,
}

------------------------------------------------------------
-- Birthplaces (each maps to a horse)
------------------------------------------------------------

CharacterCreatorConfig.Birthplaces = {
	Shiganshina = { DisplayName = "Shiganshina", Horse = "RuralStallion" },
	Trost       = { DisplayName = "Trost",       Horse = "MerchantSteed"  },
	Karanes     = { DisplayName = "Karanes",     Horse = "MountainPony"   },
	Stohess     = { DisplayName = "Stohess",     Horse = "NobleMare"      },
}

CharacterCreatorConfig.BirthplaceOrder = {
	"Shiganshina",
	"Trost",
	"Karanes",
	"Stohess",
}

------------------------------------------------------------
-- Sexes
------------------------------------------------------------

CharacterCreatorConfig.Sexes = { "Male", "Female" }

------------------------------------------------------------
-- Colour palettes
------------------------------------------------------------

CharacterCreatorConfig.SkinTones = {
	Pale  = Color3.fromRGB(238, 215, 191),
	Fair  = Color3.fromRGB(222, 188, 156),
	Tan   = Color3.fromRGB(196, 152, 110),
	Olive = Color3.fromRGB(168, 128, 92),
	Brown = Color3.fromRGB(120, 82, 55),
	Deep  = Color3.fromRGB(74, 48, 33),
}

CharacterCreatorConfig.HairColors = {
	Brown  = Color3.fromRGB(92, 60, 35),
	Black  = Color3.fromRGB(20, 20, 20),
	Blonde = Color3.fromRGB(220, 185, 90),
	Red    = Color3.fromRGB(145, 55, 35),
	White  = Color3.fromRGB(230, 230, 230),
}

CharacterCreatorConfig.EyeColors = {
	Brown = Color3.fromRGB(90, 55, 30),
	Blue  = Color3.fromRGB(70, 130, 210),
	Green = Color3.fromRGB(60, 150, 90),
	Gray  = Color3.fromRGB(145, 145, 145),
	Amber = Color3.fromRGB(200, 135, 40),
}

------------------------------------------------------------
-- Asset folder names. Discovered at runtime by scanning these
-- folders inside ReplicatedStorage.CharacterAssets.
------------------------------------------------------------

CharacterCreatorConfig.AssetFolders = {
	Eyes        = "Eyes",
	Brows       = "Eyebrows",
	Noses       = "Noses",
	Mouths      = "Mouths",
	Hairs       = "Hairs",        -- contains Male / Female / Unisex subfolders
	Accessories = "Accessories",  -- optional
	FacePart    = "Face",         -- single instance, cloned onto head
}

------------------------------------------------------------
-- Robux developer products for paid rerolls.
--
-- Replace each with the real developer product ID. Server's
-- ProcessReceipt rolls a fresh value on purchase and pushes it back
-- to the client. ID 0 disables the corresponding reroll button.
------------------------------------------------------------

CharacterCreatorConfig.RollProducts = {
	Height     = 0,
	Weight     = 0,
	Birthplace = 0,
}

CharacterCreatorConfig.RollPriceLabels = {
	Height     = "Reroll Height",
	Weight     = "Reroll Weight",
	Birthplace = "Reroll Birthplace",
}

------------------------------------------------------------
-- Name validation
------------------------------------------------------------

CharacterCreatorConfig.Name = {
	MinLength = 2,
	MaxLength = 16,
}

------------------------------------------------------------
-- Default colour selections (per-asset defaults are picked from the
-- runtime manifest by index 1).
------------------------------------------------------------

CharacterCreatorConfig.Defaults = {
	Sex       = "Male",
	HairColor = { Base = "Brown", Tone = 0.5 },
	EyeColor  = { Base = "Brown", Tone = 0.5 },
	SkinTone  = { Base = "Fair",  Tone = 0.5 },
}

return CharacterCreatorConfig
