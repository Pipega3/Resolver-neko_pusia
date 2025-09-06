 

local ffi = require('ffi')
local client = client
local entity = entity
local ui = ui
local renderer = renderer
local globals = globals
local bit = bit
 
ffi.cdef[[
    struct animstate_t {
        char pad[108];
        float m_flEyeYaw;
        float m_flPitch;
        float m_flGoalFeetYaw;
        float m_flCurrentFeetYaw;
        float m_flCurrentTorsoYaw;
        float m_flFeetCycle;
        float m_flFeetYawRate;
        float m_fDuckAmount;
        float m_flSpeed2D;
        bool m_bOnGround;
        float m_flTimeSinceInAir;
        float m_flMaxYaw;
    };
]]

 
local enabled = ui.new_checkbox("Rage", "Other", "Enable Resolver")
local resolver_mode = ui.new_combobox("Rage", "Other", "Resolver Mode", 
    "Adaptive", "Brute Force", "Static velocity", "Max Desync", "Desync angles Sync", "Crouch Fix")
    local bone_priority = ui.new_multiselect("Rage", "Other", "Bone Priority", "Head", "Neck", "Upper Chest", "Lower Chest", "Stomach", "Fast Body")
local brute_steps = ui.new_slider("Rage", "Other", "Brute Steps", 1, 8, 3, true, "", 1)
local crouch_prediction = ui.new_checkbox("Rage", "Other", "Enable Crouch Prediction Fix")
local crouch_jitter_fix = ui.new_checkbox("Rage", "Other", "Fix Crouch Jitter")
 
local multipoint_enabled = ui.new_checkbox("Rage", "Other", "Enable MultiPoint fix!")
local multipoint_scale = ui.new_slider("Rage", "Other", "MultiPoint Scale %", 0, 100, 15, true, "%", 1)
 
local hitchance_enabled = ui.new_checkbox("Rage", "Other", "Enable Spread Hitchance")
local hitchance_slider = ui.new_slider("Rage", "Other", "Fire start ms + Hitchance spread %", -100, 100, -50, true, "%", 1)
local auto_stop_enabled = ui.new_checkbox("Rage", "Other", "Auto Stop on Shot")
local smooth_stop = ui.new_checkbox("Rage", "Other", "Smooth Stop")
local stop_delay = ui.new_slider("Rage", "Other", "Stop Delay (ms)", -100, 100, -50)

 
local lagcomp_enabled = ui.new_checkbox("Rage", "Other", "Enable Custom LagComp")
local backtrack_enabled = ui.new_checkbox("Rage", "Other", "Enable extend backtrack")

local lagcomp_ticks = ui.new_slider("Rage", "Other", "LagComp Ticks", -100, 100, 1, true, "", 1)
local lagcomp_filter_ground = ui.new_checkbox("Rage", "Other", "Only LagComp on Ground")
local extrapolate_fix = ui.new_checkbox("Rage", "Other", "Enable Extrapolation Fix")
local extrapolate_max_ticks = ui.new_slider("Rage", "Other", "Max Extrapolate Ticks", 1, 100, 1, true, "", 1)

 
 

 
local player_data = setmetatable({}, { __mode = 'k' })
local backtrack_data = setmetatable({}, { __mode = 'k' })

local function get_data(ent)
    if not player_data[ent] then
        player_data[ent] = {
            lby = 0,
            eye_yaw = 0,
            velocity = 0,
            on_ground = true,
            duck_amount = 0,
            eye_yaw_history = {}
        }
    end
    return player_data[ent]
end

 
local function normalize_yaw(yaw)
    while yaw > 180 do yaw = yaw - 360 end
    while yaw < -180 do yaw = yaw + 360 end
    return yaw
end

local function angle_diff(a, b)
    return math.abs(normalize_yaw(a - b))
end

 
local function get_max_desync(player)
    local pose = entity.get_prop(player, "m_flPoseParameter", 11) or 0
    return pose * 58 + 0.5
end

 
local function is_crouching_jitter(player)
    local duck = entity.get_prop(player, "m_flDuckAmount") or 0
    local flags = entity.get_prop(player, "m_fFlags")
    local on_ground = bit.band(flags, 1) ~= 0
    return duck > 0.1 and duck < 0.95 and on_ground
end

 
local function resolve_player(player)
    if not entity.is_enemy(player) or not entity.is_alive(player) then return end

    local data = get_data(player)
    local eye_yaw = entity.get_prop(player, "m_angEyeAngles[1]") or 0
    local lby = entity.get_prop(player, "m_flLowerBodyYawTarget") or 0
    local velocity = { entity.get_prop(player, "m_vecVelocity[0]"), entity.get_prop(player, "m_vecVelocity[1]") }
    local speed2d = math.sqrt(velocity[1]^2 + velocity[2]^2)
    local flags = entity.get_prop(player, "m_fFlags")
    local on_ground = bit.band(flags, 1) ~= 0
    local duck_amount = entity.get_prop(player, "m_flDuckAmount") or 0

    data.eye_yaw = eye_yaw
    data.lby = lby
    data.velocity = speed2d
    data.on_ground = on_ground
    data.duck_amount = duck_amount

    local mode = ui.get(resolver_mode)
    local resolved_yaw = eye_yaw
    local max_desync = get_max_desync(player)

    if max_desync ~= max_desync then max_desync = 58 end

    if ui.get(crouch_jitter_fix) and is_crouching_jitter(player) then
        resolved_yaw = normalize_yaw(eye_yaw + max_desync)
    elseif mode == "Crouch Fix" then
        if duck_amount > 0.1 then
            resolved_yaw = speed2d < 5 and lby or normalize_yaw(eye_yaw + max_desync * 0.8)
        else
            resolved_yaw = speed2d < 5 and lby or normalize_yaw(eye_yaw + max_desync)
        end
    else
        if mode == "Adaptive" then
            resolved_yaw = angle_diff(eye_yaw, lby) > 35 and normalize_yaw(eye_yaw + max_desync) or lby
        elseif mode == "Brute Force" then
            local steps = ui.get(brute_steps)
            for i = 1, steps do
                local offset = (i / steps) * max_desync
                entity.set_prop(player, "m_angEyeAngles[1]", normalize_yaw(lby + offset))
            end
            return
        elseif mode == "Static velocity" then
            resolved_yaw = not on_ground and normalize_yaw(eye_yaw + max_desync) or
                           speed2d < 5 and lby or normalize_yaw(eye_yaw + max_desync)
        elseif mode == "Max Desync" then
            resolved_yaw = normalize_yaw(eye_yaw + max_desync)
        elseif mode == "Desync angles Sync" then
            resolved_yaw = lby
        end
    end

    if resolved_yaw ~= resolved_yaw then resolved_yaw = eye_yaw end
    entity.set_prop(player, "m_angEyeAngles[1]", resolved_yaw)

end
 
local weapon_data = {
    ["weapon_awp"] = { spread = 0.010 }, ["weapon_m4a1"] = { spread = 0.014 }, ["weapon_ak47"] = { spread = 0.014 },
    ["weapon_deagle"] = { spread = 0.013 }, ["weapon_glock"] = { spread = 0.017 }, ["weapon_elite"] = { spread = 0.015 },
    ["weapon_fiveseven"] = { spread = 0.017 }, ["weapon_hkp2000"] = { spread = 0.015 }, ["weapon_p250"] = { spread = 0.015 },
    ["weapon_tec9"] = { spread = 0.017 }, ["weapon_usp_silencer"] = { spread = 0.015 }, ["weapon_cz75a"] = { spread = 0.017 },
    ["weapon_famas"] = { spread = 0.015 }, ["weapon_galilar"] = { spread = 0.015 }, ["weapon_m4a1_silencer"] = { spread = 0.014 },
    ["weapon_aug"] = { spread = 0.015 }, ["weapon_sg556"] = { spread = 0.015 }, ["weapon_ssg08"] = { spread = 0.012 },
    ["weapon_scar20"] = { spread = 0.013 }, ["weapon_g3sg1"] = { spread = 0.013 }, ["weapon_mac10"] = { spread = 0.018 },
    ["weapon_ump45"] = { spread = 0.016 }, ["weapon_bizon"] = { spread = 0.018 }, ["weapon_mp7"] = { spread = 0.016 },
    ["weapon_mp9"] = { spread = 0.018 }, ["weapon_p90"] = { spread = 0.017 }, ["weapon_nova"] = { spread = 0.022 },
    ["weapon_xm1014"] = { spread = 0.022 }, ["weapon_sawedoff"] = { spread = 0.022 }, ["weapon_mag7"] = { spread = 0.022 },
    ["weapon_m249"] = { spread = 0.018 }, ["weapon_negev"] = { spread = 0.018 }
}

 
local function calculate_hitchance(target)
    if not ui.get(hitchance_enabled) then return 100 end

    local local_player = entity.get_local_player()
    if not local_player or not target then return 0 end

    local weapon_ent = entity.get_player_weapon(local_player)
    if not weapon_ent then return 0 end

    local weapon_name = entity.get_classname(weapon_ent)
    local data = weapon_data[weapon_name]
    if not data then return 50 end

    local origin_local = { entity.get_prop(local_player, "m_vecOrigin") }
    local origin_target = { entity.get_prop(target, "m_vecOrigin") }
    local distance = math.sqrt((origin_local[1] - origin_target[1])^2 + (origin_local[2] - origin_target[2])^2) / 50

    return math.max(0, math.min(100, 100 / (1 + data.spread * distance * 20)))
end

 
local function get_backtrack_data(player)
    if not backtrack_data[player] then backtrack_data[player] = {} end
    return backtrack_data[player]
end

 
local function extrapolate_position(player, record, ticks)
 
    if not ui.get(extrapolate_fix) then 
        return record.origin 
    end

   
    local velocity = { 
        entity.get_prop(player, "m_vecVelocity[0]"), 
        entity.get_prop(player, "m_vecVelocity[1]") 
    }

     
    local speed2d = math.sqrt(velocity[1]^2 + velocity[2]^2)

     
    if speed2d < 5 then 
        return record.origin 
    end

    
    local tick_interval = globals.tickinterval()
    if tick_interval <= 0 then 
        return record.origin   
    end

 
    local normalized_forward = velocity[1] / speed2d
    local normalized_side   = velocity[2] / speed2d

 
    local total_forward = normalized_forward * speed2d * tick_interval * ticks
    local total_side    = normalized_side   * speed2d * tick_interval * ticks

 
    return {
        record.origin[1] + total_forward,
        record.origin[2] + total_side,
        record.origin[3]   
    }
end

 
local function get_best_record(player)
    if not ui.get(lagcomp_enabled) then return nil end

    local data = get_backtrack_data(player)
    if #data == 0 then return nil end

    local latency = client.latency()
    local correct = latency + globals.interp_amount()
    local curtime = globals.curtime()
    local target_time = curtime - correct

    local best_record = nil
    local best_diff = math.huge

    for i = 1, #data do
        local record = data[i]
        local diff = math.abs(record.sim_time - target_time)
        if diff < best_diff then
            best_diff = diff
            best_record = record
        end
    end

    return best_record
end

 
client.set_event_callback("paint", function()
    if not ui.get(enabled) then return end

    local enemies = entity.get_players(true)
    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then return end

   
    if ui.get(lagcomp_enabled) then
        local max_ticks = ui.get(lagcomp_ticks)

        for i = 1, #enemies do
            local player = enemies[i]
            if not entity.is_enemy(player) or not entity.is_alive(player) then
                backtrack_data[player] = nil
               
            end

            local flags = entity.get_prop(player, "m_fFlags")
            local on_ground = bit.band(flags, 1) ~= 0

            if ui.get(lagcomp_filter_ground) and not on_ground then
               
            end

                local data = get_backtrack_data(player)
                local origin = { entity.get_prop(player, "m_vecOrigin") }
                local lby = entity.get_prop(player, "m_flLowerBodyYawTarget")
                local eye_yaw = entity.get_prop(player, "m_angEyeAngles[1]")
                local sim_time = entity.get_prop(player, "m_flSimulationTime")

            table.insert(data, 1, {
                origin = origin,
                lby = lby,
                eye_yaw = eye_yaw,
                sim_time = sim_time,
                tick = globals.tickcount(),
                on_ground = on_ground
            })

            while #data > max_ticks do table.remove(data, #data) end
        end
    end
 
  
    for i = 1, #enemies do
        local player = enemies[i]
        if not entity.is_enemy(player) or not entity.is_alive(player)  then

      
        local hitchance = calculate_hitchance(player)
        if hitchance < ui.get(hitchance_slider) then
            if ui.get(show_hitchance) then
                local screen = { renderer.world_to_screen(entity.get_prop(player, "m_vecOrigin")) }
                if screen[1] and screen[2] then
                   
                end
            end
          
        end

      
               local record = get_best_record(player)
        if record then
            local extrapolate_ticks = globals.tickcount() - record.tick
            local predicted_origin = extrapolate_position(player, record, extrapolate_ticks)

           
            local current_origin = { entity.get_prop(player, "m_vecOrigin") }
            local lerped_origin = {
                current_origin[1] + (predicted_origin[1] - current_origin[1]) * 0.3,
                current_origin[2] + (predicted_origin[2] - current_origin[2]) * 0.3,
                predicted_origin[3]
            }

          
            local eye_yaw = entity.get_prop(player, "m_angEyeAngles[1]")
            if not eye_yaw or angle_diff(eye_yaw, record.eye_yaw) < 90 then
                entity.set_prop(player, "m_vecOrigin", unpack(lerped_origin))
                entity.set_prop(player, "m_flLowerBodyYawTarget", record.lby)
                entity.set_prop(player, "m_angEyeAngles[1]", record.eye_yaw)

             
                local animstate = ffi.cast("struct animstate_t*", entity.get_prop(player, "m_PlayerAnimState"))
                if animstate ~= nil then
                    animstate.m_flEyeYaw = record.eye_yaw
                    animstate.m_flGoalFeetYaw = record.eye_yaw
                end
            end
        end

        if record then
            local extrapolate_ticks = globals.tickcount() - record.tick
            local predicted_origin = extrapolate_position(player, record, extrapolate_ticks)

            local current_origin = { entity.get_prop(player, "m_vecOrigin") }
            if not current_origin[1] then goto next_player end

         
            local lerp_factor = 0.3
            local lerped_origin = {
                current_origin[1] + (predicted_origin[1] - current_origin[1]) * lerp_factor,
                current_origin[2] + (predicted_origin[2] - current_origin[2]) * lerp_factor,
                predicted_origin[3]
            }

           
            local eye_yaw = entity.get_prop(player, "m_angEyeAngles[1]")
            if eye_yaw and angle_diff(eye_yaw, record.eye_yaw) < 90 then
                entity.set_prop(player, "m_vecOrigin", unpack(lerped_origin))
                entity.set_prop(player, "m_flLowerBodyYawTarget", record.lby)
                entity.set_prop(player, "m_angEyeAngles[1]", record.eye_yaw)

               
                local animstate_ptr = entity.get_prop(player, "m_PlayerAnimState")
                if animstate_ptr ~= nil then
                    local animstate = ffi.cast("struct animstate_t*", animstate_ptr)
                    if animstate ~= nil then
                        animstate.m_flEyeYaw = record.eye_yaw
                        animstate.m_flGoalFeetYaw = record.eye_yaw
                    end
                end
            end
        end

          ::next_player::
       
        resolve_player(player)
            end
        end
    end)
 

 local function get_multipoint_targets(player)
    local scale = ui.get(multipoint_scale) / 100
    local bones = {}
    local head = entity.get_hitbox_location(player, 0) -- head
    local neck = entity.get_hitbox_location(player, 1) -- neck
    local chest = entity.get_hitbox_location(player, 4) -- upper chest
    local stomach = entity.get_hitbox_location(player, 3) -- stomach

    if not head or not neck or not chest or not stomach then return {} end

    
    local function offset_point(point, dir, dist)
        return { point[1] + dir[1]*dist, point[2] + dir[2]*dist, point[3] + dir[3]*dist }
    end

    
    local down = { 0, 0, -1 }

    if ui.get(bone_priority) == "Head" then
        table.insert(bones, head)
        table.insert(bones, offset_point(head, down, 2 * scale))
    elseif ui.get(bone_priority) == "Neck" then
        table.insert(bones, neck)
        table.insert(bones, offset_point(neck, down, 3 * scale))
    elseif ui.get(bone_priority) == "Upper Chest" then
        table.insert(bones, chest)
        table.insert(bones, offset_point(chest, down, 4 * scale))
    elseif ui.get(bone_priority) == "Lower Chest" then
        table.insert(bones, offset_point(chest, down, 5))
        table.insert(bones, offset_point(chest, down, 8))
    elseif ui.get(bone_priority) == "Stomach" then
        table.insert(bones, stomach)
        table.insert(bones, offset_point(stomach, down, 5))
    elseif ui.get(bone_priority) == "Fast Body" then
        table.insert(bones, chest)
        table.insert(bones, stomach)
    end

    return bones
end

 
local function get_best_record(player)
  
    if not ui.get(backtrack_enabled) then
        return nil
    end

  
    local data = get_backtrack_data(player)
    if not data or #data == 0 then
        return nil
    end
 
    local curtime = globals.curtime()
    local correct = client.latency() + globals.interp_amount()

    local target_time = curtime - correct
    local best_record = nil
    local best_diff = 1e9   

   
    for i = 1, #data do
        local record = data[i]
        local diff = record.sim_time - target_time
        diff = (diff >= 0) and diff or -diff   

        if diff < best_diff then
            best_diff = diff
            best_record = record
        end
    end

    return best_record
end

 
client.set_event_callback("setup_command", function(cmd)
    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then return end

    local shots_fired = entity.get_prop(local_player, "m_iShotsFired")
    if ui.get(auto_stop_enabled) and shots_fired > 0 then
        local delay = ui.get(stop_delay)
        client.delay_call(delay / 1000, function()
            if ui.get(smooth_stop) then
                cmd.forwardmove = 0
                cmd.sidemove = 0
            else
                entity.set_prop(local_player, "m_vecVelocity[0]", 0)
                entity.set_prop(local_player, "m_vecVelocity[1]", 0)
            end
        end)
    end
end) 
  
