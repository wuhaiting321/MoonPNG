// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Pack raw samples into the row-major, bit-packed layout a PNG datastream
/// uses: `depth` bits per sample, most-significant-bit first, with every
/// scanline padded up to a byte boundary.
fn pack_samples(
  width : Int,
  height : Int,
  depth : Int,
  channels : Int,
  samples : Array[Int],
) -> Bytes {
  let bytes_per_row = (width * channels * depth + 7) / 8
  let row_samples = width * channels
  let out : Array[Byte] = []
  let mut y = 0
  while y < height {
    let row : Array[Byte] = Array::make(bytes_per_row, b'\x00')
    let mut index = 0
    while index < row_samples {
      let value = samples[y * row_samples + index]
      if depth == 8 {
        row[index] = value.to_byte()
      } else if depth == 16 {
        row[index * 2] = ((value >> 8) & 0xFF).to_byte()
        row[index * 2 + 1] = (value & 0xFF).to_byte()
      } else {
        let shift = 8 - depth - index * depth % 8
        let mask = ((1 << depth) - 1) << shift
        let at = index * depth / 8
        row[at] = ((row[at].to_int() & (mask ^ 0xFF)) |
        ((value << shift) & mask)).to_byte()
      }
      index = index + 1
    }
    let mut i = 0
    while i < bytes_per_row {
      out.push(row[i])
      i = i + 1
    }
    y = y + 1
  }
  Bytes::from_array(out)
}

///|
/// Build an image whose samples sit in the datastream layout the encoder
/// expects, so encoding starts from a known raster rather than a fixture.
fn image_of(
  width : Int,
  height : Int,
  depth : Int,
  color : @image.ColorType,
  samples : Array[Int],
) -> @image.Image {
  @image.Image::new(
    width,
    height,
    depth,
    color,
    pack_samples(width, height, depth, color.channels(), samples),
  )
}

///|
/// Deterministic sample pattern that fills the full range of `depth` bits.
fn pattern(count : Int, depth : Int) -> Array[Int] {
  let top = if depth >= 16 { 65535 } else { (1 << depth) - 1 }
  let step = if depth >= 16 { 4111 } else { 3 }
  let out : Array[Int] = []
  let mut i = 0
  while i < count {
    out.push(i * step % (top + 1))
    i = i + 1
  }
  out
}

///|
/// Encode `image`, decode the result again, and assert that every field of the
/// datastream survives the round trip untouched.
fn assert_round_trip(image : @image.Image) -> Unit raise {
  let bytes = @png.encode(image)
  assert_true(@png_decode.is_png(bytes))
  let decoded = @png.decode(bytes)
  assert_eq(decoded.width, image.width)
  assert_eq(decoded.height, image.height)
  assert_eq(decoded.bit_depth, image.bit_depth)
  assert_eq(decoded.color_type, image.color_type)
  assert_eq(decoded.pixels, image.pixels)
  assert_eq(decoded.palette, image.palette)
  assert_eq(decoded.transparency, image.transparency)
}

///|
test "round-trips grayscale images at every legal bit depth" {
  for depth in [1, 2, 4] {
    let width = 5
    let height = 3
    assert_round_trip(
      image_of(
        width,
        height,
        depth,
        @image.ColorType::Grayscale,
        pattern(width * height, depth),
      ),
    )
  }
  for depth in [8, 16] {
    assert_round_trip(
      image_of(7, 4, depth, @image.ColorType::Grayscale, pattern(7 * 4, depth)),
    )
  }
}

///|
test "round-trips every image layout that carries color samples" {
  let layouts : Array[(Int, @image.ColorType)] = [
    (8, @image.ColorType::Truecolor),
    (16, @image.ColorType::Truecolor),
    (8, @image.ColorType::TruecolorAlpha),
    (16, @image.ColorType::TruecolorAlpha),
    (8, @image.ColorType::GrayscaleAlpha),
    (16, @image.ColorType::GrayscaleAlpha),
  ]
  let mut i = 0
  while i < layouts.length() {
    let (depth, color) = layouts[i]
    assert_round_trip(
      image_of(6, 5, depth, color, pattern(6 * 5 * color.channels(), depth)),
    )
    i = i + 1
  }
}

///|
test "round-trips indexed images with a palette and a tRNS payload" {
  let palette : Bytes = b"\xff\x00\x00\x00\xff\x00\x00\x00\xff\xff\xff\xff"
  let two_colors : Bytes = b"\xff\x00\x00\x20\x40\x80"
  let one_bit = image_of(8, 2, 1, @image.ColorType::Indexed, pattern(8 * 2, 1))
    .with_palette(two_colors)
    .with_transparency(b"\x00\xff")
  assert_round_trip(one_bit)
  let eight_bit = image_of(6, 3, 8, @image.ColorType::Indexed, [
      0, 1, 2, 3, 0, 1, 3, 2, 1, 0, 2, 3, 1, 0, 3, 2, 0, 1,
    ])
    .with_palette(palette)
    .with_transparency(b"\x00\x40\x80\xff")
  assert_round_trip(eight_bit)
}

///|
test "round-trips the PngSuite baseline corpus through the encoder" {
  let corpus : Array[Bytes] = [
    basn0g01, basn0g04, basn0g16, basn3p01, basn2c16, basn6a08,
  ]
  let mut i = 0
  while i < corpus.length() {
    let original = @png.decode(corpus[i])
    let restored = @png.decode(@png.encode(original))
    assert_eq(restored.width, original.width)
    assert_eq(restored.height, original.height)
    assert_eq(restored.bit_depth, original.bit_depth)
    assert_eq(restored.color_type, original.color_type)
    assert_eq(restored.pixels, original.pixels)
    assert_eq(restored.palette, original.palette)
    i = i + 1
  }
}

///|
/// Total size a datastream would occupy if its IDAT carried the scanlines
/// verbatim: signature, IHDR, IDAT framing plus stored-block headers, IEND.
fn stored_datastream_size(scanlines : Int) -> Int {
  let blocks = (scanlines + 65534) / 65535
  63 + 5 * blocks + scanlines
}

///|
test "compressing a real image beats storing its scanlines" {
  let corpus : Array[Bytes] = [basn0g04, basn0g16, basn2c16, basn6a08]
  let mut i = 0
  while i < corpus.length() {
    let image = @png.decode(corpus[i])
    let scanlines = image.row_bytes() * image.height + image.height
    let encoded = @png.encode(image).length()
    let stored = stored_datastream_size(scanlines)
    println("corpus stored=\{stored} compressed=\{encoded}")
    assert_true(encoded * 5 <= stored * 4)
    i = i + 1
  }
}

///|
test "the encoder rejects images it cannot describe" {
  let empty = @image.Image::new(0, 0, 8, @image.ColorType::Truecolor, b"")
  let caught_empty = try {
    let _ = @png.encode(empty)
    false
  } catch {
    @png_encode.PngEncodeError::EmptyImage => true
    _ => false
  }
  assert_true(caught_empty)
  let illegal_depth = @image.Image::new(
    2,
    2,
    1,
    @image.ColorType::Truecolor,
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
  )
  let caught_depth = try {
    let _ = @png.encode(illegal_depth)
    false
  } catch {
    @png_encode.PngEncodeError::Unsupported(_) => true
    _ => false
  }
  assert_true(caught_depth)
  let short_stream = @image.Image::new(
    4,
    2,
    8,
    @image.ColorType::Grayscale,
    b"\x00\x00\x00",
  )
  let caught_short = try {
    let _ = @png.encode(short_stream)
    false
  } catch {
    @png_encode.PngEncodeError::BadImage(_) => true
    _ => false
  }
  assert_true(caught_short)
  let palette_less = @image.Image::new(
    2,
    2,
    8,
    @image.ColorType::Indexed,
    b"\x00\x01\x02\x03",
  )
  let caught_palette = try {
    let _ = @png.encode(palette_less)
    false
  } catch {
    @png_encode.PngEncodeError::BadImage(_) => true
    _ => false
  }
  assert_true(caught_palette)
  let alpha_with_trns = image_of(
    2,
    2,
    8,
    @image.ColorType::TruecolorAlpha,
    pattern(2 * 2 * 4, 8),
  ).with_transparency(b"\x00\x00\x00\x00\x00\x00")
  let caught_trns = try {
    let _ = @png.encode(alpha_with_trns)
    false
  } catch {
    @png_encode.PngEncodeError::Unsupported(_) => true
    _ => false
  }
  assert_true(caught_trns)
}
