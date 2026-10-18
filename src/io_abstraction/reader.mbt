// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Error raised when a byte source or sink is accessed outside its bounds.
pub suberror IoError {
  ///
  /// `requested` bytes were needed at cursor position `offset`, but only
  /// `capacity` bytes exist in the underlying buffer.
  OutOfBounds(offset~ : Int, requested~ : Int, capacity~ : Int)
} derive(Debug, Eq)

///|
/// Backend-agnostic byte source.
///
/// Every MoonPNG codec consumes its input through this trait rather than a
/// platform file API, so one implementation compiles unchanged for the Native,
/// WebAssembly, and JavaScript targets. Concrete backends only need to satisfy
/// these five operations.
pub trait Reader {
  ///|
  /// Read a single byte and advance the cursor.
  fn read_byte(Self) -> Byte raise IoError

  ///|
  /// Read exactly `len` bytes and advance the cursor by `len`.
  fn read_bytes(Self, Int) -> Bytes raise IoError

  ///|
  /// Advance the cursor by `len` bytes without copying.
  fn skip(Self, Int) -> Unit raise IoError

  ///|
  /// Number of bytes still readable.
  fn remaining(Self) -> Int

  ///|
  /// Absolute cursor position measured from the start of the source.
  fn position(Self) -> Int
}

///|
/// Bounds-checked cursor over an in-memory byte buffer.
///
/// `ByteReader` is the concrete `Reader` shared by all three targets. It owns
/// no platform handle, so it can be constructed inside a WASI sandbox without
/// any capability request.
pub(all) struct ByteReader {
  data : Bytes
  mut pos : Int
}

///|
/// Create a reader positioned at the first byte of `data`.
pub fn ByteReader::new(data : Bytes) -> ByteReader {
  { data, pos: 0, }
}

///|
/// The buffer being read, exposed so codecs can slice it without copying.
pub fn ByteReader::data(self : ByteReader) -> Bytes {
  self.data
}

///|
/// Total capacity of the underlying buffer.
pub fn ByteReader::capacity(self : ByteReader) -> Int {
  self.data.length()
}

///|
/// Raise [IoError::OutOfBounds] unless `len` bytes remain readable.
fn ByteReader::ensure(self : ByteReader, len : Int) -> Unit raise IoError {
  if len < 0 ||
    self.pos > self.data.length() ||
    len > self.data.length() - self.pos {
    raise OutOfBounds(
      offset=self.pos,
      requested=len,
      capacity=self.data.length(),
    )
  }
}

///|
pub impl Reader for ByteReader with fn read_byte(self) -> Byte raise IoError {
  self.ensure(1)
  let value = self.data[self.pos]
  self.pos = self.pos + 1
  value
}

///|
pub impl Reader for ByteReader with fn read_bytes(self : ByteReader, len : Int) -> Bytes raise IoError {
  self.ensure(len)
  let out : Array[Byte] = Array::make(len, b'\x00')
  let mut i = 0
  while i < len {
    out[i] = self.data[self.pos + i]
    i = i + 1
  }
  self.pos = self.pos + len
  Bytes::from_array(out)
}

///|
pub impl Reader for ByteReader with fn skip(self : ByteReader, len : Int) -> Unit raise IoError {
  self.ensure(len)
  self.pos = self.pos + len
}

///|
pub impl Reader for ByteReader with fn remaining(self : ByteReader) -> Int {
  let left = self.data.length() - self.pos
  if left < 0 {
    0
  } else {
    left
  }
}

///|
pub impl Reader for ByteReader with fn position(self : ByteReader) -> Int {
  self.pos
}

///|
/// Promote the [Reader] methods to direct methods on [ByteReader].
pub extend ByteReader with Reader::{
  read_byte,
  read_bytes,
  skip,
  remaining,
  position,
}

///|
/// Read a big-endian 16-bit integer.
///
/// PNG stores every multi-byte field in network byte order (RFC 2083,
/// section 2.1), so the codecs use the `be` helpers almost exclusively.
pub fn ByteReader::read_u16be(self : ByteReader) -> UInt raise IoError {
  let hi = self.read_byte().to_uint()
  let lo = self.read_byte().to_uint()
  (hi << 8) | lo
}

///|
/// Read a big-endian 32-bit integer.
pub fn ByteReader::read_u32be(self : ByteReader) -> UInt raise IoError {
  let b0 = self.read_byte().to_uint()
  let b1 = self.read_byte().to_uint()
  let b2 = self.read_byte().to_uint()
  let b3 = self.read_byte().to_uint()
  (b0 << 24) | (b1 << 16) | (b2 << 8) | b3
}
