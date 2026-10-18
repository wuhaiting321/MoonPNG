// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Error raised when a byte stream cannot be decoded as a PNG image.
pub suberror PngDecodeError {
  ///
  /// The eight-byte PNG signature is missing or malformed.
  NotPng
  ///
  /// A chunk is structurally invalid, truncated, or of a kind the decoder does
  /// not support.
  BadChunk(reason~ : String)
} derive(Debug, Eq)

///|
/// The eight bytes that open every PNG datastream (RFC 2083, section 3.1).
pub fn signature() -> Bytes {
  b"\x89PNG\r\n\x1a\n"
}

///|
/// Whether `data` starts with the PNG signature.
pub fn is_png(data : Bytes) -> Bool {
  let sig = signature()
  if data.length() < sig.length() {
    return false
  }
  let mut i = 0
  while i < sig.length() {
    if data[i] != sig[i] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// The fields carried by the IHDR chunk, which must open every datastream
/// (RFC 2083 section 11.2.2).
pub(all) struct PngHeader {
  width : Int
  height : Int
  bit_depth : Int
  color_type : @image.ColorType
  /// Zero for a progressive scan, one for Adam7 interlacing.
  interlace : Int
} derive(Debug, Eq)

///|
/// Read a big-endian 32-bit field at `offset` inside `bytes`.
fn be_u32(bytes : Bytes, offset : Int) -> Int {
  ((bytes[offset].to_uint() << 24) |
  (bytes[offset + 1].to_uint() << 16) |
  (bytes[offset + 2].to_uint() << 8) |
  bytes[offset + 3].to_uint()).reinterpret_as_int()
}

///|
/// Whether `depth` is one of the bit depths IHDR may pair with `color`, per the
/// table in RFC 2083 section 11.2.2.
fn depth_is_legal(color : @image.ColorType, depth : Int) -> Bool {
  if color == @image.ColorType::Grayscale {
    depth == 1 || depth == 2 || depth == 4 || depth == 8 || depth == 16
  } else if color == @image.ColorType::Indexed {
    depth == 1 || depth == 2 || depth == 4 || depth == 8
  } else {
    depth == 8 || depth == 16
  }
}

///|
/// Parse and validate the IHDR chunk that follows the signature.
fn parse_ihdr(
  reader : @io_abstraction.ByteReader,
) -> PngHeader raise PngDecodeError {
  let chunk = Chunk::read(reader)
  if chunk.ctype != "IHDR" {
    raise BadChunk(reason="the first chunk must be IHDR but is \{chunk.ctype}")
  }
  if chunk.data.length() != 13 {
    raise BadChunk(reason="the IHDR payload must be exactly 13 bytes")
  }
  let raw = chunk.data
  let width = be_u32(raw, 0)
  let height = be_u32(raw, 4)
  let bit_depth = raw[8].to_int()
  let color_code = raw[9].to_int()
  let compression = raw[10].to_int()
  let filter_method = raw[11].to_int()
  let interlace = raw[12].to_int()
  if width <= 0 || height <= 0 {
    raise BadChunk(reason="the image dimensions must both be positive")
  }
  let color_type = match @image.ColorType::from_code(color_code) {
    Some(value) => value
    None =>
      raise BadChunk(
        reason="IHDR declares the reserved color type \{color_code}",
      )
  }
  if !depth_is_legal(color_type, bit_depth) {
    raise BadChunk(
      reason="IHDR pairs color type \{color_code} with the illegal bit depth \{bit_depth}",
    )
  }
  if compression != 0 {
    raise BadChunk(
      reason="IHDR declares the unsupported compression method \{compression}",
    )
  }
  if filter_method != 0 {
    raise BadChunk(
      reason="IHDR declares the unsupported filter method \{filter_method}",
    )
  }
  if interlace != 0 && interlace != 1 {
    raise BadChunk(
      reason="IHDR declares the unknown interlace method \{interlace}",
    )
  }
  { width, height, bit_depth, color_type, interlace, }
}

///|
/// Parse the PNG signature and the IHDR chunk without touching pixel data.
pub fn header(data : Bytes) -> PngHeader raise PngDecodeError {
  if !is_png(data) {
    raise NotPng
  }
  let reader = @io_abstraction.ByteReader::new(data)
  skip(reader, 8)
  parse_ihdr(reader)
}

///|
/// Decode a PNG datastream into an `Image`.
///
/// The chunk pipeline (PLTE/tRNS/IDAT/IEND, zlib inflate, filter
/// reconstruction, and Adam7 de-interlacing) lands in the decoder milestones.
/// This entry point currently validates the signature and the IHDR chunk, then
/// reports the sample pipeline as pending.
pub fn decode(data : Bytes) -> @image.Image raise PngDecodeError {
  let info = header(data)
  raise BadChunk(
    reason="the sample pipeline is not implemented yet for a \{info.width}x\{info.height} image",
  )
}
