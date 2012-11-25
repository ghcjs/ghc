cabal unpack mtl-2.1.2
rm -rf libraries/mtl
mv mtl-2.1.2 libraries/mtl

cabal unpack syb-0.3.7
rm -rf libraries/syb
mv syb-0.3.7 libraries/syb

#cabal unpack jmacro-0.6.2
#rm -rf libraries/jmacro
#mv jmacro-0.6.2 libraries/jmacro

cabal unpack parsec-3.1.3
rm -rf libraries/parsec
mv parsec-3.1.3 libraries/parsec

cabal unpack haskell-src-meta-0.6.0.1
rm -rf libraries/haskell-src-meta
mv haskell-src-meta-0.6.0.1 libraries/haskell-src-meta

cabal unpack haskell-src-exts-1.13.5
rm -rf libraries/haskell-src-exts
mv haskell-src-exts-1.13.5 libraries/haskell-src-exts
happy libraries/haskell-src-exts/src/Language/Haskell/Exts/InternalParser.ly

cabal unpack wl-pprint-text-1.1.0.0
rm -rf libraries/wl-pprint-text
mv wl-pprint-text-1.1.0.0 libraries/wl-pprint-text

cabal unpack text-0.11.2.3
rm -rf libraries/text
mv text-0.11.2.3 libraries/text

cabal unpack unordered-containers-0.2.2.1
rm -rf libraries/unordered-containers
mv unordered-containers-0.2.2.1 libraries/unordered-containers

cabal unpack hashable-1.1.2.5
rm -rf libraries/hashable
mv hashable-1.1.2.5 libraries/hashable

cabal unpack vector-0.10
rm -rf libraries/vector
mv vector-0.10 libraries/vector

cabal unpack primitive-0.5
rm -rf libraries/primitive
mv primitive-0.5 libraries/primitive

cabal unpack aeson-0.6.0.2
rm -rf libraries/aeson
mv aeson-0.6.0.2 libraries/aeson

cabal unpack attoparsec-0.10.2.0
rm -rf libraries/attoparsec
mv attoparsec-0.10.2.0 libraries/attoparsec

cabal unpack blaze-builder-0.3.1.0
rm -rf libraries/blaze-builder
mv blaze-builder-0.3.1.0 libraries/blaze-builder

cabal unpack safe-0.3.3
rm -rf libraries/safe
mv safe-0.3.3 libraries/safe

cabal unpack regex-posix-0.95.2
rm -rf libraries/regex-posix
mv regex-posix-0.95.2 libraries/regex-posix

cabal unpack regex-base-0.93.2
rm -rf libraries/regex-base
mv regex-base-0.93.2 libraries/regex-base

cabal unpack cpphs-1.14
rm -rf libraries/cpphs
mv cpphs-1.14 libraries/cpphs

cabal unpack th-orphans-0.6
rm -rf libraries/th-orphans
mv th-orphans-0.6 libraries/th-orphans

cabal unpack th-lift-0.5.5
rm -rf libraries/th-lift
mv th-lift-0.5.5 libraries/th-lift

cabal unpack dlist-0.5
rm -rf libraries/dlist
mv dlist-0.5 libraries/dlist

cabal unpack parseargs-0.1.3.2
rm -rf libraries/parseargs
mv parseargs-0.1.3.2 libraries/parseargs

cabal unpack cereal-0.3.5.2
rm -rf libraries/cereal
mv cereal-0.3.5.2 libraries/cereal

cabal unpack lens-3.2
rm -rf libraries/lens
mv lens-3.2 libraries/lens

cabal unpack comonad-3.0.0.2
rm -rf libraries/comonad
mv comonad-3.0.0.2 libraries/comonad

cabal unpack comonad-transformers-3.0
rm -rf libraries/comonad-transformers
mv comonad-transformers-3.0 libraries/comonad-transformers

cabal unpack comonads-fd-3.0
rm -rf libraries/comonads-fd
mv comonads-fd-3.0 libraries/comonads-fd

cabal unpack parallel-3.2.0.3
rm -rf libraries/parallel
mv parallel-3.2.0.3 libraries/parallel

cabal unpack semigroups-0.8.4.1
rm -rf libraries/semigroups
mv semigroups-0.8.4.1 libraries/semigroups

cabal unpack contravariant-0.2.0.2
rm -rf libraries/contravariant
mv contravariant-0.2.0.2 libraries/contravariant

cabal unpack distributive-0.2.2
rm -rf libraries/distributive
mv distributive-0.2.2 libraries/distributive

cabal unpack semigroupoids-3.0.0.1
rm -rf libraries/semigroupoids
mv semigroupoids-3.0.0.1 libraries/semigroupoids

cabal unpack yaml-0.8.1.1
rm -rf libraries/yaml
mv yaml-0.8.1.1 libraries/yaml

cabal unpack resourcet-0.4.4
rm -rf libraries/resourcet
mv resourcet-0.4.4 libraries/resourcet

cabal unpack conduit-0.5.4.1
rm -rf libraries/conduit
mv conduit-0.5.4.1 libraries/conduit

cabal unpack monad-control-0.3.1.4
rm -rf libraries/monad-control
mv monad-control-0.3.1.4 libraries/monad-control

cabal unpack lifted-base-0.2
rm -rf libraries/lifted-base
mv lifted-base-0.2 libraries/lifted-base

cabal unpack transformers-base-0.4.1
rm -rf libraries/transformers-base
mv transformers-base-0.4.1 libraries/transformers-base

cabal unpack base-unicode-symbols-0.2.2.4
rm -rf libraries/base-unicode-symbols
mv base-unicode-symbols-0.2.2.4 libraries/base-unicode-symbols

cabal unpack void-0.5.8
rm -rf libraries/void
mv void-0.5.8 libraries/void

cp -f ghcjs-patches/cpphs.cabal libraries/cpphs/
cp -f ghcjs-patches/parseargs.cabal libraries/parseargs/
cp mk/build.mk.sample mk/build.mk
echo "HADDOCK_DOCS = NO" >> mk/build.mk
cd libraries
rm -rf jmacro
darcs get --lazy http://patch-tag.com/r/gershomb/jmacro
darcs apply --repodir=jmacro ../ghcjs-patches/jmacro.patch
cd ghcjs
git checkout gen2
cd ../..
patch -p0 < ghcjs-patches/th-orphans.patch

