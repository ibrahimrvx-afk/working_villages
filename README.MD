# minetest mod working_villages
[![luacheck][luacheck badge]][luacheck workflow]  
This mod adds Villagers performing work.
The plan is to make villagers build up their own villages.


## Planned Features
* villages
  * built up by the villagers
* villagers
  * trading and building up an economy

## implemented Features
no crafting recipes yet (you will have to use creative)
features:
* building markers
  * for building houses and saving the houses details
  * save the position of the door and the bed
  * some jobs will let the villagers return home at night
  * at home the villagers will go to bed
* spawn-eggs for villagers
  * female and male
  * (just for a nicer look)
* commanding sceptre
  * leftclick villagers to let them pause their work
  * rightclick villagers to open the inventory
  * items can be exchanged in the inventory
  * home can be set in the inventory
  * jobs can be changed in the inventory
* wizard stick
  * craftable tool with a full GUI wizard for managing a villager
  * assign a job, or two jobs at once with the dual-skill system below
  * define a work area (circle or square) the villager won't leave
  * set work hours so the villager only works during a chosen shift
  * assign a bed and a home position by clicking the target node
  * assign a chest for the villager to deposit/take items from
  * set the villager's walk speed, rename it, or teleport it to you
  * toggle a chat bubble that shows the villager's current mood
* mood system
  * villagers track a mood value (0-100) based on whether they have
    a bed, a home, are working, or are stuck
  * visible in the wizard stick GUI and optionally as a chat bubble
* dual-skill system
  * combine any two of the jobs below into a single villager
  * the villager alternates between both jobs automatically
  * assign with the wizard stick
* jobs
  * jobs define what the villagers should do
  * jobs can be changed in the inventory by clicking change job
  * in the job change form the jobs can be changed by replacing the current job by one of the jobs below (shift+click possible)
* registered jobs:
  * miner (searching nearby stone for ore veins, tunneling through plain stone if none is found)
  * plant collector (collecting all sort of fauna to produce dyes etc.)
  * player follower (following any player, night active)
  * builder (builds the nearest building defined by a building marker)
  * farmer (plants, tends and harvests farmland crops)
  * chickener (collects eggs, hatches and breeds chickens, harvests raw chicken)
  * fisher (fishes at the water's edge and deposits the catch)
  * guard (keeps watch and chases off nearby enemies)
  * any dual-skill combination of the jobs above
* testing jobs:
  * snowclearer (clearing snow away)
  * torcher (following player and placing torches in the dark, night active)

for developing jobs, villagers, etc. read [api.md](api.MD)

## Settings
These can be configured in the engine's settings menu or `minetest.conf`:
* `working_villages_enable_spawn` — let self-employed villagers spawn on their own (default: off)
* `working_villages_enable_debug_tools` — adds debug items to the creative inventory (default: off)
* `working_villages_enable_debug_checks` — extra runtime asserts that help catch bugs, small performance cost (default: on)
* `working_villages_owner_protection` — controls whether villagers may dig/build in protected areas (`false`/`true`/`ignore`/a prefix), see `settingtypes.txt` for details (default: `false`, i.e. villagers never grief protected land)

## screenshots
![Screenshot 1](screenshot.png)
![Screenshot 2](screenshot.2.png)
![Screenshot 3](screenshot.4.png)

## Submodules
Currently working_villages only has the modutil portable submodule.
It is needed to be able to run without the modutil mod.  
This means you can either download the modutil mod and enable it or get the submodule:

When cloning add "--recursive" option to clone including all submodules:
```
git clone --recursive https://github.com/ibrahimrvx-afk/working_villages.git
```

If one of the submodule folders is empty use:
```
git submodule update --init
```
This will clone all missing submodules.

## Dependencies
working_villages needs modutil to load utilities it can also use modutil portable though  
doors can be used by the villagers that's why there is a dependency

## missing modutil
If you clone the mod you either need to **install and activate the modutil mod** or you need to **[clone it recursively](#cloning)**.  
If modutil is not present you will get the following error:
`.minetest/mods/working_villages/modutil/portable.lua: No such file or directory`

## cloning
When cloning first add "--recursive" option to clone including all submodules:
```
git clone --recursive https://github.com/ibrahimrvx-afk/working_villages.git
```
else the submodule folders will be empty.

If one of the submodule folders is empty use:
```
git submodule update --init
```
This will clone all missing submodules.

To pull all changes in the repo including changes in the submodules use:
```
git pull --recurse-submodules
```

## License
* working_villages by theFox6 is avalible under the MIT License

Exceptions to the above:
* villager skin textures from the Homedecor mod: CC-by-SA 3.0 or higher
* the base of the api is the source code of the Maidroid mod: [LGPLv2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.txt) or later license.
* the egg textures are included in the Maidroid mod: [CC-BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/) or later license.
* the letters texture is from the Memorandum mod
* the sign textures and the base of the torcher job texture are from the default mod in minetest_game and from Gambit: CC BY-SA 3.0
* horsetail texture as base for the herb collectors job texture from Mossmanikin's Ferns: CC-By-SA 3.0

[luacheck badge]: https://github.com/theFox6/working_villages/workflows/luacheck/badge.svg
[luacheck workflow]: https://github.com/theFox6/working_villages/actions?query=workflow%3Aluacheck
