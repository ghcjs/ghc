#!/bin/sh -ex

# Start from scratch
make distclean || true

# Normal GHC Build
perl boot
./configure --prefix=$HOME/ghcjs
make -j5 || make

# Build Stage 3 which has been set up to include GHCJS
make -j5 stage=3 || make stage=3

# Replace the stage 1 and 2 binaries with the stage 3 one
cp inplace/lib/ghc-stage3 inplace/lib/ghc-stage1
cp inplace/lib/ghc-stage3 inplace/lib/ghc-stage2
cp ghc/stage3/build/tmp/ghc-stage3 ghc/stage2/build/tmp/ghc-stage2

rm -rf compiler/stage2
rm -rf libraries/*/dist-install
rm -rf libraries/*/*/dist-install
make -j5 || make

# Replace the stage 1 and 2 binaries with the stage 3 one
cp inplace/lib/ghc-stage3 inplace/lib/ghc-stage2
cp ghc/stage3/build/tmp/ghc-stage3 ghc/stage2/build/tmp/ghc-stage2

# Delete the stuff that was built without JavaScript
rm -rf libraries/haskell98/dist-install
rm -rf libraries/haskell2010/dist-install
make -j5 || make

# Install
make install

export PATH=$HOME/ghcjs/bin:$PATH
hash -r

# Delete old ghcjs cabal if it is there
rm $HOME/ghcjs/bin/cabal || true
hash -r
cabal install cabal-install --prefix=$HOME/ghcjs
hash -r

ghc-pkg unregister HTTP
ghc-pkg unregister network
ghc-pkg unregister parsec
ghc-pkg unregister mtl
ghc-pkg unregister transformers
ghc-pkg unregister zlib
ghc-pkg unregister random
ghc-pkg unregister text

cabal install cabal-meta cabal-src --prefix=$HOME/ghcjs

cd libraries/ghcjs
cabal-meta install -f-compiler-only -fgen2 -ftrampoline -fplain

cd ../..
ghcjs-boot


