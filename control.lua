require "config"

local mod_version="0.0.2"
local mod_data_version="0.0.2"

local termbelts = {}
local curvebelts = {}

local belt_polling_rate = math.max(math.min(belt_polling_rate,60),1)

local polling_cycles = math.floor(60/belt_polling_rate)

local function debug() end
-- local function debug(...)
--   if game.players[1] then
--     game.players[1].print(...)
--   end
-- end

local function pos2s(pos)
  if pos then
    return pos.x..','..pos.y
  end
  return ''
end

local function rotate_pos(pos,dir)
  local x,y=pos.x,pos.y
  if not x then
    x,y=pos[1],pos[2]
  end
  if     dir==defines.direction.north then
  elseif dir==defines.direction.south then
    x = -x
    y = -y
  elseif dir==defines.direction.east then
    t = x
    x = -y
    y = t
  elseif dir==defines.direction.west then
    t = x
    x = y
    y = -t
  end
  return {x,y,x=x,y=y}
end

local belt_speeds = {basic=1,fast=2,express=3,faster=4,purple=5}

-- starting_entity is a belt(-like) entity, or a belt combinator
-- lines are which side to follow, array of 2-8 booleans
local function terminal_belt_lines(entity,entity_to_ignore)
  if entity==entity_to_ignore then return {} end
  if entity.type=="transport-belt-to-ground" and 
    entity.belt_to_ground_type=="input" then
    if #entity.neighbours>0 then
      return {}
    else
      return {1,2,3,4}
    end
  end
  local dir = entity.direction
  local pos = entity.position
  local to_check = {}
  if entity.type=="splitter" then
    to_check = {
      {pos=rotate_pos({x=pos.x-0.5,y=pos.y},dir),lines={5,6}},
      {pos=rotate_pos({x=pos.x+0.5,y=pos.y},dir),lines={7,8}}}
  elseif entity.type=="transport-belt-to-ground" and 
    entity.belt_to_ground_type=="input" then
    to_check = {{pos=pos,lines={3,4}}}
  else
    to_check = {{pos=pos,lines={1,2}}}
  end
  if #to_check>0 then
    local result_lines = {}
    local function result(lines)
      for _,line in pairs(lines) do
        result_lines[#result_lines+1] = line
      end
    end
    -- following code originally copied from https://github.com/sparr/factorio-mod-belt-combinators
    for _,check in pairs(to_check) do
      debug("checking "..pos2s(check.pos))
      local delta = rotate_pos({0,-1},dir)
      local tpos = {x=check.pos.x+delta.x,y=check.pos.y+delta.y}
      debug("tpos "..pos2s(tpos))
      local entities = game.get_surface(entity.surface.index).find_entities({tpos,tpos})
      local target = nil
      for _,candidate in pairs(entities) do
        if candidate ~= entity_to_ignore then
          if candidate.type == "transport-belt" or
            candidate.type == "transport-belt-to-ground" or
            candidate.type == "splitter" then
            target = candidate
            break
          end
        end
      end
      if target then
        debug("target found "..target.type)
        local function beltspeedword(name)
          local m = string.match("^(.*)-transport-belt",name)
          if not m then m = string.match("^(.*)-transport-belt-to-ground",name) end
          if not m then m = string.match("^(.*)-splitter",name) end
          return m
        end
        -- any feed into a slower belt can be terminal
        local bsw1 = beltspeedword(entity.name)
        local bsw2 = beltspeedword(target.name)
        if bsw1~=bsw2 then -- different speeds
          if (not belt_speeds[bsw1]) or (not belt_speeds[bsw2]) or -- unknown speed(s)
            belt_speeds[bsw1]>belt_speeds[bsw2] then -- slower
            result(check.lines)
          end
        -- nothing accepts connections from the front
        elseif math.abs(target.direction-dir)==4 then
          result(check.lines) 
        -- underground belt outputs don't accept connections from behind
        elseif target.type=="transport-belt-to-ground" and 
          target.belt_to_ground_type=="output" and 
          target.direction==dir then
          result(check.lines) 
        -- splitters don't accept connections from the side
        elseif target.type=="splitter" and target.direction~=dir then
          result(check.lines) 
        else
          -- insertion from the side can be terminal
          if target.direction~=dir then
            local turn = false
            -- belts can be curves, anything else must side load
            if target.type=='transport-belt' then
              local belt_behind_target = false
              -- find a belt-like entity behind the target or on the far side
              local bpd = {
                {pos=rotate_pos({target.position.x,target.position.y+1},target.direction),dir=target.direction},
                {pos=rotate_pos({pos.x,pos.y-2},dir),dir=defines.direction.south}
              }
              for _,bpos in pairs(bpd) do
                local entities = game.get_surface(entity.surface.index).find_entities({bpos.pos,bpos.pos})
                for _,candidate in pairs(entities) do
                  if candidate.type == "transport-belt" or
                    candidate.type == "transport-belt-to-ground" or
                    candidate.type == "splitter" then
                    if candidate.direction == bpos.dir then
                      belt_behind_target = true
                    end
                    break
                  end
                end
                if belt_behind_target then break end
              end
              if not belt_behind_target then
                turn = true
                if not curvebelts[target.position.y] then curvebelts[target.position.y]={} end
                curvebelts[target.position.y][target.position.x] = ((target.direction-dir+8)%8==2) and "right" or "left"
              end
            end
            if not turn then
              result(check.lines)
            end
          end
        end
      else
        result(check.lines)
      end
    end
    return result_lines
  end
  return {}
end

local function onTick(event)
  if event.tick%polling_cycles == 0 then
    for y,row in pairs(termbelts) do
      for x,belt in pairs(row) do
        debug(x..','..y)
        if not belt.entity or not belt.entity.valid then
          termbelts[y][x]=nil
        else
          local e = belt.entity
          local pos = e.position
          local line_caps = {}
          if e.type=="transport-belt" then
            if curvebelts[pos.y] and curvebelts[pos.y][pos.x]=="right" then
              line_caps={5,2}
            elseif curvebelts[pos.y] and curvebelts[pos.y][pos.x]=="left" then
              line_caps={2,5}
            else
              line_caps={4,4}
            end
          elseif e.type=="transport-belt-to-ground" then
            -- caps for lines 3/4 will get set iff 1/2 are full
            line_caps={2,2,9999,9999}
          elseif e.type=="splitter" then
            line_caps={nil,nil,nil,nil,2,2,2,2}
          end
          for _,line in pairs(belt.lines) do
            -- debug(pos2s(pos)..' line '..line..':')
            local tl = e.get_transport_line(line)
            local item_name = nil
            for name,count in pairs(tl.get_contents()) do
              -- debug(line..' '..name..' '..count)
              item_name = name
            end
            if tl.get_item_count()>=line_caps[line] then
              if e.type=="transport-belt-to-ground" and e.belt_to_ground_type=="input" and line<3 then
                -- overflow lines 3/4 iff 1/2 are full, and don't overflor 1/2
                line_caps[line+2] = 4
              else
                debug("overflow "..e.type.." "..line.." "..tl.get_item_count())
                -- overflow!
                -- figure out where the overflow spot is
                local x,y = pos.x,pos.y
                local dir = e.direction
                local dx,dy = 0,0
                if e.type=="transport-belt-to-ground" and e.belt_to_ground_type=="input" then
                  -- spill beside the underground input
                  dy = dy + 0.25
                  if (line%2)==0 then 
                    dx = dx + 0.65
                  else 
                    dx = dx - 0.65
                 end
                else
                  -- spill past the end of the belt
                  dy = dy-0.85
                  if e.type=="splitter" then
                    if line==5 or line==6 then dx = dx-0.5 else dx = dx+0.5 end
                  end
                  if (line%2)==0 then dx = dx + 0.23 else dx = dx - 0.23 end
                end
                -- rotate the coordinate deltas
                local rp = rotate_pos({dx,dy},dir)
                x = x + rp.x
                y = y + rp.y
                if e.surface.find_entity("item-on-ground", {x,y}) then
                  e.surface.spill_item_stack({x,y}, {name=item_name, count=1})
                else -- spill always skips the target spot, fill it first
                  e.surface.create_entity{name="item-on-ground", 
                    position={x,y}, force=e.force, 
                    stack={name=item_name, count=1}}
                end
                if tl.remove_item({name=item_name, count=1})==0 then
                  debug("failed to remove "..item_name)
                else
                  debug("removed "..item_name.." at "..pos2s(pos))
                end
              end
            end
          end
        end
      end
    end
  end
end

local function lines2s(lines)
  out = '['
  for k,v in pairs(lines) do
    out = out .. v .. ','
  end
  out = out .. ']'
  return out
end

local function check_and_update(entity,ignore_entity,just_one)
  if entity then
    local box = {}
    if just_one then
      box = {entity.position,entity.position}
    else
      box = {{entity.position.x-1.5,entity.position.y-1.5},{entity.position.x+1.5,entity.position.y+1.5}}
    end
    local entities = game.get_surface(entity.surface.index).find_entities(box)
    for _,candidate in pairs(entities) do
      if candidate.type == "transport-belt" or
        candidate.type == "transport-belt-to-ground" or
        candidate.type == "splitter" then
        if ignore_entity and candidate==entity then
        else
          local pos = candidate.position
          if not termbelts[pos.y] then termbelts[pos.y] = {} end
          t = terminal_belt_lines(candidate,ignore_entity and entity or nil)
          if #t>0 then
            termbelts[pos.y][pos.x] = {entity=candidate,lines=t}
            debug(pos2s(pos)..' terminal '..candidate.type..' '..lines2s(termbelts[pos.y][pos.x].lines))
          else
            termbelts[pos.y][pos.x] = nil
            debug(pos2s(pos)..' non-terminal '..candidate.type)
          end
        end
      end
    end
  end
end

local function onPlaceEntity(event)
  local e = event.created_entity and event.created_entity or event.entity
  if e.type=="transport-belt" or
    e.type=="transport-belt-to-ground" or
    e.type=="splitter" then
    check_and_update(e,false,false)
    if e.type=="transport-belt-to-ground" and #e.neighbours>0 then
      check_and_update(e.neighbours[1],false,true)
    end
  end
end

local function onRemoveEntity(event)
  local e = event.entity
  if e.type=="transport-belt" or
    e.type=="transport-belt-to-ground" or
    e.type=="splitter" then
    check_and_update(e,true,false)
    if e.type=="transport-belt-to-ground" and #e.neighbours>0 then
      check_and_update(e.neighbours[1],false,true)
    end
  end
end

-- thanks to KeyboardHack on irc.freenode.net #factorio for this function
local function find_all_entities(args)
  local entities = {}
  for _,surface in pairs(game.surfaces) do
    for chunk in surface.get_chunks() do
        local top, left = chunk.x * 32, chunk.y * 32
        local bottom, right = top + 32, left + 32
        args.area={{top, left}, {bottom, right}}
        for _, ent in pairs(surface.find_entities_filtered(args)) do
            entities[#entities+1] = ent
        end
        debug("checked chunk during initialisation")
    end
  end
  return entities
end

local function refreshData()
  global.terminal_belts={}
  global.curve_belts={}
  curvebelts = global.curve_belts
  termbelts = global.terminal_belts
  for _,type in pairs({"transport-belt","transport-belt-to-ground","splitter"}) do
    for _,e in pairs(find_all_entities{type=type}) do
      check_and_update(e,false,true)
    end
  end
end

local function checkForMigration(old_version, new_version)
  -- TODO: when a migration is necessary, trigger it here or set a flag.
end

local function checkForDataMigration(old_data_version, new_data_version)
  -- TODO: when a migration is necessary, trigger it here or set a flag.
  if old_data_version ~= new_data_version then
    refreshData()
  end
end

local function onLoad()
  -- The only reason to have version/data_version is to trigger migrations, so do that here.
  checkForMigration(global.version, mod_version)
  checkForDataMigration(global.data_version, mod_data_version)

  -- After these lines, we can no longer check for migration.
  global.version=mod_version
  global.data_version=mod_data_version

  if global.terminal_belts==nil then
    refreshData()
  end

  for y,row in pairs(termbelts) do
    for x,belt in pairs(row) do
      debug(x..','..y)
    end
  end

end

script.on_init(onLoad)
script.on_configuration_changed(onLoad)
script.on_load(onLoad)

script.on_event(defines.events.on_built_entity, onPlaceEntity)
script.on_event(defines.events.on_robot_built_entity, onPlaceEntity)

script.on_event(defines.events.on_player_rotated_entity, onPlaceEntity)

script.on_event(defines.events.on_preplayer_mined_item, onRemoveEntity)
script.on_event(defines.events.on_robot_pre_mined, onRemoveEntity)
script.on_event(defines.events.on_entity_died, onRemoveEntity)

script.on_event(defines.events.on_tick, onTick)
