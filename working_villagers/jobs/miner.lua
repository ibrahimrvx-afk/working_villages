-- Miner job: digs ore veins and stone out of the ground, deposits
-- ores/minerals to a chest while keeping its pick and food.
--
-- Behaviour:
--  * Searches a box around the villager for ore-bearing stone first
--    (anything in the "stone" group whose name looks like an ore,
--    e.g. "default:stone_with_iron", "mcl_core:stone_with_coal", ...).
--  * If no ore is found nearby, it will tunnel through plain stone
--    instead, slowly carving out a mine.
--  * Avoids protected areas and remembers positions it failed to
--    reach/dig for a few minutes (same mechanism the woodcutter uses)
--    so it doesn't get stuck retrying the same spot forever.
--  * Deposits everything except its pickaxe and food into the nearest
--    assigned chest.

local func = working_villages.require("jobs/util")

-- Nodes that should never be dug even though they're in the "stone"
-- group (ex: cobble/stone walls placed by players as part of a build).
-- Kept intentionally small; rely on protection + failed_pos memory for
-- the rest.
local ignored_stone = {
	["default:stonebrick"]  = true,
	["default:stone_block"] = true,
	["default:desert_stonebrick"] = true,
}

local function is_ore(name)
	if ignored_stone[name] then return false end
	if minetest.get_item_group(name, "stone") == 0
			and minetest.get_item_group(name, "ore") == 0 then
		return false
	end
	return (string.find(name, "_with_") ~= nil) or (string.find(name, "ore") ~= nil)
end

local function is_plain_stone(name)
	if ignored_stone[name] then return false end
	if is_ore(name) then return false end
	return minetest.get_item_group(name, "stone") > 0
		or minetest.get_item_group(name, "cracky") > 0
end

local function find_ore(p)
	local node = minetest.get_node(p)
	if not is_ore(node.name) then return false end
	if minetest.is_protected(p, "") then return false end
	if working_villages.failed_pos_test(p) then return false end
	return true
end

local function find_stone(p)
	local node = minetest.get_node(p)
	if not is_plain_stone(node.name) then return false end
	if minetest.is_protected(p, "") then return false end
	if working_villages.failed_pos_test(p) then return false end
	return true
end

local function put_func(_, stack)
	local name = stack:get_name()
	if (minetest.get_item_group(name, "pickaxe") ~= 0)
			or (minetest.get_item_group(name, "food") ~= 0) then
		return false
	end
	return true
end
local function take_func(self, stack, data)
	return not put_func(self, stack, data)
end

local searching_range = {x = 12, y = 8, z = 12, h = 6}

local function dig_target(self, target, action_text)
	local destination = func.find_adjacent_clear(target)
	if destination ~= false then
		destination = func.find_ground_below(destination) or destination
	end
	if destination == false then
		destination = target
	end
	self:set_displayed_action(action_text)
	local success, _ = self:go_to(destination)
	if not success then
		working_villages.failed_pos_record(target)
		self:set_displayed_action("confused about how to reach the rock")
		self:delay(100)
		return
	end
	success = self:dig(target, true)
	if not success then
		working_villages.failed_pos_record(target)
		self:set_displayed_action("confused as to why digging failed")
		self:delay(100)
	end
end

working_villages.register_job("working_villages:job_miner", {
	description      = "miner (working_villages)",
	long_description = "I search nearby stone for ore veins and dig them out.\
If I can't find any ore I'll tunnel through plain stone instead.\
I'll bring anything I find back to my chest, but I keep my pick and some food on me.",
	inventory_image  = "default_paper.png^working_villages_miner.png",
	jobfunc = function(self)
		self:handle_night()
		self:handle_chest(take_func, put_func)
		self:handle_job_pos()

		self:count_timer("miner:search")
		self:count_timer("miner:change_dir")
		self:handle_obstacles()
		if self:timer_exceeded("miner:search", 20) then
			local target = func.search_surrounding(self.object:get_pos(), find_ore, searching_range)
			if target ~= nil then
				dig_target(self, target, "mining an ore vein")
			else
				target = func.search_surrounding(self.object:get_pos(), find_stone, searching_range)
				if target ~= nil then
					dig_target(self, target, "tunneling through stone")
				end
			end
			self:set_displayed_action("looking for work")
		elseif self:timer_exceeded("miner:change_dir", 50) then
			self:change_direction_randomly()
		end
	end,
})
