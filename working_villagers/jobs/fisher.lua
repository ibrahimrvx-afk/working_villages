-- Fisher job v2
-- * Finds a proper land-edge-to-water fishing spot (ground level only, not floating)
-- * Stands still, faces water, waits, then adds fish directly to inventory
-- * Never picks up water buckets or liquid nodes
-- * Uses fishing mod API if available, otherwise simulates catch directly
-- * Deposits fish to chest when full

local func = working_villages.require("jobs/util")
local pathfinder = working_villages.require("pathfinder")

local searching_range = {x=24, y=3, z=24}

-- ---------------------------------------------------------------
-- Fish item registry: known raw fish items across common mods
-- No water buckets, no liquid items, only actual fish food items
-- ---------------------------------------------------------------
local known_fish = {
	"fishing:fish_raw",
	"fishing:pike_raw",
	"fishing:perch_raw",
	"fishing:catfish_raw",
	"fishing:trout_raw",
	"fishing:bass_raw",
	"fishing:salmon_raw",
	"animalia:fish_raw",
	"animalia:salmon_raw",
	"mobs:fish_raw",
	"mobs_fish:fish",
	"petz:fish_raw",
	"ethereal:fish_raw",
	"fish:fish",
}

-- Build a lookup for fast checking
local fish_lookup = {}
for _, n in ipairs(known_fish) do fish_lookup[n] = true end

local function is_fish_item(item)
	local name = type(item) == "table" and item.name or tostring(item)
	-- Exact match first
	if fish_lookup[name] then return true end
	-- Never match water/liquid related items
	if string.find(name, "water") or string.find(name, "bucket") or
	   string.find(name, "liquid") or string.find(name, "lava") then
		return false
	end
	-- Pattern: ends with _raw and contains fish
	if string.find(name, "fish") and string.find(name, "_raw") then return true end
	return false
end

-- ---------------------------------------------------------------
-- Water detection (only proper liquid source/flowing nodes)
-- ---------------------------------------------------------------
local function is_water_node(pos)
	local node = minetest.get_node(pos)
	if node.name == "air" or node.name == "ignore" then return false end
	local def = minetest.registered_nodes[node.name]
	if not def then return false end
	-- Must be liquid but NOT lava
	return def.liquidtype ~= nil and def.liquidtype ~= "none"
	       and not string.find(node.name, "lava")
end

-- ---------------------------------------------------------------
-- Find fishing spot: a ground-level land tile adjacent to water
-- Returns: spot_pos, water_direction_vec
-- ---------------------------------------------------------------
local function find_fishing_spot(center, range)
	local cx = math.floor(center.x)
	local cy = math.floor(center.y)
	local cz = math.floor(center.z)

	for r = 1, math.max(range.x, range.z) do
		for dx = -r, r do
		for dz = -r, r do
			if math.abs(dx) == r or math.abs(dz) == r then
				for dy = -range.y, range.y do
					local land = {x=cx+dx, y=cy+dy, z=cz+dz}
					local land_node  = minetest.get_node(land)
					local above_node = minetest.get_node({x=land.x, y=land.y+1, z=land.z})
					local above2_node= minetest.get_node({x=land.x, y=land.y+2, z=land.z})

					-- Land tile must be solid ground
					if not pathfinder.walkable(land_node) then goto continue end
					-- Must have clear space above to stand
					if pathfinder.walkable(above_node) then goto continue end
					if pathfinder.walkable(above2_node) then goto continue end
					-- The node above the land must NOT be water (we stand on land)
					if is_water_node(above_node) then goto continue end

					-- Check the 4 cardinal horizontal neighbours at standing height
					-- for water adjacency
					local standing = {x=land.x, y=land.y+1, z=land.z}
					local dirs4 = {
						{x=1,y=0,z=0}, {x=-1,y=0,z=0},
						{x=0,y=0,z=1}, {x=0,y=0,z=-1},
					}
					for _, d in ipairs(dirs4) do
						local check = vector.add(standing, d)
						if is_water_node(check) then
							-- Found a valid spot: land tile with water at standing-eye level
							return land, d
						end
						-- Also accept water one block below standing level
						local check_low = {x=check.x, y=check.y-1, z=check.z}
						if is_water_node(check_low) then
							return land, d
						end
					end

					::continue::
				end
			end
		end
		end
	end
	return nil, nil
end

-- ---------------------------------------------------------------
-- Catch simulation
-- Uses fishing mod hook if available, otherwise direct inventory add
-- ---------------------------------------------------------------
local function do_fishing(self)
	-- Try fishing mod API first (fishing mod by TenPlus1 / PilzAdam)
	if minetest.registered_items["fishing:rod"] and rawget(_G, "fishing") and fishing.do_fishing then
		pcall(function() fishing.do_fishing(self) end)
	end

	-- Always also do direct simulation so villager always catches something
	-- 45% base catch chance per session
	if math.random(100) <= 45 then
		local inv = self:get_inventory()
		-- Find first registered fish item and add it
		for _, fname in ipairs(known_fish) do
			if minetest.registered_items[fname] then
				local stack = ItemStack(fname .. " 1")
				if inv:room_for_item("main", stack) then
					inv:add_item("main", stack)
					self:set_state_info("Caught a fish! 🐟")
					return true
				end
			end
		end
	else
		self:set_state_info("Nothing this time... trying again.")
	end
	return false
end

-- ---------------------------------------------------------------
-- put / take functions for chest
-- ---------------------------------------------------------------
local function put_func(_, stack)
	return is_fish_item(stack:get_name())
end
local function take_func() return false end

-- ---------------------------------------------------------------
-- Count fish in inventory
-- ---------------------------------------------------------------
local function count_fish(self)
	local inv = self:get_inventory()
	local n = 0
	for _, item in ipairs(inv:get_list("main")) do
		if is_fish_item(item:get_name()) then
			n = n + item:get_count()
		end
	end
	return n
end

-- ---------------------------------------------------------------
-- Job registration
-- ---------------------------------------------------------------
working_villages.register_job("working_villages:job_fisher", {
	description      = "fisher (working_villages)",
	long_description = "I find a water edge, fish there patiently, and deposit my catch to a chest.",
	inventory_image  = "default_paper.png^working_villages_farmer.png",
	jobfunc = function(self)
		self:handle_night()
		self:handle_chest(take_func, put_func)
		self:handle_job_pos()

		self:count_timer("fisher:search")
		self:count_timer("fisher:cast")
		self:handle_obstacles()

		local pos  = self.object:get_pos()
		local area = self.job_data and self.job_data.work_area or nil

		-- Deposit when carrying 6+ fish
		if count_fish(self) >= 6 then
			self:set_state_info("Full basket! Heading to chest.")
			self.job_data.manipulated_chest = false
			self:handle_chest(take_func, put_func)
			return
		end

		-- Find a fishing spot if we don't have one, or recheck every ~200 ticks
		if self:timer_exceeded("fisher:search", 200) or not self.job_data.fishing_spot then
			local center = (area and area.center) or pos
			local range  = area and {x=area.radius, y=3, z=area.radius} or searching_range
			local spot, water_dir = find_fishing_spot(center, range)

			if spot then
				self.job_data.fishing_spot  = spot
				self.job_data.water_dir     = water_dir
				self:set_state_info("Found a fishing spot, heading there.")
				self:go_to(spot)
			else
				self:set_state_info("No water nearby, wandering...")
				self:change_direction_randomly()
			end
		end

		-- Fish at the spot
		if self.job_data.fishing_spot and self:timer_exceeded("fisher:cast", 80) then
			local spot = self.job_data.fishing_spot

			-- Walk to spot if not already there
			if not self:is_near(spot, 1.5) then
				self:go_to(spot)
				return
			end

			-- Stop moving, face the water
			self.object:set_velocity({x=0, y=0, z=0})
			if self.job_data.water_dir then
				self:set_yaw_by_direction(self.job_data.water_dir)
			end

			-- Cast animation: stand still and use MINE anim as "casting"
			self:set_animation(working_villages.animation_frames.MINE)
			self:set_state_info("Casting line... 🎣")

			-- Wait: simulate waiting for a bite (2–5 second pause)
			local wait_ticks = 40 + math.random(0, 60)
			for _ = 0, wait_ticks do coroutine.yield() end

			-- Attempt catch
			do_fishing(self)

			-- Reset animation
			self:set_animation(working_villages.animation_frames.STAND)

			-- Occasionally move to a different spot to seem more natural
			if math.random(5) == 1 then
				self.job_data.fishing_spot = nil
			end
		end
	end,
})
