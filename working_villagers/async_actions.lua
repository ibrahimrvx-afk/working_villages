local fail = working_villages.require("failures")
local log = working_villages.require("log")
local func = working_villages.require("jobs/util")
local pathfinder = working_villages.require("pathfinder")

local BASE_SPEED    = 2.0   -- default walk speed
local ARRIVE_DIST   = 0.7   -- XZ distance to consider waypoint reached
local STUCK_TICKS   = 55    -- ticks on same waypoint before declaring stuck
local REPATH_TICKS  = 60    -- ticks between periodic re-path checks

-- ---------------------------------------------------------------
-- Chest position validation + reachability helper
-- ---------------------------------------------------------------
local function is_clear_standing(pos)
	local n  = minetest.get_node(pos)
	local n1 = minetest.get_node({x=pos.x, y=pos.y+1, z=pos.z})
	local nf = minetest.get_node({x=pos.x, y=pos.y-1, z=pos.z})
	return not pathfinder.walkable(n) and
	       not pathfinder.walkable(n1) and
	       pathfinder.walkable(nf)
end

local function resolve_chest_approach(chest_pos, villager_pos)
	if not chest_pos then return nil, nil end
	local node = minetest.get_node(chest_pos)
	if node.name == "air" or node.name == "ignore" then return nil, nil end
	local is_chest = (node.name == "default:chest" or
	                  node.name == "default:chest_locked" or
	                  minetest.get_item_group(node.name, "chest") > 0)
	if not is_chest then return nil, nil end

	-- Search in a 5x5 area around the chest for a clear reachable standing pos.
	-- Prioritise cells closest to the chest (Manhattan distance).
	local candidates = {}
	for dx = -2, 2 do
		for dz = -2, 2 do
			if not (dx == 0 and dz == 0) then
				local p = {x=chest_pos.x+dx, y=chest_pos.y, z=chest_pos.z+dz}
				local priority = math.abs(dx) + math.abs(dz)
				if is_clear_standing(p) then
					table.insert(candidates, {pos=p, pri=priority})
				end
				local pa = {x=p.x, y=p.y+1, z=p.z}
				if is_clear_standing(pa) then
					table.insert(candidates, {pos=pa, pri=priority+0.5})
				end
			end
		end
	end

	table.sort(candidates, function(a,b) return a.pri < b.pri end)

	-- Prefer a cell the pathfinder can actually reach from the villager
	if villager_pos and #candidates > 0 then
		for _, c in ipairs(candidates) do
			local path = pathfinder.find_path(
				func.validate_pos(villager_pos), c.pos, nil, nil)
			if path and #path > 0 then
				return chest_pos, c.pos
			end
		end
	end

	if #candidates > 0 then
		return chest_pos, candidates[1].pos
	end

	return chest_pos, {x=chest_pos.x+1, y=chest_pos.y, z=chest_pos.z}
end

-- ---------------------------------------------------------------
-- go_to: smooth pathing with continuous re-path and stuck escape
-- ---------------------------------------------------------------
function working_villages.villager:go_to(pos)
	self.destination = vector.round(pos)
	if func.walkable_pos(self.destination) then
		self.destination = pathfinder.get_ground_level(vector.round(self.destination))
	end

	local area = self.job_data and self.job_data.work_area or nil
	local val_pos = func.validate_pos(self.object:get_pos())
	self.path = pathfinder.find_path(val_pos, self.destination, self, area)

	self:set_timer("go_to:repath",   0)
	self:set_timer("go_to:give_up",  0)
	self:set_timer("go_to:stuck",    0)
	self._stuck_pos = nil
	self._stuck_count = 0

	if self.path == nil or #self.path == 0 then
		self.path = {self.destination}
	end

	-- Face first waypoint
	local dir0 = vector.subtract(self.path[1], self.object:get_pos())
	dir0.y = 0
	if vector.length(dir0) > 0.1 then
		self:set_yaw_by_direction(dir0)
	end
	self.object:set_velocity({
		x = dir0.x ~= 0 and (dir0.x/math.abs(dir0.x+0.001)) * BASE_SPEED or 0,
		y = 0,
		z = dir0.z ~= 0 and (dir0.z/math.abs(dir0.z+0.001)) * BASE_SPEED or 0,
	})
	self:set_animation(working_villages.animation_frames.WALK)

	while #self.path ~= 0 do
		self:count_timer("go_to:repath")
		self:count_timer("go_to:stuck")

		local wp  = self.path[1]
		local cur = self.object:get_pos()

		-- ---- Stuck detection ----
		local cur_rounded = vector.round(cur)
		if self._stuck_pos and vector.equals(cur_rounded, self._stuck_pos) then
			self._stuck_count = self._stuck_count + 1
		else
			self._stuck_pos  = cur_rounded
			self._stuck_count = 0
		end

		if self._stuck_count >= STUCK_TICKS then
			-- Escape: random-angle jump nudge
			local angle = math.random() * math.pi * 2
			local spd = (self.job_data and self.job_data.wander_speed or BASE_SPEED) * 1.8
			self.object:set_velocity({
				x = math.cos(angle) * spd,
				y = 3.5,
				z = math.sin(angle) * spd,
			})
			self._stuck_count = 0
			self._stuck_pos   = nil
			for _ = 0, 15 do coroutine.yield() end
			self.object:set_velocity({x=0, y=0, z=0})
			-- Full re-path from new position
			val_pos = func.validate_pos(self.object:get_pos())
			local escaped = pathfinder.find_path(val_pos, self.destination, self, area)
			if escaped and #escaped > 0 then
				self.path = escaped
			end
			self:set_timer("go_to:repath", 0)
		end

		-- ---- Continuous re-path every REPATH_TICKS ----
		-- This catches cases where the pre-calculated path became invalid
		-- (e.g. a block was placed, or the villager drifted off path)
		if self:timer_exceeded("go_to:repath", REPATH_TICKS) then
			val_pos = func.validate_pos(self.object:get_pos())
			if func.walkable_pos(self.destination) then
				self.destination = pathfinder.get_ground_level(vector.round(self.destination))
			end
			local newpath = pathfinder.find_path(val_pos, self.destination, self, area)
			if newpath == nil then
				self:count_timer("go_to:give_up")
				if self:timer_exceeded("go_to:give_up", 4) then
					self.object:set_velocity({x=0, y=0, z=0})
					self:set_animation(working_villages.animation_frames.STAND)
					return false, fail.no_path
				end
			else
				self.path = newpath
				self._stuck_count = 0
			end
		end

		-- ---- Smooth velocity toward current waypoint ----
		local speed = self.job_data and self.job_data.wander_speed or BASE_SPEED
		local dx = wp.x - cur.x
		local dz = wp.z - cur.z
		local horiz_dist = math.sqrt(dx*dx + dz*dz)

		if horiz_dist > 0.05 then
			-- Scale speed: slow down as we approach waypoint to avoid overshoot
			local factor = math.min(1.0, horiz_dist / 0.8)
			local vx = (dx / horiz_dist) * speed * factor
			local vz = (dz / horiz_dist) * speed * factor

			-- Smooth facing: only update yaw when direction differs enough
			local cur_vel = self.object:get_velocity()
			local vel_diff = math.abs(vx - (cur_vel.x or 0)) + math.abs(vz - (cur_vel.z or 0))
			if vel_diff > 0.3 then
				self:set_yaw_by_direction({x=dx, y=0, z=dz})
			end

			self.object:set_velocity({x=vx, y=cur_vel.y, z=vz})
		end

		-- ---- Waypoint arrival ----
		if horiz_dist <= ARRIVE_DIST then
			table.remove(self.path, 1)
			self._stuck_count = 0
			if #self.path == 0 then
				coroutine.yield()
				break
			else
				-- Immediately steer toward next waypoint
				local nwp = self.path[1]
				local nd = vector.subtract(nwp, cur)
				nd.y = 0
				if vector.length(nd) > 0.1 then
					self:set_yaw_by_direction(nd)
				end
				self:set_timer("go_to:repath", 0)
			end
		end

		self:handle_obstacles(true)
		coroutine.yield()
	end

	self.object:set_velocity({x=0, y=0, z=0})
	self.path = nil
	self._stuck_count = 0
	self:set_animation(working_villages.animation_frames.STAND)
	return true
end

-- ---------------------------------------------------------------
-- collect_nearest_item_by_condition
-- ---------------------------------------------------------------
function working_villages.villager:collect_nearest_item_by_condition(cond, searching_range)
	local item = self:get_nearest_item_by_condition(cond, searching_range)
	if item == nil then return false end
	local pos = item:get_pos()
	local inv = self:get_inventory()
	if inv:room_for_item("main", ItemStack(item:get_luaentity().itemstring)) then
		self:go_to(pos)
		self:pickup_item()
	end
end

-- ---------------------------------------------------------------
-- delay
-- ---------------------------------------------------------------
function working_villages.villager:delay(step_count)
	for _ = 0, step_count do coroutine.yield() end
end

local drop_range = {x=2, y=10, z=2}

-- ---------------------------------------------------------------
-- dig
-- ---------------------------------------------------------------
function working_villages.villager:dig(pos, collect_drops)
	if func.is_protected(self, pos) then return false, fail.protected end
	self.object:set_velocity({x=0, y=0, z=0})
	local dist = vector.subtract(pos, self.object:get_pos())
	if vector.length(dist) > 5 then
		self:set_animation(working_villages.animation_frames.STAND)
		return false, fail.too_far
	end
	self:set_animation(working_villages.animation_frames.MINE)
	self:set_yaw_by_direction(dist)
	for _ = 0, 30 do coroutine.yield() end
	local destnode = minetest.get_node(pos)
	local def_node = minetest.registered_items[destnode.name]
	local old_meta = nil
	if def_node and def_node.after_dig_node then
		old_meta = minetest.get_meta(pos):to_table()
	end
	minetest.remove_node(pos)
	local stacks = minetest.get_node_drops(destnode.name)
	for _, stack in ipairs(stacks) do
		local leftover = self:add_item_to_main(stack)
		if not leftover:is_empty() then minetest.add_item(pos, leftover) end
	end
	if old_meta then
		def_node.after_dig_node(pos, destnode, old_meta, nil)
	end
	for _, callback in ipairs(minetest.registered_on_dignodes) do
		callback({x=pos.x,y=pos.y,z=pos.z},
		         {name=destnode.name,param1=destnode.param1,param2=destnode.param2}, nil)
	end
	local sounds = minetest.registered_nodes[destnode.name]
	if sounds and sounds.sounds and sounds.sounds.dug then
		minetest.sound_play(sounds.sounds.dug, {object=self.object, max_hear_distance=10})
	end
	self:set_animation(working_villages.animation_frames.STAND)
	if collect_drops then
		local mystacks = minetest.get_node_drops(destnode.name)
		for _, stack in ipairs(mystacks) do
			local function is_drop(n)
				local name = type(n)=="table" and n.name or n
				return name == stack
			end
			self:collect_nearest_item_by_condition(is_drop, drop_range)
		end
	end
	return true
end

-- ---------------------------------------------------------------
-- place
-- ---------------------------------------------------------------
function working_villages.villager:place(item, pos)
	if type(pos) ~= "table" then error("no target position given") end
	if func.is_protected(self, pos) then return false, fail.protected end
	local dist = vector.subtract(pos, self.object:get_pos())
	if vector.length(dist) > 5 then return false, fail.too_far end
	local destnode = minetest.get_node(pos)
	if not minetest.registered_nodes[destnode.name].buildable_to then
		return false, fail.blocked
	end
	local find_item = function(name)
		if type(item)=="string" then
			return name == working_villages.buildings.get_registered_nodename(item)
		elseif type(item)=="table" then
			return name == working_villages.buildings.get_registered_nodename(item.name)
		elseif type(item)=="function" then
			return item(name)
		else
			log.error("got %s instead of an item", item)
			error("no item to place given")
		end
	end
	local wield_stack = self:get_wield_item_stack()
	if not (find_item(wield_stack:get_name()) or self:move_main_to_wield(find_item)) then
		return false, fail.not_in_inventory
	end
	if self.object:get_velocity().x==0 and self.object:get_velocity().z==0 then
		self:set_animation(working_villages.animation_frames.MINE)
	else
		self:set_animation(working_villages.animation_frames.WALK_MINE)
	end
	self:set_yaw_by_direction(dist)
	for _ = 0, 15 do coroutine.yield() end
	local stack = self:get_wield_item_stack()
	local pointed_thing = {
		type = "node",
		above = pos,
		under = vector.add(pos, {x=0, y=-1, z=0}),
	}
	local itemname = stack:get_name()
	if type(item)=="table" then
		minetest.set_node(pointed_thing.above, item)
		stack:take_item(1)
	else
		local before_node  = minetest.get_node(pos)
		local before_count = stack:get_count()
		local itemdef = stack:get_definition()
		if itemdef.on_place then
			stack = itemdef.on_place(stack, self, pointed_thing)
		elseif itemdef.type=="node" then
			stack = minetest.item_place_node(stack, self, pointed_thing)
		end
		local after_node = minetest.get_node(pos)
		if before_node.name == after_node.name then return false, fail.protected end
		if before_count == stack:get_count() then stack:take_item(1) end
	end
	self:set_wield_item_stack(stack)
	coroutine.yield()
	local sounds = minetest.registered_nodes[itemname]
	if sounds and sounds.sounds and sounds.sounds.place then
		minetest.sound_play(sounds.sounds.place, {object=self.object, max_hear_distance=10})
	end
	if self.object:get_velocity().x==0 and self.object:get_velocity().z==0 then
		self:set_animation(working_villages.animation_frames.STAND)
	else
		self:set_animation(working_villages.animation_frames.WALK)
	end
	return true
end

-- ---------------------------------------------------------------
-- manipulate_chest
-- ---------------------------------------------------------------
function working_villages.villager:manipulate_chest(chest_pos, take_func, put_func, data)
	if func.is_chest(chest_pos) then
		local vil_inv = self:get_inventory()
		if put_func then
			local size = vil_inv:get_size("main")
			for index = 1, size do
				local stack = vil_inv:get_stack("main", index)
				if (not stack:is_empty()) and (put_func(self, stack, data)) then
					local chest_meta = minetest.get_meta(chest_pos)
					local chest_inv  = chest_meta:get_inventory()
					local leftover   = chest_inv:add_item("main", stack)
					vil_inv:set_stack("main", index, leftover)
					for _ = 0, 10 do coroutine.yield() end
				end
			end
		end
		if take_func then
			local chest_meta = minetest.get_meta(chest_pos)
			local chest_inv  = chest_meta:get_inventory()
			local size = chest_inv:get_size("main")
			for index = 1, size do
				chest_meta = minetest.get_meta(chest_pos)
				chest_inv  = chest_meta:get_inventory()
				local stack = chest_inv:get_stack("main", index)
				if (not stack:is_empty()) and (take_func(self, stack, data)) then
					local leftover = vil_inv:add_item("main", stack)
					chest_inv:set_stack("main", index, leftover)
					for _ = 0, 10 do coroutine.yield() end
				end
			end
		end
	else
		log.error("Villager %s does not find chest at %s.",
			self.inventory_name, minetest.pos_to_string(chest_pos))
	end
end

-- ---------------------------------------------------------------
-- sleep / night helpers
-- ---------------------------------------------------------------
function working_villages.villager.wait_until_dawn()
	local daytime = minetest.get_timeofday()
	while (daytime < 0.2 or daytime > 0.805) do
		coroutine.yield()
		daytime = minetest.get_timeofday()
	end
end

function working_villages.villager:sleep()
	log.action("villager %s is laying down", self.inventory_name)
	self.object:set_velocity({x=0, y=0, z=0})
	local bed_pos = vector.new(self.pos_data.bed_pos)
	local bed_top = func.find_adjacent_pos(bed_pos,
		function(p) return string.find(minetest.get_node(p).name, "_top") end)
	local bed_bottom = func.find_adjacent_pos(bed_pos,
		function(p) return string.find(minetest.get_node(p).name, "_bottom") end)
	if bed_top and bed_bottom then
		self:set_yaw_by_direction(vector.subtract(bed_bottom, bed_top))
		bed_pos = vector.divide(vector.add(bed_top, bed_bottom), 2)
	else
		log.info("villager %s found no bed", self.inventory_name)
	end
	self:set_animation(working_villages.animation_frames.LAY)
	self.object:setpos(bed_pos)
	self:set_state_info("Zzzzzzz...")
	self:set_displayed_action("sleeping")
	self.wait_until_dawn()
	local p = self.object:get_pos()
	self.object:setpos({x=p.x, y=p.y+0.5, z=p.z})
	log.action("villager %s gets up", self.inventory_name)
	self:set_animation(working_villages.animation_frames.STAND)
	self:set_state_info("I'm starting into the new day.")
	self:set_displayed_action("active")
end

function working_villages.villager:goto_bed()
	if self.pos_data.home_pos == nil then
		log.action("villager %s waiting until dawn", self.inventory_name)
		self:set_state_info("I'm waiting for dawn to come.")
		self:set_displayed_action("waiting until dawn")
		self:set_animation(working_villages.animation_frames.SIT)
		self.object:set_velocity({x=0, y=0, z=0})
		self.wait_until_dawn()
		self:set_animation(working_villages.animation_frames.STAND)
		self:set_state_info("I'm starting into the new day.")
		self:set_displayed_action("active")
	else
		self:set_state_info("I'm going home, it's late.")
		self:set_displayed_action("going home")
		self:go_to(self.pos_data.home_pos)
		if self.pos_data.bed_pos == nil then
			self:set_state_info("I'd love a bed...")
			self:set_displayed_action("waiting for dusk")
			local tod = minetest.get_timeofday()
			while (tod > 0.2 and tod < 0.805) do
				coroutine.yield(); tod = minetest.get_timeofday()
			end
			self:set_state_info("I'm waiting for dawn to come.")
			self:set_displayed_action("waiting until dawn")
			self:set_animation(working_villages.animation_frames.SIT)
			self.object:set_velocity({x=0, y=0, z=0})
			self.wait_until_dawn()
		else
			self:set_state_info("I'm going to bed, it's late.")
			self:set_displayed_action("going to bed")
			self:go_to(self.pos_data.bed_pos)
			self:set_state_info("Waiting for dusk...")
			self:set_displayed_action("waiting for dusk")
			local tod = minetest.get_timeofday()
			while (tod > 0.2 and tod < 0.805) do
				coroutine.yield(); tod = minetest.get_timeofday()
			end
			self:sleep()
			self:go_to(self.pos_data.home_pos)
		end
	end
	return true
end

function working_villages.villager:handle_night()
	local tod = minetest.get_timeofday()
	if tod < 0.2 or tod > 0.76 then
		if self.job_data.in_work == true then
			self.job_data.in_work = false
		end
		self:goto_bed()
		self.job_data.manipulated_chest = false
	end
end

function working_villages.villager:goto_job()
	log.action("villager %s going to job", self.inventory_name)
	if self.pos_data.job_pos == nil then
		log.warning("villager %s has no job position", self.inventory_name)
		self.job_data.in_work = true
	else
		self:set_state_info("I am going to my job position.")
		self:set_displayed_action("going to job")
		self:go_to(self.pos_data.job_pos)
		self.job_data.in_work = true
	end
	self:set_state_info("I'm working.")
	self:set_displayed_action("active")
	return true
end

-- ---------------------------------------------------------------
-- handle_chest: validate chest position before going to it,
-- re-find if broken/missing, support both chest and chest_pos keys
-- ---------------------------------------------------------------
function working_villages.villager:handle_chest(take_func, put_func, data)
	if self.job_data.manipulated_chest then return end

	-- Prefer wizard-assigned chest (pos_data.chest), fall back to pos_data.chest_pos
	local chest_pos = self.pos_data.chest or self.pos_data.chest_pos

	if chest_pos ~= nil then
		-- Validate the chest still exists at that position
		local valid_chest, approach = resolve_chest_approach(chest_pos, self.object:get_pos())

		if valid_chest == nil then
			-- Chest is gone or moved — clear stored position so it won't spam errors
			log.warning("villager %s: chest at %s is no longer valid, clearing.",
				self.inventory_name, minetest.pos_to_string(chest_pos))
			self.pos_data.chest     = nil
			self.pos_data.chest_pos = nil
			self.job_data.manipulated_chest = true
			return
		end

		log.action("villager %s handling chest at %s",
			self.inventory_name, minetest.pos_to_string(valid_chest))
		self:set_state_info("I am handling my chest.")
		self:set_displayed_action("active")

		-- Walk to the approach position in front of the chest
		if approach then
			self:go_to(approach)
		end
		self:manipulate_chest(valid_chest, take_func, put_func, data)
	end

	self.job_data.manipulated_chest = true
end

function working_villages.villager:handle_job_pos()
	if not self.job_data.in_work then
		self:goto_job()
	end
end
