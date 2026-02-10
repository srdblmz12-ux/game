return {
	Name = "SetToken",
	Aliases = {"Token", "SetCash"},
	Description = "Adds token to selected players.",
	Group = "Admin",
	Args = {
		{
			Type = "player", -- Oyuncu seçtirecegiz
			Name = "Target",
			Description = "The selected players will get tokens."
		},
		{
			Type = "number", -- Sayi isteyecegiz
			Name = "Amount",
			Description = "Amount of token"
		}
	}
}