require "openssl/lib_crypto"
require "crystal-jose"

# Additional LibCrypto bindings for EC point arithmetic, needed by
# the Tang client recovery dance (point addition, scalar
# multiplication, negation). Builds on `CrystalJose`'s bindings.
lib LibCrypto
  fun ec_point_add = EC_POINT_add(group : EcGroup, r : EcPoint, a : EcPoint, b : EcPoint, ctx : BignumCtx) : Int
  fun ec_point_invert = EC_POINT_invert(group : EcGroup, point : EcPoint, ctx : BignumCtx) : Int
  fun ec_point_mul = EC_POINT_mul(group : EcGroup, r : EcPoint, n : Bignum, q : EcPoint, m : Bignum, ctx : BignumCtx) : Int
  fun ec_point_dup = EC_POINT_dup(src : EcPoint, group : EcGroup) : EcPoint
  fun ec_point_is_at_infinity = EC_POINT_is_at_infinity(group : EcGroup, point : EcPoint) : Int
end
