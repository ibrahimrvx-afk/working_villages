-- Chickener job v2:
-- * Collect eggs from ground
-- * Hatch eggs when chicken count is low
-- * Breed chickens using seeds when population allows
-- * Kill EXCESS chickens (above max) and collect drops
-- * Collect raw chicken from ground
-- * Deposit raw chicken + feathers to chest

local func = working_villages.require("jobs/util")
local pathfinder = working_villages.require("pathfinder")

local searching_range = {x = 16, y = 4, z = 16}

-- Seed items for breeding
local breeding_seeds = {
	"farming:seed_wheat", "farming:wheat", "farming:seed_barley",
	"default:grass", "default:dry_grass", "farming:seed_rice",
	"mcl_farming:wheat_item", "seeds:seed_wheat",
}

local function is_egg_item(name)
	return name == "animalia:chicken_egg" or
	       name == "mobs:egg" or
	       name == "mob_core:egg" or
	       (string.find(name, "_egg") ~= nil and string.find(name, "chicken") ~= nil) or
	       name:find("egg") ~= nil
end

local function is_raw_chicken(name)
	return name == "animalia:raw_chicken" or
	       name == "mobs:chicken_raw" or
	       name == "mob_core:chicken_raw" or
	       name:find("raw_chicken") ~= nil or
	       name:find("chicken_raw") ~= nil
end

local function is_feather(name)
	return name:find("feather") ~= nil
end

local function is_chicken_entity(ename)
	return ename == "animalia:chicken" or
	       ename == "mobs:chicken" or
	       ename:find("chicken") ~= nil
end

local function is_seed_item(name)
	for _, s in ipairs(breeding_seeds) do
		if name == s then return true end
	end
	return false
end

-- Get all chicken objects in range
local function get_chickens_in_range(pos, range)
	local chickens = {}
	local objects = minetest.get_objects_in_area(
		vector.subtract(pos, vector.new(range.x, range.y, range.z)),
		vector.add(pos, vector.new(range.x, range.y, range.z))
	)
	for _, obj in ipairs(objects) do
		local le = obj:get_luaentity()
		if le and is_chicken_entity(le.name) then
			table.insert(chickens, obj)
		end
	end
	return chickens
end

local function find_item_on_ground(pos, range, cond)
	local objects = minetest.get_objects_in_area(
		vector.subtract(pos, vector.new(range.x, range.y, range.z)),
		vector.add(pos, vector.new(range.x, range.y, range.z))
	)
	for _, obj in ipairs(objects) do
		local le = obj:get_luaentity()
		if le and le.name == "__builtin:item" then
			if cond(le.itemstring or "") then return obj end
		end
	end
	return nil
end

local function count_eggs_in_inv(self)
	local inv = self:get_inventory()
	local count = 0
	for _, item in ipairs(inv:get_list("main")) do
		if is_egg_item(item:get_name()) then count = count + item:get_count() end
	end
	return count
end

local function count_raw_chicken_in_inv(self)
	local inv = self:get_inventory()
	local count = 0
	for _, item in ipairs(inv:get_list("main")) do
		if is_raw_chicken(item:get_name()) then count = count + item:get_count() end
	end
	return count
end

local function has_seed(self)
	local inv = self:get_inventory()
	for _, item in ipairs(inv:get_list("main")) do
		if is_seed_item(item:get_name()) and item:get_count() > 0 then
			return item:get_name()
		end
	end
	return nil
end

local function remove_one_seed(self, seed_name)
	local inv = self:get_inventory()
	inv:remove_item("main", ItemStack(seed_name .. " 1"))
end

-- Hatch an egg
local function hatch_egg(self)
	local inv = self:get_inventory()
	for i, item in ipairs(inv:get_list("main")) do
		local iname = item:get_name()
		if is_egg_item(iname) and item:get_count() > 0 then
			local pos = self.object:get_pos()
			if iname == "animalia:chicken_egg" then
				minetest.add_entity(pos, "animalia:chicken")
			elseif iname == "mobs:egg" then
				minetest.add_entity(pos, "mobs:chicken")
			else
				local entity_name = iname:gsub("_egg$", "")
				if minetest.registered_entities[entity_name] then
					minetest.add_entity(pos, entity_name)
				end
			end
			inv:remove_item("main", ItemStack(iname .. " 1"))
			self:set_state_info("Hatching an egg! 🐣")
			return true
		end
	end
	return false
end

-- Kill a chicken and collect drops
local function kill_chicken(self, chicken_obj)
	if not chicken_obj or not chicken_obj:get_luaentity() then return end
	local cpos = chicken_obj:get_pos()
	if not cpos then return end
	self:go_to(cpos)

	-- Re-check after moving (chicken may have moved/despawned)
	local le = chicken_obj:get_luaentity()
	if not le then return end

	-- Always remove directly and add drops manually.
	-- We do NOT call on_punch with the villager because mods like creatura/animalia
	-- expect a real player ObjectRef with get_pos() as the puncher, which the
	-- villager entity table is not.
	local drop_pos = chicken_obj:get_pos() or cpos
	chicken_obj:remove()

	-- Add drops directly to villager inventory
	local inv = self:get_inventory()
	local drop_candidates = {
		"animalia:raw_chicken",
		"mobs:chicken_raw",
		"mob_core:chicken_raw",
	}
	for _, iname in ipairs(drop_candidates) do
		if minetest.registered_items[iname] then
			local stack = ItemStack(iname .. " 1")
			if inv:room_for_item("main", stack) then
				inv:add_item("main", stack)
			else
				minetest.add_item(drop_pos, stack)
			end
			break
		end
	end
	-- Feathers are intentionally discarded (not collected)
	self:set_state_info("Culling excess chicken.")
end

-- Try to breed two nearby chickens using seeds.
-- We cannot call on_rightclick(self) because animalia/creatura expect a real
-- player ObjectRef. Instead we use animalia's trust/feed API if available,
-- or fall back to spawning a new chick directly (simulating a successful breed).
local function try_breed(self, chickens, seed_name)
	if #chickens < 2 then return false end
	local c1 = chickens[1]
	local c2 = chickens[2]
	if not c1 or not c2 then return false end

	self:go_to(c1:get_pos())
	remove_one_seed(self, seed_name)

	local le1 = c1:get_luaentity()
	local le2 = c2:get_luaentity()

	-- Try animalia feed API (increases trust/saturation, may trigger breed)
	-- These calls are pcall-wrapped so any incompatibility is silent
	if le1 and le1.feed then
		pcall(function() le1:feed() end)
	end
	if le2 and le2.feed then
		pcall(function() le2:feed() end)
	end

	-- Regardless of API result, directly spawn a baby chicken after a short delay
	-- to guarantee breeding actually happens (villager "assisted" the breeding)
	local spawn_pos = c1:get_pos()
	if spawn_pos then
		minetest.after(2, function()
			-- Spawn as a baby if the entity supports it, otherwise normal
			local baby_names = {
				"animalia:chicken",
				"mobs:chicken",
			}
			for _, bname in ipairs(baby_names) do
				if minetest.registered_entities[bname] then
					local chick = minetest.add_entity(spawn_pos, bname)
					if chick then
						local ble = chick:get_luaentity()
						-- Try to set baby/child state via animalia API
						if ble then
							if ble.growth_stage ~= nil then
								ble.growth_stage = 1  -- animalia baby
							elseif ble.child ~= nil then
								ble.child = true  -- mobs_redo baby
							end
						end
					end
					break
				end
			end
		end)
	end

	self:set_state_info("Breeding chickens! 💕")
	return true
end

local function put_func(_, stack)
	local name = stack:get_name()
	return is_raw_chicken(name) or is_egg_item(name)
end
local function take_func(_, stack)
	return is_seed_item(stack:get_name())
end

working_villages.register_job("working_villages:job_chickener", {
	description      = "chickener (working_villages)",
	long_description = "I collect eggs, hatch them, breed chickens with seeds from chest, cull excess chickens, collect raw chicken and feathers, deposit to chest.",
	inventory_image  = "default_paper.png^working_villages_farmer.png",
	jobfunc = function(self)
		self:handle_night()
		self:handle_chest(take_func, put_func)
		self:handle_job_pos()

		self:count_timer("chickener:search")
		self:count_timer("chickener:hatch")
		self:count_timer("chickener:breed")
		self:count_timer("chickener:cull")
		self:count_timer("chickener:feed")
		self:handle_obstacles()

		local pos = self.object:get_pos()
		local max_chickens = (self.job_data and self.job_data.max_chickens) or 8
		local min_chickens = (self.job_data and self.job_data.min_chickens) or 3

		-- Deposit when carrying lots of raw chicken
		if count_raw_chicken_in_inv(self) >= 8 then
			self:set_state_info("Bag full! Heading to chest.")
			self.job_data.manipulated_chest = false
			self:handle_chest(take_func, put_func)
			return
		end

		-- Collect eggs from ground
		if self:timer_exceeded("chickener:search", 10) then
			local egg_obj = find_item_on_ground(pos, searching_range, is_egg_item)
			if egg_obj then
				self:go_to(egg_obj:get_pos())
				self:pickup_item()
				self:set_state_info("Collecting egg from ground!")
			else
				-- Collect raw chicken from ground
				local meat_obj = find_item_on_ground(pos, searching_range, is_raw_chicken)
				if meat_obj then
					self:go_to(meat_obj:get_pos())
					self:pickup_item()
					self:set_state_info("Collecting raw chicken!")
				end
			end
		end

		local chickens = get_chickens_in_range(pos, searching_range)
		local chicken_count = #chickens

		-- HATCH eggs when population is low
		if self:timer_exceeded("chickener:hatch", 40) then
			local egg_count = count_eggs_in_inv(self)
			if egg_count > 0 and chicken_count < min_chickens then
				hatch_egg(self)
			elseif egg_count > 6 then
				-- Too many eggs piling up, hatch regardless
				hatch_egg(self)
			end
		end

		-- RANDOMLY FEED nearby chickens wheat seeds (just for fun/mood, not breeding)
		self:count_timer("chickener:feed")
		if self:timer_exceeded("chickener:feed", 60 + math.random(0, 60)) then
			if chicken_count > 0 and math.random(1, 3) == 1 then
				-- Pick a random chicken to walk to and "feed"
				local target_chicken = chickens[math.random(1, chicken_count)]
				if target_chicken and target_chicken:get_luaentity() then
					local cpos = target_chicken:get_pos()
					if cpos then
						self:go_to(cpos)
						-- Face the chicken
						local dir = vector.subtract(cpos, self.object:get_pos())
						if vector.length(dir) > 0 then
							self:set_yaw_by_direction(dir)
						end
						self:set_animation(working_villages.animation_frames.MINE)
						self:set_state_info("Feeding a chicken some seeds! 🌾")
						for _ = 0, 20 do coroutine.yield() end
						self:set_animation(working_villages.animation_frames.STAND)
						-- Consume one seed from inventory if available
						local seed = has_seed(self)
						if seed then
							remove_one_seed(self, seed)
						end
					end
				end
			end
		end

		-- BREED chickens when population is moderate
		if self:timer_exceeded("chickener:breed", 80) then
			if chicken_count >= 2 and chicken_count < max_chickens then
				local seed = has_seed(self)
				if seed then
					try_breed(self, chickens, seed)
				else
					-- Try to take seeds from chest
					self.job_data.manipulated_chest = false
					self:handle_chest(take_func, put_func)
				end
			end
		end

		-- CULL excess chickens
		if self:timer_exceeded("chickener:cull", 100) then
			if chicken_count > max_chickens then
				-- Kill the furthest chicken from center
				local furthest = nil
				local furthest_dist = -1
				for _, c in ipairs(chickens) do
					local cp = c:get_pos()
					local d = vector.distance(pos, cp)
					if d > furthest_dist then
						furthest_dist = d
						furthest = c
					end
				end
				if furthest then
					kill_chicken(self, furthest)
				end
			end
		end

		-- Idle wander
		if self:timer_exceeded("chickener:search", 80) then
			self:change_direction_randomly()
		end
	end,
})
