// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// A canonical Huffman table for JPEG entropy coding (ITU T.81, section C.2).
///
/// `counts[len]` holds how many symbols carry a code of that length, and
/// `symbols` lists the symbols in order of increasing code length, which is the
/// order the two arrays of a DHT segment are transmitted in.
priv struct HuffmanTable {
  counts : Array[Int]
  symbols : Array[Int]
}

///|
fn HuffmanTable::empty() -> HuffmanTable {
  { counts: Array::make(17, 0), symbols: [], }
}

///|
fn HuffmanTable::build(
  counts : Array[Int],
  symbols : Array[Int],
) -> HuffmanTable {
  let copy : Array[Int] = Array::make(17, 0)
  let mut length = 1
  while length <= 16 {
    copy[length] = counts[length]
    length = length + 1
  }
  { counts: copy, symbols, }
}

///|
/// Decode one symbol by walking the canonical code space one bit at a time: at
/// each length, the codes in that length form a contiguous range that starts at
/// `first`, so the offset into `symbols` follows from the code read so far.
fn HuffmanTable::decode(
  self : HuffmanTable,
  reader : BitReader,
) -> Int raise JpegDecodeError {
  let mut code = 0
  let mut first = 0
  let mut index = 0
  let mut length = 1
  while length <= 16 {
    code = (code << 1) | reader.read_bit()
    let count = self.counts[length]
    if code - first < count {
      let at = index + code - first
      if at < 0 || at >= self.symbols.length() {
        raise BadData(reason="a Huffman code points outside its symbol table")
      }
      return self.symbols[at]
    }
    index = index + count
    first = (first + count) << 1
    length = length + 1
  }
  raise BadData(reason="a Huffman code exceeds the sixteen-bit limit")
}

///|
/// Sign-extend the `bits` read for a coefficient, per the "receive" procedure
/// of ITU T.81 section F.2.2.1: the leading bit says whether the value is
/// negative, and negative values are stored in one's complement offset form.
fn receive_extend(value : Int, bits : Int) -> Int {
  if bits == 0 {
    0
  } else if value < 1 << (bits - 1) {
    value - (1 << bits) + 1
  } else {
    value
  }
}
