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
/// The chunks are read in order, the concatenated `IDAT` payload is inflated,
/// and every scanline is reconstructed through its filter. Depth packing,
/// palette handling, and Adam7 de-interlacing land in the next milestone, so
/// this entry point currently accepts eight-bit progressive images.
pub fn decode(data : Bytes) -> @image.Image raise PngDecodeError {
  let info = header(data)
  if info.bit_depth != 8 {
    raise BadChunk(reason="bit depth \{info.bit_depth} is not decoded yet")
  }
  if info.interlace != 0 {
    raise BadChunk(reason="Adam7 interlacing is not decoded yet")
  }
  let reader = @io_abstraction.ByteReader::new(data)
  skip(reader, 8)
  let _ = Chunk::read(reader)
  let mut palette : Bytes = b""
  let mut transparency : Bytes = b""
  let compressed : Array[Byte] = []
  let mut ended = false
  while !ended {
    if reader.remaining() == 0 {
      raise BadChunk(reason="the datastream ended before an IEND chunk")
    }
    let chunk = Chunk::read(reader)
    if chunk.ctype == "IDAT" {
      let mut i = 0
      while i < chunk.data.length() {
        compressed.push(chunk.data[i])
        i = i + 1
      }
    } else if chunk.ctype == "PLTE" {
      palette = chunk.data
    } else if chunk.ctype == "tRNS" {
      transparency = chunk.data
    } else if chunk.ctype == "IEND" {
      ended = true
    }
  }
  if compressed.length() == 0 {
    raise BadChunk(reason="the datastream carries no IDAT payload")
  }
  let samples = @zlib.inflate_zlib(Bytes::from_array(compressed)) catch {
    @zlib.InflateError::BadData(reason~) => raise BadChunk(reason~)
  }
  let indexed = info.color_type == @image.ColorType::Indexed
  if indexed && palette.length() == 0 {
    raise BadChunk(reason="an indexed image must carry a PLTE chunk")
  }
  let bits_per_pixel = info.bit_depth * info.color_type.channels()
  let row_bytes = (bits_per_pixel * info.width + 7) / 8
  let needed = (row_bytes + 1) * info.height
  if samples.length() < needed {
    raise BadChunk(
      reason="the inflated data is shorter than the image geometry requires",
    )
  }
  let pixels : Array[Byte] = Array::make(row_bytes * info.height, b'\x00')
  let bpp = bits_per_pixel / 8
  let mut prior : Bytes = Bytes::make(row_bytes, b'\x00')
  let mut offset = 0
  let mut y = 0
  while y < info.height {
    let row : Array[Byte] = Array::make(row_bytes, b'\x00')
    let mut i = 0
    while i < row_bytes {
      row[i] = samples[offset + 1 + i]
      i = i + 1
    }
    unfilter_row(samples[offset].to_int(), row, prior, bpp)
    i = 0
    while i < row_bytes {
      pixels[y * row_bytes + i] = row[i]
      i = i + 1
    }
    prior = Bytes::from_array(row)
    offset = offset + row_bytes + 1
    y = y + 1
  }
  let image = @image.Image::new(
    info.width,
    info.height,
    info.bit_depth,
    info.color_type,
    Bytes::from_array(pixels),
  )
  let mut image = if indexed { image.with_palette(palette) } else { image }
  if transparency.length() > 0 {
    image = image.with_transparency(transparency)
  }
  image
}
