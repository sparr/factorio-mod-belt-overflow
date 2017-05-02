local mod_version="0.15.0"
local mod_data_version="0.13.0"

global.terminal_belts = global.terminal_belts
global.curve_belts = global.curve_belts

-- poll_frequency is checks per second, polling_cycles is ticks per check
local polling_cycles = math.floor(60 / settings.global['belt_overflow_poll_frequency'].value)
local polling_remainder = math.random(polling_cycles)-1

-- local function debug(...)
--   if game and game.players[1] then
--     game.players[1].print("DEBUG: " .. serpent.line(...,{comment=false}))
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

-- takes in an [x,y,direction] and rotates it
local function rotate_posd(posd,rotation)
  local x,y,d = posd[1],posd[2],posd[3]
  if     rotation==defines.direction.south then
    d = (d + 4) % 8
    x, y = -x, -y
  elseif rotation==defines.direction.east then
    d = (d + 2) % 8
    x, y = -y, x
  elseif rotation==defines.direction.west then
    d = (d + 6) % 8
    x, y = y, -x
  end
  return x, y, d
end

local function rotate_pos(x, y, rotation)
  return rotate_posd( {x, y, 0}, rotation)
end

local function find_belt_at(surface,pos)
  local targets = surface.find_entities_filtered{position=pos, type="transport-belt"}
  if targets[1] == nil then
    targets = surface.find_entities_filtered{position=pos, type="underground-belt"}
  end
  if targets[1] == nil then
    targets = surface.find_entities_filtered{position=pos, type="splitter"}
  end
  if targets[1] == nil then
    return nil
  else
    return targets[1]
  end
end


local function terminal_belt_lines(args)
  local entity = args.entity
  local entity_to_ignore = args.entity_to_ignore
  if entity == entity_to_ignore then return {} end
  if entity.type == "underground-belt" and
    entity.belt_to_ground_type == "input" then
    if #entity.neighbours > 0 and entity.neighbours[1] ~= entity_to_ignore then
      return {}
    else
      return {1, 2, 3, 4}
    end
  end
  local dir = entity.direction
  local pos = entity.position
  -- debug(dir)
  -- debug(pos)
  pos[1] = pos.x
  pos[2] = pos.y
  local to_check = {}
  if entity.type=="splitter" then
    local dx,dy = rotate_pos(-0.5,0,dir)
    to_check = {
      {pos={pos.x+dx,pos.y+dy},lines={5,6}},
      {pos={pos.x-dx,pos.y-dy},lines={7,8}}
    }
  elseif entity.type=="underground-belt" and
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
      local target = find_belt_at(entity.surface, tpos)
      -- debug("target "..serpent.line(target))
      if target ~= nil and target ~= entity_to_ignore then
        -- debug("target found " .. target.type)
        -- fast belts can overflow onto slow belts
        if entity.prototype.belt_speed > target.prototype.belt_speed then
          result(check.lines)
        -- nothing accepts connections from the front
        elseif math.abs(target.direction-dir)==4 then
          result(check.lines)
        -- underground belt outputs don't accept connections from behind
        elseif target.type=="underground-belt" and
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
                local candidate = find_belt_at(entity.surface, bpos.pos)
                if candidate ~= nil and candidate ~= entity_to_ignore then
                  -- underground inputs don't cause T junctions when pointed at transport belts
                  if not (candidate.type == "underground-belt" and candidate.belt_to_ground_type == "input") then
                    -- debug("candidate "..candidate.type.." ".."dir="..candidate.direction)
                    if candidate.direction == bpos.dir then
                      -- debug("yep")
                      belt_behind_target = true
                    end
                    break
                  end
                end
                if belt_behind_target then break end
              end
              if not belt_behind_target then
                turn = true
                if not global.curve_belts[target.position.y] then global.curve_belts[target.position.y]={} end
                global.curve_belts[target.position.y][target.position.x] = ((target.direction-dir+8)%8==2) and "right" or "left"
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
    -- splitters can't be just half-terminal
    if entity.type=="splitter" and #result_lines>0 then return {5,6,7,8} end
    return result_lines
  end
  return {}
end

local function cleartermbelt(x,y)
  -- debug("clearing "..x..","..y)
  if global.terminal_belts[y] and global.terminal_belts[y][x] then
    if global.terminal_belts[y][x].indicator then
      -- debug("and your little dog, too")
      global.terminal_belts[y][x].indicator.destroy()
    end
    global.terminal_belts[y][x] = nil
  end
end

local line_caps = {curve_right={5,2},curve_left={2,5},straight={4,4},ground={2,2,4,4},splitter={nil,nil,nil,nil,2,2,2,2}}

local function onTick(event)
  if event.tick%polling_cycles == polling_remainder then
    for y,row in pairs(global.terminal_belts) do
      for x,belt in pairs(row) do
        -- -- debug(x..','..y)
        if not belt.entity or not belt.entity.valid then
          cleartermbelt(x,y)
        else
          local e = belt.entity
          local pos = e.position
          local caps
          if e.type=="transport-belt" then
            if global.curve_belts[pos.y] and global.curve_belts[pos.y][pos.x]=="right" then
              caps=line_caps.curve_right
            elseif global.curve_belts[pos.y] and global.curve_belts[pos.y][pos.x]=="left" then
              caps=line_caps.curve_left
            else
              caps=line_caps.straight
            end
          elseif e.type=="underground-belt" then
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
              end
              if e.type=="underground-belt" and
                e.belt_to_ground_type=="input" and
                line<3 then
                -- track this for future reference, but don't overflow here
                ground_prefill[line]=true
              elseif e.type=="underground-belt" and
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
                if e.type=="underground-belt" and e.belt_to_ground_type=="input" then
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
  if settings.global['belt_overflow_draw_indicators'].value then
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
  return nil
end

local function check_and_update_entity(args)
  local entity = args.entity
  local entity_to_ignore = args.entity_to_ignore
  if entity then
    local pos = entity.position
    t = terminal_belt_lines{entity=entity,entity_to_ignore=entity_to_ignore}
    if #t>0 then
      if not global.terminal_belts[pos.y] then global.terminal_belts[pos.y] = {} end
      if not global.terminal_belts[pos.y][pos.x] then
        global.terminal_belts[pos.y][pos.x] = {
          entity = entity,
          lines = t,
          indicator = create_indicator(entity)
        }
      else
        global.terminal_belts[pos.y][pos.x].entity = entity
        global.terminal_belts[pos.y][pos.x].lines = t
        if not global.terminal_belts[pos.y][pos.x].indicator then
          global.terminal_belts[pos.y][pos.x].indicator = create_indicator(entity)
        end
      end
      -- debug(pos2s(pos)..' terminal '..entity.type..' '..lines2s(global.terminal_belts[pos.y][pos.x].lines))
    else
      cleartermbelt(pos.x,pos.y)
      -- debug(pos2s(pos)..' non-terminal '..entity.type)
    end
  end
end

local function check_and_update_posd(posd,surface,entity_to_ignore)
  local box = {{posd[1]-0.5,posd[2]-0.5},{posd[1]+0.5,posd[2]+0.5}}
  local candidates = surface.find_entities(box)
  for _,candidate in pairs(candidates) do
    if candidate.valid then
      if candidate.type == "transport-belt" or
        candidate.type == "underground-belt" or
        candidate.type == "splitter" then
        if candidate.direction == posd[3] then
          if candidate ~= entity_to_ignore then
            check_and_update_entity{entity=candidate,entity_to_ignore=entity_to_ignore}
          end
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
  elseif entity.type == "underground-belt" then
    if entity.belt_to_ground_type == "input" then
      hood = {
        {0,0,0}, -- check this entity itself
        {0,1,0}  -- and the entity behind it
      }
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
  if removal then cleartermbelt(entity.position.x,entity.position.y) end
end

local function onModifyEntity(args)
  local entity=args.entity
  local removal=args.removal
  if entity.type=="transport-belt" or
    entity.type=="underground-belt" or
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
  -- forget all previously found terminal belts
  if global.terminal_belts then
    for y,row in pairs(global.terminal_belts) do
      for x,belt in pairs(row) do
        cleartermbelt(x,y)
      end
    end
  end
  -- destroy any remaining indicators
  for _,name in pairs({"belt-overflow-indicator","belt-overflow-indicator-wide","belt-overflow-indicator-tall"}) do
    for _,e in pairs(find_all_entities{name=name}) do
      e.destroy()
    end
  end
  global.terminal_belts={}
  global.curve_belts={}
  global.curve_belts = global.curve_belts
  global.terminal_belts = global.terminal_belts
  -- find all terminal belts
  for _,type in pairs({"transport-belt","underground-belt","splitter"}) do
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

local function updateIndicators()
  if global.terminal_belts then
    if settings.global['belt_overflow_draw_indicators'].value then
      -- add indicators to existing global.terminal_belts without them
      for y,row in pairs(global.terminal_belts) do
        for x,belt in pairs(row) do
          if (belt.indicator and not belt.indicator.valid) or not belt.indicator then
            belt.indicator = create_indicator(belt.entity)
          end
        end
      end
    else
      -- remove existing indicators
      for y,row in pairs(global.terminal_belts) do
        for x,belt in pairs(row) do
          if belt.indicator.valid then belt.indicator.destroy() end
          belt.indicator = nil
        end
      end
    end
  end
end

local function onInit()
  global.version=mod_version
  global.data_version=mod_data_version

  if global.terminal_belts == nil then
    refreshData()
  end
end

local function onConfigurationChanged()
  -- The only reason to have version/data_version is to trigger migrations, so do that here.
  checkForMigration(global.version, mod_version)
  checkForDataMigration(global.data_version, mod_data_version)

  onInit()
  updateIndicators()
end

local function onRuntimeModSettingChanged(args)
  if args.setting == "belt_overflow_draw_indicators" then
    updateIndicators()
  end
end

script.on_init(onInit)
script.on_configuration_changed(onConfigurationChanged)

script.on_event(defines.events.on_runtime_mod_setting_changed, onRuntimeModSettingChanged)

script.on_event(defines.events.on_built_entity, onPlaceEntity)
script.on_event(defines.events.on_robot_built_entity, onPlaceEntity)

script.on_event(defines.events.on_player_rotated_entity, onPlaceEntity)

script.on_event(defines.events.on_preplayer_mined_item, onRemoveEntity)
script.on_event(defines.events.on_robot_pre_mined, onRemoveEntity)
script.on_event(defines.events.on_entity_died, onRemoveEntity)

script.on_event(defines.events.on_tick, onTick)

remote.add_interface("belt-overflow",
                      {refreshData = refreshData}
                    )