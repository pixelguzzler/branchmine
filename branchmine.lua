-- branchmine.lua
-- ComputerCraft Turtle branch miner with torch placement
-- Mines a main hallway with left/right branches at intervals.

-- ============ CONFIG ============
local mainLen        = 200   -- length of main corridor
local branchLen      = 40    -- length of each side branch
local branchSpacing  = 6     -- distance between branch starts along main corridor
local torchEvery     = 8     -- torch interval inside branches
local minFuelBuffer  = 200   -- try to keep at least this much fuel

-- Torch item matching: supports "minecraft:torch" and most modded torches with "torch" in name
local function isTorch(name)
  if not name then return false end
  name = string.lower(name)
  return (name == "minecraft:torch") or (string.find(name, "torch") ~= nil)
end

-- Items considered "junk" and safe to dump (edit as needed)
local junkPatterns = {
  "cobblestone", "dirt", "gravel", "andesite", "diorite", "granite",
  "tuff", "deepslate", "netherrack", "sand", "flint"
}

local function isJunk(name)
  if not name then return false end
  name = string.lower(name)
  for _, pat in ipairs(junkPatterns) do
    if string.find(name, pat) then return true end
  end
  return false
end

-- ============ UTILS ============
local function selectFirstTorchSlot()
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and isTorch(d.name) then
      turtle.select(i)
      return true
    end
  end
  return false
end

local function ensureFuel()
  local fuel = turtle.getFuelLevel()
  if fuel == "unlimited" then return true end
  if fuel >= minFuelBuffer then return true end

  -- Try refuel from any fuel items
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then
      turtle.select(i)
      -- Refuel 1 at a time to avoid burning stacks unexpectedly
      if turtle.refuel(1) then
        if turtle.getFuelLevel() >= minFuelBuffer then
          return true
        end
      end
    end
  end

  print("Low fuel! Please add fuel to turtle inventory.")
  return false
end

local function digForwardSafe()
  while turtle.detect() do
    turtle.dig()
    sleep(0.1)
  end
end

local function forwardSafe()
  ensureFuel()
  while not turtle.forward() do
    -- If something blocks movement, try digging/attacking
    if turtle.detect() then turtle.dig() end
    turtle.attack()
    sleep(0.1)
  end
end

local function digUpSafe()
  while turtle.detectUp() do
    turtle.digUp()
    sleep(0.1)
  end
end

local function digDownSafe()
  while turtle.detectDown() do
    turtle.digDown()
    sleep(0.1)
  end
end

local function clear3High()
  -- Make a 1x1 tunnel that is 3 blocks tall (floor unchanged)
  digForwardSafe()
  forwardSafe()
  digUpSafe()
  turtle.up()
  digUpSafe()
  turtle.up()
  -- Now at y+2 relative to entry; come back down to floor level of movement
  turtle.down()
  turtle.down()
end

local function placeTorchDown()
  if not selectFirstTorchSlot() then
    -- No torches available; silently skip
    return false
  end
  -- Prefer placing on floor; if occupied, try place on wall ahead
  if turtle.detectDown() then
    -- placing torch on a block below is fine
    turtle.placeDown()
    return true
  else
    -- If there's air below (cave), try forward placement instead
    if turtle.detect() then
      turtle.place()
      return true
    end
  end
  return false
end

local function inventoryNearlyFull()
  local empty = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) == 0 then empty = empty + 1 end
  end
  return empty <= 1
end

local function dumpJunkToChestBehind()
  -- Optional: If you place a chest behind the turtle at start, it will dump junk into it.
  turtle.turnLeft()
  turtle.turnLeft()
  for i = 1, 16 do
    local d = turtle.getItemDetail(i)
    if d and isJunk(d.name) then
      turtle.select(i)
      turtle.drop()
    end
  end
  turtle.turnLeft()
  turtle.turnLeft()
end

-- ============ BRANCH MINING ============
local function mineBranch(length)
  -- Assumes turtle is facing into the branch direction on the main corridor line.
  -- Places a torch at branch start, then every torchEvery blocks.
  placeTorchDown()

  for i = 1, length do
    clear3High()

    if (i % torchEvery) == 0 then
      placeTorchDown()
    end

    if inventoryNearlyFull() then
      -- Try dumping junk into chest behind (back at start of branch would be ideal, but we keep it simple)
      -- If you want perfect behavior: you can implement a return-to-main routine here.
      dumpJunkToChestBehind()
    end
  end

  -- Return to main corridor line
  turtle.turnLeft()
  turtle.turnLeft()
  for i = 1, length do
    forwardSafe()
  end
  turtle.turnLeft()
  turtle.turnLeft()
end

local function run()
  print("Branch miner starting...")
  if not ensureFuel() then return end

  local steps = 0
  while steps < mainLen do
    -- Move forward one in main corridor
    clear3High()
    steps = steps + 1

    -- Every branchSpacing blocks, cut branches
    if (steps % branchSpacing) == 0 then
      -- Left branch
      turtle.turnLeft()
      mineBranch(branchLen)
      turtle.turnRight()

      -- Right branch
      turtle.turnRight()
      mineBranch(branchLen)
      turtle.turnLeft()
    end

    if inventoryNearlyFull() then
      dumpJunkToChestBehind()
    end
  end

  print("Done. Main corridor length reached.")
end

run()
