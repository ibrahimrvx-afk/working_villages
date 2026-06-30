--[[
  Path Visualizer (working_villages)
  Toggleable real-time display of villager pathfinding.

  Usage:
  - Craft the Path Visualizer item (or use /give)
  - Right-click any villager to toggle its path display ON/OFF
  - Path waypoints shown as glowing particles + numbered HUD markers
  - Current destination shown in a different colour
  - Active on all nearby villagers when held (optional, toggle with sneak+use)

  Craft: Glass + Stick + Compass
  OR just use: /give <player> working_villages:path_visualizer
]]--

-- Per-villager visualizer state: {inventory_name -> bool}
local vis_enabled = {}

-- Per-player "show all nearby" mode
local show_all = {}

-- Particle colours for path steps
local COLOUR_PATH    = {r=50,  g=200, b=255, a=230}  -- cyan-blue waypoints
local COLOUR_DEST    = {r=255, g=80,  b=80,  a=255}  -- red destination
local COLOUR_CURRENT = {r=80,  g=255, b=80,  a=255}  -- green current pos

local function spawn_path_particle(pos, colour, size)
	minetest.add_particle({
		pos         = {x=pos.x, y=pos.y+0.5, z=pos.z},
		velocity    = {x=0, y=0.05, z=0},
		acceleration= {x=0, y=0,    z=0},
		expirationtime = 0.5,
		size        = size or 0.8,
		collisiondetection = false,
		vertical    = false,
		texture     = "working_villages_path_dot.png^[colorize:#"
		              .. string.format("%02x%02x%02x", colour.r, colour.g, colour.b)
		              .. ":200",
		glow        = 10,
	})
end

-- Draw a line of particles between two positions
local function draw_line_particles(from, to, colour)
	local steps = math.max(1, math.floor(vector.distance(from, to) * 2))
	for i = 0, steps do
		local t = i / steps
		local p = {
			x = from.x + (to.x - from.x) * t,
			y = from.y + (to.y - from.y) * t + 0.5,
			z = from.z + (to.z - from.z) * t,
		}
		minetest.add_particle({
			pos         = p,
			velocity    = {x=0, y=0, z=0},
			acceleration= {x=0, y=0, z=0},
			expirationtime = 0.4,
			size        = 0.3,
			collisiondetection = false,
			texture     = "working_villages_path_dot.png^[colorize:#"
			              .. string.format("%02x%02x%02x", colour.r, colour.g, colour.b)
			              .. ":180",
			glow        = 8,
		})
	end
end

-- Draw full path for a villager entity
local function draw_villager_path(le, viewer_name)
	if not le or not le.object then return end
	local pos = le.object:get_pos()
	if not pos then return end

	-- Current position marker (green)
	spawn_path_particle(pos, COLOUR_CURRENT, 1.2)

	-- Path waypoints
	local path = le.path
	if path and #path > 0 then
		local prev = pos
		for i, wp in ipairs(path) do
			-- Line from previous to this waypoint
			draw_line_particles(prev, wp, COLOUR_PATH)
			-- Dot at waypoint
			local col = (i == #path) and COLOUR_DEST or COLOUR_PATH
			local sz  = (i == #path) and 1.5 or 0.8
			spawn_path_particle(wp, col, sz)
			prev = wp
		end
	end

	-- Destination marker (even if path is empty)
	if le.destination then
		spawn_path_particle(le.destination, COLOUR_DEST, 1.8)
	end

	-- Show state info as floating text above villager
	if viewer_name then
		local job = le:get_job()
		local job_str = job and job.description or "no job"
		local state   = le.state_info or "..."
		local mood    = le.mood or 50
		local mood_icon = mood >= 80 and "Happy" or mood >= 50 and "Content" or "Unhappy"
		minetest.add_particlespawner({
			amount = 0,
			time   = 0.1,
			-- no particles, we just want the hud text effect via infotext
		})
		-- Update infotext with debug info for this viewer
		le.object:set_properties({
			infotext = string.format(
				"[PATH VIS]\nJob: %s\nState: %s\nMood: %s (%d)\nPath steps: %d\nDest: %s",
				job_str,
				state,
				mood_icon, mood,
				path and #path or 0,
				le.destination and minetest.pos_to_string(le.destination) or "none"
			)
		})
	end
end

-- ---------------------------------------------------------------
-- Global step: redraw paths for all enabled villagers
-- ---------------------------------------------------------------
local vis_timer = 0
minetest.register_globalstep(function(dtime)
	vis_timer = vis_timer + dtime
	if vis_timer < 0.3 then return end  -- update ~3x per second
	vis_timer = 0

	-- Find all players with visualizer active
	for _, player in ipairs(minetest.get_connected_players()) do
		local pname = player:get_player_name()
		local wielded = player:get_wielded_item():get_name()
		local holding_vis = (wielded == "working_villages:path_visualizer")

		if not holding_vis and not show_all[pname] then
			-- Only draw for specifically toggled villagers even without holding
			-- if they were toggled via right-click
		end

		if holding_vis or show_all[pname] then
			local ppos = player:get_pos()
			local range = show_all[pname] and 60 or 30
			local objects = minetest.get_objects_inside_radius(ppos, range)
			for _, obj in ipairs(objects) do
				local le = obj:get_luaentity()
				if le and working_villages.is_villager(le.name) then
					-- In "show all" mode show all, else only toggled ones
					if show_all[pname] or vis_enabled[le.inventory_name] then
						draw_villager_path(le, pname)
					end
				end
			end
		else
			-- Still draw individually toggled villagers
			local ppos = player:get_pos()
			local objects = minetest.get_objects_inside_radius(ppos, 60)
			for _, obj in ipairs(objects) do
				local le = obj:get_luaentity()
				if le and working_villages.is_villager(le.name) then
					if vis_enabled[le.inventory_name] then
						draw_villager_path(le, nil)
					end
				end
			end
		end
	end
end)

-- ---------------------------------------------------------------
-- Tool registration
-- ---------------------------------------------------------------
minetest.register_tool("working_villages:path_visualizer", {
	description = "Path Visualizer\n"
	              .. "Right-click villager: toggle path display for that villager\n"
	              .. "Sneak + right-click air: toggle ALL nearby villagers\n"
	              .. "Hold to see paths in real-time",
	inventory_image = "working_villages_commanding_sceptre.png^[colorize:#00CCFF:140",
	on_use = function(itemstack, user, pointed_thing)
		local pname = user:get_player_name()

		-- Sneak + right-click air = toggle show-all mode
		if user:get_player_control().sneak and pointed_thing.type ~= "object" then
			show_all[pname] = not show_all[pname]
			minetest.chat_send_player(pname,
				"[Path Vis] Show ALL nearby villagers: " ..
				(show_all[pname] and "ON" or "OFF"))
			return itemstack
		end

		-- Right-click a villager = toggle that specific one
		if pointed_thing.type == "object" then
			local obj = pointed_thing.ref
			local le  = obj:get_luaentity()
			if le and working_villages.is_villager(le.name) then
				local inv_name = le.inventory_name
				vis_enabled[inv_name] = not vis_enabled[inv_name]
				local state = vis_enabled[inv_name] and "ON" or "OFF"
				minetest.chat_send_player(pname,
					"[Path Vis] Path display for '" ..
					(le.nametag ~= "" and le.nametag or inv_name) ..
					"': " .. state)
				-- Immediately restore normal infotext if turned off
				if not vis_enabled[inv_name] then
					le:update_infotext()
				end
				return itemstack
			end
		end

		-- Right-click empty = remind player of controls
		minetest.chat_send_player(pname,
			"[Path Vis] Right-click a villager to toggle path. " ..
			"Sneak+right-click to toggle ALL. Hold to see live paths.")
		return itemstack
	end,
})

-- Craft recipe: Glass pane + stick + compass (or just /give)
minetest.register_craft({
	output = "working_villages:path_visualizer",
	recipe = {
		{"default:glass",    "",             ""},
		{"",                 "default:stick",""},
		{"",                 "",          "default:stick"},
	},
})

-- ---------------------------------------------------------------
-- Path dot texture (simple white circle, colorized at runtime)
-- Register a simple fallback texture if none exists
-- ---------------------------------------------------------------
minetest.register_alias(
	"working_villages_path_dot.png",
	"working_villages_commanding_sceptre.png"
)

minetest.log("action", "[working_villages] Path Visualizer loaded.")
