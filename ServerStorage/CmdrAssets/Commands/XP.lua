return {
	Name = "SetXP",
	Aliases = {"Level", "SetLevel"},
	Description = "Adds XP to selected players.",
	Group = "Admin",
	Args = {
		{
			Type = "player", -- Oyuncu seçtirecegiz
			Name = "Target",
			Description = "The selected players gets more XP."
		},
		{
			Type = "number", -- Sayi isteyecegiz
			Name = "Amount",
			Description = "Amount of XP"
		}
	}
}