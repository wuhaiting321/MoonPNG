// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Error raised when an image cannot be encoded as a PNG datastream.
pub suberror PngEncodeError {
  ///
  /// The image carries no pixels to encode.
  EmptyImage
  ///
  /// The requested image shape is not supported by the encoder yet.
  Unsupported(reason~ : String)
} derive(Debug, Eq)

///|
/// Encode `image` into a lossless PNG datastream.
///
/// The chunk writer, the per-row filter-selection heuristic, and the zlib
/// DEFLATE stage land in the encoder milestone. This entry point currently
/// validates the input and reports the pipeline as pending.
pub fn encode(image : @image.Image) -> Bytes raise PngEncodeError {
  if image.width <= 0 || image.height <= 0 || image.pixels.length() == 0 {
    raise EmptyImage
  }
  raise Unsupported(reason="PNG encoding pipeline is not implemented yet")
}
