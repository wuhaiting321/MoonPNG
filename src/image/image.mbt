// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Color type of an image, matching the IHDR color-type field of RFC 2083
/// section 4.1.1.
pub(all) enum ColorType {
  /// One sample per pixel, stored as a gray level.
  Grayscale
  /// Three samples per pixel: red, green, and blue.
  Truecolor
  /// One palette index per pixel into an RGB palette.
  Indexed
  /// Two samples per pixel: gray level and alpha.
  GrayscaleAlpha
  /// Four samples per pixel: red, green, blue, and alpha.
  TruecolorAlpha
} derive(Eq, Debug)

///|
/// Samples stored per pixel for this color type.
pub fn ColorType::channels(self : ColorType) -> Int {
  match self {
    Grayscale => 1
    Truecolor => 3
    Indexed => 1
    GrayscaleAlpha => 2
    TruecolorAlpha => 4
  }
}

///|
/// The numeric code written into the IHDR color-type field.
pub fn ColorType::code(self : ColorType) -> Int {
  match self {
    Grayscale => 0
    Truecolor => 2
    Indexed => 3
    GrayscaleAlpha => 4
    TruecolorAlpha => 6
  }
}

///|
/// Decode an IHDR color-type code, or `None` for a reserved value.
pub fn ColorType::from_code(code : Int) -> ColorType? {
  match code {
    0 => Some(Grayscale)
    2 => Some(Truecolor)
    3 => Some(Indexed)
    4 => Some(GrayscaleAlpha)
    6 => Some(TruecolorAlpha)
    _ => None
  }
}

///|
/// Whether the color type carries an alpha sample.
pub fn ColorType::is_alpha(self : ColorType) -> Bool {
  match self {
    GrayscaleAlpha | TruecolorAlpha => true
    _ => false
  }
}

///|
/// An in-memory raster image.
///
/// `pixels` holds the raw sample stream exactly as it is laid out in a PNG
/// datastream: row-major, `bit_depth` bits per sample, [ColorType::channels]
/// samples per pixel. Samples narrower than eight bits are packed
/// most-significant-bit first, and 16-bit samples are stored big-endian, per
/// RFC 2083 section 2.2.
///
/// `palette` holds RGB triples for [ColorType::Indexed] images and is empty
/// otherwise. `transparency` holds the raw `tRNS` payload (a palette alpha
/// table, a single gray level, or a single RGB triple) and is empty when the
/// image has no transparent color.
pub(all) struct Image {
  width : Int
  height : Int
  bit_depth : Int
  color_type : ColorType
  pixels : Bytes
  palette : Bytes
  transparency : Bytes
}

///|
/// Build an image from its pixel stream; palette and transparency start empty.
pub fn Image::new(
  width : Int,
  height : Int,
  bit_depth : Int,
  color_type : ColorType,
  pixels : Bytes,
) -> Image {
  {
    width,
    height,
    bit_depth,
    color_type,
    pixels,
    palette: b"",
    transparency: b"",
  }
}

///|
/// Set the RGB palette of an indexed image.
pub fn Image::with_palette(self : Image, palette : Bytes) -> Image {
  { ..self, palette, }
}

///|
/// Attach the raw `tRNS` payload.
pub fn Image::with_transparency(self : Image, transparency : Bytes) -> Image {
  { ..self, transparency, }
}

///|
/// Samples stored per pixel.
pub fn Image::channels(self : Image) -> Int {
  self.color_type.channels()
}

///|
/// Bits occupied by one pixel.
pub fn Image::bits_per_pixel(self : Image) -> Int {
  self.bit_depth * self.channels()
}

///|
/// Total number of samples in the image.
pub fn Image::sample_count(self : Image) -> Int {
  self.width * self.height * self.channels()
}

///|
/// Bytes needed for one unfiltered scanline, rounded up to a byte boundary.
pub fn Image::row_bytes(self : Image) -> Int {
  (self.bits_per_pixel() * self.width + 7) / 8
}

///|
/// Bytes needed for the whole unfiltered pixel stream.
pub fn Image::pixel_bytes(self : Image) -> Int {
  self.row_bytes() * self.height
}

///|
/// Whether the image is palette-based.
pub fn Image::is_indexed(self : Image) -> Bool {
  self.color_type == Indexed
}

///|
/// Whether the image declares transparency, either through an alpha color type
/// or through a `tRNS` payload.
pub fn Image::has_transparency(self : Image) -> Bool {
  self.color_type.is_alpha() || self.transparency.length() > 0
}
