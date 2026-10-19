// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// A raster with the smooth gradients and repeated structure a real photograph
/// exhibits, so the comparison below runs on data the way an image supplies it
/// rather than on a synthetic worst case.
fn gradient_raster(width : Int, height : Int) -> @image.Image {
  let pixels : Array[Byte] = []
  let mut y = 0
  while y < height {
    let mut x = 0
    while x < width {
      pixels.push((x * 2 % 256).to_byte())
      pixels.push((y * 3 % 256).to_byte())
      pixels.push(((x + y) % 256).to_byte())
      x = x + 1
    }
    y = y + 1
  }
  @image.Image::new(
    width,
    height,
    8,
    @image.ColorType::Truecolor,
    Bytes::from_array(pixels),
  )
}

///|
/// A 16-bit xorshift byte stream, standing in for data no compressor can model.
fn noise(count : Int) -> Bytes {
  let out : Array[Byte] = []
  let mut state = 1
  let mut i = 0
  while i < count {
    state = state ^ ((state << 7) & 0xFFFF)
    state = state ^ (state >> 9)
    state = state ^ ((state << 8) & 0xFFFF)
    out.push((state & 0xFF).to_byte())
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
test "lz77 with fixed huffman shrinks a filtered raster well below stored" {
  let scanlines = filtered_scanlines(gradient_raster(64, 64))
  let stored = stored_body(scanlines)
  let compressed = compressed_body(scanlines)
  println(
    "sizes raw=\{scanlines.length()} stored=\{stored.length()} compressed=\{compressed.length()}",
  )
  assert_true(compressed.length() * 5 <= stored.length() * 4)
  assert_eq(@zlib.inflate_zlib(zlib_compress(scanlines)), scanlines)
}

///|
test "compression never enlarges data it cannot model" {
  let data = noise(4096)
  assert_eq(@zlib.inflate_zlib(zlib_compress(data)), data)
  assert_true(zlib_compress(data).length() <= stored_body(data).length() + 6)
}

///|
test "round trips data a single match has to reach across" {
  let data : Bytes = Array::make(70000, b'\x5a') |> Bytes::from_array
  assert_eq(@zlib.inflate_zlib(zlib_compress(data)), data)
  let stored = stored_body(data)
  let compressed = compressed_body(data)
  println(
    "sizes long raw=\{data.length()} stored=\{stored.length()} compressed=\{compressed.length()}",
  )
  assert_true(compressed.length() * 10 <= stored.length())
}
