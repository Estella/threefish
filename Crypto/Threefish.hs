{-# LANGUAGE MultiParamTypeClasses, FunctionalDependencies #-}
-- | 256 and 512 bit variants of the Threefish block cipher used as the
--   foundation of the Skein hash function.
module Crypto.Threefish (  
    Block256, Threefish256, Key256,
    Block512, Threefish512, Key512,
    Tweak (..), parseHex, readHex, defaultTweak,
    Threefish (..)
) where
import Crypto.Threefish.Threefish256 as TF256
import Crypto.Threefish.Threefish512 as TF512
import Crypto.Threefish.Common as Common
import Data.Serialize
import qualified Data.ByteString as BS

class Serialize a => Threefish a b | a -> b where
  -- | Create a Threefish key using a custom tweak value.
  threefishKey :: Tweak -> a -> b
  -- | Encrypt a block using the given key and tweak value.
  threefishEncrypt :: a -> Tweak -> a -> a
  -- | Decrypt a block using the given key and tweak value.
  threefishDecrypt :: a -> Tweak -> a -> a
  -- | Create an appropriately sized block.
  toBlock :: BS.ByteString -> Maybe a
  -- | Extract the contents of a block.
  fromBlock :: a -> BS.ByteString

instance Threefish Block256 Threefish256 where
  threefishKey = Threefish256
  threefishEncrypt = encrypt256
  threefishDecrypt = decrypt256
  toBlock bs = if BS.length bs /= 32 then Nothing else Just (Block256 bs)
  fromBlock (Block256 bs) = bs

instance Threefish Block512 Threefish512 where
  threefishKey = Threefish512
  threefishEncrypt = encrypt512
  threefishDecrypt = decrypt512
  toBlock bs =
    case decode bs of
      Right block -> Just block
      _           -> Nothing
  fromBlock = encode
