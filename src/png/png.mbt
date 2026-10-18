// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// MoonPNG facade: the top-level `decode` and `encode` entry points.
///
/// ```
/// let image = @png.decode(bytes)      // Bytes -> @image.Image
/// let bytes = @png.encode(image)      // @image.Image -> Bytes
/// ```

///|
/// Decode a PNG datastream into an `@image.Image`.
pub fn decode(data : Bytes) -> @image.Image raise @png_decode.PngDecodeError {
  @png_decode.decode(data)
}

///|
/// Encode an `@image.Image` into a lossless PNG datastream.
pub fn encode(image : @image.Image) -> Bytes raise @png_encode.PngEncodeError {
  @png_encode.encode(image)
}

///|
/// Version of the MoonPNG module.
pub fn version() -> String {
  "0.1.0"
}
