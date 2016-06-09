require "config"

local mod_version="0.12.0"
local mod_data_version="0.12.0"

local termbelts = {}
local curvebelts = {}

local belt_polling_rate = math.max(math.min(belt_polling_rate,60),1)

local polling_cycles = math.floor(60/belt_polling_rate)

local polling_remainder = math.random(polling_cycles)-1

-- local function debug(...)
--   if game.players[1] then
--     game.players[1].print(...)
--   end
-- end

-- local function pos2s(pos)
--   if pos.x then
--     return pos.x..','..pos.y
--   elseif pos[1] then
--     return pos[1]..','..pos[2]
--   end
--   return ''
-- end

-- local function lines2s(lines)
--   out = '['
--   for k,v in pairs(lines) do
--     out = out .. v .. ','
--   end
--   out = out .. ']'
--   return out
-- end

local function rotate_posd(posd,rotation)
  local x,y,d = posd[1],posd[2],posd[3]
  if     rotation==defines.direction.south then
    d=(d+4)%8
    x = -x
    y = -y
  elseif rotation==defines.direction.east then
    d=(d+2)%8
    t = x
    x = -y
    y = t
  elseif rotation==defines.direction.west then
    d=(d+6)%8
    t = x
    x = y
    y = -t
  end
  return x,y,d
end

local function rotate_pos(x,y,rotation)
  return rotate_posd({x,y,0},rotation)
end

local belt_speeds = {basic=1,fast=2,express=3,faster=4,purple=5}

local function beltspeedword(name)
  local m = string.match(name,"^(.*)%-transport%-belt")
  if not m then m = string.match(name,"^(.*)%-transport%-belt%-to%-ground") end
  if not m then m = string.match(name,"^(.*)%-splitter") end
  return m
end

local function terminal_belt_lines(args)
  local entity = args.entity
  local entity_to_ignore = args.entity_to_ignore
  if entity==entity_to_ignore then return {} end
  if entity.type=="transport-belt-to-ground" and 
    entity.belt_to_ground_type=="input" then
    if #entity.neighbours>0 and entity.neighbours[1] ~= entity_to_ignore then
      return {}
    else
      return {1,2,3,4}
    end
  end
  local dir = entity.direction
  local pos = entity.position
  pos[1] = pos.x
  pos[2] = pos.y
  local to_check = {}
  if entity.type=="splitter" then
    local dx,dy = rotate_pos(-0.5,0,dir)
    to_check = {
      {pos={pos.x+dx,pos.y+dy},lines={5,6}},
      {pos={pos.x-dx,pos.y-dy},lines={7,8}}
    }
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
      -- debug("checking "..pos2s(check.pos))
      local dx,dy = rotate_pos(0,-1,dir)
      local tpos = {check.pos[1]+dx,check.pos[2]+dy}
      -- debug("tpos "..pos2s(tpos))
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
        -- debug("target found "..target.type)
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
              local tpxd,tpyd=rotate_pos(0,1,target.direction)
              local pxd, pyd =rotate_pos(0,-2,dir)
              local bpd = {
                {pos={target.position.x+tpxd,target.position.y+tpyd},dir=target.direction},
                {pos={pos.x+pxd,pos.y+pyd},dir=(dir+4)%8}
              }
              for _,bpos in pairs(bpd) do
                -- debug("checking for belt-behind at "..pos2s(bpos.pos).." dir="..bpos.dir)
                local entities = game.get_surface(entity.surface.index).find_entities({bpos.pos,bpos.pos})
                for _,candidate in pairs(entities) do
                  if candidate ~= entity_to_ignore then
                    -- debug("candidate "..candidate.type.." ".."dir="..candidate.direction)
                    if candidate.type == "transport-belt" or
                      candidate.type == "transport-belt-to-ground" or
                      candidate.type == "splitter" then
                      if candidate.direction == bpos.dir then
                        belt_behind_target = true
                      end
                      break
                    end
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
    -- splitters can't be half-terminal
    if entity.type=="splitter" and #result_lines<4 then return {} end
    return result_lines
  end
  return {}
end

local function cleartermbelt(x,y)
  if termbelts[y] and termbelts[y][x] then
    if termbelts[y][x].indicator then
      termbelts[y][x].indicator.destroy()
    end
    termbelts[y][x] = nil
  end
end

local line_caps = {curve_right={5,2},curve_left={2,5},straight={4,4},ground={2,2,4,4},splitter={nil,nil,nil,nil,2,2,2,2}}

local function onTick(event)
  if event.tick%polling_cycles == polling_remainder then
    for y,row in pairs(termbelts) do
      for x,belt in pairs(row) do
        -- debug(x..','..y)
        if not belt.entity or not belt.entity.valid then
          cleartermbelt(x,y)
        else
          local e = belt.entity
          local pos = e.position
          local caps
          if e.type=="transport-belt" then
            if curvebelts[pos.y] and curvebelts[pos.y][pos.x]=="right" then
              caps=line_caps.curve_right
            elseif curvebelts[pos.y] and curvebelts[pos.y][pos.x]=="left" then
              caps=line_caps.curve_left
            else
              caps=line_caps.straight
            end
          elseif e.type=="transport-belt-to-ground" then
            caps=line_caps.ground
          elseif e.type=="splitter" then
            caps=line_caps.splitter
          end
          local ground_prefill = {}
          for i=1,#belt.lines do
            local line = belt.lines[i]
            -- debug(pos2s(pos)..' line '..line..':')
            local tl = e.get_transport_line(line)
            local item_name
            if tl.get_item_count()>=caps[line] then
              for name,count in pairs(tl.get_contents()) do
                -- debug(line..' '..name..' '..count)
                item_name = name
                break
              end
              if e.type=="transport-belt-to-ground" and 
                e.belt_to_ground_type=="input" and 
                line<3 then
                -- track this for future reference, but don't overflow here
                ground_prefill[line]=true
              elseif e.type=="transport-belt-to-ground" and 
                e.belt_to_ground_type=="input" and 
                line>2 and not ground_prefill[line-2] then
                -- do nothing, this won't overflow until the prior line overflows
              else
                -- debug("overflow "..e.type.." "..line.." "..tl.get_item_count())
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
                local rpx,rpy = rotate_pos(dx,dy,dir)
                local spill_pos = {x + rpx, y + rpy}
                local itemstack = {name=item_name, count=1}
                -- if e.surface.find_entity("item-on-ground", spill_pos) then
                  e.surface.spill_item_stack(spill_pos, itemstack)
                -- disabled this condition for performance reasons
                -- else -- spill always skips the target spot, fill it first
                --   e.surface.create_entity{name="item-on-ground", 
                --     position=spill_pos, force=e.force, 
                --     stack={name=item_name, count=1}}
                -- end
                if tl.remove_item(itemstack)==0 then
                  -- debug("belt-overflow failed to remove "..item_name)
                else
                  -- debug("removed "..item_name.." at "..pos2s(pos))
                end
              end
            end
          end
        end
      end
    end
  end
end

local function create_indicator(entity)
  local indicator_variant = ""
  if entity.type == "splitter" then
    if (entity.direction%4)==0 then
      indicator_variant = "-wide"
    else
      indicator_variant = "-tall"
    end
  end
  return entity.surface.create_entity{
            name = "belt-overflow-indicator" .. indicator_variant,
            position = entity.position
          }
end

local function check_and_update_entity(args)
  local entity = args.entity
  local entity_to_ignore = args.entity_to_ignore
  if entity then
    local pos = entity.position
    t = terminal_belt_lines{entity=entity,entity_to_ignore=entity_to_ignore}
    if #t>0 then
      if not termbelts[pos.y] then termbelts[pos.y] = {} end
      if not termbelts[pos.y][pos.x] then
        termbelts[pos.y][pos.x] = {
          entity = entity,
          lines = t,
          indicator = create_indicator(entity)
        }
      else
        termbelts[pos.y][pos.x].entity = entity
        termbelts[pos.y][pos.x].lines = t
        if not termbelts[pos.y][pos.x].indicator then 
          termbelts[pos.y][pos.x].indicator = create_indicator(entity)
        end
      end
      -- debug(pos2s(pos)..' terminal '..entity.type..' '..lines2s(termbelts[pos.y][pos.x].lines))
    else
      cleartermbelt(pos.x,pos.y)
      -- debug(pos2s(pos)..' non-terminal '..entity.type)
    end
  end
end

local function check_and_update_posd(posd,surface,entity_to_ignore)
  local box = {{posd[1]-0.5,posd[2]-0.5},{posd[1]+0.5,posd[2]+0.5}}
  local entities = surface.find_entities(box)
  for _,candidate in pairs(entities) do
    if candidate.type == "transport-belt" or
      candidate.type == "transport-belt-to-ground" or
      candidate.type == "splitter" then
      if candidate.direction == posd[3] then
        if candidate ~= entity_to_ignore then
          check_and_update_entity{entity=candidate,entity_to_ignore=entity_to_ignore}
        end
      end
    end
  end
end

local function check_and_update_neighborhood(args)
  local entity = args.entity
  local removal = args.removal
  local hood -- list of {dx,dy,dir} for a north-facing entity
  if entity.type == "transport-belt" then
    hood = {
      {0,0,0}, -- check this entity itself
      {-1,0,2},{1,0,6}, -- left and right sides can change if they point at this belt
      {0,1,0}, -- ditto behind
      {-1,-1,2},{1,-1,6}, -- ahead and left/right can change if they point at the same belt as this does
      {0,-2,4} -- and so can two-ahead
    }
  elseif entity.type == "transport-belt-to-ground" then
    if entity.belt_to_ground_type == "input" then
      hood = {{0,0,0}} -- no neighbors can change for an underground input
    else
      hood = {
        {0,0,0}, -- check this entity itself
        {-1,-1,2},{1,-1,6}, -- ahead and left/right can change if they point at the same belt as this does
        {0,-2,4} -- and so can two-ahead
      }
    end
    if #entity.neighbours>0 then
      check_and_update_entity{entity=entity.neighbours[1],entity_to_ignore=removal and entity or nil}
    end
  elseif entity.type == "splitter" then
    hood = {
      {0,0,0}, -- check this entity itself
      {-0.5,1,0},{0.5,1,0}, -- behinds can change if they point at this splitter
      {-1.5,-1,2},{1.5,-1,6}, -- aheads and left/right can change if they point at the same belt as this does
      {-0.5,-2,4},{0.5,-2,4} -- and so can two-aheads
    }
  end
  for _,posd in pairs(hood) do
    posd = {rotate_posd(posd,entity.direction)}
    if removal and posd[1]==0 and posd[2]==0 then
      -- skip checking the to-be-removed element itself
    else
      check_and_update_posd({entity.position.x+posd[1],entity.position.y+posd[2],posd[3]},entity.surface,removal and entity or nil)
    end
  end
end

local function onModifyEntity(args)
  local entity=args.entity
  local removal=args.removal
  if entity.type=="transport-belt" or
    entity.type=="transport-belt-to-ground" or
    entity.type=="splitter" then
    check_and_update_neighborhood{entity=entity,removal=removal}
  end
end

local function onPlaceEntity(event)
  onModifyEntity{entity=event.created_entity and event.created_entity or event.entity, removal=false}
end

local function onRemoveEntity(event)
  onModifyEntity{entity=event.entity, removal=true}
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
        -- debug("checked chunk during initialisation")
    end
  end
  return entities
end

local function refreshData()
  if global.terminal_belts then
    for y,row in pairs(global.terminal_belts) do
      for x,belt in pairs(row) do
        -- debug('refreshData clear '..x..','..y)
        cleartermbelt(x,y)
      end
    end
  end
  global.terminal_belts={}
  global.curve_belts={}
  curvebelts = global.curve_belts
  termbelts = global.terminal_belts
  for _,type in pairs({"transport-belt","transport-belt-to-ground","splitter"}) do
    for _,e in pairs(find_all_entities{type=type}) do
      check_and_update_entity{entity=e}
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

  -- for y,row in pairs(termbelts) do
  --   for x,belt in pairs(row) do
  --     -- debug(x..','..y)
  --   end
  -- end

end

script.on_init(onLoad)
script.on_configuration_changed(onLoad)
-- script.on_load(onLoad)

script.on_event(defines.events.on_built_entity, onPlaceEntity)
script.on_event(defines.events.on_robot_built_entity, onPlaceEntity)

script.on_event(defines.events.on_player_rotated_entity, onPlaceEntity)

script.on_event(defines.events.on_preplayer_mined_item, onRemoveEntity)
script.on_event(defines.events.on_robot_pre_mined, onRemoveEntity)
script.on_event(defines.events.on_entity_died, onRemoveEntity)

script.on_event(defines.events.on_tick, onTick)
