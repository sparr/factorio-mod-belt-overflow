local util = require("util")

---@alias BeltLikeEntity LuaEntity.TransportBelt|LuaEntity.UndergroundBelt|LuaEntity.Splitter|LuaEntity.TransportBeltConnectable|LuaEntity.Ghost

---@class TerminalBelt
---@field indicator? LuaEntity UI indicator rendered on top of a belt
---@field entity BeltLikeEntity The belt, underground, or splitter that might be terminal
---@field lines integer[] The indices of the transport lines of this belt that might be terminal

---@class Array2D<T>: { [number]: { [number]: T } }

---For performing arithmetic on directions
---@alias DirectionInteger defines.direction|integer

---@type {}
global=global

---Cache of all belts that are "terminal", i.e. might be the start of an overflow
---@type Array2D<TerminalBelt>
global.terminal_belts = global.terminal_belts
---@alias CurveBelts Array2D<"right"|"left">
---Cache of all belts that are corners
---@type CurveBelts
global.curve_belts = global.curve_belts

-- poll_frequency is checks per second, polling_cycles is ticks per check
local polling_cycles = math.floor(60 / settings.global['belt_overflow_poll_frequency'].value)

-- use of math.random() during game loading was broken due to desyncs somewhere around 0.15.25
-- local polling_remainder = math.random(polling_cycles)-1
local polling_remainder = 23 % polling_cycles


---@param entity LuaEntity.UndergroundBelt
---@return boolean
local function has_real_underground_neighbours(entity)
  return entity and entity.valid and entity.neighbours and entity.neighbours.type ~= 'entity-ghost'
end

---North=0, East=90 degrees clockwi se, South=180, West=270
---@alias Rotation DirectionInteger

---@class (exact) POSD
---@field pos Vector
---@field d DirectionInteger

local defines_direction = defines.direction
local N, E, S, W = defines_direction.north, defines_direction.east, defines_direction.south, defines_direction.west

---Rotates a POSD around the origin by the given amount
---@param posd POSD
---@param rotation Rotation
---@return POSD
local function rotate_posd(posd,rotation)
  local x,y,d = posd.pos[1],posd.pos[2],posd.d
  if     rotation == S then
    d = (d + 4) % 8
    x, y = -x, -y
  elseif rotation == E then
    d = (d + 2) % 8
    ---I don't know why the `y` here intermittently produces a no-unknown violation
    ---@diagnostic disable-next-line: no-unknown
    x, y = -y, x
  elseif rotation == W then
    d = (d + 6) % 8
    x, y = y, -x
  end
  return {pos={x, y}, d=d}
end

---Rotates a position around the origin by the given amount
---@param pos Vector
---@param rotation Rotation
---@return POSD
local function rotate_pos(pos, rotation)
  return rotate_posd( {pos=pos, d=N}, rotation)
end

---Takes non-ghost filter params and finds equivalent ghosts
---@param surface LuaSurface
---@param param LuaSurface.find_entities_filtered_param
local function find_ghost_entities_filtered(surface, param)
  new_param = util.table.deepcopy(param)
  new_param.ghost_name = new_param.name
  new_param.ghost_type = new_param.type
  new_param.name = "entity-ghost"
  new_param.type = "entity-ghost"
  -- TODO support collision_mask filter by looking up the prototype for the ghost_name  
  return surface.find_entities_filtered(new_param)
end

---@param surface LuaSurface
---@param pos Vector
---@param ghosts boolean
---@return BeltLikeEntity?
local function find_belt_at(surface,pos,ghosts)
  ---@type LuaSurface.find_entities_filtered_param
  local param = {position=pos, radius=0, type="transport-belt"}
  ---@type BeltLikeEntity
  local targets
  targets = (surface.find_entities_filtered(param))--[[@as LuaEntity.TransportBelt]]
  if targets[1] then return targets[1] end
  if ghosts then
    targets = (find_ghost_entities_filtered(surface, param))--[[@as LuaEntity.Ghost]]
    if targets[1] then return targets[1] end
  end
  param.type = "underground-belt"
  targets = (surface.find_entities_filtered(param))--[[@as LuaEntity.UndergroundBelt]]
  if targets[1] then return targets[1] end
  if ghosts then
    targets = (find_ghost_entities_filtered(surface, param))--[[@as LuaEntity.Ghost]]
    if targets[1] then return targets[1] end
  end
  param.radius = nil
  param.type = "splitter"
  targets = (surface.find_entities_filtered(param))--[[@as LuaEntity.Splitter]]
  if targets[1] then return targets[1] end
  if ghosts then
    targets = (find_ghost_entities_filtered(surface, param))--[[@as LuaEntity.Ghost]]
    if targets[1] then return targets[1] end
  end
  return nil
end


---Identify which transport lines on a BeltLikeEntity are potentially terminal
---@param args check_and_update_entity_param
---@return integer[] lines Indices of the terminal belt lines
local function terminal_belt_lines(args)
  local entity = args.entity
  local entity_to_ignore = args.entity_to_ignore
  local entity_type = entity.type
  if entity == entity_to_ignore then return {} end
  if entity_type == "underground-belt" and
    entity.belt_to_ground_type == "input" then
    if has_real_underground_neighbours(entity--[[@as LuaEntity.UndergroundBelt]]) and entity.neighbours ~= entity_to_ignore then
      -- underground input can't be terminal if the output exists and isn't being removed
      return {}
    else
      return {1, 2, 3, 4}
    end
  end
  ---@type DirectionInteger
  local entity_direction = entity.direction
  ---@type Vector
  local entity_position = entity.position
  local entity_position_x, entity_position_y = entity_position.x, entity_position.y
  -- debug(dir)
  -- debug(pos)
  entity_position[1] = entity_position_x
  entity_position[2] = entity_position_y
  ---The position(s) and line indices to check for terminal-ness on this entity
  ---@type { pos: Vector, lines: integer[] }[]
  local to_check = {}
  if entity_type=="splitter" then
    -- the center of a splitter is half a tile off from the center of either of its two tiles we might be checking
    local rotated = rotate_pos({-0.5,0},entity_direction)
    local dx,dy = rotated.pos[1], rotated.pos[2]
    to_check = {
      {pos={entity_position_x+dx,entity_position_y+dy},lines={5,6}},
      {pos={entity_position_x-dx,entity_position_y-dy},lines={7,8}}
    }
  elseif entity_type=="underground-belt" and
    entity.belt_to_ground_type=="input" then
    -- TODO this might be redundant with early returns above, and might be wrong. investigate.
    to_check = {{pos=entity_position,lines={3,4}}}
  else
    to_check = {{pos=entity_position,lines={1,2}}}
  end
  if #to_check>0 then
    ---The line indices identified as terminal
    ---@type integer[]
    local result_lines = {}
    ---Add line indices to `result_lines`
    ---@param lines integer[]
    local function result(lines)
      for _,line in pairs(lines) do
        result_lines[#result_lines+1] = line
      end
    end
    -- following code originally copied from https://github.com/sparr/factorio-mod-belt-combinators
    for _,check in pairs(to_check) do
      -- debug("checking "..pos2s(check.pos))
      local rotated = rotate_pos({0,-1},entity_direction)
      local dx,dy = rotated.pos[1], rotated.pos[2]
      ---@type Vector
      local target_position = {check.pos[1]+dx,check.pos[2]+dy}
      -- debug("tpos "..pos2s(tpos))
      local target = find_belt_at(entity.surface, target_position, false)
      -- debug("target "..serpent.line(target))
      if target ~= nil and target ~= entity_to_ignore then
        -- debug("target found " .. target.type)
        local check_lines = check.lines
        local target_direction = target.direction
        -- fast belts can overflow onto slow belts
        if entity.prototype.belt_speed > target.prototype.belt_speed then
          result(check_lines)
        -- nothing accepts connections from the front
        elseif math.abs(target_direction - entity_direction)==4 then
          result(check_lines)
        -- underground belt outputs don't accept connections from behind
        elseif target.type=="underground-belt" and
          target.belt_to_ground_type=="output" and
          target_direction==entity_direction then
          result(check_lines)
        -- splitters don't accept connections from the side or front
        elseif target.type=="splitter" and target_direction~=entity_direction then
          result(check_lines)
        else
          -- insertion from the side can be terminal
          if target_direction~=entity_direction then
            local turn = false
            -- belts can be curves, anything else must side load and thus is terminal
            if target.type=='transport-belt' then
              ---Is there a belt feeding into the start or other side of the target belt?
              local belt_behind_target = false
              rotated = rotate_pos({0,1},target_direction)
              local tpxd,tpyd=rotated.pos[1], rotated.pos[2]
              rotated = rotate_pos({0,-2},entity_direction)
              local pxd, pyd =rotated.pos[1], rotated.pos[2]
              local bpd = {
                {pos={target.position.x+tpxd,target.position.y+tpyd},dir=target_direction},
                {pos={entity_position_x+pxd,entity_position_y+pyd},dir=(entity_direction+4)%8}
              }
              for _,bpos in pairs(bpd) do
                -- debug("checking for belt-behind at "..pos2s(bpos.pos).." dir="..bpos.dir)
                local candidate = find_belt_at(entity.surface, bpos.pos, true)
                if candidate ~= nil and candidate ~= entity_to_ignore then
                  -- underground inputs don't cause T junctions when pointed at transport belts
                  if not ((candidate.type == "underground-belt" or candidate.ghost_type == "underground-belt") and candidate.belt_to_ground_type == "input") then
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
              if belt_behind_target then
                -- target belt doesn't curve
                if global.curve_belts[target.position.y] and global.curve_belts[target.position.y][target.position.x] then
                  global.curve_belts[target.position.y][target.position.x] = nil
                  if next(global.curve_belts[target.position.y]) == nil then
                    global.curve_belts[target.position.y] = nil
                  end
                end
              else
                turn = true
                if not global.curve_belts[target.position.y] then global.curve_belts[target.position.y]={} end
                global.curve_belts[target.position.y][target.position.x] = ((target_direction-entity_direction+8)%8==2) and "right" or "left"
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
    if entity_type=="splitter" and #result_lines>0 then return {5,6,7,8} end
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
    if next(global.terminal_belts[y]) == nil then
      global.terminal_belts[y] = nil
    end
  end
end

---@alias LineCaps (integer?)[]
---@type { [string]: LineCaps }
local line_caps = {curve_right={5,2},curve_left={2,5},straight={4,4},underground={2,2,4,4},splitter={nil,nil,nil,nil,2,2,2,2}}

---@param event EventData.on_tick
local function onTick(event)
  if event.tick%polling_cycles == polling_remainder then
    for y,row in pairs(global.terminal_belts) do
      for x,terminal_belt in pairs(row) do
        -- -- debug(x..','..y)
        if not terminal_belt.entity or not terminal_belt.entity.valid then
          cleartermbelt(x,y)
        else
          local entity = terminal_belt.entity
          local pos = entity.position
          local caps --[[@type LineCaps]]
          if entity.type=="transport-belt" then
            if global.curve_belts[pos.y] and global.curve_belts[pos.y][pos.x]=="right" then
              caps=line_caps.curve_right
            elseif global.curve_belts[pos.y] and global.curve_belts[pos.y][pos.x]=="left" then
              caps=line_caps.curve_left
            else
              caps=line_caps.straight
            end
          elseif entity.type=="underground-belt" then
            caps=line_caps.underground
          elseif entity.type=="splitter" then
            caps=line_caps.splitter
          end
          ---
          ---@type boolean[]
          local ground_prefill = {}
          for i=1,#terminal_belt.lines do
            local line = terminal_belt.lines[i]
            -- debug(pos2s(pos)..' line '..line..':')
            local tl = entity.get_transport_line(line)
            local item_name --[[@type string]]
            if tl.get_item_count()>=caps[line] then
              item_name = tl[1].name
              if entity.type=="underground-belt" and
                entity.belt_to_ground_type=="input" and
                has_real_underground_neighbours(entity--[[@as LuaEntity.UndergroundBelt]]) and
                line<3 then
                -- track this for future reference, but don't overflow here
                ground_prefill[line]=true
              elseif entity.type=="underground-belt" and
                entity.belt_to_ground_type=="input" and
                has_real_underground_neighbours(entity--[[@as LuaEntity.UndergroundBelt]]) and
                line>2 and not ground_prefill[line-2] then
                -- do nothing, this won't overflow until the prior line overflows
              else
                -- debug("overflow "..e.type.." "..line.." "..tl.get_item_count())
                -- overflow!
                -- figure out where the overflow spot is
                local x,y = pos.x,pos.y
                local dir = entity.direction
                local dx,dy = 0,0
                if entity.type=="underground-belt" and entity.belt_to_ground_type=="input" then
                  -- spill beside the underground input
                  dy = dy + 0.25
                  if (line%2)==0 then
                    dx = dx + 0.65
                  else
                    dx = dx - 0.65
                  end
                else
                  -- spill past the end of the belt
                  dy = dy - 1.05
                  if entity.type=="splitter" then
                    if line==5 or line==6 then dx = dx-0.5 else dx = dx+0.5 end
                  end
                  if (line%2)==0 then dx = dx + 0.23 else dx = dx - 0.23 end
                end
                -- rotate the coordinate deltas
                local rotated = rotate_pos({dx,dy},dir)
                local rpx,rpy = rotated.pos[1], rotated.pos[2]
                local spill_pos = {x + rpx, y + rpy}
                local itemstack = {name=item_name, count=1}
                -- if e.surface.find_entity("item-on-ground", spill_pos) then
                  entity.surface.spill_item_stack(spill_pos, itemstack)
                -- disabled this condition for performance reasons
                -- else -- spill always skips the target spot, fill it first
                --   e.surface.create_entity{name="item-on-ground",
                --     position=spill_pos, force=e.force,
                --     stack={name=item_name, count=1}}
                -- end
                -- if tl.remove_item(itemstack)==0 then
                --   -- debug("belt-overflow failed to remove "..item_name)
                -- else
                --   -- debug("removed "..item_name.." at "..pos2s(pos))
                -- end
              end
            end
          end
        end
      end
    end
  end
end

---Create an indicator entity to render above a given entity, if the indicator option is enabled
---@param entity BeltLikeEntity The entity to create an indicator above
---@return LuaEntity|nil The created indicator entity, or nil if none was created
local function create_indicator(entity)
  if settings.global['belt_overflow_draw_indicators'].value then
    local indicator_entity_name = "belt-overflow-indicator"
    if entity.type == "splitter" then
      if (entity.direction%4)==0 then
        indicator_entity_name = indicator_entity_name .. "-wide"
      else
        indicator_entity_name = indicator_entity_name .. "-tall"
      end
    end
    return entity.surface.create_entity{
              name = indicator_entity_name,
              position = entity.position
            }
  end
  return nil
end

---@class EntityToIgnore
---@field entity_to_ignore? BeltLikeEntity An entity that should be ignored while checking, probably because it's being deleted

---@class check_and_update_entity_param:EntityToIgnore
---@field entity BeltLikeEntity

---Evaluate a belt-like entity and cache or un-cache it as terminal as appropriate
---@param args check_and_update_entity_param
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

---Evaluate a belt-like entity at a given POSD and cache or un-cache it as terminal as appropriate
---@param posd POSD
---@param surface LuaSurface
---@param entity_to_ignore BeltLikeEntity?
local function check_and_update_posd(posd,surface,entity_to_ignore)
  local x, y = posd.pos[1], posd.pos[2]
  local box = {{x-0.5,y-0.5},{x+0.5,y+0.5}}
  local candidates = surface.find_entities(box)
  for _,candidate in pairs(candidates) do
    if candidate.valid then
      if candidate.type == "transport-belt" or
        candidate.type == "underground-belt" or
        candidate.type == "splitter" then
        if candidate.direction == posd.d then
          if candidate ~= entity_to_ignore then
            check_and_update_entity{entity=candidate--[[@as BeltLikeEntity]],entity_to_ignore=entity_to_ignore}
          end
        end
      end
    end
  end
end


---@class params_entity_removal
---@field entity BeltLikeEntity The entity to check the neighbors of
---@field removal boolean Is the entity being checked because it's being removed?

---@alias Neighborhood POSD[]

---Relative location and direction of neighbors that could be affected by a change to an entity
---Relative direction assumes the origin entity is pointing north
---@type { [string]: Neighborhood }
local neighborhoods = {
  belt = {
    {pos={0,0},d=N}, -- check this entity itself
    {pos={-1,0},d=E},{pos={1,0},d=W}, -- left and right sides can change if they point at this belt
    {pos={0,1},d=N}, -- ditto behind
    {pos={-1,-1},d=E},{pos={1,-1},d=W}, -- ahead and left/right can change if they point at the same belt as this does
    {pos={0,-2},d=S} -- and so can two-ahead
  },
  input = {
    {pos={0,0},d=N}, -- check this entity itself
    {pos={0,1},d=N}  -- and the entity behind it
  },
  output = {
    {pos={0,0},d=N}, -- check this entity itself
    {pos={-1,-1},d=E},{pos={1,-1},d=W}, -- ahead and left/right can change if they point at the same belt as this does
    {pos={0,-2},d=S} -- and so can two-ahead
  },
  splitter = {
    {pos={0,0},d=N}, -- check this entity itself
    {pos={-0.5,1},d=N},{pos={0.5,1},d=N}, -- behinds can change if they point at this splitter
    {pos={-1.5,-1},d=E},{pos={1.5,-1},d=W}, -- aheads and left/right can change if they point at the same belt as this does
    {pos={-0.5,-2},d=S},{pos={0.5,-2},d=S} -- and so can two-aheads
  }
}

---Evaluate a neighborhood of belt-like entities and cache or un-cache them as terminal as appropriate
---@param args params_entity_removal
local function check_and_update_neighborhood(args)
  local entity = args.entity
  local removal = args.removal
  ---@type Neighborhood
  local neighborhood
  if entity.type == "transport-belt" then
    neighborhood = neighborhoods.belt
  elseif entity.type == "underground-belt" then
    if entity.belt_to_ground_type == "input" then
      neighborhood = neighborhoods.input
    else
      neighborhood = neighborhoods.output
    end
    if has_real_underground_neighbours(entity--[[@as LuaEntity.UndergroundBelt]]) then
      check_and_update_entity{entity=entity.neighbours--[[@as LuaEntity.UndergroundBelt]],entity_to_ignore=removal and entity or nil}
    end
  elseif entity.type == "splitter" then
    neighborhood = neighborhoods.splitter
  end
  for _,posd in pairs(neighborhood) do
    posd = rotate_posd(posd,entity.direction)
    if removal and posd[1]==0 and posd[2]==0 then
      -- skip checking the to-be-removed element itself
    else
      check_and_update_posd({pos={entity.position.x+posd.pos[1],entity.position.y+posd.pos[2]},d=posd.d},entity.surface,removal and entity or nil)
    end
  end
  if removal then cleartermbelt(entity.position.x,entity.position.y) end
end

---@param args params_entity_removal
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

---Use find_entities_filtered across all chunks in all surfaces
---Thanks to KeyboardHack on irc.freenode.net #factorio for this function
---@param args LuaSurface.find_entities_filtered_param
---@return LuaEntity[] entites
local function find_all_entities(args)
  ---@type LuaEntity[]
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
    for _,e in pairs((find_all_entities{type=type})--[=[@as BeltLikeEntity[]]=]) do
      check_and_update_entity{entity=e}
    end
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
          if belt.indicator and belt.indicator.valid then belt.indicator.destroy() end
          belt.indicator = nil
        end
      end
    end
  end
end

local function onInit()
  if global.terminal_belts == nil then
    refreshData()
  end
end

local function onConfigurationChanged()
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

script.on_event(defines.events.on_pre_player_mined_item, onRemoveEntity)
script.on_event(defines.events.on_robot_pre_mined, onRemoveEntity)
script.on_event(defines.events.on_entity_died, onRemoveEntity)

script.on_event(defines.events.on_tick, onTick)

remote.add_interface("belt-overflow",
                      {refreshData = refreshData}
                    )
