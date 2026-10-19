// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Bytes occupied by one complete pixel for filter arithmetic: whole pixels,
/// rounded up to a single byte for sub-byte depths (RFC 2083 section 6).
fn filter_bpp(image : @image.Image) -> Int {
  let bits = image.bits_per_pixel()
  if bits < 8 {
    1
  } else {
    bits / 8
  }
}

///|
/// Magnitude of a filtered byte once it is read as a signed difference, which
/// is how the filter heuristic scores a scanline.
fn magnitude(value : Int) -> Int {
  let signed = if value > 127 { value - 256 } else { value }
  if signed < 0 {
    -signed
  } else {
    signed
  }
}

///|
/// Absolute value of a plain difference, which is what the Paeth predictor
/// compares its candidate neighbours by.
fn distance(value : Int) -> Int {
  if value < 0 {
    -value
  } else {
    value
  }
}

///|
/// Paeth predictor: the neighbour closest to the planar estimate `a + b - c`
/// (RFC 2083 section 6.6).
fn paeth(a : Int, b : Int, c : Int) -> Int {
  let p = a + b - c
  let pa = distance(p - a)
  let pb = distance(p - b)
  let pc = distance(p - c)
  if pa <= pb && pa <= pc {
    a
  } else if pb <= pc {
    b
  } else {
    c
  }
}

///|
/// Apply filter `kind` to one scanline, where `prior` holds the reconstructed
/// bytes of the previous scanline and `bpp` the bytes per complete pixel.
fn apply_filter(kind : Int, row : Bytes, prior : Bytes, bpp : Int) -> Bytes {
  let out : Array[Byte] = Array::make(row.length(), b'\x00')
  let mut i = 0
  while i < row.length() {
    let left = if i >= bpp { row[i - bpp].to_int() } else { 0 }
    let up = prior[i].to_int()
    let upleft = if i >= bpp { prior[i - bpp].to_int() } else { 0 }
    let predicted = if kind == 1 {
      left
    } else if kind == 2 {
      up
    } else if kind == 3 {
      (left + up) / 2
    } else if kind == 4 {
      paeth(left, up, upleft)
    } else {
      0
    }
    out[i] = ((row[i].to_int() - predicted) & 0xFF).to_byte()
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
/// Score a filtered scanline by the sum of the magnitudes of its bytes; a
/// lower score means the filter left less residual energy for the compressor.
fn filter_score(row : Bytes) -> Int {
  let mut total = 0
  let mut i = 0
  while i < row.length() {
    total = total + magnitude(row[i].to_int())
    i = i + 1
  }
  total
}

///|
/// Filter every scanline, choosing for each row the filter among the five
/// defined methods that minimises the sum of magnitudes, and interleave each
/// choice with its filtered row as the datastream requires.
fn filtered_scanlines(image : @image.Image) -> Bytes {
  let row_bytes = image.row_bytes()
  let bpp = filter_bpp(image)
  let out : Array[Byte] = []
  let mut prior : Bytes = Bytes::make(row_bytes, b'\x00')
  let mut y = 0
  while y < image.height {
    let row : Array[Byte] = Array::make(row_bytes, b'\x00')
    let mut i = 0
    while i < row_bytes {
      row[i] = image.pixels[y * row_bytes + i]
      i = i + 1
    }
    let raw = Bytes::from_array(row)
    let mut best_kind = 0
    let mut best = apply_filter(0, raw, prior, bpp)
    let mut best_score = filter_score(best)
    let mut kind = 1
    while kind <= 4 {
      let candidate = apply_filter(kind, raw, prior, bpp)
      let score = filter_score(candidate)
      if score < best_score {
        best_kind = kind
        best = candidate
        best_score = score
      }
      kind = kind + 1
    }
    out.push(best_kind.to_byte())
    i = 0
    while i < row_bytes {
      out.push(best[i])
      i = i + 1
    }
    prior = raw
    y = y + 1
  }
  Bytes::from_array(out)
}
