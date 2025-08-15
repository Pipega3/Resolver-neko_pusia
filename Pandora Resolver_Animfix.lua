 
local menu = {
  resolver_checkbox = ui.add_checkbox("Enable resolver"),
    force_side_check = ui.add_checkbox("Force side resolver"),
    brute_check = ui.add_checkbox("Brute resolver"),
    smart_check = ui.add_checkbox("Smart resolver"),
    anti_freestand = ui.add_checkbox("Anti-freestand"),
    adaptive_resolver = ui.add_checkbox("Adaptive resolver"),
    lby_prediction = ui.add_checkbox("LBY prediction"),
    dynamic_sides = ui.add_checkbox("Dynamic sides"),
    resolver_debug = ui.add_checkbox("Resolver debug"),
    fakewalk_detection = ui.add_checkbox("Fakewalk detection"),
    
    
    animfix_checkbox = ui.add_checkbox("Enable step animfix"),
        animfix_enable = ui.add_checkbox("Enable animfix"),
    animfix_aggressive = ui.add_checkbox("Aggressive animfix"),
    animfix_conservative = ui.add_checkbox("Conservative animfix"),
    animfix_adaptive = ui.add_checkbox("Adaptive animfix"),
    desync_correction = ui.add_checkbox("Desync correction"),
    jitter_resolver = ui.add_checkbox("Jitter resolver"),
    resolver_smoothing = ui.add_slider("Resolver smoothing", 0, 100),
    static_point_scale = ui.add_slider("Static point scale", 0, 100),
    break_lby_on_shot = ui.add_checkbox("Break LBY on shot"),
     animfix_pitch = ui.add_checkbox("Pitch correction"),
    animfix_yaw = ui.add_checkbox("Yaw correction"),
    animfix_body_yaw = ui.add_checkbox("Body yaw correction"),
    animfix_lean = ui.add_checkbox("Lean correction"),
    animfix_jitter = ui.add_checkbox("Jitter fix"),
    animfix_extrapolation = ui.add_checkbox("Extrapolation"),
    animfix_smoothing = ui.add_slider("Smoothing amount", 0, 100),
    animfix_tolerance = ui.add_slider("Correction tolerance", 1, 30),
    animfix_lby_threshold = ui.add_slider("LBY threshold", 1, 60),
 
}

 
local const = {
   PITCH_LIMIT = 89,
    LBY_UPDATE_INTERVAL = 1.1,
    FAKEWALK_THRESHOLD = 34.0,
    
        MAX_YAW_MODIFIER = 60.0,
        MIN_YAW_MODIFIER = 0.1,
        EXTRAPOLATION_TICKS = 2,
        FAKEWALK_SPEED = 34.0,
        ON_SHOT_CORRECTION_STRENGTH = 0.75

    
}




local animfix_data = {
    last_poses = {},
    last_sequences = {},
    last_animtimes = {},
    last_simtimes = {},
    extrapolated_angles = {},
    correction_history = {},
    last_lby_updates = {},
    last_shot_correction = {}
}
 
local resolver = {
    data = {},
    last_shot_time = 0,
    override_angles = {},
    last_resolved = {},
    last_lby_update = 0,
    lby_updates = {},
    fakewalk_players = {},
    last_eye_angles = {},
    jitter_detected = {},
    smoothed_angles = {}
}

 
local function normalize_angle(angle)
    angle = math.fmod(angle, 360)
    if angle > 180 then angle = angle - 360 end
    if angle < -180 then angle = angle + 360 end
    return angle
end

local function apply_advanced_animfix(player)
    if not menu.animfix_enable:get() then return end
    
    local idx = player:get_index()
    local cur_angles = player:get_eye_angles()
    local velocity = player:get_prop("m_vecVelocity")
    local speed = math.sqrt(velocity.x^2 + velocity.y^2)
    local lby = player:get_prop("m_flLowerBodyYawTarget")
    
 
    local tolerance = menu.animfix_tolerance:get()
    local smoothing = menu.animfix_smoothing:get() / 100
    
    if menu.animfix_aggressive:get() then
        tolerance = tolerance * 0.7
        smoothing = smoothing * 0.5
    elseif menu.animfix_conservative:get() then
        tolerance = tolerance * 1.3
        smoothing = smoothing * 1.5
    elseif menu.animfix_adaptive:get() then
        tolerance = tolerance * (1 - math.min(speed / 300, 0.5))
        smoothing = smoothing * (1 + math.min(speed / 300, 0.5))
    end

 
local function reset_resolver_data()
    resolver.data = {}
    resolver.override_angles = {}
    resolver.last_resolved = {}
end

 
local function resolve_player(player)
    if not player or not player:is_alive() or player:is_dormant() then
        return
    end

    local idx = player:get_index()
    resolver.data[idx] = resolver.data[idx] or {
        last_angles = {0, 0, 0},
        last_simtime = 0,
        last_delta = 0,
        side = 1,
        shots_missed = 0,
        desync_amount = 0
    }

    local data = resolver.data[idx]
    local cur_angles = player:get_eye_angles()

  
    if data.last_simtime == player:get_prop("m_flSimulationTime") then
        local delta = math.abs(normalize_angle(cur_angles.y - data.last_angles.y))
        if delta > 35 then
            data.last_delta = delta
            data.side = delta > 0 and 1 or -1
            data.desync_amount = delta
        end
    end

 

   
    if menu.resolver_checkbox:get() then
        local resolved_angles = {
            pitch = math.clamp(cur_angles.x, -const.PITCH_LIMIT, const.PITCH_LIMIT),
            yaw = cur_angles.y,
            roll = 0
        }

        
        if menu.force_side_check:get() then
            resolved_angles.yaw = resolved_angles.yaw + (60 * data.side)
            resolver.last_resolved[idx] = "Force side"
        end

     
        if menu.brute_check:get() then
            local brute_step = global_vars.tickcount % 4
            resolved_angles.yaw = resolved_angles.yaw + (45 * brute_step)
            resolver.last_resolved[idx] = "Brute: " .. brute_step
        end

      
        if menu.smart_check:get() then
            if data.shots_missed > 2 then
                resolved_angles.yaw = resolved_angles.yaw + 180
                data.shots_missed = 0
                resolver.last_resolved[idx] = "Smart: 180°"
            else
                resolved_angles.yaw = resolved_angles.yaw + (60 * data.side)
                resolver.last_resolved[idx] = "Smart: " .. (60 * data.side) .. "°"
            end
        end

        resolver.override_angles[idx] = resolved_angles
    end

 
    data.last_angles = cur_angles
    data.last_simtime = player:get_prop("m_flSimulationTime")
end

 
 
local function on_createmove(cmd)
    if not menu.resolver_checkbox:get() then return end

    local target = entitylist.get_entity_by_index(cmd.target_idx)
    if target and resolver.override_angles[target:get_index()] then
        cmd.viewangles = angle_t(
            resolver.override_angles[target:get_index()].pitch, 
            resolver.override_angles[target:get_index()].yaw, 
            resolver.override_angles[target:get_index()].roll
        )
    end
end

 
local function on_event(event)
    if event:get_name() == "player_hurt" then
        local attacker = entitylist.get_entity_by_index(engine.get_player_for_user_id(event:get_int("attacker")))
        local victim = entitylist.get_entity_by_index(engine.get_player_for_user_id(event:get_int("userid")))
        
        if attacker == entitylist.get_local_player() then
            resolver.data[victim:get_index()] = resolver.data[victim:get_index()] or {}
            resolver.data[victim:get_index()].shots_missed = 0
        end
    elseif event:get_name() == "weapon_fire" then
        local shooter = entitylist.get_entity_by_index(engine.get_player_for_user_id(event:get_int("userid")))
        if shooter == entitylist.get_local_player() then
            resolver.last_shot_time = global_vars.curtime
            
       
            for i = 1, 64 do
                local player = entitylist.get_entity_by_index(i)
                if player and player:is_player() and player:is_enemy() then
                    resolver.data[i] = resolver.data[i] or {}
                    resolver.data[i].shots_missed = (resolver.data[i].shots_missed or 0) + 1
                end
            end
        end
    elseif event:get_name() == "player_death" then
        local victim = entitylist.get_entity_by_index(engine.get_player_for_user_id(event:get_int("userid")))
        resolver.data[victim:get_index()] = nil
    end
end

 local function check_anti_freestand(player, data)
    if not menu.anti_freestand:get() then return end
    
    local local_player = entitylist.get_local_player()
    if not local_player then return end
    
    local player_pos = player:get_origin()
    local local_pos = local_player:get_origin()
    
    if not player_pos or not local_pos then return end
    
    local delta = player_pos - local_pos
    local angle_to_player = math.deg(math.atan2(delta.y, delta.x))
    
    
    if math.abs(normalize_angle(angle_to_player - data.last_angles.y)) > 90 then
        data.side = data.side * -1
    end
end

 
local function adaptive_resolver_logic(player, data)
    if not menu.adaptive_resolver:get() then return end
    
    -- Адаптация на основе скорости игрока
    local velocity = player:get_prop("m_vecVelocity")
    local speed = math.sqrt(velocity.x^2 + velocity.y^2)
    
    if speed > 5 then
        data.side = (global_vars.tickcount % 3) - 1   
    else
        data.side = (global_vars.tickcount % 2) * 2 - 1  
    end
end

 
local function update_lby_prediction(player, data)
    if not menu.lby_prediction:get() then return end
    
    local idx = player:get_index()
    resolver.lby_updates[idx] = resolver.lby_updates[idx] or {
        last_update = 0,
        next_update = 0
    }
    
    local lby_data = resolver.lby_updates[idx]
    local simtime = player:get_prop("m_flSimulationTime")
    
    if data.last_simtime ~= simtime then
        local lby = player:get_prop("m_flLowerBodyYawTarget")
        local delta = math.abs(normalize_angle(lby - data.last_angles.y))
        
        if delta > 35 then
            lby_data.last_update = global_vars.curtime
            lby_data.next_update = global_vars.curtime + const.LBY_UPDATE_INTERVAL
        end
        
  
        if global_vars.curtime >= lby_data.next_update then
            resolved_angles.yaw = lby
            resolver.last_resolved[idx] = "LBY update"
            lby_data.next_update = global_vars.curtime + const.LBY_UPDATE_INTERVAL
        end
    end
end

 
local function dynamic_sides_logic(player, data)
    if not menu.dynamic_sides:get() then return end
    
    -- Динамическое изменение силы резольвера на основе дельта угла
    if data.desync_amount > 0 then
        local factor = math.min(data.desync_amount / 60, 2.0)
        data.side = data.side * factor
    end
end
 
local function detect_fakewalk(player, data)
    if not menu.fakewalk_detection:get() then return end
    
    local idx = player:get_index()
    local velocity = player:get_prop("m_vecVelocity")
    local speed = math.sqrt(velocity.x^2 + velocity.y^2)
    
    if speed > 1 and speed < const.FAKEWALK_THRESHOLD then
        resolver.fakewalk_players[idx] = true
        resolver.last_resolved[idx] = "Fakewalk detected"
    else
        resolver.fakewalk_players[idx] = false
    end
end


local function apply_animfix(player, data)
    if not menu.animfix_checkbox:get() then return end
    
    local idx = player:get_index()
    resolver.last_eye_angles[idx] = resolver.last_eye_angles[idx] or player:get_eye_angles()
    
    local delta = math.abs(normalize_angle(player:get_eye_angles().y - resolver.last_eye_angles[idx].y))
    
    if delta < const.ANIMFIX_TOLERANCE then
        player:set_eye_angles(resolver.last_eye_angles[idx])
    else
        resolver.last_eye_angles[idx] = player:get_eye_angles()
    end
end
 
local function correct_desync(player, data)
    if not menu.desync_correction:get() then return end
    
    local velocity = player:get_prop("m_vecVelocity")
    local speed = math.sqrt(velocity.x^2 + velocity.y^2)
    local duck_amount = player:get_prop("m_flDuckAmount")
    
    if speed < 5 and duck_amount < 0.5 then
        data.side = data.side * 0.5 -- Уменьшаем силу резольвера для стоячих игроков
    end
end

 
local function detect_jitter(player, data)
    if not menu.jitter_resolver:get() then return end
    
    local idx = player:get_index()
    resolver.jitter_detected[idx] = resolver.jitter_detected[idx] or {count = 0, last_time = 0}
    
    local jitter_data = resolver.jitter_detected[idx]
    local cur_time = global_vars.curtime
    
    if data.last_simtime ~= player:get_prop("m_flSimulationTime") then
        local delta = math.abs(normalize_angle(data.last_angles.y - player:get_eye_angles().y))
        
        if delta > const.JITTER_THRESHOLD then
            if cur_time - jitter_data.last_time < 0.2 then
                jitter_data.count = jitter_data.count + 1
            else
                jitter_data.count = 1
            end
            
            jitter_data.last_time = cur_time
        end
    end
    
    if jitter_data.count > 3 then
        resolver.last_resolved[idx] = "Jitter detected"
        data.side = (global_vars.tickcount % 2) * 2 - 1 -- Форсируем случайную сторону
    end
end

 
local function smooth_resolver_angles(player, data, resolved_angles)
    if menu.resolver_smoothing:get() <= 0 then return resolved_angles end
    
    local idx = player:get_index()
    resolver.smoothed_angles[idx] = resolver.smoothed_angles[idx] or resolved_angles
    
    local smoothing_factor = menu.resolver_smoothing:get() / 100
    local smoothed_yaw = resolver.smoothed_angles[idx].yaw + (resolved_angles.yaw - resolver.smoothed_angles[idx].yaw) * smoothing_factor
    
    return {
        pitch = resolved_angles.pitch,
        yaw = smoothed_yaw,
        roll = resolved_angles.roll
    }
end

 
local function apply_static_point_scale(player, data, resolved_angles)
    if menu.static_point_scale:get() <= 0 then return resolved_angles end
    
    local scale_factor = menu.static_point_scale:get() / 100
    local velocity = player:get_prop("m_vecVelocity")
    local speed = math.sqrt(velocity.x^2 + velocity.y^2)
    
    if speed < 5 then  
        resolved_angles.yaw = resolved_angles.yaw * scale_factor
    end
    
    return resolved_angles
end

 
local function break_lby_on_shot(player, data)
    if not menu.break_lby_on_shot:get() then return end
    
    local idx = player:get_index()
    if resolver.last_shot_time and global_vars.curtime - resolver.last_shot_time < 0.2 then
        local lby = player:get_prop("m_flLowerBodyYawTarget")
        data.side = (lby > 0) and -1 or 1
        resolver.last_resolved[idx] = "LBY break"
    end
end
 
local function apply_resolver_override(player, data, resolved_angles)
    if not menu.resolver_override:get() then return resolved_angles end
    
    local idx = player:get_index()
    local local_player = entitylist.get_local_player()
    
    if local_player then
        local view_angles = engine.get_view_angles()
        local delta = normalize_angle(view_angles.y - player:get_eye_angles().y)
        
        resolved_angles.yaw = view_angles.y + 180
        resolver.last_resolved[idx] = "Override: " .. string.format("%.1f°", delta)
    end
    
    return resolved_angles
end
 
local function resolve_player(player)
    if not player or not player:is_alive() or player:is_dormant() then
        return
    end

    local idx = player:get_index()
    resolver.data[idx] = resolver.data[idx] or {
        last_angles = {0, 0, 0},
        last_simtime = 0,
        last_delta = 0,
        side = 1,
        shots_missed = 0,
        desync_amount = 0
    }

    local data = resolver.data[idx]
    local cur_angles = player:get_eye_angles()

 
    if data.last_simtime == player:get_prop("m_flSimulationTime") then
        local delta = math.abs(normalize_angle(cur_angles.y - data.last_angles.y))
        if delta > 35 then
            data.last_delta = delta
            data.side = delta > 0 and 1 or -1
            data.desync_amount = delta
        end
    end

   
    apply_animfix(player, data)
    detect_jitter(player, data)
    break_lby_on_shot(player, data)
    correct_desync(player, data)

 
    if menu.resolver_checkbox:get() then
        local resolved_angles = {
            pitch = math.clamp(cur_angles.x, -const.PITCH_LIMIT, const.PITCH_LIMIT),
            yaw = cur_angles.y,
            roll = 0
        }

    
        if menu.force_side_check:get() then
            resolved_angles.yaw = resolved_angles.yaw + (60 * data.side)
            resolver.last_resolved[idx] = "Force side"
        end
 
        if menu.brute_check:get() then
            local brute_step = global_vars.tickcount % 4
            resolved_angles.yaw = resolved_angles.yaw + (45 * brute_step)
            resolver.last_resolved[idx] = "Brute: " .. brute_step
        end
 
        if menu.smart_check:get() then
            if data.shots_missed > 2 then
                resolved_angles.yaw = resolved_angles.yaw + 180
                data.shots_missed = 0
                resolver.last_resolved[idx] = "Smart: 180°"
            else
                resolved_angles.yaw = resolved_angles.yaw + (60 * data.side)
                resolver.last_resolved[idx] = "Smart: " .. (60 * data.side) .. "°"
            end
        end

       
        resolved_angles = apply_resolver_override(player, data, resolved_angles)
        resolved_angles = smooth_resolver_angles(player, data, resolved_angles)
        resolved_angles = apply_static_point_scale(player, data, resolved_angles)

        resolver.override_angles[idx] = resolved_angles
    end

   
    data.last_angles = cur_angles
    data.last_simtime = player:get_prop("m_flSimulationTime")
end

end

 