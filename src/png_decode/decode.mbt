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
/// Decode a PNG datastream into an `Image`.
///
/// The chunk pipeline (IHDR/PLTE/tRNS/IDAT/IEND, zlib inflate, filter
/// reconstruction, and Adam7 de-interlacing) is implemented in the decoder
/// milestone. This entry point currently validates the signature and reports
/// the pipeline as pending.
pub fn decode(data : Bytes) -> @image.Image raise PngDecodeError {
  if !is_png(data) {
    raise NotPng
  }
  raise BadChunk(reason="PNG decoding pipeline is not implemented yet")
}
