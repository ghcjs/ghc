#!/bin/sh -ex

# Start from scratch
make distclean || true

# Normal GHC Build
perl boot
./configure --prefix=$HOME/ghcjs
make -j5 || make -j5 || make -j5 || make -j5

# Build Stage 3 which has been set up to include GHCJS
make -j5 stage=3 || make -j5 stage=3 || make -j5 stage=3 || make -j5 stage=3

# Replace the stage 1 and 2 binaries with the stage 3 one
cp inplace/lib/ghc-stage3 inplace/lib/ghc-stage1
cp inplace/lib/ghc-stage3 inplace/lib/ghc-stage2
cp ghc/stage3/build/tmp/ghc-stage3 ghc/stage2/Build/tmp/ghc-stage2

rm -rf compiler/stage2
rm -rf libraries/*/dist-install
rm -rf libraries/*/*/dist-install
make -j5 || make -j5 || make -j5 || make -j5

# Replace the stage 1 and 2 binaries with the stage 3 one
cp inplace/lib/ghc-stage3 inplace/lib/ghc-stage2
cp ghc/stage3/build/tmp/ghc-stage3 ghc/stage2/Build/tmp/ghc-stage2

# Delete the stuff that was built without JavaScript
rm -rf libraries/haskell98/dist-install
rm -rf libraries/haskell2010/dist-install
make -j5 || make -j5 || make -j5 || make -j5

# Install
make install

