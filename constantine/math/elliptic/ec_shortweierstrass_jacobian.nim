# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  ./ec_shortweierstrass_affine

export Subgroup

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                 with Jacobian Coordinates
#
# ############################################################

type EC_ShortW_Jac*[F; G: static Subgroup] = object
  ## Elliptic curve point for a curve in Short Weierstrass form
  ##   y² = x³ + a x + b
  ##
  ## over a field F
  ##
  ## in Jacobian coordinates (X, Y, Z)
  ## corresponding to (x, y) with X = xZ² and Y = yZ³
  ##
  ## Note that jacobian coordinates are not unique
  x*, y*, z*: F

template getName*(EC: type EC_ShortW_Jac): untyped =
  EC.F.Name

template getScalarField*(EC: type EC_ShortW_Jac): untyped =
  Fr[EC.F.Name]

func isNeutral*(P: EC_ShortW_Jac): SecretBool {.inline.} =
  ## Returns true if P is the neutral element / identity element
  ## and false otherwise, i.e. ∀Q, P+Q == Q
  ## For Short Weierstrass curves, this is the infinity point.
  # The jacobian coordinates equation is
  #       Y² = X³ + aXZ⁴ + bZ⁶
  #
  # When Z = 0 in the equation, it reduces to
  # Y² = X³
  # (yZ³)² = (xZ²)³ which is true for any x, y coordinates
  result = P.z.isZero()

func setNeutral*(P: var EC_ShortW_Jac) {.inline.} =
  ## Set P to the neutral element / identity element
  ## i.e. ∀Q, P+Q == Q
  ## For Short Weierstrass curves, this is the infinity point.
  P.x.setOne()
  P.y.setOne()
  P.z.setZero()

func `==`*(P, Q: EC_ShortW_Jac): SecretBool {.meter.} =
  ## Constant-time equality check
  ## This is a costly operation
  # Reminder: the representation is not unique
  type F = EC_ShortW_Jac.F

  var z1z1 {.noInit.}, z2z2 {.noInit.}: F
  var a{.noInit.}, b{.noInit.}: F

  z1z1.square(P.z, lazyReduce = true)
  z2z2.square(Q.z, lazyReduce = true)

  a.prod(P.x, z2z2)
  b.prod(Q.x, z1z1)
  result = a == b

  a.prod(P.y, Q.z, lazyReduce = true)
  b.prod(Q.y, P.z, lazyReduce = true)
  a *= z2z2
  b *= z1z1
  result = result and a == b

  # Ensure a zero-init point doesn't propagate 0s and match any
  result = result and not(P.isNeutral() xor Q.isNeutral())

func ccopy*(P: var EC_ShortW_Jac, Q: EC_ShortW_Jac, ctl: SecretBool) {.inline.} =
  ## Constant-time conditional copy
  ## If ctl is true: Q is copied into P
  ## if ctl is false: Q is not copied and P is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  for fP, fQ in fields(P, Q):
    ccopy(fP, fQ, ctl)

func trySetFromCoordsXandZ*[F; G](
       P: var EC_ShortW_Jac[F, G],
       x, z: F): SecretBool =
  ## Try to create a point the elliptic curve
  ## Y² = X³ + aXZ⁴ + bZ⁶  (Jacobian coordinates)
  ## y² = x³ + a x + b     (affine coordinate)
  ## return true and update `P` if `x` leads to a valid point
  ## return false otherwise, in that case `P` is undefined.
  ##
  ## Note: Dedicated robust procedures for hashing-to-curve
  ##       will be provided, this is intended for testing purposes.
  ##
  ##       For **test case generation only**,
  ##       this is preferred to generating random point
  ##       via random scalar multiplication of the curve generator
  ##       as the latter assumes:
  ##       - point addition, doubling work
  ##       - scalar multiplication works
  ##       - a generator point is defined
  ##       i.e. you can't test unless everything is already working
  P.y.curve_eq_rhs(x, G)
  result = sqrt_if_square(P.y)

  var z2 {.noInit.}: F
  z2.square(z, lazyReduce = true)
  P.x.prod(x, z2)
  P.y.prod(P.y, z2, lazyReduce = true)
  P.y *= z
  P.z = z

func trySetFromCoordX*[F; G](
       P: var EC_ShortW_Jac[F, G],
       x: F): SecretBool =
  ## Try to create a point the elliptic curve
  ## y² = x³ + a x + b     (affine coordinate)
  ##
  ## The `Z` coordinates is set to 1
  ##
  ## return true and update `P` if `x` leads to a valid point
  ## return false otherwise, in that case `P` is undefined.
  ##
  ## Note: Dedicated robust procedures for hashing-to-curve
  ##       will be provided, this is intended for testing purposes.
  ##
  ##       For **test case generation only**,
  ##       this is preferred to generating random point
  ##       via random scalar multiplication of the curve generator
  ##       as the latter assumes:
  ##       - point addition, doubling work
  ##       - scalar multiplication works
  ##       - a generator point is defined
  ##       i.e. you can't test unless everything is already working
  P.y.curve_eq_rhs(x, G)
  result = sqrt_if_square(P.y)
  P.x = x
  P.z.setOne()

func neg*(P: var EC_ShortW_Jac, Q: EC_ShortW_Jac) {.inline.} =
  ## Negate ``P``
  P.x = Q.x
  P.y.neg(Q.y)
  P.z = Q.z

func neg*(P: var EC_ShortW_Jac) {.inline.} =
  ## Negate ``P``
  P.y.neg()

func cneg*(P: var EC_ShortW_Jac, ctl: CTBool)  {.inline.} =
  ## Conditional negation.
  ## Negate if ``ctl`` is true
  P.y.cneg(ctl)

template sumImpl[F; G: static Subgroup](
       r: var EC_ShortW_Jac[F, G],
       P, Q: EC_ShortW_Jac[F, G],
       CoefA: typed) {.dirty.} =
  ## Elliptic curve point addition for Short Weierstrass curves in Jacobian coordinates
  ## with the curve ``a`` being a parameter for summing on isogenous curves.
  ##
  ##   R = P + Q
  ##
  ## Short Weierstrass curves have the following equation in Jacobian coordinates
  ##   Y² = X³ + aXZ⁴ + bZ⁶
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ## ``CoefA`` allows fast path for curve with a == 0 or a == -3
  ##            and also allows summing on curve isogenies.
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that P == Q or P == -Q or P or Q are the infinity points
  ## to simple side-channel attacks (SCA)
  ## This is done by using a "complete" or "exception-free" addition law.
  #
  # Implementation, see write-up in the accompanying Markdown file.
  # We fuse addition and doubling with condition copy by swapping
  # terms with the following table
  #
  # |  Addition, Cohen et al, 1998  |      Doubling, Cohen et al, 1998         |   Doubling = -3   | Doubling a = 0 |
  # |  12M + 4S + 6add + 1*2        | 3M + 6S + 1*a + 4add + 1*2 + 1*3 + 1half |                   |                |
  # | ----------------------------- | -----------------------------------------| ----------------- | -------------- |
  # | Z₁Z₁ = Z₁²                    | Z₁Z₁ = Z₁²                               |                   |                |
  # | Z₂Z₂ = Z₂²                    |                                          |                   |                |
  # |                               |                                          |                   |                |
  # | U₁ = X₁*Z₂Z₂                  |                                          |                   |                |
  # | U₂ = X₂*Z₁Z₁                  |                                          |                   |                |
  # | S₁ = Y₁*Z₂*Z₂Z₂               |                                          |                   |                |
  # | S₂ = Y₂*Z₁*Z₁Z₁               |                                          |                   |                |
  # | H  = U₂-U₁ # P=-Q, P=Inf, P=Q |                                          |                   |                |
  # | R  = S₂-S₁ # Q=Inf            |                                          |                   |                |
  # |                               |                                          |                   |                |
  # | HH  = H²                      | YY = Y₁²                                 |                   |                |
  # | V   = U₁*HH                   | S  = X₁*YY                               |                   |                |
  # | HHH = H*HH                    | M  = (3*X₁²+a*ZZ²)/2                     | 3(X₁-ZZ)(X₁+ZZ)/2 | 3X₁²/2         |
  # |                               |                                          |                   |                |
  # | X₃ = R²-HHH-2*V               | X₃ = M²-2*S                              |                   |                |
  # | Y₃ = R*(V-X₃)-S₁*HHH          | Y₃ = M*(S-X₃)-YY*YY                      |                   |                |
  # | Z₃ = Z₁*Z₂*H                  | Z₃ = Y₁*Z₁                               |                   |                |

  bind mulCheckSparse

  # "when" static evaluation doesn't shortcut booleans :/
  # which causes issues when CoefA isn't an int but Fp or Fp2
  when CoefA is int:
    const CoefA_eq_zero = CoefA == 0
    const CoefA_eq_minus3 {.used.} = CoefA == -3
  else:
    const CoefA_eq_zero = false
    const CoefA_eq_minus3 = false

  var Z1Z1 {.noInit.}, U1 {.noInit.}, S1 {.noInit.}, H {.noInit.}, R {.noinit.}: F

  block: # Addition-only, check for exceptional cases
    var Z2Z2 {.noInit.}, U2 {.noInit.}, S2 {.noInit.}: F
    Z2Z2.square(Q.z, lazyReduce = true)
    S1.prod(Q.z, Z2Z2, lazyReduce = true)
    S1 *= P.y           # S₁ = Y₁*Z₂³
    U1.prod(P.x, Z2Z2)  # U₁ = X₁*Z₂²

    Z1Z1.square(P.z, lazyReduce = not CoefA_eq_minus3)
    S2.prod(P.z, Z1Z1, lazyReduce = true)
    S2 *= Q.y           # S₂ = Y₂*Z₁³
    U2.prod(Q.x, Z1Z1)  # U₂ = X₂*Z₁²

    H.diff(U2, U1)      # H = U₂-U₁
    R.diff(S2, S1)      # R = S₂-S₁

  # Exceptional cases
  # Expressing H as affine, if H == 0, P == Q or -Q
  # H = U₂-U₁ = X₂*Z₁² - X₁*Z₂² = x₂*Z₂²*Z₁² - x₁*Z₁²*Z₂²
  # if H == 0 && R == 0, P = Q -> doubling
  # if only H == 0, P = -Q     -> infinity, implied in Z₃ = Z₁*Z₂*H = 0
  # if only R == 0, P and Q are related by the cubic root endomorphism
  let isDbl = H.isZero() and R.isZero()

  # Rename buffers under the form (add_or_dbl)
  template R_or_M: untyped = R
  template H_or_Y: untyped = H
  template V_or_S: untyped = U1
  var HH_or_YY {.noInit.}: F
  var HHH_or_Mpre {.noInit.}: F

  H_or_Y.ccopy(P.y, isDbl) # H         (add) or Y₁        (dbl)
  HH_or_YY.square(H_or_Y)  # H²        (add) or Y₁²       (dbl)

  V_or_S.ccopy(P.x, isDbl) # U₁        (add) or X₁        (dbl)
  V_or_S *= HH_or_YY       # V = U₁*HH (add) or S = X₁*YY (dbl)

  block: # Compute M for doubling
    when CoefA_eq_zero:
      var a {.noInit.} = H
      var b {.noInit.} = HH_or_YY
      a.ccopy(P.x, isDbl)           # H or X₁
      b.ccopy(P.x, isDbl)           # HH or X₁
      HHH_or_Mpre.prod(a, b)        # HHH or X₁²

      var M{.noInit.} = HHH_or_Mpre # Assuming on doubling path
      M.div2()                      #  X₁²/2
      M += HHH_or_Mpre              # 3X₁²/2
      R_or_M.ccopy(M, isDbl)

    elif CoefA_eq_minus3:
      var a{.noInit.}, b{.noInit.}: F
      a.sum(P.x, Z1Z1)
      b.diff(P.z, Z1Z1)
      a.ccopy(H_or_Y, not isDbl)    # H   or X₁+ZZ
      b.ccopy(HH_or_YY, not isDbl)  # HH  or X₁-ZZ
      HHH_or_Mpre.prod(a, b)        # HHH or X₁²-ZZ²

      var M{.noInit.} = HHH_or_Mpre # Assuming on doubling path
      M.div2()                      # (X₁²-ZZ²)/2
      M += HHH_or_Mpre              # 3(X₁²-ZZ²)/2
      R_or_M.ccopy(M, isDbl)

    else:
      # TODO: Costly `a` coefficients can be computed
      # by merging their computation with Z₃ = Z₁*Z₂*H (add) or Z₃ = Y₁*Z₁ (dbl)
      var a{.noInit.} = H
      var b{.noInit.} = HH_or_YY
      a.ccopy(P.x, isDbl)
      b.ccopy(P.x, isDbl)
      HHH_or_Mpre.prod(a, b)  # HHH or X₁²

      # Assuming doubling path
      a.square(HHH_or_Mpre, lazyReduce = true)
      a *= HHH_or_Mpre              # a = 3X₁²
      b.square(Z1Z1)
      b.mulCheckSparse(CoefA)       # b = αZZ, with α the "a" coefficient of the curve

      a += b
      a.div2()
      R_or_M.ccopy(a, isDbl)        # (3X₁² - αZZ)/2

  # Let's count our horses, at this point:
  # - R_or_M is set with R (add) or M (dbl)
  # - HHH_or_Mpre contains HHH (add) or garbage precomputation (dbl)
  # - V_or_S is set with V = U₁*HH (add) or S = X₁*YY (dbl)
  var o {.noInit.}: typeof(r)
  block: # Finishing line
    var t {.noInit.}: F
    t.double(V_or_S)
    o.x.square(R_or_M)
    o.x -= t                           # X₃ = R²-2*V (add) or M²-2*S (dbl)
    o.x.csub(HHH_or_Mpre, not isDbl)   # X₃ = R²-HHH-2*V (add) or M²-2*S (dbl)

    V_or_S -= o.x                      # V-X₃ (add) or S-X₃ (dbl)
    o.y.prod(R_or_M, V_or_S)           # Y₃ = R(V-X₃) (add) or M(S-X₃) (dbl)
    HHH_or_Mpre.ccopy(HH_or_YY, isDbl) # HHH (add) or YY (dbl)
    S1.ccopy(HH_or_YY, isDbl)          # S1 (add) or YY (dbl)
    HHH_or_Mpre *= S1                  # HHH*S1 (add) or YY² (dbl)
    o.y -= HHH_or_Mpre                 # Y₃ = R(V-X₃)-S₁*HHH (add) or M(S-X₃)-YY² (dbl)

    t = Q.z
    t.ccopy(H_or_Y, isDbl)             # Z₂ (add) or Y₁ (dbl)
    t.prod(t, P.z, true)               # Z₁Z₂ (add) or Y₁Z₁ (dbl)
    o.z.prod(t, H_or_Y)                # Z₁Z₂H (add) or garbage (dbl)
    o.z.ccopy(t, isDbl)                # Z₁Z₂H (add) or Y₁Z₁ (dbl)

  # if P or R were infinity points they would have spread 0 with Z₁Z₂
  block: # Infinity points
    o.ccopy(Q, P.isNeutral())
    o.ccopy(P, Q.isNeutral())

  r = o

func sum*[F; G: static Subgroup](
       r: var EC_ShortW_Jac[F, G],
       P, Q: EC_ShortW_Jac[F, G],
       CoefA: static F) {.meter.} =
  ## Elliptic curve point addition for Short Weierstrass curves in Jacobian coordinates
  ## with the curve ``a`` being a parameter for summing on isogenous curves.
  ##
  ##   R = P + Q
  ##
  ## Short Weierstrass curves have the following equation in Jacobian coordinates
  ##   Y² = X³ + aXZ⁴ + bZ⁶
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ## ``CoefA`` allows fast path for curve with a == 0 or a == -3
  ##            and also allows summing on curve isogenies.
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that P == Q or P == -Q or P or Q are the infinity points
  ## to simple side-channel attacks (SCA)
  ## This is done by using a "complete" or "exception-free" addition law.
  r.sumImpl(P, Q, CoefA)

func sum*[F; G: static Subgroup](
       r: var EC_ShortW_Jac[F, G],
       P, Q: EC_ShortW_Jac[F, G]) {.meter.} =
  ## Elliptic curve point addition for Short Weierstrass curves in Jacobian coordinates
  ##
  ##   R = P + Q
  ##
  ## Short Weierstrass curves have the following equation in Jacobian coordinates
  ##   Y² = X³ + aXZ⁴ + bZ⁶
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that P == Q or P == -Q or P or Q are the infinity points
  ## to simple side-channel attacks (SCA)
  ## This is done by using a "complete" or "exception-free" addition law.
  r.sumImpl(P, Q, F.Name.getCoefA())

func mixedSum*[F; G: static Subgroup](
       r: var EC_ShortW_Jac[F, G],
       P: EC_ShortW_Jac[F, G],
       Q: EC_ShortW_Aff[F, G]) {.meter.} =
  ## Elliptic curve mixed addition for Short Weierstrass curves in Jacobian coordinates
  ## with the curve ``a`` being a parameter for summing on isogenous curves.
  ##
  ##   R = P + Q
  ##
  ## Short Weierstrass curves have the following equation in Jacobian coordinates
  ##   Y² = X³ + aXZ⁴ + bZ⁶
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ## ``CoefA`` allows fast path for curve with a == 0 or a == -3
  ##            and also allows summing on curve isogenies.
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that P == Q or P == -Q or P or Q are the infinity points
  ## to simple side-channel attacks (SCA)
  ## This is done by using a "complete" or "exception-free" addition law.
  #
  # Implementation, see write-up in the accompanying markdown file.
  # We fuse addition and doubling with condition copy by swapping
  # terms with the following table
  #
  # |  Addition, Cohen et al, 1998  |      Doubling, Cohen et al, 1998         |   Doubling = -3   | Doubling a = 0 |
  # |  12M + 4S + 6add + 1*2        | 3M + 6S + 1*a + 4add + 1*2 + 1*3 + 1half |                   |                |
  # | ----------------------------- | -----------------------------------------| ----------------- | -------------- |
  # | Z₁Z₁ = Z₁²                    | Z₁Z₁ = Z₁²                               |                   |                |
  # | Z₂Z₂ = Z₂²                    |                                          |                   |                |
  # |                               |                                          |                   |                |
  # | U₁ = X₁*Z₂Z₂                  |                                          |                   |                |
  # | U₂ = X₂*Z₁Z₁                  |                                          |                   |                |
  # | S₁ = Y₁*Z₂*Z₂Z₂               |                                          |                   |                |
  # | S₂ = Y₂*Z₁*Z₁Z₁               |                                          |                   |                |
  # | H  = U₂-U₁ # P=-Q, P=Inf, P=Q |                                          |                   |                |
  # | R  = S₂-S₁ # Q=Inf            |                                          |                   |                |
  # |                               |                                          |                   |                |
  # | HH  = H²                      | YY = Y₁²                                 |                   |                |
  # | V   = U₁*HH                   | S  = X₁*YY                               |                   |                |
  # | HHH = H*HH                    | M  = (3*X₁²+a*ZZ²)/2                     | 3(X₁-ZZ)(X₁+ZZ)/2 | 3X₁²/2         |
  # |                               |                                          |                   |                |
  # | X₃ = R²-HHH-2*V               | X₃ = M²-2*S                              |                   |                |
  # | Y₃ = R*(V-X₃)-S₁*HHH          | Y₃ = M*(S-X₃)-YY*YY                      |                   |                |
  # | Z₃ = Z₁*Z₂*H                  | Z₃ = Y₁*Z₁                               |                   |                |
  #
  # For mixed adddition we just set Z₂ = 1

  # "when" static evaluation doesn't shortcut booleans :/
  # which causes issues when CoefA isn't an int but Fp or Fp2
  const CoefA = F.Name.getCoefA()
  when CoefA is int:
    const CoefA_eq_zero = CoefA == 0
    const CoefA_eq_minus3 {.used.} = CoefA == -3
  else:
    const CoefA_eq_zero = false
    const CoefA_eq_minus3 = false

  var Z1Z1 {.noInit.}, U1 {.noInit.}, S1 {.noInit.}, H {.noInit.}, R {.noinit.}: F

  block: # Addition-only, check for exceptional cases
    var U2 {.noInit.}, S2 {.noInit.}: F
    U1 = P.x
    S1 = P.y

    Z1Z1.square(P.z, lazyReduce = not CoefA_eq_minus3)
    S2.prod(P.z, Z1Z1, lazyReduce = true)
    S2 *= Q.y           # S₂ = Y₂*Z₁³
    U2.prod(Q.x, Z1Z1)  # U₂ = X₂*Z₁²

    H.diff(U2, U1)      # H = U₂-U₁
    R.diff(S2, S1)      # R = S₂-S₁

  # Exceptional cases
  # Expressing H as affine, if H == 0, P == Q or -Q
  # H = U₂-U₁ = X₂*Z₁² - X₁*Z₂² = x₂*Z₂²*Z₁² - x₁*Z₁²*Z₂²
  # if H == 0 && R == 0, P = Q -> doubling
  # if only H == 0, P = -Q     -> infinity, implied in Z₃ = Z₁*Z₂*H = 0
  # if only R == 0, P and Q are related by the cubic root endomorphism
  let isDbl = H.isZero() and R.isZero()

  # Rename buffers under the form (add_or_dbl)
  template R_or_M: untyped = R
  template H_or_Y: untyped = H
  template V_or_S: untyped = U1
  var HH_or_YY {.noInit.}: F
  var HHH_or_Mpre {.noInit.}: F

  H_or_Y.ccopy(P.y, isDbl) # H         (add) or Y₁        (dbl)
  HH_or_YY.square(H_or_Y)  # H²        (add) or Y₁²       (dbl)

  V_or_S.ccopy(P.x, isDbl) # U₁        (add) or X₁        (dbl)
  V_or_S *= HH_or_YY       # V = U₁*HH (add) or S = X₁*YY (dbl)

  block: # Compute M for doubling
    when CoefA_eq_zero:
      var a {.noInit.} = H
      var b {.noInit.} = HH_or_YY
      a.ccopy(P.x, isDbl)           # H or X₁
      b.ccopy(P.x, isDbl)           # HH or X₁
      HHH_or_Mpre.prod(a, b)        # HHH or X₁²

      var M{.noInit.} = HHH_or_Mpre # Assuming on doubling path
      M.div2()                      #  X₁²/2
      M += HHH_or_Mpre              # 3X₁²/2
      R_or_M.ccopy(M, isDbl)

    elif CoefA_eq_minus3:
      var a{.noInit.}, b{.noInit.}: F
      a.sum(P.x, Z1Z1)
      b.diff(P.z, Z1Z1)
      a.ccopy(H_or_Y, not isDbl)    # H   or X₁+ZZ
      b.ccopy(HH_or_YY, not isDbl)  # HH  or X₁-ZZ
      HHH_or_Mpre.prod(a, b)        # HHH or X₁²-ZZ²

      var M{.noInit.} = HHH_or_Mpre # Assuming on doubling path
      M.div2()                      # (X₁²-ZZ²)/2
      M += HHH_or_Mpre              # 3(X₁²-ZZ²)/2
      R_or_M.ccopy(M, isDbl)

    else:
      # TODO: Costly `a` coefficients can be computed
      # by merging their computation with Z₃ = Z₁*Z₂*H (add) or Z₃ = Y₁*Z₁ (dbl)
      var a{.noInit.} = H
      var b{.noInit.} = HH_or_YY
      a.ccopy(P.x, isDbl)
      b.ccopy(P.x, isDbl)
      HHH_or_Mpre.prod(a, b)        # HHH or X₁²

      # Assuming doubling path
      a.square(HHH_or_Mpre, lazyReduce = true)
      a *= HHH_or_Mpre              # a = 3X₁²
      b.square(Z1Z1)
      b.mulCheckSparse(CoefA)       # b = αZZ, with α the "a" coefficient of the curve

      a += b
      a.div2()
      R_or_M.ccopy(a, isDbl)        # (3X₁² - αZZ)/2

  # Let's count our horses, at this point:
  # - R_or_M is set with R (add) or M (dbl)
  # - HHH_or_Mpre contains HHH (add) or garbage precomputation (dbl)
  # - V_or_S is set with V = U₁*HH (add) or S = X₁*YY (dbl)
  var o {.noInit.}: typeof(r)
  block: # Finishing line
    var t {.noInit.}: F
    t.double(V_or_S)
    o.x.square(R_or_M)
    o.x -= t                           # X₃ = R²-2*V (add) or M²-2*S (dbl)
    o.x.csub(HHH_or_Mpre, not isDbl)   # X₃ = R²-HHH-2*V (add) or M²-2*S (dbl)

    V_or_S -= o.x                      # V-X₃ (add) or S-X₃ (dbl)
    o.y.prod(R_or_M, V_or_S)           # Y₃ = R(V-X₃) (add) or M(S-X₃) (dbl)
    HHH_or_Mpre.ccopy(HH_or_YY, isDbl) # HHH (add) or YY (dbl)
    S1.ccopy(HH_or_YY, isDbl)          # S1 (add) or YY (dbl)
    HHH_or_Mpre *= S1                  # HHH*S1 (add) or YY² (dbl)
    o.y -= HHH_or_Mpre                 # Y₃ = R(V-X₃)-S₁*HHH (add) or M(S-X₃)-YY² (dbl)

    t.setOne()
    t.ccopy(H_or_Y, isDbl)             # Z₂ (add) or Y₁ (dbl)
    t.prod(t, P.z, true)               # Z₁Z₂ (add) or Y₁Z₁ (dbl)
    o.z.prod(t, H_or_Y)                # Z₁Z₂H (add) or garbage (dbl)
    o.z.ccopy(t, isDbl)                # Z₁Z₂H (add) or Y₁Z₁ (dbl)

  block: # Infinity points
    o.x.ccopy(Q.x, P.isNeutral())
    o.y.ccopy(Q.y, P.isNeutral())
    o.z.csetOne(P.isNeutral())

    o.ccopy(P, Q.isNeutral())

  r = o

func dbl_1998_cmo_rescaled_a0_impl[F; G: static Subgroup](r: var EC_ShortW_Jac[F, G], P: EC_ShortW_Jac[F, G]) {.inline.} =
  static: doAssert F.Name.getCoefA() == 0
  # "dbl-1998-cmo" doubling formula - https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html#doubling-dbl-1998-cmo
  # rescaled by 1/2, 1/4, 1/8 (inspiration from Bos et al https://eprint.iacr.org/2014/130.pdf)
  # See [./ec_shortweierstrass_jacobian.md](./ec_shortweierstrass_jacobian.md)
  #
  #     Cost: 3M + 4S + 3add + 1*2 + 1*3 + 1half
  #
  #        YY = Y₁²
  #         M = 3X₁²/2
  #         S = X₁*YY
  #        X₃ = M²-2*S
  #        Y₃ = M*(S-X₃)-YY²
  #        Z₃ = Y₁*Z₁
  var Y {.noInit.}, M {.noInit.}, S {.noInit.}: F
  Y.square(P.y)
  M.square(P.x)
  M *= 3
  M.div2()
  S.prod(P.x, Y)
  Y.square()

  r.z.prod(P.z, P.y) # Z₃ = Y₁*Z₁, no aliasing
  r.x.square(M)      # X₃ = M²
  r.x -= S           # X₃ = M²-S
  r.x -= S           # X₃ = M²-2*S
  r.y.diff(S, r.x)   # Y₃ = S-X₃
  r.y *= M           # Y₃ = M*(S-X₃)
  r.y -= Y           # Y₃ = M*(S-X₃)-YY²

func double*[F; G: static Subgroup](r: var EC_ShortW_Jac[F, G], P: EC_ShortW_Jac[F, G]) {.meter.} =
  ## Elliptic curve point doubling for Short Weierstrass curves in projective coordinate
  ##
  ##   R = [2] P
  ##
  ## Short Weierstrass curves have the following equation in Jacobian coordinates
  ##   Y² = X³ + aXZ⁴ + bZ⁶
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ##
  ## Implementation is constant-time.
  when F.Name.getCoefA() == 0:
    dbl_1998_cmo_rescaled_a0_impl(r, P)
  else:
    {.error: "Not implemented.".}

func `+=`*(P: var EC_ShortW_Jac, Q: EC_ShortW_Jac) {.inline.} =
  ## In-place point addition
  P.sum(P, Q)

func `+=`*(P: var EC_ShortW_Jac, Q: EC_ShortW_Aff) {.inline.} =
  ## In-place mixed point addition
  P.mixedSum(P, Q)

func double*(P: var EC_ShortW_Jac) {.inline.} =
  ## In-place point doubling
  P.double(P)

func diff*(r: var EC_ShortW_Jac, P, Q: EC_ShortW_Jac) {.inline.} =
  ## r = P - Q
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  r.sum(P, nQ)

func `-=`*(P: var EC_ShortW_Jac, Q: EC_ShortW_Jac) {.inline.} =
  ## In-place point substraction
  P.diff(P, Q)

func mixedDiff*(r: var EC_ShortW_Jac, P: EC_ShortW_Jac, Q: EC_ShortW_Aff) {.inline.} =
  ## r = P - Q
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  r.mixedSum(P, nQ)

func `-=`*(P: var EC_ShortW_Jac, Q: EC_ShortW_Aff) {.inline.} =
  ## In-place point substraction
  P.mixedDiff(P, Q)

# Conversions
# -----------

template affine*[F, G](_: type EC_ShortW_Jac[F, G]): untyped =
  ## Returns the affine type that corresponds to the Jacobian type input
  EC_ShortW_Aff[F, G]

template jacobian*[F, G](_: type EC_ShortW_Aff[F, G]): untyped =
  ## Returns the jacobian type that corresponds to the affine type input
  EC_ShortW_Jac[F, G]

func affine*[F; G](
       aff: var EC_ShortW_Aff[F, G],
       jac: EC_ShortW_Jac[F, G]) {.meter.} =
  var invZ {.noInit.}, invZ2{.noInit.}: F
  invZ.inv(jac.z)
  invZ2.square(invZ, lazyReduce = true)

  aff.x.prod(jac.x, invZ2)
  invZ.prod(invZ, invZ2, lazyReduce = true)
  aff.y.prod(jac.y, invZ)

func fromAffine*[F; G](
       jac: var EC_ShortW_Jac[F, G],
       aff: EC_ShortW_Aff[F, G]) {.inline.} =
  jac.x = aff.x
  jac.y = aff.y
  jac.z.setOne()
  jac.z.csetZero(aff.isNeutral())

# Variable-time
# -------------

# In some primitives like FFTs, the extra work done for constant-time
# is amplified by O(n log n) which may result in extra tens of minutes
# to hours of computations. Those primitives do not need constant-timeness.

func sum_vartime*[F; G: static Subgroup](
       r: var EC_ShortW_Jac[F, G],
       p, q: EC_ShortW_Jac[F, G])
       {.tags:[VarTime], meter.} =
  ## **Variable-time** Jacobian addition
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.

  if p.isNeutral().bool:
    r = q
    return
  if q.isNeutral().bool:
    r = p
    return

  # Accelerate mixed additions
  let isPz1 = p.z.isOne().bool
  let isQz1 = q.z.isOne().bool

  # Addition, Cohen et al, 1998
  # General case:            12M + 4S + 6add + 1*2
  #
  # Mixed-addition:          8M + 3S + 6add + 1*2
  # Affine+Affine->Jacobian: 4M + 2S + 6add + 1*2

  # |  Addition, Cohen et al, 1998  |
  # |  12M + 4S + 6add + 1*2        |
  # | ----------------------------- |
  # | Z₁Z₁ = Z₁²                    |
  # | Z₂Z₂ = Z₂²                    |
  # |                               |
  # | U₁ = X₁*Z₂Z₂                  |
  # | U₂ = X₂*Z₁Z₁                  |
  # | S₁ = Y₁*Z₂*Z₂Z₂               |
  # | S₂ = Y₂*Z₁*Z₁Z₁               |
  # | H  = U₂-U₁ # P=-Q, P=Inf, P=Q |
  # | R  = S₂-S₁ # Q=Inf            |
  # |                               |
  # | HH  = H²                      |
  # | V   = U₁*HH                   |
  # | HHH = H*HH                    |
  # |                               |
  # | X₃ = R²-HHH-2*V               |
  # | Y₃ = R*(V-X₃)-S₁*HHH          |
  # | Z₃ = Z₁*Z₂*H                  |

  var U {.noInit.}, S{.noInit.}, H{.noInit.}, R{.noInit.}: F

  if not isPz1:                            # case Z₁ != 1
    R.square(p.z, lazyReduce = true)       #   Z₁Z₁ = Z₁²
  if isQz1:                                # case Z₂ = 1
    U = p.x                                #   U₁ = X₁*Z₂Z₂
    if isPz1:                              #   case Z₁ = Z₂ = 1
      H = q.x
    else:
      H.prod(q.x, R)
    H -= U                                 #   H  = U₂-U₁
    S = p.y                                #   S₁ = Y₁*Z₂*Z₂Z₂
  else:                                    # case Z₂ != 1
    S.square(q.z, lazyReduce = true)
    U.prod(p.x, S)                         #   U₁ = X₁*Z₂Z₂
    if isPz1:
      H = q.x
    else:
      H.prod(q.x, R)
    H -= U                                 #   H  = U₂-U₁
    S.prod(S, q.z, lazyReduce = true)
    S *= p.y                               #   S₁ = Y₁*Z₂*Z₂Z₂
  if isPz1:
    R = q.y
  else:
    R.prod(R, p.z, lazyReduce = true)
    R *= q.y                               #   S₂ = Y₂*Z₁*Z₁Z₁
  R -= S                                   # R  = S₂-S₁

  if H.isZero().bool:                      # Same x coordinate
    if R.isZero().bool:                    # case P = Q
      r.double(p)
      return
    else:                                  # case P = -Q
      r.setNeutral()
      return

  var HHH{.noInit.}: F
  template V: untyped = U

  HHH.square(H, lazyReduce = true)
  V *= HHH                                # V   = U₁*HH
  HHH *= H                                # HHH = H*HH

  # X₃ = R²-HHH-2*V, we use the y coordinate as temporary (should we? cache misses?)
  r.y.square(R)
  r.y -= V
  r.y -= V
  r.x.diff(r.y, HHH)

  # Y₃ = R*(V-X₃)-S₁*HHH
  V -= r.x
  V *= R
  HHH *= S
  r.y.diff(V, HHH)

  # Z₃ = Z₁*Z₂*H
  if isPz1:
    if isQz1:
      r.z = H
    else:
      r.z.prod(H, q.z)
  else:
    if isQz1:
      r.z.prod(H, p.z)
    else:
      r.z.prod(p.z, q.z, lazyReduce = true)
      r.z *= H

func mixedSum_vartime*[F; G: static Subgroup](
       r: var EC_ShortW_Jac[F, G],
       p: EC_ShortW_Jac[F, G],
       q: EC_ShortW_Aff[F, G])
       {.tags:[VarTime], meter.} =
  ## **Variable-time** Jacobian mixed addition
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.

  if p.isNeutral().bool:
    r.fromAffine(q)
    return
  if q.isNeutral().bool:
    r = p
    return

  # Accelerate mixed additions
  let isPz1 = p.z.isOne().bool

  # Addition, Cohen et al, 1998
  #
  # Mixed-addition:          8M + 3S + 6add + 1*2
  # Affine+Affine->Jacobian: 4M + 2S + 6add + 1*2

  # |  Addition, Cohen et al, 1998  |
  # |  12M + 4S + 6add + 1*2        |
  # | ----------------------------- |
  # | Z₁Z₁ = Z₁²                    |
  # | Z₂Z₂ = Z₂²                    |
  # |                               |
  # | U₁ = X₁*Z₂Z₂                  |
  # | U₂ = X₂*Z₁Z₁                  |
  # | S₁ = Y₁*Z₂*Z₂Z₂               |
  # | S₂ = Y₂*Z₁*Z₁Z₁               |
  # | H  = U₂-U₁ # P=-Q, P=Inf, P=Q |
  # | R  = S₂-S₁ # Q=Inf            |
  # |                               |
  # | HH  = H²                      |
  # | V   = U₁*HH                   |
  # | HHH = H*HH                    |
  # |                               |
  # | X₃ = R²-HHH-2*V               |
  # | Y₃ = R*(V-X₃)-S₁*HHH          |
  # | Z₃ = Z₁*Z₂*H                  |

  var U {.noInit.}, S{.noInit.}, H{.noInit.}, R{.noInit.}: F

  if not isPz1:                            # case Z₁ != 1
    R.square(p.z, lazyReduce = true)     #   Z₁Z₁ = Z₁²

  U = p.x                                  #   U₁ = X₁*Z₂Z₂
  if isPz1:                                #   case Z₁ = Z₂ = 1
    H = q.x
  else:
    H.prod(q.x, R)
  H -= U                                   #   H  = U₂-U₁
  S = p.y                                  #   S₁ = Y₁*Z₂*Z₂Z₂

  if isPz1:
    R = q.y
  else:
    R.prod(R, p.z, lazyReduce = true)
    R *= q.y                               #   S₂ = Y₂*Z₁*Z₁Z₁
  R -= S                                   # R  = S₂-S₁

  if H.isZero().bool:                      # Same x coordinate
    if R.isZero().bool:                    # case P = Q
      r.double(p)
      return
    else:                                  # case P = -Q
      r.setNeutral()
      return

  var HHH{.noInit.}: F
  template V: untyped = U

  HHH.square(H, lazyReduce = true)
  V *= HHH                                # V   = U₁*HH
  HHH *= H                                # HHH = H*HH

  # X₃ = R²-HHH-2*V, we use the y coordinate as temporary (should we? cache misses?)
  r.y.square(R)
  r.y -= V
  r.y -= V
  r.x.diff(r.y, HHH)

  # Y₃ = R*(V-X₃)-S₁*HHH
  V -= r.x
  V *= R
  HHH *= S
  r.y.diff(V, HHH)

  # Z₃ = Z₁*Z₂*H
  if isPz1:
    r.z = H
  else:
    r.z.prod(H, p.z)

func diff_vartime*(r: var EC_ShortW_Jac, P, Q: EC_ShortW_Jac) {.inline.} =
  ## r = P - Q
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  r.sum_vartime(P, nQ)

func mixedDiff_vartime*(r: var EC_ShortW_Jac, P: EC_ShortW_Jac, Q: EC_ShortW_Aff) {.inline.} =
  ## r = P - Q
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  r.mixedSum_vartime(P, nQ)

template `~+=`*(P: var EC_ShortW_Jac, Q: EC_ShortW_Jac) =
  ## Variable-time in-place point addition
  P.sum_vartime(P, Q)

template `~+=`*(P: var EC_ShortW_Jac, Q: EC_ShortW_Aff) =
  ## Variable-time in-place point mixed addition
  P.mixedSum_vartime(P, Q)

template `~-=`*(P: var EC_ShortW_Jac, Q: EC_ShortW_Jac) =
  P.diff_vartime(P, Q)

template `~-=`*(P: var EC_ShortW_Jac, Q: EC_ShortW_Aff) =
  P.mixedDiff_vartime(P, Q)

# ############################################################
#
#                 Out-of-Place functions
#
# ############################################################
#
# Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
# tend to generate useless memory moves or have difficulties to minimize stack allocation
# and our types might be large (Fp12 ...)
# See: https://github.com/mratsim/constantine/issues/145

func `+`*(a, b: EC_ShortW_Jac): EC_ShortW_Jac {.noInit, inline.} =
  ## Elliptic curve addition
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.sum(a, b)

func `+`*(a: EC_ShortW_Jac, b: EC_ShortW_Aff): EC_ShortW_Jac {.noInit, inline.} =
  ## Elliptic curve addition
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.mixedSum(a, b)

func `~+`*(a, b: EC_ShortW_Jac): EC_ShortW_Jac {.noInit, inline.} =
  ## Elliptic curve variable-time addition
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.sum_vartime(a, b)

func `~+`*(a: EC_ShortW_Jac, b: EC_ShortW_Aff): EC_ShortW_Jac {.noInit, inline.} =
  ## Elliptic curve variable-time addition
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.mixedSum_vartime(a, b)

func `-`*(a, b: EC_ShortW_Jac): EC_ShortW_Jac {.noInit, inline.} =
  ## Elliptic curve substraction
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.diff(a, b)

func `-`*(a: EC_ShortW_Jac, b: EC_ShortW_Aff): EC_ShortW_Jac {.noInit, inline.} =
  ## Elliptic curve addition
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.mixedDiff(a, b)

func `~-`*(a, b: EC_ShortW_Jac): EC_ShortW_Jac {.noInit, inline.} =
  ## Elliptic curve variable-time substraction
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.diff_vartime(a, b)

func `~-`*(a: EC_ShortW_Jac, b: EC_ShortW_Aff): EC_ShortW_Jac {.noInit, inline.} =
  ## Elliptic curve variable-time substraction
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.]
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.mixedDiff_vartime(a, b)

func getAffine*[F, G](jac: EC_ShortW_Jac[F, G]): EC_ShortW_Aff[F, G] {.noInit, inline.} =
  ## Jacobian to Affine conversion
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.affine(jac)

func getJacobian*[F, G](aff: EC_ShortW_Aff[F, G]): EC_ShortW_Jac[F, G] {.noInit, inline.} =
  ## Affine to Jacobian conversion
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.fromAffine(aff)
