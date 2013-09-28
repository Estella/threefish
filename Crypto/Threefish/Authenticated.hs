{-# LANGUAGE OverloadedStrings #-}
-- | Authenticated encryption using Skein for PRNG, KDF, stream cipher and MAC.
module Crypto.Threefish.Authenticated (
    DecryptFailure (..), Encrypted, Plaintext, Block256, Nonce256,
    encrypt, decrypt, encrypt', decrypt', generateNonce, toBlock, fromBlock
  ) where
import Crypto.Threefish
import Crypto.Threefish.Threefish256 (Block256(..))
import Crypto.Threefish.Skein
import Crypto.Threefish.Skein.KDF hiding (deriveKeys)
import qualified Crypto.Threefish.Skein.StreamCipher as SC
import Crypto.Threefish.Random
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy as BSL
import System.IO.Unsafe
import Data.IORef
import Data.Serialize
import Control.Monad

{-# NOINLINE prng #-}
prng :: IORef SkeinGen
prng = unsafePerformIO $ newSkeinGen >>= newIORef

-- | Generate a 256 bit nonce using the Skein PRNG.
generateNonce :: IO Nonce256
generateNonce =
    Block256 `fmap` atomicModifyIORef' prng (pflip . randomBytes 32)
  where
    pflip (a, b) = (b, a)

type MAC256 = Block256
type Plaintext = BSL.ByteString

data DecryptFailure = BadMAC | NoDecode String deriving Show

-- | An encrypt-then-MACed value. The binary format is as follows:
--   Bytes    What
--   0-31     256 bit nonce
--   32-63    256 bit Skein-MAC
--   64-71    Length of cryptotext as a 64 bit little endian word.
--   71-      Cryptotext
data Encrypted a = Encrypted {
    encNonce :: Nonce256, 
    encMAC   :: MAC256, 
    encData  :: BSL.ByteString
  } deriving Show

instance Serialize (Encrypted a) where
  put (Encrypted (Block256 nonce) (Block256 mac) cryptotext) = do
    putByteString nonce
    putByteString mac
    putWord64le (fromIntegral $ BSL.length cryptotext)
    putLazyByteString cryptotext
  get = do
    nonce <- getByteString 32
    mac <- getByteString 32
    len <- getWord64le
    cryptotext <- getLazyByteString (fromIntegral len)
    return $! Encrypted (Block256 nonce) (Block256 mac) cryptotext

deriveKeys :: Key256 -> (Key256, Key256)
deriveKeys k = (deriveKey k (Block256 $ BS.append "crypt" (BS.replicate 27 0)),
                deriveKey k (Block256 $ BS.append "mac" (BS.replicate 29 0)))

-- | Encrypt-then-MAC a message given a key and a nonce. Note that using the
--   same nonce more than once for a given key will completely destroy
--   security.
encrypt' :: Key256 -> Nonce256 -> Plaintext -> Encrypted a
encrypt' k n plaintext =
    Encrypted n mac cryptotext
  where
    (cryptKey, macKey) = deriveKeys k
    cryptotext = SC.encrypt cryptKey n plaintext
    mac = skeinMAC macKey (BSL.toStrict cryptotext)

-- | Verify and decrypt a message.
decrypt' :: Key256 -> Encrypted a -> Either DecryptFailure Plaintext
decrypt' k (Encrypted n mac cryptotext) = do
    when (mac' /= mac) $ Left BadMAC
    return $! SC.decrypt cryptKey n cryptotext
  where
    (cryptKey, macKey) = deriveKeys k
    mac' = skeinMAC macKey (BSL.toStrict cryptotext)

-- | Encrypt-then-MAC any serializable value.
--   The 256 bit nonce is generated using a Skein-based PRNG seeded from the
--   system's entropy pool. This means that two successive calls to encrypt
--   will not yield the exact same output; however, the identity
--   forall k, x. Right x == decrypt k (encrypt k x)
--   will always hold.
--
--   The subkeys for encryption and MAC are generated by applying Skein-KDF
--   to the master key, with the key identifiers "crypt" and "mac"
--   respectively, zero padded at the end until 32 bytes.
encrypt :: Serialize a => Key256 -> a -> Encrypted a
encrypt k x = unsafePerformIO $ do
  nonce <- generateNonce
  return $! encrypt' k nonce (runPutLazy (put x))

-- | Decrypt and decode a message. Will fail if there is a MAC mismatch or if
--   the message can't be decoded into the given data type.
decrypt :: Serialize a => Key256 -> Encrypted a -> Either DecryptFailure a
decrypt k enc = do
  plaintext <- decrypt' k enc
  case runGetLazy get plaintext of
    Right x  -> return x
    Left err -> Left (NoDecode err)
