// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Error raised when a zlib stream cannot be decompressed.
pub suberror InflateError {
  ///
  /// The DEFLATE payload is malformed, truncated, or uses a feature MoonPNG
  /// deliberately rejects, such as a preset dictionary.
  BadData(reason~ : String)
} derive(Debug, Eq)

///|
/// Order in which the code-length alphabet is stored in a dynamic block
/// (RFC 1951 section 3.2.7).
let code_length_order : Array[Int] = [
  16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15,
]

///|
/// First length represented by each literal/length symbol from 257 upwards
/// (RFC 1951 section 3.2.5).
let length_bases : Array[Int] = [
  3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83,
  99, 115, 131, 163, 195, 227, 258,
]

///|
/// Extra bits carried by each literal/length symbol from 257 upwards.
let length_extra_bits : Array[Int] = [
  0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5,
  5, 0,
]

///|
/// First distance represented by each of the 30 distance symbols.
let distance_bases : Array[Int] = [
  1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769,
  1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577,
]

///|
/// Extra bits carried by each of the 30 distance symbols.
let distance_extra_bits : Array[Int] = [
  0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11,
  12, 12, 13, 13,
]

///|
/// A canonical Huffman decoding table (RFC 1951 section 3.2.2): `count[len]`
/// holds how many symbols use a code of that length, and `symbol` lists the
/// symbols sorted by code length, then by symbol value.
priv struct Huffman {
  count : Array[Int]
  symbol : Array[Int]
}

///|
/// Build a decoding table from `n` code lengths stored at `start` in `lengths`.
fn build_huffman(
  lengths : Array[Int],
  start : Int,
  n : Int,
) -> Huffman raise InflateError {
  let count : Array[Int] = Array::make(16, 0)
  let mut i = 0
  while i < n {
    let length = lengths[start + i]
    if length < 0 || length > 15 {
      raise BadData(reason="a Huffman code length falls outside 0..15")
    }
    count[length] = count[length] + 1
    i = i + 1
  }
  let mut spare = 1
  let mut length = 1
  while length <= 15 {
    spare = (spare << 1) - count[length]
    if spare < 0 {
      raise BadData(reason="the Huffman code set is over-subscribed")
    }
    length = length + 1
  }
  let symbol : Array[Int] = Array::make(n, 0)
  let offsets : Array[Int] = Array::make(16, 0)
  let mut running = 0
  length = 1
  while length <= 15 {
    offsets[length] = running
    running = running + count[length]
    length = length + 1
  }
  i = 0
  while i < n {
    let code_length = lengths[start + i]
    if code_length != 0 {
      symbol[offsets[code_length]] = i
      offsets[code_length] = offsets[code_length] + 1
    }
    i = i + 1
  }
  { count, symbol, }
}

///|
/// Least-significant-bit-first bit cursor over a compressed buffer, matching the
/// bit packing rules of RFC 1951 section 3.1.1.
priv struct BitReader {
  data : Bytes
  mut byte_pos : Int
  mut accumulator : Int
  mut bit_count : Int
}

///|
/// Create a cursor that starts reading at byte `start`.
fn BitReader::new(data : Bytes, start : Int) -> BitReader {
  { data, byte_pos: start, accumulator: 0, bit_count: 0, }
}

///|
/// Pull whole bytes into the accumulator until at least `n` bits are buffered.
fn BitReader::fill(self : BitReader, n : Int) -> Unit raise InflateError {
  while self.bit_count < n {
    if self.byte_pos >= self.data.length() {
      raise BadData(reason="the compressed data ended inside a symbol")
    }
    self.accumulator = self.accumulator |
      (self.data[self.byte_pos].to_int() << self.bit_count)
    self.byte_pos = self.byte_pos + 1
    self.bit_count = self.bit_count + 8
  }
}

///|
/// Consume the next bit, least-significant-first.
fn BitReader::next_bit(self : BitReader) -> Int raise InflateError {
  self.fill(1)
  let bit = self.accumulator & 1
  self.accumulator = self.accumulator >> 1
  self.bit_count = self.bit_count - 1
  bit
}

///|
/// Consume `n` bits as an unsigned integer, least-significant-first.
fn BitReader::take_bits(self : BitReader, n : Int) -> Int raise InflateError {
  if n == 0 {
    return 0
  }
  self.fill(n)
  let value = self.accumulator & ((1 << n) - 1)
  self.accumulator = self.accumulator >> n
  self.bit_count = self.bit_count - n
  value
}

///|
/// Drop the buffered bits so the next read starts on a byte boundary.
fn BitReader::align_to_byte(self : BitReader) -> Unit {
  self.accumulator = 0
  self.bit_count = 0
}

///|
/// Decode one Huffman symbol, assembling the code most-significant-bit-first
/// because DEFLATE transmits Huffman codes in that bit order. Returns `-1`
/// when the next bits do not spell any code.
fn decode_symbol(reader : BitReader, table : Huffman) -> Int raise InflateError {
  let mut code = 0
  let mut first = 0
  let mut index = 0
  let mut length = 1
  while length <= 15 {
    code = code | reader.next_bit()
    let count = table.count[length]
    if code >= first && code - first < count {
      return table.symbol[index + code - first]
    }
    index = index + count
    first = (first + count) << 1
    code = code << 1
    length = length + 1
  }
  -1
}

///|
/// The fixed literal/length code from RFC 1951 section 3.2.6.
fn fixed_literal_table() -> Huffman raise InflateError {
  let lengths : Array[Int] = Array::make(288, 0)
  let mut i = 0
  while i < 144 {
    lengths[i] = 8
    i = i + 1
  }
  while i < 256 {
    lengths[i] = 9
    i = i + 1
  }
  while i < 280 {
    lengths[i] = 7
    i = i + 1
  }
  while i < 288 {
    lengths[i] = 8
    i = i + 1
  }
  build_huffman(lengths, 0, 288)
}

///|
/// The fixed distance code from RFC 1951 section 3.2.6: 32 five-bit codes, of
/// which only the first 30 are legal.
fn fixed_distance_table() -> Huffman raise InflateError {
  build_huffman(Array::make(30, 5), 0, 30)
}

///|
/// Copy `count` copies of `value` into `lengths` starting at `index`.
fn fill_run(
  lengths : Array[Int],
  index : Int,
  count : Int,
  value : Int,
  total : Int,
) -> Int raise InflateError {
  if index + count > total {
    raise BadData(reason="a code-length repeat runs past the end of the table")
  }
  let mut i = 0
  while i < count {
    lengths[index + i] = value
    i = i + 1
  }
  index + count
}

///|
/// Read the two Huffman tables declared at the head of a dynamic block.
fn read_dynamic_tables(
  reader : BitReader,
) -> (Huffman, Huffman) raise InflateError {
  let literal_count = reader.take_bits(5) + 257
  let distance_count = reader.take_bits(5) + 1
  let order_count = reader.take_bits(4) + 4
  let order_lengths : Array[Int] = Array::make(19, 0)
  let mut i = 0
  while i < order_count {
    order_lengths[code_length_order[i]] = reader.take_bits(3)
    i = i + 1
  }
  let order_table = build_huffman(order_lengths, 0, 19)
  let total = literal_count + distance_count
  let lengths : Array[Int] = Array::make(total, 0)
  let mut index = 0
  while index < total {
    let symbol = decode_symbol(reader, order_table)
    if symbol < 0 {
      raise BadData(
        reason="the code-length table has no code for the next bits",
      )
    } else if symbol < 16 {
      lengths[index] = symbol
      index = index + 1
    } else if symbol == 16 {
      if index == 0 {
        raise BadData(reason="a repeat code appears before any code length")
      }
      index = fill_run(
        lengths,
        index,
        reader.take_bits(2) + 3,
        lengths[index - 1],
        total,
      )
    } else if symbol == 17 {
      index = fill_run(lengths, index, reader.take_bits(3) + 3, 0, total)
    } else {
      index = fill_run(lengths, index, reader.take_bits(7) + 11, 0, total)
    }
  }
  (
    build_huffman(lengths, 0, literal_count),
    build_huffman(lengths, literal_count, distance_count),
  )
}

///|
/// Copy a stored (uncompressed) block into `output`.
fn inflate_stored(
  reader : BitReader,
  output : Array[Byte],
) -> Unit raise InflateError {
  reader.align_to_byte()
  let length = reader.take_bits(16)
  let complement = reader.take_bits(16)
  if (length ^ complement) != 0xFFFF {
    raise BadData(reason="a stored block declares mismatched block lengths")
  }
  let mut i = 0
  while i < length {
    output.push(reader.take_bits(8).to_byte())
    i = i + 1
  }
}

///|
/// Expand one Huffman-coded block into `output` until the end-of-block symbol.
fn inflate_block(
  reader : BitReader,
  output : Array[Byte],
  literals : Huffman,
  distances : Huffman,
) -> Unit raise InflateError {
  let mut done = false
  while !done {
    let symbol = decode_symbol(reader, literals)
    if symbol < 0 {
      raise BadData(
        reason="the literal/length table has no code for the next bits",
      )
    } else if symbol < 256 {
      output.push(symbol.to_byte())
    } else if symbol == 256 {
      done = true
    } else {
      let code = symbol - 257
      if code >= 29 {
        raise BadData(
          reason="the literal/length table produced a reserved symbol",
        )
      }
      let length = length_bases[code] +
        reader.take_bits(length_extra_bits[code])
      let distance_code = decode_symbol(reader, distances)
      if distance_code < 0 || distance_code >= 30 {
        raise BadData(reason="the distance table has no code for the next bits")
      }
      let distance = distance_bases[distance_code] +
        reader.take_bits(distance_extra_bits[distance_code])
      if distance > output.length() {
        raise BadData(
          reason="a back reference reaches before the start of the output",
        )
      }
      let mut i = 0
      while i < length {
        output.push(output[output.length() - distance])
        i = i + 1
      }
    }
  }
}

///|
/// Expand the DEFLATE stream that starts at byte `start`.
fn inflate_deflate(data : Bytes, start : Int) -> Bytes raise InflateError {
  let reader = BitReader::new(data, start)
  let output : Array[Byte] = []
  let mut last = false
  while !last {
    last = reader.take_bits(1) != 0
    let kind = reader.take_bits(2)
    if kind == 0 {
      inflate_stored(reader, output)
    } else if kind == 1 {
      inflate_block(
        reader,
        output,
        fixed_literal_table(),
        fixed_distance_table(),
      )
    } else if kind == 2 {
      let (literals, distances) = read_dynamic_tables(reader)
      inflate_block(reader, output, literals, distances)
    } else {
      raise BadData(reason="DEFLATE reserves block type 3")
    }
  }
  Bytes::from_array(output)
}

///|
/// Decompress one complete zlib stream (RFC 1950), verifying the trailing
/// Adler-32 checksum against the decoded bytes.
pub fn inflate_zlib(data : Bytes) -> Bytes raise InflateError {
  if data.length() < 6 {
    raise BadData(
      reason="the zlib stream is too short to hold a header and a checksum",
    )
  }
  let cmf = data[0].to_int()
  let flg = data[1].to_int()
  if (cmf & 0x0F) != 8 {
    raise BadData(
      reason="the zlib stream does not use the DEFLATE compression method",
    )
  }
  if ((cmf << 8) | flg) % 31 != 0 {
    raise BadData(reason="the zlib header check bits are inconsistent")
  }
  if (flg & 0x20) != 0 {
    raise BadData(reason="MoonPNG does not support zlib preset dictionaries")
  }
  let decoded = inflate_deflate(data, 2)
  let trailer = data.length() - 4
  let stored = (data[trailer].to_uint() << 24) |
    (data[trailer + 1].to_uint() << 16) |
    (data[trailer + 2].to_uint() << 8) |
    data[trailer + 3].to_uint()
  if adler32(decoded) != stored {
    raise BadData(
      reason="the zlib Adler-32 checksum does not match the decoded data",
    )
  }
  decoded
}
