-- branchmine.lua
-- Usage: branchmine [mainLength] [branchLength] [spacing] [dumpEvery] [torchEvery]
-- Example: branchmine 120 20 3 6 8

local args = { ... }

local mainLength   = tonumber(args[1]) or 120
local branchLength = tonumber(args[2]) or 20
local spacing      = tonumber(args[3]) or 3
local dumpEvery    = tonumber(args[4]) or 6    -- branch-pairs between dumps; 0 disables periodic dumps
local torchEvery   = tonumber(args[5]) or 8    -- blocks between torches in the *main corridor*; 0 disables torches

local TORCH_SLOT = 16
local MAX_TRIES  = 60       -- how long we try before giving up on a move (ticks)
local SLEEP_T    = 0.05

-- ---------------- Utility ----------------

local function say(msg) print(msg) end

local function invUsed()
  local used = 0
  for i = 1, 16 do
    if turtle.getItemCount(i) > 0 then used = used + 1 end
  end
  return used
end

local function invAlmostFull()
  -- keep 2 slots free for overflow (and to avoid being jammed by random drops)
  return invUsed() >= 14
end

local function selectSafeSlot(preferred)
  if preferred and preferred >= 1 and preferred <= 16 then
    turtle.select(preferred)
    return
  end
  turtle.select(1)
end

local function isTorchSlot(slot) return slot == TORCH_SLOT end

-- Try to clear a blocked direction.
local function clearForward()
  if turtle.detect() then turtle.dig() end
  turtle.attack()
end

local function clearUp()
  if turtle.detectUp() then turtle.digUp() end
  turtle.attackUp()
end

local function clearDown()
  if turtle.detectDown() then turtle.digDown() end
  turtle.attackDown()
end

local function forward()
  for tries = 1, MAX_TRIES do
    if turtle.forward() then return true end
    clearForward()
    sleep(SLEEP_T)
  end
  return false
end

local function up()
  for tries = 1, MAX_TRIES do
    if turtle.up() then return true end
    clearUp()
    sleep(SLEEP_T)
  end
  return false
end

local function down()
  for tries = 1, MAX_TRIES do
    if turtle.down() then return true end
    clearDown()
    sleep(SLEEP_T)
  end
  return false
end

local function turnAround()
  turtle.turnLeft()
  turtle.turnLeft()
end

-- ---------------- Fuel ----------------

local function fuelLevel()
  return turtle.getFuelLevel()
end

local function hasUnlimitedFuel()
  return fuelLevel() == "unlimited"
end

-- Refuel from any slot except torches.
local function refuelTo(minNeeded)
  if hasUnlimitedFuel() then return true end
  if fuelLevel() >= minNeeded then return true end

  for slot = 1, 16 do
    if not isTorchSlot(slot) and turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      if turtle.refuel(0) then
        while fuelLevel() < minNeeded and turtle.refuel(1) do end
        if fuelLevel() >= minNeeded then
          selectSafeSlot(1)
          return true
        end
      end
    end
  end

  selectSafeSlot(1)
  return (hasUnlimitedFuel() or fuelLevel() >= minNeeded)
end

-- ---------------- Mining primitives ----------------

-- Mines a 2-high tunnel step (front + ceiling), and moves forward 1.
local function mineStep2High()
  -- clear ceiling at current spot
  clearUp()
  -- clear forward and move
  if not forward() then return false, "Stuck moving forward" end
  -- clear ceiling at new spot
  clearUp()
  return true
end

-- Place a torch behind the turtle on the floor (common corridor lighting).
local function placeTorchBehind()
  if torchEvery <= 0 then return end
  if turtle.getItemCount(TORCH_SLOT) <= 0 then return end

  -- place on the block behind turtle on the ground:
  -- turn around, try placeDown, turn back
  turtle.select(TORCH_SLOT)
  turnAround()
  turtle.placeDown()
  turnAround()
  selectSafeSlot(1)
end

-- ---------------- Navigation / dump ----------------

-- Return "home" along the main corridor by moving back N.
-- Uses forward() while facing back; more robust than turtle.back() loops.
local function goHome(stepsForward)
  turnAround()
  for i = 1, stepsForward do
    if not forward() then
      say("ERROR: couldn't return home; stuck while backtracking.")
      return false
    end
  end
  turnAround()
  return true
end

-- Dumps everything (except torches) into the chest behind the turtle.
local function dumpToChestBehind()
  turnAround()
  for slot = 1, 16 do
    if not isTorchSlot(slot) then
      turtle.select(slot)
      turtle.drop()
    end
  end
  selectSafeSlot(1)
  turnAround()
end

-- ---------------- Branch mining ----------------

-- side: "L" or "R"
-- returns: minedLen, earlyDumpNeeded(boolean)
local function mineBranch(side, length)
  if side == "L" then turtle.turnLeft() else turtle.turnRight() end

  local progressed = 0
  for i = 1, length do
    local ok, err = mineStep2High()
    if not ok then
      say(("ERROR in branch %s: %s"):format(side, err))
      -- try to retreat what we can
      break
    end
    progressed = progressed + 1

    if invAlmostFull() then
      -- back to branch start
      turnAround()
      for b = 1, progressed do
        if not forward() then
          say("ERROR: stuck returning from branch early (inventory full).")
          break
        end
      end
      turnAround()

      -- face main corridor again
      if side == "L" then turtle.turnRight() else turtle.turnLeft() end
      return progressed, true
    end
  end

  -- Return to branch start
  turnAround()
  for i = 1, progressed do
    if not forward() then
      say("ERROR: stuck returning from branch end.")
      break
    end
  end
  turnAround()

  -- face main corridor again
  if side == "L" then turtle.turnRight() else turtle.turnLeft() end
  return progressed, false
end

-- ---------------- Planning / safety checks ----------------

-- Conservative fuel estimate:
-- main out+back + (pairs * branches out+back) + buffer.
local branchPairsPlanned = math.floor(mainLength / spacing)
local estimatedMoves = (mainLength * 2) + (branchPairsPlanned * (branchLength * 4)) + 400
local MIN_RETURN_RESERVE = 200

say(("Branch mining: main=%d, branch=%d, spacing=%d"):format(mainLength, branchLength, spacing))
say(("dumpEvery=%d (0 disables), torchEvery=%d (0 disables)"):format(dumpEvery, torchEvery))
say("Chest must be behind turtle at start. Torches (optional) in slot 16.")

if not refuelTo(estimatedMoves + MIN_RETURN_RESERVE) then
  say("Not enough fuel. Add more fuel and run again.")
  say(("Need about %d+%d moves worth of fuel. Current: %s")
    :format(estimatedMoves, MIN_RETURN_RESERVE, tostring(fuelLevel())))
  return
end

-- ---------------- Main routine ----------------

local forwardFromHome = 0
local branchPairsDone = 0

for step = 1, mainLength do
  -- keep enough fuel to return home + some buffer
  if not hasUnlimitedFuel() then
    local needToReturn = forwardFromHome + MIN_RETURN_RESERVE
    if fuelLevel() < needToReturn then
      say("Fuel low vs return distance; going home to refuel/dump.")
      if not goHome(forwardFromHome) then return end
      dumpToChestBehind()
      if not refuelTo(estimatedMoves + MIN_RETURN_RESERVE) then
        say("Still not enough fuel after dumping/refuel attempt.")
        return
      end
      -- go back out
      for i = 1, forwardFromHome do
        local ok, err = mineStep2High()
        if not ok then say("ERROR returning to work position: " .. err); return end
      end
    end
  end

  local ok, err = mineStep2High()
  if not ok then
    say("ERROR main tunnel: " .. err)
    break
  end
  forwardFromHome = forwardFromHome + 1

  if torchEvery > 0 and (step % torchEvery == 0) then
    placeTorchBehind()
  end

  if step % spacing == 0 then
    -- Left branch
    local _, earlyL = mineBranch("L", branchLength)
    if earlyL then
      if not goHome(forwardFromHome) then return end
      dumpToChestBehind()
      if not refuelTo(estimatedMoves + MIN_RETURN_RESERVE) then
        say("Not enough fuel after dump.")
        return
      end
      for i = 1, forwardFromHome do
        local ok2, err2 = mineStep2High()
        if not ok2 then say("ERROR returning to position: " .. err2); return end
      end
    end

    -- Right branch
    local _, earlyR = mineBranch("R", branchLength)
    if earlyR then
      if not goHome(forwardFromHome) then return end
      dumpToChestBehind()
      if not refuelTo(estimatedMoves + MIN_RETURN_RESERVE) then
        say("Not enough fuel after dump.")
        return
      end
      for i = 1, forwardFromHome do
        local ok2, err2 = mineStep2High()
        if not ok2 then say("ERROR returning to position: " .. err2); return end
      end
    end

    branchPairsDone = branchPairsDone + 1

    -- Periodic dump
    if dumpEvery > 0 and (branchPairsDone % dumpEvery == 0) then
      if not goHome(forwardFromHome) then return end
      dumpToChestBehind()
      if not refuelTo(estimatedMoves + MIN_RETURN_RESERVE) then
        say("Not enough fuel after periodic dump.")
        return
      end
      for i = 1, forwardFromHome do
        local ok2, err2 = mineStep2High()
        if not ok2 then say("ERROR returning to position: " .. err2); return end
      end
    end

    -- top up a little (if fuel items are present)
    refuelTo(MIN_RETURN_RESERVE + forwardFromHome + 50)
  end
end

-- Final return + dump
if not goHome(forwardFromHome) then return end
dumpToChestBehind()
say("Done. Returned home and dumped.")
