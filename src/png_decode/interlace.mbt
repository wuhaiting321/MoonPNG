// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// The origin and step of one Adam7 pass (RFC 2083 section 8.2), in the order
/// the passes appear inside an interlaced datastream. The first pass is the
/// sparsest, laying down one pixel every eight rows and columns.
fn pass_geometry(pass : Int) -> (Int, Int, Int, Int) {
  if pass == 0 {
    (0, 0, 8, 8)
  } else if pass == 1 {
    (4, 0, 8, 8)
  } else if pass == 2 {
    (0, 4, 4, 8)
  } else if pass == 3 {
    (2, 0, 4, 4)
  } else if pass == 4 {
    (0, 2, 2, 4)
  } else if pass == 5 {
    (1, 0, 2, 2)
  } else {
    (0, 1, 1, 2)
  }
}

///|
/// Number of pixels of pass `pass` that fit across a `width`-wide image.
fn pass_width_of(pass : Int, width : Int) -> Int {
  let (x_start, _, x_step, _) = pass_geometry(pass)
  if width > x_start {
    (width - x_start + x_step - 1) / x_step
  } else {
    0
  }
}

///|
/// Number of scanlines of pass `pass` that fit down a `height`-tall image.
fn pass_height_of(pass : Int, height : Int) -> Int {
  let (_, y_start, _, y_step) = pass_geometry(pass)
  if height > y_start {
    (height - y_start + y_step - 1) / y_step
  } else {
    0
  }
}

///|
/// Bytes needed for one unfiltered scanline of `pixels` samples.
fn scanline_bytes(pixels : Int, depth : Int) -> Int {
  (pixels * depth + 7) / 8
}

///|
/// Smallest number of inflated bytes that can hold the filtered scanlines of an
/// image of this geometry, used to reject truncated data before allocating.
fn required_sample_bytes(
  width : Int,
  height : Int,
  interlace : Int,
  bits_per_pixel : Int,
) -> Int {
  if interlace == 0 {
    (scanline_bytes(width, bits_per_pixel) + 1) * height
  } else {
    let mut total = 0
    let mut pass = 0
    while pass < 7 {
      let pass_width = pass_width_of(pass, width)
      let pass_height = pass_height_of(pass, height)
      if pass_width > 0 && pass_height > 0 {
        total = total +
          pass_height * (scanline_bytes(pass_width, bits_per_pixel) + 1)
      }
      pass = pass + 1
    }
    total
  }
}

///|
/// Read sample `index` of a scanline stored `depth` bits per sample,
/// most-significant-bit first. Sub-byte depths always divide eight, so a sample
/// never straddles two bytes.
fn packed_sample(
  row : Array[Byte],
  row_start : Int,
  index : Int,
  depth : Int,
) -> Int {
  let bit = index * depth
  (row[row_start + bit / 8].to_int() >> (8 - depth - bit % 8)) &
  ((1 << depth) - 1)
}

///|
/// Write one packed sample back into a scanline, clearing the target bits first.
fn set_packed_sample(
  row : Array[Byte],
  row_start : Int,
  index : Int,
  depth : Int,
  value : Int,
) -> Unit {
  let bit = index * depth
  let shift = 8 - depth - bit % 8
  let mask = ((1 << depth) - 1) << shift
  let at = row_start + bit / 8
  row[at] = ((row[at].to_int() & (mask ^ 0xFF)) | ((value << shift) & mask)).to_byte()
}

///|
/// Scatter one reconstructed Adam7 scanline into the packed scanlines of the
/// fully de-interlaced image.
fn place_pass_row(
  pixels : Array[Byte],
  row_start : Int,
  pass_row : Array[Byte],
  pass_width : Int,
  x_start : Int,
  x_step : Int,
  channels : Int,
  depth : Int,
) -> Unit {
  let mut column = 0
  while column < pass_width {
    let x = x_start + column * x_step
    let mut channel = 0
    while channel < channels {
      let source = column * channels + channel
      let target = x * channels + channel
      if depth < 8 {
        let value = packed_sample(pass_row, 0, source, depth)
        set_packed_sample(pixels, row_start, target, depth, value)
      } else if depth == 8 {
        pixels[row_start + target] = pass_row[source]
      } else {
        pixels[row_start + target * 2] = pass_row[source * 2]
        pixels[row_start + target * 2 + 1] = pass_row[source * 2 + 1]
      }
      channel = channel + 1
    }
    column = column + 1
  }
}
