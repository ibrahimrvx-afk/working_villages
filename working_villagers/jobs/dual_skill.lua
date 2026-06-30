-- Dual-skill job system: combine two existing jobs into one villager
-- Registered immediately at load time (no minetest.after)

local function short_name(job_name)
	return job_name:match(":job_(.+)$") or job_name:match(":(.+)$") or job_name
end

local function dual_item_name(job_a_name, job_b_name)
	local a = short_name(job_a_name):gsub("[^%w]", "_")
	local b = short_name(job_b_name):gsub("[^%w]", "_")
	return "working_villages:dual_" .. a .. "_" .. b
end

local function create_dual_job(job_a_name, job_b_name)
	local job_a = working_villages.registered_jobs[job_a_name]
	local job_b = working_villages.registered_jobs[job_b_name]
	if not job_a or not job_b then
		minetest.log("warning", "[working_villages] dual skill: unknown job '"
			.. tostring(job_a_name) .. "' or '" .. tostring(job_b_name) .. "'")
		return nil
	end

	local combo_name = dual_item_name(job_a_name, job_b_name)
	if working_villages.registered_jobs[combo_name] then
		return combo_name
	end

	working_villages.register_job(combo_name, {
		description      = job_a.description .. " + " .. job_b.description,
		long_description = "I do both: " .. (job_a.long_description or job_a.description)
		                   .. " AND: " .. (job_b.long_description or job_b.description),
		inventory_image  = job_a.inventory_image,
		jobfunc = function(self)
			if not self.dual_skill_toggle then self.dual_skill_toggle = false end
			self.dual_skill_toggle = not self.dual_skill_toggle
			if self.dual_skill_toggle then
				job_a.jobfunc(self)
			else
				job_b.jobfunc(self)
			end
		end,
	})
	return combo_name
end

working_villages.create_dual_job = create_dual_job

-- Register combinations at load time (not deferred)
-- Only jobs that exist at this point in init.lua loading are included
-- Woodcutter excluded per user request
local jobs = {
	"working_villages:job_farmer",
	"working_villages:job_chickener",
	"working_villages:job_plant_collector",
	"working_villages:job_fisher",
	"working_villages:job_torcher",
	"working_villages:job_guard",
	"working_villages:job_follow_player",
	"working_villages:job_snowclearer",
	"working_villages:job_miner",
}

for i = 1, #jobs do
	for j = i + 1, #jobs do
		local a = working_villages.registered_jobs[jobs[i]]
		local b = working_villages.registered_jobs[jobs[j]]
		if a and b then
			create_dual_job(jobs[i], jobs[j])
		end
	end
end
