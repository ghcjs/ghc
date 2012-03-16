import ConcRRSched
import MVarPrim
import System.Environment

putter sched m n = do
  (blockAct, unblockAct) <- getSchedActionPair sched
  -- print $ "Before Putting " ++ show n
  putMVarPrim blockAct unblockAct m n
  -- print $ "After Putting " ++ show n

taker sched m n = do
  (blockAct, unblockAct) <- getSchedActionPair sched
  -- print $ "Before Taking in " ++ show n
  v <- takeMVarPrim blockAct unblockAct m
  -- print $ "After Taking " ++ show n ++ " Value: " ++ show v
  return ()

parse (a:b:_) = (rInt a, rInt b)
parse otherwise = undefined

rInt :: String -> Int
rInt = read

main = do
  args <- getArgs
  let (c, maxTicks) = parse args
  m <- newEmptyMVarPrim
  sched <- newConcRRSched
  let fork task tick 0 = return ()
      fork task tick n = do
        forkIO sched $ task sched m n
        tick <- if tick == maxTicks
                   then do {
                     yield sched;
                     return 0
                   }
                   else return (tick+1)
        fork task tick $ n-1
  fork putter 0 c
  fork taker 0 c
  yield sched
