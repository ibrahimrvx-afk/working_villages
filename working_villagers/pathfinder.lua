local pathfinder = {}

--[[
Improved pathfinder v2:
- Fence/wall aware: treats fence-like nodes as blockers on horizontal movement
- Stuck corner recovery
- Area constraint support (circle or square zones)
]]--

local openSet = {}
local closedSet = {}

local function get_distance(start_pos, end_pos)
	local distX = math.abs(start_pos.x - end_pos.x)
	local distZ = math.abs(start_pos.z - end_pos.z)
	if distX > distZ then
		return 14 * distZ + 10 * (distX - distZ)
	else
		return 14 * distX + 10 * (distZ - distX)
	end
end

local function get_distance_to_neighbor(start_pos, end_pos)
	local distX = math.abs(start_pos.x - end_pos.x)
	local distY = math.abs(start_pos.y - end_pos.y)
	local distZ = math.abs(start_pos.z - end_pos.z)
	if distX > distZ then
		return (14 * distZ + 10 * (distX - distZ)) * (distY + 1)
	else
		return (14 * distX + 10 * (distZ - distX)) * (distY + 1)
	end
end

-- Returns true if a node name looks like a fence or wall
local function is_fence_like(node_name)
	if not node_name or node_name == "air" or node_name == "ignore" then
		return false
	end
	if string.find(node_name, "fence") or
	   string.find(node_name, "wall") or
	   string.find(node_name, "bars") or
	   string.find(node_name, "railing") or
	   string.find(node_name, "gate") then
		return true
	end
	local def = minetest.registered_nodes[node_name]
	if def and def.groups then
		if (def.groups.fence and def.groups.fence > 0) or
		   (def.groups.wall and def.groups.wall > 0) then
			return true
		end
	end
	return false
end

local function walkable(node)
	if node == nil then return true end
	if string.find(node.name, "doors:") then
		return false
	end
	if is_fence_like(node.name) then
		return true -- treat fences as solid barriers
	end
	if minetest.registered_nodes[node.name] ~= nil then
		return minetest.registered_nodes[node.name].walkable
	else
		return true
	end
end

-- Check if moving from current_pos to neighbor_pos is blocked by a fence at either end
local function fence_blocks_path(from_pos, to_pos)
	for dy = 0, 1 do
		local n = minetest.get_node({x=to_pos.x, y=to_pos.y+dy, z=to_pos.z})
		if is_fence_like(n.name) then return true end
		-- diagonal: check intermediate nodes too
		if from_pos.x ~= to_pos.x and from_pos.z ~= to_pos.z then
			local n1 = minetest.get_node({x=from_pos.x, y=from_pos.y+dy, z=to_pos.z})
			local n2 = minetest.get_node({x=to_pos.x, y=from_pos.y+dy, z=from_pos.z})
			if is_fence_like(n1.name) or is_fence_like(n2.name) then return true end
		end
	end
	return false
end

local function check_clearance(cpos, x, z, height)
	for i = 1, height do
		local n_name = minetest.get_node({x = cpos.x + x, y = cpos.y + i, z = cpos.z + z}).name
		local c_name = minetest.get_node({x = cpos.x, y = cpos.y + i, z = cpos.z}).name
		if walkable({name=n_name}) or walkable({name=c_name}) then
			return false
		end
	end
	return true
end
assert(check_clearance)

local function get_neighbor_ground_level(pos, jump_height, fall_height)
	local node = minetest.get_node(pos)
	local height = 0
	if walkable(node) then
		repeat
			height = height + 1
			if height > jump_height then return nil end
			pos.y = pos.y + 1
			node = minetest.get_node(pos)
		until not(walkable(node))
		return pos
	else
		repeat
			height = height + 1
			if height > fall_height then return nil end
			pos.y = pos.y - 1
			node = minetest.get_node(pos)
		until walkable(node)
		return {x = pos.x, y = pos.y + 1, z = pos.z}
	end
end

local function get_neighbors(current_pos, entity_height, entity_jump_height, entity_fear_height)
	local neighbors = {}
	local neighbors_index = 1
	for z = -1, 1 do
	for x = -1, 1 do
		local neighbor_pos = {x = current_pos.x + x, y = current_pos.y, z = current_pos.z + z}
		local neighbor = minetest.get_node(neighbor_pos)
		local neighbor_ground_level = get_neighbor_ground_level(neighbor_pos, entity_jump_height, entity_fear_height)
		local neighbor_clearance = false
		local empty = {hash=nil, pos=nil, clear=nil, walkable=nil}

		if neighbor_ground_level and not fence_blocks_path(current_pos, neighbor_ground_level) then
			local node_above_head = minetest.get_node(
					{x=current_pos.x, y=current_pos.y+entity_height, z=current_pos.z})
			if neighbor_ground_level.y - current_pos.y > 0 and not(walkable(node_above_head)) then
				local height = -1
				repeat
					height = height + 1
					local nd = minetest.get_node(
							{x=neighbor_ground_level.x, y=neighbor_ground_level.y+height, z=neighbor_ground_level.z})
				until walkable(nd) or height > entity_height
				if height >= entity_height then neighbor_clearance = true end
			elseif neighbor_ground_level.y - current_pos.y > 0 and walkable(node_above_head) then
				neighbors[neighbors_index] = empty
			else
				local height = -1
				repeat
					height = height + 1
					local nd = minetest.get_node(
							{x=neighbor_ground_level.x, y=current_pos.y+height, z=neighbor_ground_level.z})
				until walkable(nd) or height > entity_height
				if height >= entity_height then neighbor_clearance = true end
			end
			neighbors[neighbors_index] = {
				hash = minetest.hash_node_position(neighbor_ground_level),
				pos = neighbor_ground_level,
				clear = neighbor_clearance,
				walkable = walkable(neighbor),
			}
		else
			neighbors[neighbors_index] = empty
		end
		neighbors_index = neighbors_index + 1
	end
	end
	return neighbors
end

-- Area constraint: returns true if pos is inside the defined work area
function pathfinder.pos_in_area(pos, area)
	if area == nil then return true end
	local center = area.center
	local radius = area.radius
	local shape = area.shape or "circle"
	if shape == "circle" then
		local dx = pos.x - center.x
		local dz = pos.z - center.z
		return (dx*dx + dz*dz) <= (radius * radius)
	elseif shape == "square" then
		return math.abs(pos.x - center.x) <= radius and
		       math.abs(pos.z - center.z) <= radius
	end
	return true
end

function pathfinder.find_path(pos, endpos, entity, area)
	local start_index = minetest.hash_node_position(pos)
	local target_index = minetest.hash_node_position(endpos)
	local count = 1

	openSet = {}
	closedSet = {}

	local h_start = get_distance(pos, endpos)
	openSet[start_index] = {hCost=h_start, gCost=0, fCost=h_start, parent=nil, pos=pos}

	local entity_height = 2
	local entity_fear_height = 2
	local entity_jump_height = 1
	if entity then
		local collisionbox = entity.collisionbox or entity.initial_properties.collisionbox
		entity_height = math.ceil(collisionbox[5] - collisionbox[2])
		entity_fear_height = entity.fear_height or 2
		entity_jump_height = entity.jump_height or 1
	end

	repeat
		local current_index, current_values = next(openSet)
		for i, v in pairs(openSet) do
			if v.fCost < openSet[current_index].fCost or
			   (v.fCost == current_values.fCost and v.hCost < current_values.hCost) then
				current_index = i
				current_values = v
			end
		end

		openSet[current_index] = nil
		closedSet[current_index] = current_values
		count = count - 1

		if current_index == target_index then
			local path = {}
			local reverse_path = {}
			repeat
				if not(closedSet[current_index]) then return {endpos} end
				table.insert(path, closedSet[current_index].pos)
				current_index = closedSet[current_index].parent
				if #path > 100 then return end
			until start_index == current_index
			for _,wp in pairs(path) do
				table.insert(reverse_path, 1, wp)
			end
			return reverse_path, path
		end

		local current_pos = current_values.pos
		local neighbors = get_neighbors(current_pos, entity_height, entity_jump_height, entity_fear_height)

		for id, neighbor in pairs(neighbors) do
			local cut_corner = false
			if id == 1 then
				if not(neighbors[2].clear) or not(neighbors[4].clear)
					or neighbors[2].walkable or neighbors[4].walkable then cut_corner = true end
			elseif id == 3 then
				if not neighbors[2].clear or not neighbors[6].clear
					or neighbors[2].walkable or neighbors[6].walkable then cut_corner = true end
			elseif id == 7 then
				if not neighbors[8].clear or not neighbors[4].clear
					or neighbors[8].walkable or neighbors[4].walkable then cut_corner = true end
			elseif id == 9 then
				if not neighbors[8].clear or not neighbors[6].clear
					or neighbors[8].walkable or neighbors[6].walkable then cut_corner = true end
			end

			local in_area = (area == nil) or (neighbor.pos and pathfinder.pos_in_area(neighbor.pos, area))

			if neighbor.hash ~= current_index and not closedSet[neighbor.hash] and
			   neighbor.clear and not cut_corner and in_area then
				local move_cost = current_values.gCost + get_distance_to_neighbor(current_values.pos, neighbor.pos)
				local gCost = openSet[neighbor.hash] and openSet[neighbor.hash].gCost or 0
				if move_cost < gCost or not openSet[neighbor.hash] then
					if not openSet[neighbor.hash] then count = count + 1 end
					local hCost = get_distance(neighbor.pos, endpos)
					openSet[neighbor.hash] = {
						gCost = move_cost, hCost = hCost,
						fCost = move_cost + hCost,
						parent = current_index, pos = neighbor.pos
					}
				end
			end
		end
		if count > 100 then return end
	until count < 1
	return {endpos}
end

pathfinder.walkable = walkable
pathfinder.is_fence_like = is_fence_like

function pathfinder.get_ground_level(pos)
	return get_neighbor_ground_level(pos, 30927, 30927)
end

return pathfinder
