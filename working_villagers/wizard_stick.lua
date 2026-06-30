--[[
  Wizard Stick v2 (working_villages)
  Full GUI wizard for villager management.

  Features:
  - Assign / change job (single or dual)
  - Define work area (circle or square) by clicking ground
  - Set max / min chickens (for chickener job)
  - Set work hours (start/end game time)
  - Set wander speed
  - Pause / Resume
  - Rename villager
  - Assign nearest chest automatically
  - Assign bed (click a bed node)
  - Assign home position (click ground)
  - View villager inventory
  - Teleport villager to player
  - Chat bubble toggle (show action above head)
  - Mood system display
]]--

local forms = working_villages.require("forms")
local log = working_villages.require("log")

-- Per-player pending actions
-- {player_name -> {mode="area"|"bed"|"home", villager=..., shape=..., radius=...}}
local pending = {}

-- ---------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------

local function get_area_str(villager)
	local area = villager.job_data and villager.job_data.work_area
	if area then
		return area.shape .. " r=" .. tostring(area.radius) ..
		       " @(" .. math.floor(area.center.x) .. "," .. math.floor(area.center.z) .. ")"
	end
	return "None"
end

local function get_mood_str(villager)
	local mood = villager.mood or 50
	if mood >= 80 then return "Happy 😊 (" .. mood .. ")"
	elseif mood >= 50 then return "Content 😐 (" .. mood .. ")"
	elseif mood >= 25 then return "Unhappy 😟 (" .. mood .. ")"
	else return "Miserable 😢 (" .. mood .. ")" end
end

local function get_hours_str(villager)
	local jd = villager.job_data
	if jd and jd.work_start and jd.work_end then
		return string.format("%.0fh - %.0fh", jd.work_start * 24, jd.work_end * 24)
	end
	return "All day"
end

local function inv_to_formspec(villager)
	local inv = villager:get_inventory()
	local items = inv:get_list("main") or {}
	local lines = {}
	local used = 0
	for _, item in ipairs(items) do
		if not item:is_empty() then
			table.insert(lines, item:get_name() .. " x" .. item:get_count())
			used = used + 1
		end
	end
	if used == 0 then return "label[0.5,0;(inventory empty)]" end
	local out = ""
	for i, l in ipairs(lines) do
		out = out .. "label[0.3," .. (0 + (i-1)*0.4) .. ";" .. minetest.formspec_escape(l) .. "]"
	end
	return out
end

-- ---------------------------------------------------------------
-- Formspec: Main wizard page
-- ---------------------------------------------------------------

local function build_main(villager, player_name)
	local job = villager:get_job()
	local job_desc = job and job.description or "No job"
	local paused = villager.pause
	local bed_str = (villager.pos_data and villager.pos_data.bed_pos) and
		minetest.pos_to_string(villager.pos_data.bed_pos) or "Not set"
	local home_str = (villager.pos_data and villager.pos_data.home_pos) and
		minetest.pos_to_string(villager.pos_data.home_pos) or "Not set"
	local chest_str = (villager.pos_data and (villager.pos_data.chest or villager.pos_data.chest_pos)) and
		minetest.pos_to_string(villager.pos_data.chest or villager.pos_data.chest_pos) or "Not set"
	local chat_bubble = (villager.job_data and villager.job_data.chat_bubble) and "ON" or "OFF"

	local name_display = (villager.nametag and villager.nametag ~= "") and villager.nametag or "unnamed"

	return "size[9,11]" ..
		default.gui_bg .. default.gui_bg_img .. default.gui_slots ..
		"label[0,0;=== ✨ Villager Wizard Stick ✨ ===]" ..
		"label[0,0.5;" .. minetest.formspec_escape("Name: " .. name_display) .. "]" ..
		"label[0,0.9;" .. minetest.formspec_escape("Job: " .. job_desc) .. "]" ..
		"label[0,1.3;" .. minetest.formspec_escape("Mood: " .. get_mood_str(villager)) .. "]" ..
		"label[0,1.7;" .. minetest.formspec_escape("Work area: " .. get_area_str(villager)) .. "]" ..
		"label[0,2.1;" .. minetest.formspec_escape("Work hours: " .. get_hours_str(villager)) .. "]" ..
		"label[0,2.5;" .. minetest.formspec_escape("Bed: " .. bed_str) .. "]" ..
		"label[0,2.9;" .. minetest.formspec_escape("Home: " .. home_str) .. "]" ..
		"label[0,3.3;" .. minetest.formspec_escape("Chest: " .. chest_str) .. "]" ..
		-- Row 1 buttons
		"button[0,4;3,0.8;assign_job;📋 Assign Job]" ..
		"button[3,4;3,0.8;dual_skill;⚔ Dual Job]" ..
		"button[6,4;3,0.8;view_inv;🎒 Inventory]" ..
		-- Row 2
		"button[0,4.9;3,0.8;set_area;🗺 Work Area]" ..
		"button[3,4.9;3,0.8;clear_area;✖ Clear Area]" ..
		"button[6,4.9;3,0.8;set_hours;⏰ Work Hours]" ..
		-- Row 3
		"button[0,5.8;3,0.8;set_bed;🛏 Assign Bed]" ..
		"button[3,5.8;3,0.8;set_home;🏠 Assign Home]" ..
		"button[6,5.8;3,0.8;set_chest;📦 Assign Chest]" ..
		-- Row 4
		"button[0,6.7;3,0.8;rename;✏ Rename]" ..
		"button[3,6.7;3,0.8;set_speed;💨 Speed]" ..
		"button[6,6.7;3,0.8;teleport;✈ Teleport Here]" ..
		-- Row 5
		"button[0,7.6;3,0.8;toggle_pause;" .. (paused and "▶ Resume" or "⏸ Pause") .. "]" ..
		"button[3,7.6;3,0.8;toggle_bubble;💬 Bubble: " .. chat_bubble .. "]" ..
		"button[6,7.6;3,0.8;chicken_cfg;🐔 Chicken Cfg]" ..
		-- Row 6
		"button[0,8.5;4,0.8;set_state_preset;💬 Set State Message]" ..
		"button[4.5,8.5;4,0.8;reset_job_data;🔄 Reset Job Data]" ..
		-- Close
		"button_exit[3.5,9.6;2,0.8;exit;Close]"
end

-- ---------------------------------------------------------------
-- Formspec: Job list
-- ---------------------------------------------------------------

local function build_job_list(villager)
	local jobs = {}
	for name, def in pairs(working_villages.registered_jobs) do
		if not string.find(name, ":dual_") and name ~= "working_villages:job_empty" then
			table.insert(jobs, {name=name, desc=def.description})
		end
	end
	table.sort(jobs, function(a,b) return a.desc < b.desc end)

	local form = "size[9,10]" .. default.gui_bg .. default.gui_bg_img .. default.gui_slots ..
		"label[0,0;Choose a Job:]"
	local y = 0.6
	for _, j in ipairs(jobs) do
		form = form .. "button[0.3," .. y .. ";8.4,0.75;job-" ..
			minetest.formspec_escape(j.name) .. ";" ..
			minetest.formspec_escape(j.desc) .. "]"
		y = y + 0.8
		if y > 8.5 then break end
	end
	form = form .. "button[0.3," .. (y+0.1) .. ";4,0.7;back;< Back]"
	return form
end

-- ---------------------------------------------------------------
-- Formspec: Dual job list
-- ---------------------------------------------------------------

local function build_dual_list(villager)
	local jobs = {}
	for name, def in pairs(working_villages.registered_jobs) do
		if string.find(name, ":dual_") then
			table.insert(jobs, {name=name, desc=def.description})
		end
	end
	table.sort(jobs, function(a,b) return a.desc < b.desc end)

	local form = "size[9,10]" .. default.gui_bg .. default.gui_bg_img .. default.gui_slots ..
		"label[0,0;Choose a Dual Skill:]"
	local y = 0.6
	for _, j in ipairs(jobs) do
		form = form .. "button[0.3," .. y .. ";8.4,0.75;dualjob-" ..
			minetest.formspec_escape(j.name) .. ";" ..
			minetest.formspec_escape(j.desc) .. "]"
		y = y + 0.8
		if y > 8.5 then break end
	end
	if y < 1 then
		form = form .. "label[0.3,0.8;No dual jobs available yet.]"
		y = 1.3
	end
	form = form .. "button[0.3," .. (y+0.1) .. ";4,0.7;back;< Back]"
	return form
end

-- ---------------------------------------------------------------
-- Formspec: Work area config
-- ---------------------------------------------------------------

local function build_area_form(villager)
	local cur_shape = (villager.job_data and villager.job_data.work_area and
		villager.job_data.work_area.shape) or "circle"
	local cur_radius = (villager.job_data and villager.job_data.work_area and
		villager.job_data.work_area.radius) or 16
	return "size[8,6]" .. default.gui_bg .. default.gui_bg_img .. default.gui_slots ..
		"label[0,0;Define Work Area]" ..
		"label[0,0.7;Shape (current: " .. cur_shape .. "):]" ..
		"button[0.3,1.2;3.5,0.8;shape_circle;⭕ Circle]" ..
		"button[4.2,1.2;3.5,0.8;shape_square;⬛ Square]" ..
		"label[0,2.2;Radius in blocks (current: " .. cur_radius .. "):]" ..
		"field[0.5,2.9;7,0.8;radius;;" .. cur_radius .. "]" ..
		"label[0,3.8;Click OK, then RIGHT-CLICK the ground to set center!]" ..
		"button[0.3,4.6;3.5,0.8;area_ok;✅ OK - click ground]" ..
		"button[4.2,4.6;3.5,0.8;back;Cancel]"
end

-- ---------------------------------------------------------------
-- Formspec: Work hours
-- ---------------------------------------------------------------

local function build_hours_form(villager)
	local jd = villager.job_data or {}
	local ws = jd.work_start and math.floor(jd.work_start * 24) or 6
	local we = jd.work_end and math.floor(jd.work_end * 24) or 20
	return "size[8,5]" .. default.gui_bg .. default.gui_bg_img .. default.gui_slots ..
		"label[0,0;Set Work Hours (0-24)]" ..
		"label[0,0.7;Start hour (e.g. 6 = 6am):]" ..
		"field[0.5,1.4;7,0.8;work_start;;" .. ws .. "]" ..
		"label[0,2.3;End hour (e.g. 20 = 8pm):]" ..
		"field[0.5,3.0;7,0.8;work_end;;" .. we .. "]" ..
		"button[0.3,3.9;3.5,0.8;hours_ok;✅ Save]" ..
		"button[4.2,3.9;3.5,0.8;back;Cancel]"
end

-- ---------------------------------------------------------------
-- Formspec: Speed config
-- ---------------------------------------------------------------

local function build_speed_form(villager)
	local spd = (villager.job_data and villager.job_data.wander_speed) or 2
	return "size[8,4]" .. default.gui_bg .. default.gui_bg_img .. default.gui_slots ..
		"label[0,0;Set Wander Speed]" ..
		"label[0,0.7;Speed (1=slow, 2=normal, 4=fast, max 6):]" ..
		"field[0.5,1.5;7,0.8;speed;;" .. spd .. "]" ..
		"button[0.3,2.5;3.5,0.8;speed_ok;✅ Save]" ..
		"button[4.2,2.5;3.5,0.8;back;Cancel]"
end

-- ---------------------------------------------------------------
-- Formspec: Chicken config
-- ---------------------------------------------------------------

local function build_chicken_form(villager)
	local jd = villager.job_data or {}
	local mx = jd.max_chickens or 8
	local mn = jd.min_chickens or 3
	return "size[8,5]" .. default.gui_bg .. default.gui_bg_img .. default.gui_slots ..
		"label[0,0;🐔 Chicken Settings]" ..
		"label[0,0.7;Max chickens (cull above this):]" ..
		"field[0.5,1.4;7,0.8;max_chickens;;" .. mx .. "]" ..
		"label[0,2.3;Min chickens (hatch below this):]" ..
		"field[0.5,3.0;7,0.8;min_chickens;;" .. mn .. "]" ..
		"button[0.3,3.9;3.5,0.8;chicken_ok;✅ Save]" ..
		"button[4.2,3.9;3.5,0.8;back;Cancel]"
end

-- ---------------------------------------------------------------
-- Formspec: Inventory view
-- ---------------------------------------------------------------

local function build_inv_form(villager)
	local inv = villager:get_inventory()
	local name = (villager.nametag and villager.nametag ~= "") and villager.nametag or "Villager"
	return "size[9,8]" .. default.gui_bg .. default.gui_bg_img .. default.gui_slots ..
		"label[0,0;" .. minetest.formspec_escape(name .. "'s Inventory") .. "]" ..
		"list[detached:" .. villager.inventory_name .. ";main;0,0.6;8,4;]" ..
		"button[0.3,7;4,0.8;back;< Back]"
end

-- ---------------------------------------------------------------
-- Formspec: Rename
-- ---------------------------------------------------------------

local function build_rename_form(villager)
	return "size[7,3]" .. default.gui_bg .. default.gui_bg_img ..
		"label[0,0;Enter new villager name:]" ..
		"field[0.5,0.8;6,0.8;newname;;" .. minetest.formspec_escape(villager.nametag or "") .. "]" ..
		"button[0.3,2;3,0.8;rename_ok;✅ Save]" ..
		"button[3.7,2;3,0.8;back;Cancel]"
end

-- ---------------------------------------------------------------
-- Formspec: State message
-- ---------------------------------------------------------------

local function build_state_form(villager)
	return "size[7,3]" .. default.gui_bg .. default.gui_bg_img ..
		"label[0,0;Set custom state message:]" ..
		"field[0.5,0.8;6,0.8;statemsg;;" .. minetest.formspec_escape(villager.state_info or "") .. "]" ..
		"button[0.3,2;3,0.8;state_ok;✅ Save]" ..
		"button[3.7,2;3,0.8;back;Cancel]"
end

-- ---------------------------------------------------------------
-- Show wizard helper
-- ---------------------------------------------------------------

local function show_wizard(player_name, page, inv_name)
	minetest.show_formspec(player_name, "wizard_stick:" .. page .. "_" .. inv_name,
		_G["_wiz_build_" .. page] and _G["_wiz_build_" .. page]() or "size[4,2]label[0,0;Error]")
end

-- Store villager reference
local function store_villager(villager)
	if not forms.villagers then forms.villagers = {} end
	forms.villagers[villager.inventory_name] = villager
end

local function get_villager(inv_name)
	return forms.villagers and forms.villagers[inv_name]
end

-- Set job on villager
local function assign_job(villager, job_name)
	local inv = villager:get_inventory()
	inv:set_stack("job", 1, ItemStack(job_name))
	villager.new_job = job_name
end

-- ---------------------------------------------------------------
-- Tool registration
-- ---------------------------------------------------------------

minetest.register_tool("working_villages:wizard_stick", {
	description = "Villager Wizard Stick\n" ..
	              "Right-click villager: open wizard\n" ..
	              "Right-click ground (in area/bed/home mode): set position",
	inventory_image = "working_villages_commanding_sceptre.png^[colorize:#8822FF:100",

	on_use = function(itemstack, user, pointed_thing)
		local player_name = user:get_player_name()
		local pa = pending[player_name]

		-- Handle pending ground-click modes
		if pointed_thing.type == "node" and pa then
			local click_pos = pointed_thing.under
			local villager = pa.villager

			if pa.mode == "area" then
				if not villager.job_data then villager.job_data = {} end
				villager.job_data.work_area = {
					center = {x=click_pos.x, y=click_pos.y, z=click_pos.z},
					shape  = pa.shape or "circle",
					radius = pa.radius or 16,
				}
				minetest.chat_send_player(player_name,
					"[Wizard] Work area set: " .. (pa.shape or "circle") ..
					" r=" .. (pa.radius or 16) .. " @ " .. minetest.pos_to_string(click_pos))

			elseif pa.mode == "bed" then
				-- Check it's actually a bed node
				local node = minetest.get_node(click_pos)
				if string.find(node.name, "bed") or string.find(node.name, "mattress") then
					if not villager.pos_data then villager.pos_data = {} end
					villager.pos_data.bed_pos = click_pos
					minetest.chat_send_player(player_name,
						"[Wizard] Bed assigned at " .. minetest.pos_to_string(click_pos))
				else
					minetest.chat_send_player(player_name,
						"[Wizard] That doesn't look like a bed! Try again or click a bed block.")
					return itemstack -- keep mode active
				end

			elseif pa.mode == "home" then
				if not villager.pos_data then villager.pos_data = {} end
				villager.pos_data.home_pos = click_pos
				minetest.chat_send_player(player_name,
					"[Wizard] Home position set at " .. minetest.pos_to_string(click_pos))
			end

			pending[player_name] = nil
			-- Re-open main wizard
			store_villager(villager)
			minetest.show_formspec(player_name,
				"wizard_stick:main_" .. villager.inventory_name,
				build_main(villager, player_name))
			return itemstack
		end

		-- Right-click on a villager entity
		if pointed_thing.type == "object" then
			local obj = pointed_thing.ref
			local le = obj:get_luaentity()
			if le and working_villages.is_villager(le.name) then
				if le.owner_name ~= "working_villages:self_employed" and
				   le.owner_name ~= player_name and
				   not minetest.check_player_privs(user, "debug") then
					minetest.chat_send_player(player_name, "[Wizard] This villager belongs to someone else.")
					return itemstack
				end
				store_villager(le)
				minetest.show_formspec(player_name,
					"wizard_stick:main_" .. le.inventory_name,
					build_main(le, player_name))
				return itemstack
			end
		end

		return itemstack
	end,
})

-- Crafting recipe
minetest.register_craft({
	output = "working_villages:wizard_stick",
	recipe = {
		{"default:mese_crystal", "", ""},
		{"", "default:stick", ""},
		{"", "", "default:stick"},
	},
})

-- ---------------------------------------------------------------
-- Field receiver
-- ---------------------------------------------------------------

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if not string.find(formname, "wizard_stick:") then return end
	local player_name = player:get_player_name()

	-- Extract page and inv_name from formname "wizard_stick:PAGE_INV_NAME"
	local after_prefix = formname:sub(#"wizard_stick:" + 1)
	-- The inv_name contains colons and underscores; page is first segment up to first _
	local page, inv_name = after_prefix:match("^([^_]+)_(.*)")
	if not page or not inv_name then return end

	local villager = get_villager(inv_name)
	if not villager then return end

	-- Ensure job_data and pos_data exist
	if not villager.job_data then villager.job_data = {} end
	if not villager.pos_data then villager.pos_data = {} end

	local function go_main()
		minetest.show_formspec(player_name,
			"wizard_stick:main_" .. inv_name,
			build_main(villager, player_name))
	end

	-- ===== MAIN PAGE =====
	if page == "main" then
		if fields.assign_job then
			minetest.show_formspec(player_name, "wizard_stick:jobs_" .. inv_name, build_job_list(villager))
		elseif fields.dual_skill then
			minetest.show_formspec(player_name, "wizard_stick:dual_" .. inv_name, build_dual_list(villager))
		elseif fields.view_inv then
			minetest.show_formspec(player_name, "wizard_stick:inv_" .. inv_name, build_inv_form(villager))
		elseif fields.set_area then
			minetest.show_formspec(player_name, "wizard_stick:area_" .. inv_name, build_area_form(villager))
		elseif fields.clear_area then
			villager.job_data.work_area = nil
			minetest.chat_send_player(player_name, "[Wizard] Work area cleared.")
			go_main()
		elseif fields.set_hours then
			minetest.show_formspec(player_name, "wizard_stick:hours_" .. inv_name, build_hours_form(villager))
		elseif fields.set_bed then
			pending[player_name] = {mode="bed", villager=villager}
			minetest.chat_send_player(player_name, "[Wizard] RIGHT-CLICK a bed block to assign it!")
		elseif fields.set_home then
			pending[player_name] = {mode="home", villager=villager}
			minetest.chat_send_player(player_name, "[Wizard] RIGHT-CLICK the ground to set home position!")
		elseif fields.set_chest then
			-- Auto-find nearest chest within 20 blocks
			local pos = villager.object:get_pos()
			local found, best_dist = nil, 99999
			for dx = -20, 20 do for dz = -20, 20 do for dy = -3, 3 do
				local cp = {x=pos.x+dx, y=pos.y+dy, z=pos.z+dz}
				local node = minetest.get_node(cp)
				if node.name == "default:chest" or
				   node.name == "default:chest_locked" or
				   minetest.get_item_group(node.name, "chest") > 0 then
					local d = dx*dx+dy*dy+dz*dz
					if d < best_dist then best_dist=d; found=cp end
				end
			end end end
			if found then
				villager.pos_data.chest = found
				villager.pos_data.chest_pos = found  -- keep both for compatibility
				minetest.chat_send_player(player_name, "[Wizard] Chest assigned at " .. minetest.pos_to_string(found))
			else
				minetest.chat_send_player(player_name, "[Wizard] No chest found within 20 blocks!")
			end
			go_main()
		elseif fields.rename then
			minetest.show_formspec(player_name, "wizard_stick:rename_" .. inv_name, build_rename_form(villager))
		elseif fields.set_speed then
			minetest.show_formspec(player_name, "wizard_stick:speed_" .. inv_name, build_speed_form(villager))
		elseif fields.teleport then
			local ppos = player:get_pos()
			-- Place villager slightly offset from player
			local target = {x=ppos.x+1, y=ppos.y, z=ppos.z+1}
			villager.object:setpos(target)
			villager.object:set_velocity{x=0,y=0,z=0}
			minetest.chat_send_player(player_name, "[Wizard] Villager teleported to you!")
			go_main()
		elseif fields.toggle_pause then
			local job = villager:get_job()
			villager:set_pause(not villager.pause)
			if villager.pause then
				villager:set_displayed_action("waiting")
				villager:set_state_info("Paused by Wizard Stick.")
				if job and type(job.on_pause)=="function" then job.on_pause(villager) end
			else
				villager:set_displayed_action("active")
				villager:set_state_info("Resuming work!")
				if job and type(job.on_resume)=="function" then job.on_resume(villager) end
			end
			go_main()
		elseif fields.toggle_bubble then
			villager.job_data.chat_bubble = not (villager.job_data.chat_bubble or false)
			minetest.chat_send_player(player_name,
				"[Wizard] Chat bubble " .. (villager.job_data.chat_bubble and "enabled" or "disabled"))
			go_main()
		elseif fields.chicken_cfg then
			minetest.show_formspec(player_name, "wizard_stick:chicken_" .. inv_name, build_chicken_form(villager))
		elseif fields.set_state_preset then
			minetest.show_formspec(player_name, "wizard_stick:state_" .. inv_name, build_state_form(villager))
		elseif fields.reset_job_data then
			villager.job_data = {
				work_area    = villager.job_data.work_area,    -- keep area
				chat_bubble  = villager.job_data.chat_bubble,  -- keep bubble setting
				max_chickens = villager.job_data.max_chickens,
				min_chickens = villager.job_data.min_chickens,
			}
			minetest.chat_send_player(player_name, "[Wizard] Job data reset (area/settings kept).")
			go_main()
		end

	-- ===== JOB LIST =====
	elseif page == "jobs" then
		if fields.back then go_main(); return end
		for k in pairs(fields) do
			if k:sub(1,4) == "job-" then
				local job_name = k:sub(5)
				assign_job(villager, job_name)
				minetest.chat_send_player(player_name, "[Wizard] Job assigned: " .. job_name)
				go_main(); return
			end
		end

	-- ===== DUAL JOB LIST =====
	elseif page == "dual" then
		if fields.back then go_main(); return end
		for k in pairs(fields) do
			if k:sub(1,8) == "dualjob-" then
				local job_name = k:sub(9)
				assign_job(villager, job_name)
				minetest.chat_send_player(player_name, "[Wizard] Dual job assigned: " .. job_name)
				go_main(); return
			end
		end

	-- ===== WORK AREA =====
	elseif page == "area" then
		if fields.back then go_main(); return end
		if fields.shape_circle then
			if not pending[player_name] then pending[player_name] = {villager=villager} end
			pending[player_name].shape = "circle"
			minetest.chat_send_player(player_name, "[Wizard] Shape: circle")
			minetest.show_formspec(player_name, "wizard_stick:area_" .. inv_name, build_area_form(villager))
		elseif fields.shape_square then
			if not pending[player_name] then pending[player_name] = {villager=villager} end
			pending[player_name].shape = "square"
			minetest.chat_send_player(player_name, "[Wizard] Shape: square")
			minetest.show_formspec(player_name, "wizard_stick:area_" .. inv_name, build_area_form(villager))
		elseif fields.area_ok then
			local radius = tonumber(fields.radius) or 16
			radius = math.max(4, math.min(64, radius))
			local shape = (pending[player_name] and pending[player_name].shape) or "circle"
			pending[player_name] = {
				mode    = "area",
				villager = villager,
				shape   = shape,
				radius  = radius,
			}
			minetest.chat_send_player(player_name,
				"[Wizard] Now RIGHT-CLICK the GROUND where you want the center!")
		end

	-- ===== WORK HOURS =====
	elseif page == "hours" then
		if fields.back then go_main(); return end
		if fields.hours_ok then
			local ws = tonumber(fields.work_start) or 6
			local we = tonumber(fields.work_end) or 20
			ws = math.max(0, math.min(23, ws))
			we = math.max(1, math.min(24, we))
			villager.job_data.work_start = ws / 24
			villager.job_data.work_end   = we / 24
			minetest.chat_send_player(player_name,
				"[Wizard] Work hours set: " .. ws .. "h - " .. we .. "h")
			go_main()
		end

	-- ===== SPEED =====
	elseif page == "speed" then
		if fields.back then go_main(); return end
		if fields.speed_ok then
			local spd = tonumber(fields.speed) or 2
			spd = math.max(0.5, math.min(6, spd))
			villager.job_data.wander_speed = spd
			-- Apply immediately to entity
			villager.object:set_properties({speed=spd})
			minetest.chat_send_player(player_name, "[Wizard] Speed set to " .. spd)
			go_main()
		end

	-- ===== CHICKEN CONFIG =====
	elseif page == "chicken" then
		if fields.back then go_main(); return end
		if fields.chicken_ok then
			local mx = tonumber(fields.max_chickens) or 8
			local mn = tonumber(fields.min_chickens) or 3
			mx = math.max(1, math.min(32, mx))
			mn = math.max(1, math.min(mx, mn))
			villager.job_data.max_chickens = mx
			villager.job_data.min_chickens = mn
			minetest.chat_send_player(player_name,
				"[Wizard] Chicken limits: min=" .. mn .. " max=" .. mx)
			go_main()
		end

	-- ===== INVENTORY VIEW =====
	elseif page == "inv" then
		if fields.back then go_main() end

	-- ===== RENAME =====
	elseif page == "rename" then
		if fields.back then go_main(); return end
		if fields.rename_ok then
			local newname = fields.newname or ""
			villager.nametag = newname
			villager.object:set_nametag_attributes({text=newname})
			minetest.chat_send_player(player_name, "[Wizard] Villager renamed: " .. newname)
			go_main()
		end

	-- ===== STATE MESSAGE =====
	elseif page == "state" then
		if fields.back then go_main(); return end
		if fields.state_ok then
			villager:set_state_info(fields.statemsg or "")
			go_main()
		end
	end
end)

-- ---------------------------------------------------------------
-- Mood system: update mood periodically based on conditions
-- ---------------------------------------------------------------

local mood_timer = 0
minetest.register_globalstep(function(dtime)
	mood_timer = mood_timer + dtime
	if mood_timer < 30 then return end
	mood_timer = 0

	for _, player in ipairs(minetest.get_connected_players()) do
		local ppos = player:get_pos()
		local objects = minetest.get_objects_in_area(
			vector.subtract(ppos, vector.new(50,20,50)),
			vector.add(ppos, vector.new(50,20,50))
		)
		for _, obj in ipairs(objects) do
			local le = obj:get_luaentity()
			if le and working_villages.is_villager(le.name) then
				if not le.mood then le.mood = 50 end

				-- Conditions that improve mood
				if le.pos_data and le.pos_data.bed_pos then
					le.mood = math.min(100, le.mood + 2) -- has a bed
				end
				if le.pos_data and le.pos_data.home_pos then
					le.mood = math.min(100, le.mood + 1) -- has a home
				end
				if not le.pause then
					le.mood = math.min(100, le.mood + 1) -- working = happy
				end

				-- Conditions that reduce mood
				if le.pause then
					le.mood = math.max(0, le.mood - 1) -- being paused = sad
				end
				if le._stuck_count and le._stuck_count > 20 then
					le.mood = math.max(0, le.mood - 3) -- being stuck = very sad
				end

				-- Chat bubble: show current state above head if enabled
				if le.job_data and le.job_data.chat_bubble then
					local bubble_text = le.nametag or ""
					if bubble_text ~= "" then bubble_text = bubble_text .. "\n" end
					local mood = le.mood or 50
					local mood_icon = mood >= 80 and "😊" or mood >= 50 and "😐" or "😟"
					bubble_text = bubble_text .. mood_icon .. " " .. (le.disp_action or "")
					le.object:set_nametag_attributes({
						text = bubble_text,
						color = mood >= 50 and "#FFFFFF" or "#FF8888",
					})
				end
			end
		end
	end
end)

-- ---------------------------------------------------------------
-- Work hours enforcement: pause villager outside work hours
-- ---------------------------------------------------------------

local hours_timer = 0
minetest.register_globalstep(function(dtime)
	hours_timer = hours_timer + dtime
	if hours_timer < 10 then return end
	hours_timer = 0

	local tod = minetest.get_timeofday()
	for _, player in ipairs(minetest.get_connected_players()) do
		local ppos = player:get_pos()
		local objects = minetest.get_objects_in_area(
			vector.subtract(ppos, vector.new(100,30,100)),
			vector.add(ppos, vector.new(100,30,100))
		)
		for _, obj in ipairs(objects) do
			local le = obj:get_luaentity()
			if le and working_villages.is_villager(le.name) and le.job_data then
				local ws = le.job_data.work_start
				local we = le.job_data.work_end
				if ws and we then
					local should_work = (tod >= ws and tod <= we)
					if should_work and le.pause and le.job_data._hours_paused then
						le:set_pause(false)
						le:set_displayed_action("active")
						le:set_state_info("Starting work shift!")
						le.job_data._hours_paused = false
					elseif not should_work and not le.pause then
						le:set_pause(true)
						le:set_displayed_action("off duty")
						le:set_state_info("Off duty. Resting until work hours.")
						le.job_data._hours_paused = true
					end
				end
			end
		end
	end
end)

-- ---------------------------------------------------------------
-- Wander speed: apply custom speed during movement
-- ---------------------------------------------------------------

-- Patch change_direction to apply custom speed
local orig_change_direction = working_villages.villager.change_direction
function working_villages.villager:change_direction(destination)
	orig_change_direction(self, destination)
	-- Apply custom speed if set
	if self.job_data and self.job_data.wander_speed then
		local vel = self.object:get_velocity()
		if vel then
			local spd = self.job_data.wander_speed
			local hlen = math.sqrt(vel.x*vel.x + vel.z*vel.z)
			if hlen > 0 then
				self.object:set_velocity({
					x = vel.x / hlen * spd,
					y = vel.y,
					z = vel.z / hlen * spd,
				})
			end
		end
	end
end

minetest.log("action", "[working_villages] Wizard Stick v2 loaded.")
