---@param t string
local out = function(t)
  ModLog("DRUNKFLAMINGO: "..tostring(t).." (toggle realms)")
end

local print_all_listeners_for_debug = false

local get_narrative_enabled = function()
    return core:svr_load_bool("sbool_enabled_chaos_realms")
end

local set_registered_narrative_preference = function(enable)
    out("Set the persistent preference for new campaign realms to "..tostring(enable))
    core:svr_save_registry_bool("rbool_enabled_chaos_realms", enable)
    core:svr_save_registry_bool("rbool_chaos_realm_preference_set", true)
end
  
  


local ca_setup_realms = setup_realms
local old_setup_realms = function()
    out("CA Realms Function firing")
    ca_setup_realms()
end

local ca_story_intro_panel = show_intro_story_panel
local old_story_panel = function(faction_key)
    ca_story_intro_panel(faction_key)
end

function show_intro_story_panel(faction_key)
    local show = get_narrative_enabled()
    if show then 
        out("Showing story intro!")
        old_story_panel(faction_key)
    else
        out("Skipping story intro")
    end
end


function realms_disabled_listeners()
    local humans = cm:get_human_factions()
    --lose the campaign 
    if cm:is_new_game() then

        local human_factions = cm:get_human_factions()
        for i = 1, #human_factions do
            cm:trigger_incident(human_factions[i], "df_chaos_realms_off", true, true);
            --[[
                was gonna add this for completeness sake but it looks ugly!
            cm:complete_scripted_mission_objective(human_factions[i], "wh_main_long_victory", "realm_khorne", false);
            cm:complete_scripted_mission_objective(human_factions[i], "wh_main_long_victory", "realm_nurgle", false);
            cm:complete_scripted_mission_objective(human_factions[i], "wh_main_long_victory", "realm_slaanesh", false);
            cm:complete_scripted_mission_objective(human_factions[i], "wh_main_long_victory", "realm_tzeentch", false);
            cm:complete_scripted_mission_objective(human_factions[i], "wh_main_long_victory", "forge_of_souls_battle", false);
            --]] 
        end
    end


    --this is from the CA script and might be important to making domination work?
	if not cm:is_multiplayer() then
		cm:complete_scripted_mission_objective(cm:get_local_faction_name(), "wh3_main_chaos_domination_victory", "domination", true);
	end;


    --:root:hud_campaign:resources_bar_holder:resources_bar:astral_projection_holder
 
    core:add_listener(
        "DisableRealmsUI",
        "FactionTurnStart",
        function(context)
            return context:faction():is_human()
        end,
        function(context)
            cm:real_callback(function ()
                local RealmsHolder = find_uicomponent(core:get_ui_root(), "hud_campaign", "resources_bar_holder", "resources_bar", "astral_projection_holder")
                if is_uicomponent(RealmsHolder) then
                    RealmsHolder:SetVisible(false)
                end
            end, 100)
        end,
        true)
        if cm:is_new_game() then
            --:root:events:event_layouts:incident_large:incident_large:background:footer:button_ok
            core:add_listener(
                "BelekorSilentEventClicked",
                "ComponentLClickUp",
                function (context)
                    return context.string == "button_ok" and uicomponent_descended_from(UIComponent(context.component), "event_layouts")
                end,
                function (context)
                    cm:real_callback(function ()
                        local cinematic = cm:cinematic()
                        cinematic:stop_cindy_playback(true)
                        local RealmsHolder = find_uicomponent(core:get_ui_root(), "hud_campaign", "resources_bar_holder", "resources_bar", "astral_projection_holder")
                        if is_uicomponent(RealmsHolder) then
                            RealmsHolder:SetVisible(false)
                        end
                    end, 200)
                end)
                core:add_listener(
					"BelekorSilentEventClicked",
					"PanelClosedCampaign",
					function(context) return context.string == "events" end,
					function()
                        cm:real_callback(function ()
                            local cinematic = cm:cinematic()
                            cinematic:stop_cindy_playback(true)
                            local RealmsHolder = find_uicomponent(core:get_ui_root(), "hud_campaign", "resources_bar_holder", "resources_bar", "astral_projection_holder")
                            if is_uicomponent(RealmsHolder) then
                                RealmsHolder:SetVisible(false)
                            end
                        end, 200)
                    end)
            core:progress_on_loading_screen_dismissed(function ()
                cm:real_callback(function ()
                    local RealmsHolder = find_uicomponent(core:get_ui_root(), "hud_campaign", "resources_bar_holder", "resources_bar", "astral_projection_holder")
                    if is_uicomponent(RealmsHolder) then
                        RealmsHolder:SetVisible(false)
                    end
                    local movies = find_uicomponent("movie_overlay_intro_movie")
                    if movies then
                        movies:Destroy()
                    end
                end, 100)
            end)
        else
            core:progress_on_loading_screen_dismissed(function ()
                cm:real_callback(function ()
                    local RealmsHolder = find_uicomponent(core:get_ui_root(), "hud_campaign", "resources_bar_holder", "resources_bar", "astral_projection_holder")
                    if is_uicomponent(RealmsHolder) then
                        RealmsHolder:SetVisible(false)
                    end
                end, 100)
            end)


        end
end



local function check_realms_on_resume()
    local was_ever_saved = cm:get_saved_value("was_chaos_realm_toggle_set_from_front_end")
    local enabled_from_campaign_save = cm:get_saved_value("are_chaos_realms_enabled_ongoing_campaign")
    if was_ever_saved and enabled_from_campaign_save then
        out("Saved game: enabled from save")
        old_setup_realms()
    elseif was_ever_saved then
        out("Saved game: disabled from save")
        realms_disabled_listeners()
    else
        out("Saved game: has no toggle preference set. I assume this save wasn't created with this mod active.")
        old_setup_realms()
    end
end


out("overwriting the setup function")
function setup_realms()
    out("Custom Setup Realms function is firing !")
    local enabled_from_front_end = get_narrative_enabled()

    if cm:is_multiplayer() then
        out("Is MP game")
        if cm:is_new_game() then
            local is_host = common.get_context_value("MultiplayerRootContext.HostPlayerContext.IsLocalPlayer")
            if is_host then
                out("You are the host!")
                CampaignUI.TriggerCampaignScriptEvent(cm:get_local_faction(true):command_queue_index(), "mp_chaos_realm_toggle_set_new_campaign:"..tostring(enabled_from_front_end))
            end
            return
        else
            local is_host = common.get_context_value("MultiplayerRootContext.HostPlayerContext.IsLocalPlayer")
            if is_host then
                out("You are the host!")
                CampaignUI.TriggerCampaignScriptEvent(cm:get_local_faction(true):command_queue_index(), "mp_chaos_realm_toggle_continue_campaign")
            end
            return
        end
    end

        --preserve 
    if cm:is_new_game() then
        cm:set_saved_value("are_chaos_realms_enabled_ongoing_campaign", enabled_from_front_end)
        set_registered_narrative_preference(enabled_from_front_end)
        cm:set_saved_value("was_chaos_realm_toggle_set_from_front_end", true)
        if enabled_from_front_end then
            out("New game: enabled from frontend")
            old_setup_realms()
        else
            out("New game: disabled from frontend")
            realms_disabled_listeners()
        end
    else
        check_realms_on_resume()
    end
    if print_all_listeners_for_debug then
        for event_name, listeners in pairs(core.event_listeners) do
            for i = 1, #listeners do
            local l = listeners[i]
            out(i .. ":\tname:" .. tostring(l.name) .. "\tevent:" .. tostring(l.event) .. "\tcondition:" .. tostring(l.condition) .. "\tcallback:" .. tostring(l.callback) .. "\tpersistent:" .. tostring(l.persistent))
            end
        end
    end
end

core:add_listener(
    "ToggleChaosRealmsMP",
    "UITrigger",
    function(context)
        return string.find(context:trigger(), "mp_chaos_realm_toggle_set_new_campaign")
    end,
    function(context)
        local setting = string.gsub(context:trigger(), "mp_chaos_realm_toggle_set_new_campaign:", "")
        cm:set_saved_value("was_chaos_realm_toggle_set_from_front_end", true)
        if setting == "true" then
            cm:set_saved_value("are_chaos_realms_enabled_ongoing_campaign", true)
            out("New MP game: enabled from frontend")
            old_setup_realms()
        else
            cm:set_saved_value("are_chaos_realms_enabled_ongoing_campaign", false)
            out("New MP game: disabled from frontend")
            local human_factions = cm:get_human_factions()
            for i = 1, #human_factions do
                cm:trigger_incident(human_factions[i], "df_chaos_realms_off", true, true);
            end; 
            realms_disabled_listeners()
        end
    end,
    true)

core:add_listener(
    "ToggleChaosRealmsMP",
    "UITrigger",
    function(context)
        return string.find(context:trigger(), "mp_chaos_realm_toggle_continue_campaign")
    end,
    function(context)
        check_realms_on_resume()
    end,
    true)