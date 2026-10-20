// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Natural (row-major) coefficient index of each position in the zig-zag
/// sequence that DQT and the entropy-coded block both use (ITU T.81, figure
/// A.6).
let zigzag_to_natural : Array[Int] = [
  0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48,
  41, 34, 27, 20, 13, 6, 7, 14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15,
  23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62,
  63,
]

///|
/// Two-dimensional inverse DCT basis, precomputed so that every target produces
/// bit-identical output without depending on a platform `cos`:
///
///   basis[u * 8 + x] = C(u) * cos((2x + 1) * u * pi / 16) / 2
///
/// with C(0) = 1/sqrt(2) and C(u) = 1 otherwise, so the two separable passes
/// below carry the 1/4 of the transform definition (ITU T.81, section A.3.3).
let idct_basis : Array[Double] = [
  0.353553390593, 0.353553390593, 0.353553390593, 0.353553390593, 0.353553390593,
  0.353553390593, 0.353553390593, 0.353553390593, 0.490392640202, 0.415734806151,
  0.277785116510, 0.097545161008, -0.097545161008, -0.277785116510, -0.415734806151,
  -0.490392640202, 0.461939766256, 0.191341716183, -0.191341716183, -0.461939766256,
  -0.461939766256, -0.191341716183, 0.191341716183, 0.461939766256, 0.415734806151,
  -0.097545161008, -0.490392640202, -0.277785116510, 0.277785116510, 0.490392640202,
  0.097545161008, -0.415734806151, 0.353553390593, -0.353553390593, -0.353553390593,
  0.353553390593, 0.353553390593, -0.353553390593, -0.353553390593, 0.353553390593,
  0.277785116510, -0.490392640202, 0.097545161008, 0.415734806151, -0.415734806151,
  -0.097545161008, 0.490392640202, -0.277785116510, 0.191341716183, -0.461939766256,
  0.461939766256, -0.191341716183, -0.191341716183, 0.461939766256, -0.461939766256,
  0.191341716183, 0.097545161008, -0.277785116510, 0.415734806151, -0.490392640202,
  0.490392640202, -0.415734806151, 0.277785116510, -0.097545161008,
]

///|
/// Multiply each zig-zag coefficient by its quantisation step and scatter the
/// result into natural order, so the transform below can work row-major.
fn dequantise(
  coeffs : Array[Int],
  quant : Array[Int],
  base : Int,
) -> Array[Int] {
  let natural : Array[Int] = Array::make(64, 0)
  let mut k = 0
  while k < 64 {
    natural[zigzag_to_natural[k]] = coeffs[k] * quant[base + k]
    k = k + 1
  }
  natural
}

///|
/// Invert one 8x8 block of dequantised coefficients and return its samples.
///
/// The transform is separable: the first pass turns each row of coefficients
/// into an intermediate row, the second turns each column of those into a
/// sample. The level shift of 128 that the encoder applied before the forward
/// transform is added back, and the result is clamped to the sample range.
fn idct_block(coeffs : Array[Int]) -> Array[Byte] {
  let temp : Array[Double] = Array::make(64, 0.0)
  let mut u = 0
  while u < 8 {
    let mut y = 0
    while y < 8 {
      let mut sum = 0.0
      let mut v = 0
      while v < 8 {
        sum = sum + coeffs[v * 8 + u].to_double() * idct_basis[v * 8 + y]
        v = v + 1
      }
      temp[u * 8 + y] = sum
      y = y + 1
    }
    u = u + 1
  }
  let out : Array[Byte] = Array::make(64, b'\x00')
  let mut x = 0
  while x < 8 {
    let mut y = 0
    while y < 8 {
      let mut sum = 0.0
      let mut u = 0
      while u < 8 {
        sum = sum + idct_basis[u * 8 + x] * temp[u * 8 + y]
        u = u + 1
      }
      let sample = (sum + 128.5).to_int()
      out[y * 8 + x] = if sample < 0 {
        b'\x00'
      } else if sample > 255 {
        b'\xff'
      } else {
        sample.to_byte()
      }
      y = y + 1
    }
    x = x + 1
  }
  out
}
