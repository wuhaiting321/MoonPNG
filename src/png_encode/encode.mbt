// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Error raised when an image cannot be encoded as a PNG datastream.
pub suberror PngEncodeError {
  ///
  /// The image carries no pixels to encode.
  EmptyImage
  ///
  /// The image is internally inconsistent, such as a pixel stream that does not
  /// match its declared geometry.
  BadImage(reason~ : String)
  ///
  /// The image uses a combination of color type and bit depth that PNG cannot
  /// represent.
  Unsupported(reason~ : String)
} derive(Debug, Eq)

///|
/// The eight bytes that open every PNG datastream (RFC 2083, section 3.1).
fn signature() -> Bytes {
  b"\x89PNG\r\n\x1a\n"
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
/// Reject images the datastream cannot describe before any byte is written.
fn validate(image : @image.Image) -> Unit raise PngEncodeError {
  if image.width <= 0 || image.height <= 0 || image.pixels.length() == 0 {
    raise EmptyImage
  }
  if !depth_is_legal(image.color_type, image.bit_depth) {
    raise Unsupported(
      reason="color type \{image.color_type.code()} cannot be paired with bit depth \{image.bit_depth}",
    )
  }
  if image.pixels.length() != image.pixel_bytes() {
    raise BadImage(
      reason="the pixel stream does not match the declared image geometry",
    )
  }
  if image.is_indexed() {
    let entries = image.palette.length()
    if entries == 0 || entries % 3 != 0 || entries > 768 {
      raise BadImage(
        reason="a palette must hold between one and 256 RGB triples",
      )
    }
  }
  if image.transparency.length() > 0 && image.color_type.is_alpha() {
    raise Unsupported(
      reason="a tRNS payload is only legal for color types 0, 2, and 3",
    )
  }
}

///|
/// Serialise the IHDR payload: the geometry, the sample layout, and the fixed
/// compression, filter, and interlace methods (RFC 2083 section 11.2.2).
fn ihdr_payload(image : @image.Image) -> Bytes {
  let payload = @io_abstraction.ByteWriter::new()
  payload.write_u32be(image.width.reinterpret_as_uint())
  payload.write_u32be(image.height.reinterpret_as_uint())
  payload.write_byte(image.bit_depth.to_byte())
  payload.write_byte(image.color_type.code().to_byte())
  payload.write_byte(b'\x00')
  payload.write_byte(b'\x00')
  payload.write_byte(b'\x00')
  payload.to_bytes()
}

///|
/// Append one chunk: its payload length, its type, its payload, and the CRC-32
/// of the type and payload fields (RFC 2083 section 3.2).
fn write_chunk(
  sink : @io_abstraction.ByteWriter,
  ctype : Bytes,
  data : Bytes,
) -> Unit {
  let body = @io_abstraction.ByteWriter::new()
  body.write_bytes(ctype)
  body.write_bytes(data)
  sink.write_u32be(data.length().reinterpret_as_uint())
  sink.write_bytes(ctype)
  sink.write_bytes(data)
  sink.write_u32be(@zlib.crc32(body.to_bytes()))
}

///|
/// Encode `image` into a lossless PNG datastream.
///
/// The samples already sit in the packed, row-major layout of a PNG datastream,
/// so encoding filters every scanline, compresses the result into a zlib
/// stream, and frames the IHDR, PLTE, tRNS, IDAT, and IEND chunks. The output is
/// progressive (no Adam7 interlacing) and round-trips back through
/// `@png.decode` into an identical `Image`.
pub fn encode(image : @image.Image) -> Bytes raise PngEncodeError {
  validate(image)
  let sink = @io_abstraction.ByteWriter::new()
  sink.write_bytes(signature())
  write_chunk(sink, b"IHDR", ihdr_payload(image))
  if image.is_indexed() {
    write_chunk(sink, b"PLTE", image.palette)
  }
  if image.transparency.length() > 0 {
    write_chunk(sink, b"tRNS", image.transparency)
  }
  write_chunk(sink, b"IDAT", zlib_compress(filtered_scanlines(image)))
  write_chunk(sink, b"IEND", b"")
  sink.to_bytes()
}
