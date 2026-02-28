-- branchmine.lua (CC:Tweaked / ComputerCraft)
-- Branch miner (1x2) with periodic dump to a chest BEHIND the turtle at home.
-- Reliable torch placement: wall torch in CURRENT block only (no placeUp/placeDown).

local args = { ... }
local mainLength   = tonumber(args[1]) or 120
local branchLength = tonumber(args[2]) or 20
local spacing      = tonumber(args[3]) or 3
local dumpEvery    = tonumber(args[4]) or 6    -- dump every N branch-pairs (L+R). 0 disables periodic dumping.
local torchEvery   = tonumber(args[5]) or 0    -- place torch every N blocks in branches. 0 disables.

local TORCH_SLOT = 16

-- ---------------- Inventory / Fuel ----------------

local function invUsed()
  local used = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then used = used + 1 end
  end
  return used
end

local function invAlmostFull()
  -- Keep a couple slots free so we can pick up odd items.
  return invUsed() >= 14
end

local function ensureFuel(minNeeded)
  local lvl = turtle.getFuelLevel()
  if lvl == "unlimited" then return true end
  if lvl >= minNeeded then return true end

  for slot = 1, 16 do
    if slot ~= TORCH_SLOT then
      turtle.select(slot)
      if turtle.refuel(0) then
        while turtle.getFuelLevel() < minNeeded and turtle.refuel(1) do end
        if turtle.getFuelLevel() >= minNeeded then
          turtle.select(1)
          return true
        end
      end
    end
  end

  turtle.select(1)
  lvl = turtle.getFuelLevel()
  return (lvl == "unlimited") or (lvl >= minNeeded)
end

-- ---------------- Dig / Move helpers ----------------

local function digForward()
  while turtle.detect() do
    turtle.dig()
    sleep(0.05)
  end
  while not turtle.forward() do
    turtle.attack()
    sleep(0.05)
  end
end

local function digUp()
  while turtle.detectUp() do
    turtle.digUp()
    sleep(0.05)
  end
end

-- Mines one step forward of a 1x2 tunnel:
local function mineStep2High()
  digUp()
  digForward()
  digUp()
end

-- ---------------- Torch placement (fixed) ----------------
-- Place a WALL torch in the CURRENT block by clicking a solid wall.
-- Never places in front/behind/up/down, so it won't get mined by dig() / digUp().

local function placeTorch()
  if torchEvery <= 0 then return end
  if turtle.getItemCount(TORCH_SLOT) <= 0 then return end

  turtle.select(TORCH_SLOT)

  -- Place torch in the block BEHIND the turtle (air), so it won't get dug next step.
  turtle.turnLeft(); turtle.turnLeft()
  turtle.place()
  turtle.turnLeft(); turtle.turnLeft()

  turtle.select(1)
end

-- ---------------- Home / Dump ----------------
-- Home is where program starts.
-- Chest must be BEHIND the turtle at home.

local function goHome(stepsForward)
  turtle.turnLeft(); turtle.turnLeft()
  for i = 1, stepsForward do
    while not turtle.forward() do
      turtle.attack()
      sleep(0.05)
    end
  end
  turtle.turnLeft(); turtle.turnLeft()
end

local function dumpToChestBehind()
  -- Turn around so "forward" points into the chest behind home.
  turtle.turnLeft(); turtle.turnLeft()

  for slot = 1, 16 do
    -- Keep torches in TORCH_SLOT. Everything else gets dropped.
    if slot ~= TORCH_SLOT then
      turtle.select(slot)
      turtle.drop()
    end
  end

  turtle.select(1)
  turtle.turnLeft(); turtle.turnLeft()
end

-- ---------------- Branch mining ----------------

local function mineBranch(side, length)
  -- side: "L" or "R"
  if side == "L" then turtle.turnLeft() else turtle.turnRight() end

  for i = 1, length do
    mineStep2High()

    if torchEvery > 0 and (i % torchEvery == 0) then
      placeTorch()
    end

    if invAlmostFull() then
      -- Return to branch start, then face main corridor again, signal early dump.
      turtle.turnLeft(); turtle.turnLeft()
      for b = 1, i do
        while not turtle.forward() do
          turtle.attack()
          sleep(0.05)
        end
      end
      turtle.turnLeft(); turtle.turnLeft()

      if side == "L" then turtle.turnRight() else turtle.turnLeft() end
      return i, true
    end
  end

  -- Return to branch start
  turtle.turnLeft(); turtle.turnLeft()
  for i = 1, length do
    while not turtle.forward() do
      turtle.attack()
      sleep(0.05)
    end
  end
  turtle.turnLeft(); turtle.turnLeft()

  -- Face main corridor again
  if side == "L" then turtle.turnRight() else turtle.turnLeft() end
  return length, false
end

-- ---------------- Main routine ----------------

-- Fuel estimate: main out+back + branches out+back (both sides) + buffer
local branchCount = math.floor(mainLength / spacing)
local estimatedMoves = (mainLength * 2) + (branchCount * (branchLength * 4)) + 300

if not ensureFuel(estimatedMoves) then
  print("Not enough fuel. Add more fuel and run again.")
  print(("Need about %d moves worth of fuel. Current: %s"):format(estimatedMoves, tostring(turtle.getFuelLevel())))
  return
end

print(("Branch mining: main=%d, branch=%d, spacing=%d"):format(mainLength, branchLength, spacing))
print(("DumpEvery=%d (0 disables), TorchEvery=%d (0 disables)"):format(dumpEvery, torchEvery))
print("Chest must be behind turtle at start. Torches (optional) in slot 16.")

local forwardFromHome = 0
local branchPairsDone = 0

for step = 1, mainLength do
  mineStep2High()
  forwardFromHome = forwardFromHome + 1

  if step % spacing == 0 then
    local _, earlyL = mineBranch("L", branchLength)
    if earlyL then
      goHome(forwardFromHome)
      dumpToChestBehind()
      -- Return to this main-tunnel position
      for i = 1, forwardFromHome do mineStep2High() end
    end

    local _, earlyR = mineBranch("R", branchLength)
    if earlyR then
      goHome(forwardFromHome)
      dumpToChestBehind()
      for i = 1, forwardFromHome do mineStep2High() end
    end

    branchPairsDone = branchPairsDone + 1

    if dumpEvery > 0 and (branchPairsDone % dumpEvery == 0) then
      goHome(forwardFromHome)
      dumpToChestBehind()
      for i = 1, forwardFromHome do mineStep2High() end
    end

    -- keep fuel topped up a bit
    ensureFuel(200)
  end
end

-- Final return + dump
goHome(forwardFromHome)
dumpToChestBehind()

print("Done. Returned home and dumped.")
