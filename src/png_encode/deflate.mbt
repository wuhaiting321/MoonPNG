// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Maximum match length expressible by the DEFLATE length codes, and the
/// shortest match worth spending a length/distance pair on (RFC 1951 section
/// 3.2.5).
const MAX_MATCH : Int = 258

///|
const MIN_MATCH : Int = 3

///|
/// How far back a match may reach, in bytes.
const WINDOW : Int = 32768

///|
/// Upper bound on the hash-chain walk per position. Bounds the time spent on
/// incompressible data, where every candidate fails to improve on a literal.
const MAX_CHAIN : Int = 64

///|
/// Number of buckets for three-byte prefixes; also the mask width used by
/// [hash_prefix].
const HASH_SIZE : Int = 32768

///|
/// Base match length of each length code 257..285.
let length_base : Array[Int] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83,
  99, 115, 131, 163, 195, 227, 258,
]

///|
/// Extra bits refining each length code 257..285.
let length_extra : Array[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5,
  5, 0,
]

///|
/// Base distance of each distance code 0..29.
let distance_base : Array[Int] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
  1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
]

///|
/// Extra bits refining each distance code 0..29.
let distance_extra : Array[Int] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
  12, 12, 13, 13,
]

///|
/// Bit accumulator for the DEFLATE bitstream, which packs fields least
/// significant bit first (RFC 1951 section 3.1.1).
priv struct BitWriter {
  bytes : Array[Byte]
  mut current : Int
  mut filled : Int
}

///|
fn BitWriter::new() -> BitWriter {
  { bytes: [], current: 0, filled: 0, }
}

///|
/// Append the low `count` bits of `value`, least significant bit first. Used
/// for the block header and for the extra bits that refine a length or
/// distance code.
fn BitWriter::write_bits(self : BitWriter, value : Int, count : Int) -> Unit {
  let mut i = 0
  while i < count {
    self.current = self.current | (((value >> i) & 1) << self.filled)
    self.filled = self.filled + 1
    if self.filled == 8 {
      self.bytes.push(self.current.to_byte())
      self.current = 0
      self.filled = 0
    }
    i = i + 1
  }
}

///|
/// Append a Huffman code, which is the one kind of field DEFLATE packs most
/// significant bit first, so its bits are emitted in reverse order.
fn BitWriter::write_code(self : BitWriter, code : Int, length : Int) -> Unit {
  let mut i = length - 1
  while i >= 0 {
    self.write_bits((code >> i) & 1, 1)
    i = i - 1
  }
}

///|
/// Pad the trailing partial byte with zeros and hand back the finished stream.
fn BitWriter::finish(self : BitWriter) -> Bytes {
  if self.filled > 0 {
    self.bytes.push(self.current.to_byte())
    self.current = 0
    self.filled = 0
  }
  Bytes::from_array(self.bytes)
}

///|
/// The fixed literal/length code of RFC 1951 section 3.2.6, returned as the
/// code value and the number of bits it occupies.
fn fixed_literal_code(symbol : Int) -> (Int, Int) {
  if symbol <= 143 {
    (0x30 + symbol, 8)
  } else if symbol <= 255 {
    (0x190 + symbol - 144, 9)
  } else if symbol <= 279 {
    (symbol - 256, 7)
  } else {
    (0xC0 + symbol - 280, 8)
  }
}

///|
/// The length code 257..285 for `length`, with its extra-bit count and value.
fn length_symbol(length : Int) -> (Int, Int, Int) {
  let mut index = length_base.length() - 1
  while index > 0 && length_base[index] > length {
    index = index - 1
  }
  (257 + index, length_extra[index], length - length_base[index])
}

///|
/// The distance code 0..29 for `distance`, with its extra-bit count and value.
fn distance_symbol(distance : Int) -> (Int, Int, Int) {
  let mut index = distance_base.length() - 1
  while index > 0 && distance_base[index] > distance {
    index = index - 1
  }
  (index, distance_extra[index], distance - distance_base[index])
}

///|
/// Hash the three bytes at `pos` into a bucket index, so that equal prefixes
/// can be chained together for the match search.
fn hash_prefix(data : Bytes, pos : Int) -> Int {
  (
    (data[pos].to_int() << 10) ^
    (data[pos + 1].to_int() << 5) ^
    data[pos + 2].to_int()
  ) &
  (HASH_SIZE - 1)
}

///|
/// Register the three-byte prefix at `pos` as the newest entry of its bucket,
/// linking it to the previous occupant.
fn insert_chain(
  data : Bytes,
  pos : Int,
  head : Array[Int],
  prev : Array[Int],
  size : Int,
) -> Unit {
  if pos + MIN_MATCH <= size {
    let bucket = hash_prefix(data, pos)
    prev[pos] = head[bucket]
    head[bucket] = pos
  }
}

///|
/// Find the longest match for the bytes at `pos` by walking its bucket chain,
/// reporting the match length and the distance back to it. Registers `pos`
/// itself while it is there, so a later position can match against it.
fn find_match(
  data : Bytes,
  pos : Int,
  head : Array[Int],
  prev : Array[Int],
  size : Int,
) -> (Int, Int) {
  let mut best_length = 0
  let mut best_distance = 0
  if pos + MIN_MATCH <= size {
    let bucket = hash_prefix(data, pos)
    let mut candidate = head[bucket]
    prev[pos] = candidate
    head[bucket] = pos
    let floor = if pos > WINDOW { pos - WINDOW } else { 0 }
    let mut steps = 0
    while candidate >= floor && steps < MAX_CHAIN {
      let mut length = 0
      while length < MAX_MATCH &&
            pos + length < size &&
            data[candidate + length].to_int() == data[pos + length].to_int() {
        length = length + 1
      }
      if length > best_length {
        best_length = length
        best_distance = pos - candidate
      }
      if best_length >= MAX_MATCH {
        break
      }
      candidate = prev[candidate]
      steps = steps + 1
    }
  }
  (best_length, best_distance)
}

///|
/// Compress `data` into the body of a DEFLATE stream as one final block that
/// mixes LZ77 matches with the fixed Huffman code tables.
///
/// Fixed tables cost a few bits more per literal than an optimal dynamic code,
/// but they need no transmission, which pays off on the small payloads a single
/// image produces.
fn compressed_body(data : Bytes) -> Bytes {
  let writer = BitWriter::new()
  writer.write_bits(1, 1)
  writer.write_bits(1, 2)
  let size = data.length()
  let head : Array[Int] = Array::make(HASH_SIZE, -1)
  let prev : Array[Int] = Array::make(size, -1)
  let mut pos = 0
  while pos < size {
    let (match_length, match_distance) = find_match(data, pos, head, prev, size)
    if match_length >= MIN_MATCH {
      let (symbol, extra_bits, extra) = length_symbol(match_length)
      let (code, code_length) = fixed_literal_code(symbol)
      writer.write_code(code, code_length)
      writer.write_bits(extra, extra_bits)
      let (distance, distance_bits, distance_extra) = distance_symbol(
        match_distance,
      )
      writer.write_code(distance, 5)
      writer.write_bits(distance_extra, distance_bits)
      let mut step = 1
      while step < match_length {
        insert_chain(data, pos + step, head, prev, size)
        step = step + 1
      }
      pos = pos + match_length
    } else {
      let (code, code_length) = fixed_literal_code(data[pos].to_int())
      writer.write_code(code, code_length)
      pos = pos + 1
    }
  }
  let (end_code, end_length) = fixed_literal_code(256)
  writer.write_code(end_code, end_length)
  writer.finish()
}

///|
/// Emit `data` as a chain of stored blocks (RFC 1951 section 3.2.4): the
/// fallback for data that a Huffman block could not shrink.
fn stored_body(data : Bytes) -> Bytes {
  let out : Array[Byte] = []
  let size = data.length()
  if size == 0 {
    out.push(b'\x01')
    out.push(b'\x00')
    out.push(b'\x00')
    out.push(b'\xff')
    out.push(b'\xff')
    return Bytes::from_array(out)
  }
  let mut offset = 0
  while offset < size {
    let remaining = size - offset
    let len = if remaining > 65535 { 65535 } else { remaining }
    let last = offset + len >= size
    out.push(if last { b'\x01' } else { b'\x00' })
    out.push((len & 0xFF).to_byte())
    out.push(((len >> 8) & 0xFF).to_byte())
    let nlen = len ^ 0xFFFF
    out.push((nlen & 0xFF).to_byte())
    out.push(((nlen >> 8) & 0xFF).to_byte())
    let mut i = offset
    while i < offset + len {
      out.push(data[i])
      i = i + 1
    }
    offset = offset + len
  }
  Bytes::from_array(out)
}

///|
/// Wrap `data` in a zlib stream (RFC 1950): the two-byte header, the smallest
/// DEFLATE body this encoder can produce, and a trailing Adler-32.
///
/// The body is whichever of an LZ77 plus fixed-Huffman block and a stored block
/// occupies fewer bytes, so compression can never inflate a payload that it
/// happens to fit badly.
fn zlib_compress(data : Bytes) -> Bytes {
  let compressed = compressed_body(data)
  let stored = stored_body(data)
  let body = if compressed.length() <= stored.length() {
    compressed
  } else {
    stored
  }
  let out : Array[Byte] = [b'\x78', b'\x01']
  let mut i = 0
  while i < body.length() {
    out.push(body[i])
    i = i + 1
  }
  let adler = @zlib.adler32(data)
  out.push(((adler >> 24) & 0xFF).to_byte())
  out.push(((adler >> 16) & 0xFF).to_byte())
  out.push(((adler >> 8) & 0xFF).to_byte())
  out.push((adler & 0xFF).to_byte())
  Bytes::from_array(out)
}
