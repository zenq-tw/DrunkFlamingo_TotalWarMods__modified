local out = function(t)
    ModLog("DRUNKFLAMINGO: "..tostring(t).." (Teclis)")
end

local mod = {}

mod.feature_button_name = "teclis_teleport"
mod.teclis_faction_key = "wh2_main_hef_order_of_loremasters"
mod.get_teclis_faction = function()
    return cm:get_faction(mod.teclis_faction_key)
end

---applying this effect bundle to a region causes a TP button to appear there.
mod.teleport_node_bundle = "df_teclis_teleport_node"

mod.is_teleport_panel_open = false
mod.panels_hidden = {}
mod.teleport_panel_target_settlement = nil

mod.high_elf_colony_factions = {"wh2_main_hef_fortress_of_dawn", "wh2_main_hef_citadel_of_dusk", "wh2_main_hef_tor_elasor"}



--wh3_main_combi_region_great_turtle_isle
--wh3_main_combi_region_the_star_tower
--wh3_main_combi_region_arnheim
mod.high_elf_colony_regions = {"wh3_main_combi_region_great_turtle_isle", 
"wh3_main_combi_region_the_star_tower", "wh3_main_combi_region_arnheim",
"wh3_main_combi_region_fortress_of_dawn", "wh3_main_combi_region_citadel_of_dusk", "wh3_main_combi_region_tower_of_the_sun"
}

mod.high_elf_teleportable_colonies = {
    ["wh3_main_combi_region_great_turtle_isle"] = {},
    ["wh3_main_combi_region_the_star_tower"] = {},
    ["wh3_main_combi_region_arnheim"] = {},
    ["wh3_main_combi_region_fortress_of_dawn"] = {},
    ["wh3_main_combi_region_citadel_of_dusk"] = {},
    ["wh3_main_combi_region_tower_of_the_sun"] = {}
}

mod.mission_target_subcultures = {
    wh2_dlc11_sc_cst_vampire_coast = true,
    wh2_main_sc_def_dark_elves = true,
    wh2_main_sc_skv_skaven = true,
    wh3_main_sc_dae_daemons = true,
    wh3_main_sc_kho_khorne = true,
    wh3_main_sc_nur_nurgle = true,
    wh3_main_sc_sla_slaanesh = true,
    wh3_main_sc_tze_tzeentch = true,
    wh_dlc03_sc_bst_beastmen = true,
    wh_dlc08_sc_nor_norsca = true,
    wh_main_sc_grn_greenskins = true,
    wh_main_sc_grn_savage_orcs = true,
    wh_main_sc_vmp_vampire_counts = true
} ---@type table<string, boolean>

---tables for saving information about missions

---stores the CQI (as a string) and an integer representing the threshold for triggering a mission
mod.lord_bounty_counts = {} ---@type table<string, number|nil>
cm:add_saving_game_callback(function(context) cm:save_named_value("teclis_lord_bounty_counts", mod.lord_bounty_counts, context) end)
cm:add_loading_game_callback(function(context) mod.lord_bounty_counts = cm:load_named_value("teclis_lord_bounty_counts", {}, context) end)

---stores string keys for missions that have been triggered
mod.narrative_flags = {} ---@type table<string, number|nil>
cm:add_saving_game_callback(function(context) cm:save_named_value("teclis_narative_flags", mod.narrative_flags, context) end)
cm:add_loading_game_callback(function(context) mod.narrative_flags = cm:load_named_value("teclis_narative_flags", {}, context) end)

---checks if the lord is valid for a bounty mission increment by comparing them to Teclis and to the ally they just defeated.
---@param character CHARACTER_SCRIPT_INTERFACE
---@param teclis_ally FACTION_SCRIPT_INTERFACE
---@return boolean
local function is_lord_valid_for_bounty_mission(character, teclis_ally)
    out("Checking if "..character:command_queue_index().." is strong enough to warrant a bounty")
    local enemy_value = cm:force_gold_value(character:military_force():command_queue_index())
    local teclis_char = mod.get_teclis_faction():faction_leader()
    if teclis_char:has_military_force() then
        local teclis_value = cm:force_gold_value(teclis_char:military_force():command_queue_index())
        if enemy_value < teclis_value * 0.8 then
            out("Character "..character:command_queue_index().." is not strong enough to warrant a bounty")
            out("Teclis force*08 was greater than their gold value")
            return false
        end
    end
    local ally_character_list = teclis_ally:character_list()
    for i = 0, ally_character_list:num_items() - 1 do
        local ally_char = ally_character_list:item_at(i)
        if cm:char_is_mobile_general_with_army(ally_char) then
            local ally_value = cm:force_gold_value(ally_char:military_force():command_queue_index())
            if enemy_value < ally_value * 0.8 then
                out("Character "..character:command_queue_index().." is not strong enough to warrant a bounty")
                out("Ally force*08 was greater than their gold value")
                return false
            end
        end
    end
    out("Passed")
    return true
end

local function teclis_ally_defeated_by_character(character, teclis_ally)
    out("Teclis's ally "..teclis_ally:name().." was defeated by "..character:command_queue_index().." from faction "..character:faction():name())
    if mod.mission_target_subcultures[character:faction():subculture()] then
        local has_valid_cost = is_lord_valid_for_bounty_mission(character, teclis_ally)
        if has_valid_cost then
            local cqi_as_string = character:command_queue_index()
            mod.lord_bounty_counts[cqi_as_string] = (mod.lord_bounty_counts[cqi_as_string] or 0) + 1
            out("The bounty for character "..character:command_queue_index().." is now "..mod.lord_bounty_counts[cqi_as_string])
            if mod.lord_bounty_counts[character:command_queue_index()] > 1 then
                out("Character "..character:command_queue_index().." has met the bounty threshold")
                if mod.get_teclis_faction():at_war_with(character:faction()) then
                    --TODO trigger a mission to defeat this character's force  
                else
                    --TODO triger a mission to join your allies war against this character's faction.
                end            
            end
        end
    end
end

---creates listeners which handle the issue of missions.
local function bounty_mission_listeners()

    core:add_listener(
        "TeclisMissionGenerators",
        "CharacterPerformsSettlementOccupationDecision",
        function(context)
            local prev_faction_key = context:previous_owner() ---@type string
            if prev_faction_key == nil then
                return false
            end
            local prev_faction = cm:get_faction(prev_faction_key) 
            return prev_faction:is_ally_vassal_or_client_state_of(mod.get_teclis_faction())
        end,
        function (context)
            out("Teclis ally faction lost a settlement")
            local conquesting_character = context:character() ---@type CHARACTER_SCRIPT_INTERFACE
            local prev_faction_key = context:previous_owner() ---@type string
            local prev_faction = cm:get_faction(prev_faction_key) 
            teclis_ally_defeated_by_character(conquesting_character, prev_faction)
        end,
        true
    )

    core:add_listener(
        "TeclisMissionGenerators",
        "CharacterCompletedBattle",
        function (context)
            return context:character():won_battle()
        end,
        function (context)
            local character = context:character() ---@type CHARACTER_SCRIPT_INTERFACE
            local enemies = cm:pending_battle_cache_get_enemies_of_char(character)
            for i = 1, #enemies do
                local enemy_char = enemies[i]
                if enemy_char:faction():is_ally_vassal_or_client_state_of(mod.get_teclis_faction()) then
                    teclis_ally_defeated_by_character(character, enemy_char:faction())
                end
            end
        end)

    core:add_listener(
        "TeclisMissionGenerators",
        "CharacterCompletedBattle",
        function (context)
            return mod.lord_bounty_counts[tostring(context:character():command_queue_index())] and not context:character():won_battle()
        end,
        function (context)
            local character = context:character() ---@type CHARACTER_SCRIPT_INTERFACE
            local cqi_as_string = tostring(character:command_queue_index())
            out("Character "..cqi_as_string.." has lost a battle, resetting their bounty count")
            mod.lord_bounty_counts[cqi_as_string] = 0
        end)

    local discovery_mission_regions = {
        ["wh3_main_combi_region_great_turtle_isle"] = true, 
        ["wh3_main_combi_region_the_star_tower"] = true,
        ["wh3_main_combi_region_arnheim"] = true,
        ["wh3_main_combi_region_gronti_mingol"] = true
    }

    core:add_listener(
        "TeclisMissionGenerators",
        "FactionTurnStart",
        function (context)
            return context:faction():name() == mod.teclis_faction_key and context:faction():is_human()
        end,
        function (context)
            local teclis = context:faction() ---@type FACTION_SCRIPT_INTERFACE
            local vision_list = teclis:get_foreign_visible_regions_for_player()
            for i = 0, vision_list:num_items() -  1 do
                local region = vision_list:item_at(i)
                local region_key = region:name()
                if discovery_mission_regions[region_key] and (mod.narrative_flags["discovery_mission_issued_"..region_key] or 0) < 1 then
                    out("Checkign discovery mission for "..region_key)
                    local mission_type
                    if region:is_abandoned() then
                        out("region is abandoned")
                        mission_type = "settle_"
                    elseif mod.mission_target_subcultures[region:owning_faction():subculture()] then
                        if region:owning_faction():is_ally_vassal_or_client_state_of(teclis) then
                            out("region occupied, but the faction is an ally of Teclis! Skipping this mission")
                        else
                            out("region occupied by a valid target faction")
                            mission_type = "reclaim_"
                        end
                        
                    end
                    if mission_type then
                        out("Teclis_OwnFactionTurnStart: issuing discovery mission for "..region_key)
                        cm:trigger_mission(mod.teclis_faction_key, "df_teclis_"..mission_type..region_key, true)
                        mod.narrative_flags["discovery_mission_issued_"..region_key] = 1
                    end
                end
                mod.narrative_flags["discovery_mission_issued_"..region_key] = 1

            end
        end,
        true)
end





local function get_teleport_feature_province_list()
    return find_uicomponent(core:get_ui_root(), "teclis_teleport_feature", "province_overlay_list")
end


---grabs the visible 3DUI elements currently displayed on the screen and populates them with contextual infromation.
-----Consider doing this with CCO instead of Lua.
local function teleport_feature_callback()
    local teleport_feature = find_uicomponent("teclis_teleport_feature")
end

local function open_teleport_feature()
    mod.is_teleport_panel_open = true
    out("Opening teleport feature")
    local uim = cm:get_campaign_ui_manager()
    uim:enable_character_selection_whitelist()
    local currently_selected_char = cm:get_character_by_cqi(uim:get_char_selected_cqi() or 0)
    if currently_selected_char and not currently_selected_char:faction():name() == mod.teclis_faction_key then
        CampaignUI.ClearSelection()
    end
    uim:add_all_characters_for_faction_selection_whitelist(mod.teclis_faction_key)
    uim:enable_settlement_selection_whitelist()
    cm:override_ui("disable_settlement_labels", true);
    teleport_feature_callback()
    cm:repeat_real_callback(teleport_feature_callback, 500, "teclis_teleport_feature_callback")
    local teleport_feature_address = core:get_ui_root():CreateComponent("teclis_teleport_feature", "ui/campaign ui/teclis_teleport_panel")
    local teleport_feature_panel = UIComponent(teleport_feature_address)
    teleport_feature_panel:SetContextObject(cco("CcoCampaignRoot", ""))

    mod.teleport_panel_target_settlement = nil
end

local function close_teleport_feature()
    out("Closing teleport feature")
    mod.is_teleport_panel_open = false
    local uim = cm:get_campaign_ui_manager()
    uim:disable_character_selection_whitelist()
    uim:disable_settlement_selection_whitelist()
    cm:override_ui("disable_settlement_labels", false);
    cm:remove_real_callback("teclis_teleport_feature_callback")
    local teleport_feature = find_uicomponent("teclis_teleport_feature")
    if teleport_feature then
        teleport_feature:DestroyChildren()
        teleport_feature:Destroy()
    end
    mod.teleport_panel_target_settlement = nil
end

local function set_teleport_target_settlement_with_click(clicked_component)
    if mod.teleport_panel_target_settlement then
        --reset the state of the button of the previous target settlement
        local parent = get_teleport_feature_province_list()
        if parent then
            local previous_target_button = find_uicomponent(parent, mod.teleport_panel_target_settlement, "teclis_activate_teleport_button")
            if previous_target_button then
                previous_target_button:SetState("active")
            end
        end
    end
    local settlementWorldSpaceComponent = UIComponent(clicked_component:Parent())
    mod.teleport_panel_target_settlement = settlementWorldSpaceComponent:Id()
    
end


---comment
---@return UIC|nil
local function get_button_group_management()
    return find_uicomponent(core:get_ui_root(), "hud_campaign", "faction_buttons_docker", "button_group_management")
end

---comment
---@return UIC|nil
local function get_or_create_feature_button()
    local button_parent = get_button_group_management()
    if not button_parent then
        out("get_or_create_feature_button Could not find button group management component")
        return nil
    end
    local existing_button = find_child_uicomponent(button_parent, mod.feature_button_name)
    if existing_button then
        return existing_button
    else
        local new_button = button_parent:CreateComponent(mod.feature_button_name, "ui/campaign ui/teclis_teleport_feature_button")
    end
end

local function update_feature_button_mission_counter(feature_button)
    if not feature_button then
        out("update_feature_button_mission_counter Could not find feature button")
        return
    end
    local mission_counter = find_child_uicomponent(feature_button, "label_teclis_missions_count")
    --TODO update_feature_button_mission_counter

end

---transfer multiple regions to a faction on a callback
---@param regions string[]
---@param faction_key string
local function transfer_multiple_regions(regions, faction_key)
    for i = 1, #regions do
        cm:callback(function ()
            cm:transfer_region_to_faction(regions[i], faction_key)
        end, i/10)
    end
end

local function start_ui_listeners()
    if cm:get_local_faction_name(true) ~= mod.teclis_faction_key then
        return
    end
    --nothing with gameplay effects after this point. UI code only.
    local whose_turn = cm:model():world():whose_turn_is_it()
    for i = 0, whose_turn:num_items() - 1 do
        local who = whose_turn:item_at(i)
        if who:is_human() and who:name() == mod.teclis_faction_key then
            core:progress_on_loading_screen_dismissed(function()
                cm:callback(function() update_feature_button_mission_counter(get_or_create_feature_button()) end, 0.1)
            end)
        end
    end
    core:add_listener(
        "TeclisUI_FactionTurnStart",
        "FactionTurnStart",
        function (context)
            return context:faction():name() == mod.teclis_faction_key
        end,
        function(context)
            update_feature_button_mission_counter(get_or_create_feature_button())
        end,
        true)
    core:add_listener(
        "TeclisUI_ComponentLClickUp",
        "ComponentLClickUp",
        function (context)
            return context.string == mod.feature_button_name
        end,
        function (context)
            out("TeclisUI_ComponentLClickUp")
            if mod.is_teleport_panel_open then
                close_teleport_feature()
            else
                open_teleport_feature()
            end
        end,
        true)
    core:add_listener(
        "TeclisUI_PanelOpenedCampaign",
        "PanelOpenedCampaign",
        function (context)
            return true
        end,
        function (context)
            out("Panel opened: "..tostring(context.string))
        end,
        true)
    core:add_listener(
        "TeclisUI_WorldSpaceComponentLClickUp",
        "ComponentLClickUp",
        function (context)
            return context.string == "teclis_activate_teleport_button"
        end,
        function (context)
            
        end,
        true
    )
    
end

local function new_game_setup()
    out("new game setup")
    local starting_mission = "df_teclis_start_mission"
    --grant regions to the Fortress of Dawn faction so they have a chance to survive until the player can reach them.
    transfer_multiple_regions({"wh3_main_combi_region_tor_surpindar", "wh3_main_combi_region_dawns_light"}, "wh2_main_hef_fortress_of_dawn")
    --give Teclis a defensive alliance with the Elven Colonies
    for i = 1, #mod.high_elf_colony_factions do
        cm:force_alliance(mod.high_elf_colony_factions[i], mod.teclis_faction_key, false)
    end
    --have teclis declare war on kairos and on the fortress of dusk's starting enemy.
    cm:force_declare_war(mod.teclis_faction_key, "wh3_main_tze_oracles_of_tzeentch", false, false)
    cm:force_declare_war(mod.teclis_faction_key, "wh3_main_kho_brazen_throne", false, false)
    --TODO grant Kairos additional units based on the difficulty level.

    if mod.get_teclis_faction():is_human() then

        --apply effect bundles to the elven colonies to enable teleportation to them
        for i = 1, #mod.high_elf_colony_regions do
            cm:apply_effect_bundle_to_region(mod.teleport_node_bundle, mod.high_elf_colony_regions[i], 0)
        end

        --issue the mission to rescue the fortress of dawn.
        cm:trigger_mission(mod.teclis_faction_key, starting_mission, true)
        --grant diplomatic visibility of the Empire and Tyrion
        cm:make_diplomacy_available(mod.teclis_faction_key, "wh_main_emp_empire")
        cm:make_region_visible_in_shroud(mod.teclis_faction_key, "wh3_main_combi_region_altdorf")
        cm:make_diplomacy_available(mod.teclis_faction_key, "wh2_main_hef_lothern")
        cm:make_region_visible_in_shroud(mod.teclis_faction_key, "wh3_main_combi_region_lothern")

        --on hard difficulty and above, spawn additional enemies for Teclis.
        local difficulty_level = cm:get_difficulty() ---@type integer
        if difficulty_level >= 2 then
            local skv_faction = "wh3_main_skv_clan_morbidus"
            local force_key = "wh2_main_skv_inf_plague_monks,wh2_main_skv_inf_clanrats_0,wh2_main_skv_inf_clanrat_spearmen_1,wh2_main_skv_inf_clanrat_spearmen_0"
            if difficulty_level > 2 then
                force_key = force_key .. ",wh2_main_skv_inf_plague_monks"
                if difficulty_level > 3 then
                    force_key = force_key .. ",wh2_main_skv_art_plagueclaw_catapult"
                end
            end
            cm:create_force(skv_faction, force_key, "wh3_main_combi_region_temple_avenue_of_gold", 703, 147, true, function(cqi)
                cm:apply_effect_bundle_to_characters_force("wh_main_bundle_military_upkeep_free_force", cqi, 1)
                cm:force_character_force_into_stance(cm:char_lookup_str(cqi), "MILITARY_FORCE_ACTIVE_STANCE_TYPE_AMBUSH")
            end)
            local teclis_cqi = mod.get_teclis_faction():faction_leader():military_force():command_queue_index()
            cm:apply_effect_bundle_to_force("wh2_dlc14_bundle_scripted_force_ambush", teclis_cqi, 2)
        end
    end
end


---called on first tick after world created by the mod loader.
df_teclis = function ()
    out("Mod is active")
    if cm:is_new_game() then
        new_game_setup()
    end
    start_ui_listeners()
    --mechanics
    local helf_subculture = mod.get_teclis_faction():subculture()
    local colonies = {}
    for i = 1, #mod.high_elf_colony_regions do
        colonies[mod.high_elf_colony_regions[i]] = true
    end
    bounty_mission_listeners()
    core:add_listener(
        "Teclis_OtherFactionTurnStart",
        "FactionTurnStart",
        function (context)
            return context:faction():name() ~= mod.teclis_faction_key and context:faction():has_home_region()
        end,
        function(context)
            local faction = context:faction() ---@type FACTION_SCRIPT_INTERFACE
            local home_region = faction:home_region() 
            if colonies[home_region:name()] and faction:subculture() == helf_subculture then
                out("Teclis_FactionTurnStart: "..faction:name().." capital is in a colony, so they can be teleported to regardless of alliance status.")
                return
            end
            local is_allied = faction:is_ally_vassal_or_client_state_of(mod.get_teclis_faction())
            if is_allied and not home_region:has_effect_bundle(mod.teleport_node_bundle) then
                out("Teclis_FactionTurnStart updating home region effect bundle for ally "..faction:name())
                cm:apply_effect_bundle_to_region(mod.teleport_node_bundle, home_region:name(), 0)
            elseif home_region:has_effect_bundle(mod.teleport_node_bundle) and not is_allied then
                out("Teclis_FactionTurnStart removing home region effect bundle for non-ally "..faction:name())
                cm:remove_effect_bundle_from_region(mod.teleport_node_bundle, home_region:name())
            end
        end, true)

end


--[[notes
 precache condition for ui
  PlayersFaction.FactionRecordContext.Key == &quot;wh2_main_hef_order_of_loremasters&quot;  

    - 'chapter mission' after the completion of the starting mission: ally with X factions

    SettlementList.Filter(IsPlayerOwned == false &amp;&amp; ((ResourceList.Any(Key == &quot;res_location_colony&quot;) &amp;&amp; (IsProvinceCapital == true || ProvinceContext.CapitalSettlementContext.ResourceList.Any(Key == &quot;res_location_colony&quot;) == false)) || (IsFactionCapital &amp;&amp; FactionContext.IsAlly)))

    SettlementList.Filter(EffectBundleUnfilteredList.Any(Key == &quot;df_teclis_teleport_node&quot;))

SettlementList.Filter(
        IsPlayerOwned == false 
        &amp;&amp; (
            (
                ResourceList.Any(Key == &quot;res_location_colony&quot;) 
                &amp;&amp;
                (
                    IsProvinceCapital == true
                    ||
                    ProvinceContext.CapitalSettlementContext.ResourceList.Any(Key == &quot;res_location_colony&quot;) == false
                )
            ) 
            ||
            (
                IsFactionCapital
                &amp;&amp;
                (
                    FactionContext.IsAlly
                )
            )
        )
    )

  TODO
    - replace faction and culture effects.

  ideas for AI events:
  Teleport Teclis to the player to help them when they play as an Order faction.

--]]


local function add_tables(table_to_add, table_to_recieve)
    for i = 1, #table_to_add do
        table.insert(table_to_recieve, table_to_add[i])
    end
end