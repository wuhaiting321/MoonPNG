// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Integration tests exercise the public API the way a downstream consumer
/// would, from outside the library packages.

///|
test "image reports derived geometry" {
  let pixels : Bytes = Array::make(2 * 3 * 3, b'\x00') |> Bytes::from_array
  let image = @image.Image::new(2, 3, 8, @image.ColorType::Truecolor, pixels)
  assert_eq(image.channels(), 3)
  assert_eq(image.bits_per_pixel(), 24)
  assert_eq(image.row_bytes(), 6)
  assert_eq(image.pixel_bytes(), 18)
  assert_eq(image.sample_count(), 18)
  assert_false(image.is_indexed())
  assert_false(image.has_transparency())
}

///|
test "color type codes round trip" {
  for code in [0, 2, 3, 4, 6] {
    let color = @image.ColorType::from_code(code)
    assert_true(color is Some(_))
    match color {
      Some(value) => assert_eq(value.code(), code)
      None => assert_true(false)
    }
  }
  assert_true(@image.ColorType::from_code(1) is None)
  assert_true(@image.ColorType::TruecolorAlpha.is_alpha())
}

///|
test "checksums match the standard vectors" {
  let data : Bytes = b"123456789"
  assert_eq(@zlib.crc32(data), 0xCBF43926U)
  assert_eq(@zlib.adler32(data), 0x091E01DEU)
}

///|
test "png facade exposes its version" {
  assert_eq(@png.version(), "0.1.0")
}

///|
test "png signature detection" {
  assert_true(@png_decode.is_png(@png_decode.signature()))
  assert_false(@png_decode.is_png(b"GIF89a"))
  assert_false(@png_decode.is_png(b""))
}
