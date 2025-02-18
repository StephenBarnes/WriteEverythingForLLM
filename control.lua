
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
local subgroupMembers = {}
for _, subgroups in pairs(groupsToSubgroups) do
	for _, subgroup in pairs(subgroups) do
		subgroupMembers[subgroup.name] = {item = {}, fluid = {}, recipe = {}, entity = {}}
	end
end
for _, k in pairs{"item", "fluid", "recipe", "entity"} do
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
	if tech.research_unit_ingredients ~= nil then
		return ("%010d"):format(#(tech.research_unit_ingredients or {}) or 2) .. ("%010d"):format(tech.research_unit_count or 1e6)
	end
	return ("%010d"):format((#(tech.prerequisites or {}) or 1) * 1e6)
end
table.sort(technologies, function(a, b)
	return getTechOrder(a) < getTechOrder(b)
end)

------------------------------------------------------------------------
--- FUNCTIONS TO WRITE GROUPS/SUBGROUPS/ITEMS/ETC TO FILE

local function write(locstr)
	helpers.write_file("WriteEverythingForLLM.txt", locstr, true)
end

local function ingredientOrResultName(thing)
	if thing.type == "item" then
		return prototypes.item[thing.name].localised_name
	elseif thing.type == "fluid" then
		return prototypes.fluid[thing.name].localised_name
	end
end

---@param recipe LuaRecipePrototype
local function writeRecipeSummary(recipe)
	-- Write the recipe in a format like "category: 2 iron-ore + 1 sulfuric-acid -> 1 iron-plate + 20% 0-5 sulfur"
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
		write("\tCraftable in: " .. recipe.category .. "\n")
	end
end

local function outputItem(item)
	if item.hidden or item.hidden_in_factoriopedia or item.parameter then return end
	write{"", "* Item: ", item.localised_name, "\n"}
end

local function outputFluid(fluid)
	if fluid.hidden or fluid.hidden_in_factoriopedia or fluid.parameter then return end
	write{"", "* Fluid: ", fluid.localised_name, "\n"}
end

local function outputRecipe(recipe)
	if recipe.hidden or recipe.hidden_in_factoriopedia or recipe.parameter then return end
	write{"", "* Recipe: ", recipe.localised_name, "\n"}
	writeRecipeSummary(recipe)
end

local function outputEntity(entity)
	if entity.hidden or entity.hidden_in_factoriopedia then return end
	write{"", "* Entity: ", entity.localised_name, "\n"}
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

local function subgroupAlsoHasRecipe(thing)
	local recipe = prototypes.recipe[thing.name]
	if recipe ~= nil and recipe.subgroup == thing.subgroup and not (recipe.hidden or recipe.hidden_in_factoriopedia) then
		return true
	end
	return false
end

local function outputSubgroup(subgroup, group)
	-- Write out a subgroup's items/fluids/recipes/entities.
	-- If the subgroup has no members, don't write anything.
	if not subgroupHasMembers(subgroup) then return end
	write{"", group.localised_name, " subgroup ", subgroup.name, " containing:\n"}
	-- Write out all items/etc, except don't print out multiple rows for item/entity/recipe of the same thing.
	local members = subgroupMembers[subgroup.name]
	for _, item in pairs(members.item) do
		if not subgroupAlsoHasRecipe(item) then
			outputItem(item)
		end
	end
	for _, fluid in pairs(members.fluid) do
		if not subgroupAlsoHasRecipe(fluid) then
			outputFluid(fluid)
		end
	end
	for _, recipe in pairs(members.recipe) do
		outputRecipe(recipe)
	end
	for _, entity in pairs(members.entity) do
		if not subgroupAlsoHasRecipe(entity) then
			outputEntity(entity)
		end
	end
end

local function outputGroup(group)
	if not groupHasMembers(group) then return end
	write{"", "GROUP: ", group.localised_name, "\n"}
	for _, subgroup in pairs(groupsToSubgroups[group.name]) do
		outputSubgroup(subgroup, group)
	end
	write{"", "End of group: ", group.localised_name, "\n\n\n"}
end

------------------------------------------------------------------------
--- MAIN

helpers.write_file("WriteEverythingForLLM.txt", "", false) -- False says to not append, so we remove text from the file.

for _, group in pairs(groups) do
	outputGroup(group)
end