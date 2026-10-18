// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Keep only the low eight bits of `value`, so reconstructed samples wrap
/// modulo 256 exactly as RFC 2083 section 6 requires.
fn low_byte(value : Int) -> Byte {
  (value & 0xFF).to_byte()
}

///|
/// The Paeth predictor of RFC 2083 section 6.5, choosing whichever of the left,
/// the upper, and the upper-left neighbour is closest to their linear estimate.
fn paeth(left : Int, up : Int, up_left : Int) -> Int {
  let estimate = left + up - up_left
  let to_left = if estimate > left { estimate - left } else { left - estimate }
  let to_up = if estimate > up { estimate - up } else { up - estimate }
  let to_up_left = if estimate > up_left {
    estimate - up_left
  } else {
    up_left - estimate
  }
  if to_left <= to_up && to_left <= to_up_left {
    left
  } else if to_up <= to_up_left {
    up
  } else {
    up_left
  }
}

///|
/// Reverse one scanline filter in place (RFC 2083 section 6).
///
/// `current` holds the filtered bytes of a single scanline and is overwritten
/// with the reconstructed bytes. `prior` holds the already reconstructed
/// scanline above it, or a run of zeros for the first line of a pass. `bpp` is
/// the byte distance between two neighbouring pixels on the same scanline.
fn unfilter_row(
  filter : Int,
  current : Array[Byte],
  prior : Bytes,
  bpp : Int,
) -> Unit raise PngDecodeError {
  let width = current.length()
  match filter {
    0 => ()
    1 => {
      let mut i = bpp
      while i < width {
        current[i] = low_byte(current[i].to_int() + current[i - bpp].to_int())
        i = i + 1
      }
    }
    2 => {
      let mut i = 0
      while i < width {
        current[i] = low_byte(current[i].to_int() + prior[i].to_int())
        i = i + 1
      }
    }
    3 => {
      let mut i = 0
      while i < width {
        let left = if i >= bpp { current[i - bpp].to_int() } else { 0 }
        current[i] = low_byte(
          current[i].to_int() + ((left + prior[i].to_int()) >> 1),
        )
        i = i + 1
      }
    }
    4 => {
      let mut i = 0
      while i < width {
        let left = if i >= bpp { current[i - bpp].to_int() } else { 0 }
        let up = prior[i].to_int()
        let up_left = if i >= bpp { prior[i - bpp].to_int() } else { 0 }
        current[i] = low_byte(current[i].to_int() + paeth(left, up, up_left))
        i = i + 1
      }
    }
    _ =>
      raise BadChunk(reason="scanline uses the unknown filter type \{filter}")
  }
}
