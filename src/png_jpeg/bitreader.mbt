// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Bit reader for entropy-coded scan data (ITU T.81, section B.2.3).
///
/// JPEG packs Huffman codes most significant bit first, the opposite of the
/// DEFLATE convention used elsewhere in this module, and escapes a literal
/// 0xFF inside a scan as 0xFF 0x00. Any other byte after 0xFF is a marker, so
/// the reader stops with its cursor on that 0xFF instead of consuming it.
priv struct BitReader {
  data : Bytes
  mut pos : Int
  mut buffer : Int
  mut count : Int
}

///|
fn BitReader::new(data : Bytes, pos : Int) -> BitReader {
  { data, pos, buffer: 0, count: 0, }
}

///|
/// Refill the accumulator one byte at a time, stopping at the marker that ends
/// the scan. At most 24 bits are buffered so a shift cannot overflow.
fn BitReader::fill(self : BitReader) -> Unit {
  while self.count <= 24 && self.pos < self.data.length() {
    let byte = self.data[self.pos].to_int()
    if byte == 0xFF {
      if self.pos + 1 >= self.data.length() {
        return
      }
      if self.data[self.pos + 1].to_int() != 0x00 {
        return
      }
      self.buffer = (self.buffer << 8) | 0xFF
      self.count = self.count + 8
      self.pos = self.pos + 2
    } else {
      self.buffer = (self.buffer << 8) | byte
      self.count = self.count + 8
      self.pos = self.pos + 1
    }
  }
}

///|
fn BitReader::read_bit(self : BitReader) -> Int raise JpegDecodeError {
  if self.count == 0 {
    self.fill()
  }
  if self.count == 0 {
    raise BadData(reason="the scan data ended in the middle of a code")
  }
  self.count = self.count - 1
  (self.buffer >> self.count) & 1
}

///|
fn BitReader::read_bits(
  self : BitReader,
  count : Int,
) -> Int raise JpegDecodeError {
  let mut value = 0
  let mut i = 0
  while i < count {
    value = (value << 1) | self.read_bit()
    i = i + 1
  }
  value
}

///|
/// Discard the bits still buffered and consume the restart marker that a
/// restart interval ends with, leaving the reader ready for the next MCU.
fn BitReader::restart(self : BitReader) -> Unit raise JpegDecodeError {
  self.buffer = 0
  self.count = 0
  if self.pos + 1 >= self.data.length() {
    raise BadData(reason="a restart interval ended before its marker")
  }
  if self.data[self.pos].to_int() != 0xFF {
    raise BadData(reason="a restart interval ended without a marker")
  }
  let code = self.data[self.pos + 1].to_int()
  if code < 0xD0 || code > 0xD7 {
    raise BadData(reason="a restart interval ended with the marker 0x\{code}")
  }
  self.pos = self.pos + 2
}
