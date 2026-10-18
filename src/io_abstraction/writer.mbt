// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Backend-agnostic byte sink.
///
/// Mirrors [Reader] on the output side: encoders append bytes through this
/// trait, so the same code produces a PNG datastream on every target.
pub trait Writer {
  ///|
  /// Append a single byte.
  fn write_byte(Self, Byte) -> Unit

  ///|
  /// Append every byte of `data`.
  fn write_bytes(Self, Bytes) -> Unit

  ///|
  /// Number of bytes written so far.
  fn length(Self) -> Int

  ///|
  /// Consume the accumulated bytes.
  fn to_bytes(Self) -> Bytes
}

///|
/// Growable in-memory byte sink.
pub(all) struct ByteWriter {
  mut buffer : Array[Byte]
}

///|
/// Create an empty sink.
pub fn ByteWriter::new() -> ByteWriter {
  { buffer: ([] : Array[Byte]), }
}

///|
pub impl Writer for ByteWriter with fn write_byte(self : ByteWriter, b : Byte) {
  self.buffer.push(b)
}

///|
pub impl Writer for ByteWriter with fn write_bytes(
  self : ByteWriter,
  data : Bytes,
) {
  let mut i = 0
  while i < data.length() {
    self.buffer.push(data[i])
    i = i + 1
  }
}

///|
pub impl Writer for ByteWriter with fn length(self : ByteWriter) -> Int {
  self.buffer.length()
}

///|
pub impl Writer for ByteWriter with fn to_bytes(self : ByteWriter) -> Bytes {
  Bytes::from_array(self.buffer)
}

///|
/// Promote the [Writer] methods to direct methods on [ByteWriter].
pub extend ByteWriter with Writer::{write_byte, write_bytes, length, to_bytes}

///|
/// Append a big-endian 16-bit integer.
pub fn ByteWriter::write_u16be(self : ByteWriter, value : UInt) -> Unit {
  self.write_byte(((value >> 8) & 0xFF).to_byte())
  self.write_byte((value & 0xFF).to_byte())
}

///|
/// Append a big-endian 32-bit integer.
pub fn ByteWriter::write_u32be(self : ByteWriter, value : UInt) -> Unit {
  self.write_byte(((value >> 24) & 0xFF).to_byte())
  self.write_byte(((value >> 16) & 0xFF).to_byte())
  self.write_byte(((value >> 8) & 0xFF).to_byte())
  self.write_byte((value & 0xFF).to_byte())
}
