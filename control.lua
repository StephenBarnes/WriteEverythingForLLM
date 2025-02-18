local FILENAME = "ExportFactoriopediaForLLM.txt"

------------------------------------------------------------------------
--- BUILD LISTS OF ALL GROUPS AND THEIR SUBGROUPS, ETC.

-- Make list of all groups in order they're shown.
local groups = {}
for _, group in pairs(prototypes.item_group) do
	table.insert(groups, group)
end
table.sort(groups, function(a, b)
	return a.order < b.order
end)

-- Make list from each group to all its subgroups, sorted by order.
local groupsToSubgroups = {}
for _, group in pairs(groups) do groupsToSubgroups[group.name] = {} end
for _, subgroup in pairs(prototypes.item_subgroup) do
	table.insert(groupsToSubgroups[subgroup.group.name], subgroup)
end
for _, subgroups in pairs(groupsToSubgroups) do
	table.sort(subgroups, function(a, b)
		return a.order < b.order
	end)
end

-- For each subgroup, make a list of all items/fluids/recipes/entities in it.
local kinds = {"item", "fluid", "recipe", "entity", "space_location", "space_connection"}
local subgroupMembers = {}
for _, subgroups in pairs(groupsToSubgroups) do
	for _, subgroup in pairs(subgroups) do
		subgroupMembers[subgroup.name] = {}
		for _, k in pairs(kinds) do
			subgroupMembers[subgroup.name][k] = {}
		end
	end
end
for _, k in pairs(kinds) do
	for _, thing in pairs(prototypes[k]) do
		if thing.subgroup ~= nil then
			table.insert(subgroupMembers[thing.subgroup.name][k], thing)
		end
	end
	for subgroupName, things in pairs(subgroupMembers) do
		table.sort(things[k], function(a, b)
			return a.order < b.order
		end)
	end
end

-- Make a list of all technologies.
local technologies = {}
for _, technology in pairs(prototypes.technology) do
	table.insert(technologies, technology)
end
-- Roughly sort the techs by how late-game they are.
---@param tech LuaTechnologyPrototype
local function getTechOrder(tech)
	if tech.order ~= "" then return tech.order end
	if tech.research_unit_ingredients ~= nil and #(tech.research_unit_ingredients) > 0 then
		return ("%02d"):format(#(tech.research_unit_ingredients or {}) or 2) .. ("%08d"):format(tech.research_unit_count or 1e6)
	end
	-- If we reach this point, it's a trigger tech, so use prereqs.
	if table_size(tech.prerequisites) == 0 then
		return "0"
	else
		for _, prereq in pairs(tech.prerequisites) do
			return getTechOrder(prereq) .. "-2"
		end
	end
end
table.sort(technologies, function(a, b)
	return getTechOrder(a) < getTechOrder(b)
end)

------------------------------------------------------------------------
--- FUNCTIONS TO WRITE GROUPS/SUBGROUPS/ITEMS/ETC TO FILE

local function recursiveLength(l)
	if type(l) ~= "table" then return 1 end
	local count = 0
	for _, v in pairs(l) do
		count = count + recursiveLength(v)
	end
	return count
end

-- Function that writes a string, with localisation for item names etc. Argument should be either one string, or a list of strings where the first one is "" (meaning the rest are concatenated).
local function write(locstr)
	if type(locstr) == "table" then
		assert(recursiveLength(locstr) < 20, "Localised-string writing is limited to 20 items at a time. Broken by: " .. serpent.block(locstr or "nil"))
	end
	helpers.write_file(FILENAME, locstr, true)
end

-- Uses the "?" operator (built into Factorio's localised-string system) to write a string only if all of the localised strings in it exist, otherwise does nothing.
local function writeIfExists(locstr)
	write{"?", locstr, ""}
end

local function ingredientOrResultName(thing)
	if thing.type == "item" then
		return prototypes.item[thing.name].localised_name
	elseif thing.type == "fluid" then
		return prototypes.fluid[thing.name].localised_name
	else
		assert(false, "Invalid thing type: " .. serpent.block(thing))
	end
end

---@param recipe LuaRecipePrototype
local function writeRecipeSummary(recipe)
	-- Write the recipe in a format like "category: 2 Iron ore + 1 Sulfuric acid -> 1 Iron plate + 20% 0-5 Sulfur"
	write("\t")
	for i, ingredient in pairs(recipe.ingredients) do
		write{"", ingredient.amount, " ", ingredientOrResultName(ingredient)}
		if i < #recipe.ingredients then write(" + ") end
	end
	write(" -> ")
	for i, result in pairs(recipe.products or {}) do
		if result.probability ~= 1 then
			write(result.probability * 100 .. "% ")
		end
		if result.extra_count_fraction ~= nil and result.extra_count_fraction ~= 0 then
			write("(+" .. result.extra_count_fraction * 100 .. "%) ")
		end
		if result.amount ~= nil then
			write(result.amount .. " ")
		end
		if result.amount_min ~= nil then
			write(result.amount_min .. "-" .. result.amount_max .. " ")
		end
		write(ingredientOrResultName(result))
		if i < #recipe.products then write(" + ") end
	end
	write("\n")

	-- Write the recipe category if it's not crafting or crafting-with-fluid.
	if recipe.category ~= nil and recipe.category ~= "crafting" and recipe.category ~= "crafting-with-fluid" then
		write("\tCrafting machine category: " .. recipe.category .. "\n")
	end
end

local function timeString(ticks)
	if ticks == 0 then return "(zero)" end
	local seconds = ticks / 60
	local minutes = math.floor(seconds / 60)
	seconds = seconds % 60
	if seconds > 0 then
		return minutes .. " minutes and " .. seconds .. " seconds"
	else
		return minutes .. " minutes"
	end
end

---@param item LuaItemPrototype
local function outputItem(item)
	if item.hidden or item.hidden_in_factoriopedia or item.parameter then return end
	write{"", "* Item: ", item.localised_name, "\n"}
	if item.spoil_result ~= nil then
		write{"", "\tSpoils to ", item.spoil_result.localised_name, " after " .. timeString(item.get_spoil_ticks()) .. "\n"}
	elseif item.spoil_to_trigger_result ~= nil then
		write("\tSpoils after " .. timeString(item.get_spoil_ticks()) .. " to trigger event.\n")
	end
	writeIfExists{"", "\tDescription: ", item.localised_description, "\n"}
end

local function outputFluid(fluid)
	if fluid.hidden or fluid.hidden_in_factoriopedia or fluid.parameter then return end
	write{"", "* Fluid: ", fluid.localised_name, "\n"}
	writeIfExists{"", "\tDescription: ", fluid.localised_description, "\n"}
end

local function outputRecipe(recipe)
	if recipe.hidden or recipe.hidden_in_factoriopedia or recipe.parameter then return end
	write{"", "* Recipe: ", recipe.localised_name, "\n"}
	writeRecipeSummary(recipe)
	writeIfExists{"", "\tDescription: ", recipe.localised_description, "\n"}
end

---@param entity LuaEntityPrototype
local function maybeOutputEntityMinable(entity)
	if not entity.mineable_properties.minable then return end
	local mineProducts = entity.mineable_properties.products
	if mineProducts == nil or #mineProducts == 0 then return end
	if #mineProducts == 1 and mineProducts[1].name == entity.name and mineProducts[1].amount == 1 then
		-- The entity is the only product, so don't bother printing results.
		return
	end
	write{"", "\tMined for: "}
	for i, product in pairs(mineProducts) do
		if product.type ~= "research-progress" then
			local localisedName = ingredientOrResultName(product)
			if product.probability ~= nil and product.probability ~= 1 then
				write(product.probability * 100 .. "% ")
			end
			if product.amount ~= nil then
				write{"", product.amount .. " ", localisedName}
			else
				write{"", product.amount_min .. "-" .. product.amount_max .. " ", localisedName}
			end
			if i < #mineProducts then write(" + ") end
		end
	end
	write("\n")
end

---@param entity LuaEntityPrototype
local function maybeOutputEntityCraftingCategories(entity)
	if entity.crafting_categories == nil or table_size(entity.crafting_categories) == 0 then return end
	write("\tCan craft categories: ")
	local i = 1
	for category, _ in pairs(entity.crafting_categories) do
		if category ~= "parameters" then
			if i > 1 then
				write(", ")
			end
			write(category)
			i = i + 1
		end
	end
	write("\n")
end

---@param entity LuaEntityPrototype
local function outputEntity(entity)
	if entity.hidden or entity.hidden_in_factoriopedia then return end
	write{"", "* Entity: ", entity.localised_name, "\n"}
	writeIfExists{"", "\tDescription: ", entity.localised_description, "\n"}
	maybeOutputEntityMinable(entity)
	maybeOutputEntityCraftingCategories(entity)
end

---@param spaceLocation LuaSpaceLocationPrototype
local function maybeOutputPlanetAutoplaces(spaceLocation)
	local mgs = spaceLocation.map_gen_settings
	if mgs == nil then return end
	local autoplaceSettings = mgs.autoplace_settings
	if autoplaceSettings == nil then return end
	-- This has .decorative, .tile, .entity. Ignoring decoratives.
	local ents = autoplaceSettings.entity.settings
	if ents ~= nil then
		write("\tNaturally occurring entities on this planet: ")
		local i = 1
		for entName, _ in pairs(ents) do
			if i > 1 then
				write(", ")
			end
			write(prototypes.entity[entName].localised_name)
			i = i + 1
		end
		write(".\n")
	end
	local tiles = autoplaceSettings.tile.settings
	if tiles ~= nil then
		write("\tNaturally occurring tiles on this planet: ")
		local i = 1
		for tileName, _ in pairs(tiles) do
			if i > 1 then
				write(", ")
			end
			local tile = prototypes.tile[tileName]
			write(tile.localised_name)
			if tile.fluid ~= nil then
				write{"", " (provides fluid ", tile.fluid.localised_name, ")"}
			end
			i = i + 1
		end
		write(".\n")
	end
end

---@param spaceLocation LuaSpaceLocationPrototype
local function outputSpaceLocation(spaceLocation)
	if spaceLocation.hidden or spaceLocation.hidden_in_factoriopedia then return end
	write{"", "* Space location: ", spaceLocation.localised_name, "\n"}
	writeIfExists{"", "\tDescription: ", spaceLocation.localised_description, "\n"}
	maybeOutputPlanetAutoplaces(spaceLocation)
end

---@param spaceConnection LuaSpaceConnectionPrototype
local function outputSpaceConnection(spaceConnection)
	if spaceConnection.hidden or spaceConnection.hidden_in_factoriopedia then return end
	write{"", "* Space connection: ", spaceConnection.localised_name, "\n"}
	write{"", "\tLength: " .. spaceConnection.length .. "km\n"}
	writeIfExists{"", "\tDescription: ", spaceConnection.localised_description, "\n"}
end

local function subgroupHasMembers(subgroup)
	for _, things in pairs(subgroupMembers[subgroup.name]) do
		for _, thing in pairs(things) do
			if not (thing.hidden or thing.hidden_in_factoriopedia or thing.parameter) then
				return true
			end
		end
	end
	return false
end

local function groupHasMembers(group)
	for _, subgroup in pairs(groupsToSubgroups[group.name]) do
		if subgroupHasMembers(subgroup) then return true end
	end
	return false
end

local function outputSubgroup(subgroup, group)
	-- Write out a subgroup's items/fluids/recipes/entities.
	-- If the subgroup has no members, don't write anything.
	if not subgroupHasMembers(subgroup) then return end
	write{"", "Group \"", group.localised_name, "\" has subgroup \"", subgroup.name, "\" containing:\n"}

	-- Write out all items/etc, attempting to group item/entity/recipe together.
	local members = subgroupMembers[subgroup.name]
	local alreadyPrinted = {}
	for _, kind in pairs(kinds) do
		alreadyPrinted[kind] = {}
	end

	for _, item in pairs(members.item) do
		outputItem(item)
		local entity = prototypes.entity[item.name]
		if entity ~= nil and not (entity.hidden or entity.hidden_in_factoriopedia) and entity.subgroup.name == subgroup.name then
			outputEntity(entity)
			alreadyPrinted.entity[entity.name] = true
		end
		local recipe = prototypes.recipe[item.name]
		if recipe ~= nil and not (recipe.hidden or recipe.hidden_in_factoriopedia) and recipe.subgroup.name == subgroup.name then
			outputRecipe(recipe)
			alreadyPrinted.recipe[recipe.name] = true
		end
	end
	for _, fluid in pairs(members.fluid) do
		outputFluid(fluid)
		local recipe = prototypes.recipe[fluid.name]
		if recipe ~= nil and not (recipe.hidden or recipe.hidden_in_factoriopedia) and recipe.subgroup.name == subgroup.name then
			outputRecipe(recipe)
			alreadyPrinted.recipe[recipe.name] = true
		end
	end
	for _, entity in pairs(members.entity) do
		if not alreadyPrinted.entity[entity.name] then
			outputEntity(entity)
		end
	end
	for _, recipe in pairs(members.recipe) do
		if not alreadyPrinted.recipe[recipe.name] then
			outputRecipe(recipe)
		end
	end
	for _, spaceLocation in pairs(members.space_location) do
		outputSpaceLocation(spaceLocation)
	end
	for _, spaceConnection in pairs(members.space_connection) do
		outputSpaceConnection(spaceConnection)
	end
end

local function outputGroup(group)
	if not groupHasMembers(group) then
		write{"", "GROUP: ", group.localised_name, " - entries omitted as there are no items/recipes/entities/etc.\n\n"}
		return
	end
	write{"", "GROUP: ", group.localised_name, "\n"}
	for _, subgroup in pairs(groupsToSubgroups[group.name]) do
		outputSubgroup(subgroup, group)
	end
	write{"", "End of group: ", group.localised_name, "\n\n"}
end

---@param technology LuaTechnologyPrototype
local function outputTechnology(technology)
	write{"", "* Technology: ", technology.localised_name, "\n"}
	writeIfExists{"", "\tDescription: ", technology.localised_description, "\n"}
	write("\tPrerequisites: ")
	if table_size(technology.prerequisites) == 0 then
		write("None.\n")
	else
		local i = 1
		for name, prereqTech in pairs(technology.prerequisites) do
			if i > 1 then
				write(", ")
			end
			write(prereqTech.localised_name)
			i = i + 1
		end
		write(".\n")
	end
	for _, effect in pairs(technology.effects) do
		if effect.type == "unlock-recipe" then
			local recipe = prototypes.recipe[effect.recipe]
			write{"", "\tUnlocks recipe: ", recipe.localised_name, "\n"}
		else
			write("\tNon-recipe-unlock effect of type " .. effect.type .. "\n")
		end
	end
end

------------------------------------------------------------------------
--- MAIN

helpers.write_file(FILENAME, "", false) -- False says to not append, so we remove text from the file.

write("This file contains information about prototypes that exist in the user's Factorio game, arranged by groups and subgroups. For every subgroup there is a complete list of all items, fluids, recipes, entities, and space locations/connections in that subgroup. This is followed by a list of all technologies and the recipes they unlock.\n\nOften an item is crafted using a recipe with the same name as the item. Some items represent buildings/structures; the player can place these items in the Factorio world to create entities with the same name.\n\n")

write("There are " .. table_size(groups) .. " groups: \"")
local i = 1
for _, group in pairs(groups) do
	if i > 1 then
		write("\", \"")
	end
	write(group.localised_name)
	i = i + 1
end
write("\".\n\n")

for _, group in pairs(groups) do
	outputGroup(group)
end

write("There are " .. table_size(technologies) .. " technologies, listed below:\n")
for _, technology in pairs(technologies) do
	outputTechnology(technology)
end