local recipesByMod = {}

for recipeName, recipe in pairs(prototypes.recipe) do
	if not recipe.is_parameter then
		local mod = prototypes.get_history("recipe", recipeName).created
		assert(mod ~= nil)
		if recipesByMod[mod] == nil then recipesByMod[mod] = {} end
		table.insert(recipesByMod[mod], recipe)
	end
end

---@param recipe LuaRecipePrototype
local function recipeToStr(recipe)
	-- Print out the recipe in a format like "category: 2 iron-ore + 1 sulfuric-acid -> 1 iron-plate + 20% 0-5 sulfur"
	local r = (recipe.category or "crafting") .. ": "
	--log(recipe.name)
	--log(serpent.block(recipe))
	for i, ingredient in pairs(recipe.ingredients) do
		if ingredient.amount ~= 1 then r = r .. ingredient.amount .. " " end
		r = r .. ingredient.name
		if i < #recipe.ingredients then r = r .. " + " end
	end
	r = r .. " -> "
	for i, result in pairs(recipe.products or {}) do
		if result.probability ~= 1 then
			r = r .. result.probability * 100 .. "% "
		end
		if result.extra_count_fraction ~= nil and result.extra_count_fraction ~= 0 then
			r = r .. "(+" .. result.extra_count_fraction * 100 .. "%) "
		end
		if result.amount ~= nil and result.amount ~= 1 then
			r = r .. result.amount .. " "
		end
		if result.amount_min ~= nil then
			r = r .. result.amount_min .. "-" .. result.amount_max .. " "
		end
		r = r .. result.name
		if i < #recipe.products then r = r .. " + " end
	end
	return r
end

local output = ""

for mod, recipes in pairs(recipesByMod) do
	output = output .. "\n" .. mod .. ":\n"
	for _, recipe in pairs(recipes) do
		output = output .. "  " .. recipeToStr(recipe) .. "\n"
	end
end

helpers.write_file("RecipesByMod.txt", output)
