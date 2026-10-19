// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Integration tests exercise the public API the way a downstream consumer
/// would, from outside the library packages.

///|
test "byte reader and writer round trip" {
  let writer = @io_abstraction.ByteWriter::new()
  writer.write_u32be(0x12345678U)
  writer.write_u16be(0xABCDU)
  assert_eq(writer.length(), 6)

  let bytes = writer.to_bytes()
  assert_eq(bytes.length(), 6)

  let reader = @io_abstraction.ByteReader::new(bytes)
  assert_eq(reader.read_u32be(), 0x12345678U)
  assert_eq(reader.read_u16be(), 0xABCDU)
  assert_eq(reader.remaining(), 0)
}

///|
test "reader reports bounds errors" {
  let reader = @io_abstraction.ByteReader::new(b"\x01\x02")
  let caught = try {
    let _value = reader.read_u32be()
    false
  } catch {
    @io_abstraction.IoError::OutOfBounds(_) => true
  }
  assert_true(caught)
}

///|
test "image reports derived geometry" {
  let pixels : Bytes = Array::make(2 * 3 * 3, b'\x00') |> Bytes::from_array
  let image = @image.Image::new(2, 3, 8, @image.ColorType::Truecolor, pixels)
  assert_eq(image.channels(), 3)
  assert_eq(image.bits_per_pixel(), 24)
  assert_eq(image.row_bytes(), 6)
  assert_eq(image.pixel_bytes(), 18)
  assert_eq(image.sample_count(), 18)
  assert_false(image.is_indexed())
  assert_false(image.has_transparency())
}

///|
test "color type codes round trip" {
  for code in [0, 2, 3, 4, 6] {
    let color = @image.ColorType::from_code(code)
    assert_true(color is Some(_))
    match color {
      Some(value) => assert_eq(value.code(), code)
      None => assert_true(false)
    }
  }
  assert_true(@image.ColorType::from_code(1) is None)
  assert_true(@image.ColorType::TruecolorAlpha.is_alpha())
}

///|
test "checksums match the standard vectors" {
  let data : Bytes = b"123456789"
  assert_eq(@zlib.crc32(data), 0xCBF43926U)
  assert_eq(@zlib.adler32(data), 0x091E01DEU)
}

///|
test "png facade exposes its version" {
  assert_eq(@png.version(), "0.1.0")
}

///|
test "png signature detection" {
  assert_true(@png_decode.is_png(@png_decode.signature()))
  assert_false(@png_decode.is_png(b"GIF89a"))
  assert_false(@png_decode.is_png(b""))
}

///|
/// The tests below drive the library only through the public `@png` facade and
/// hold what it produces to the two RFCs it claims to implement. The per-package
/// suites check each codec against a known answer; these check that the two
/// halves agree with the specification and with each other on whole datastreams.

///|
/// Append every byte of `data` to `out`.
fn append_bytes(out : Array[Byte], data : Bytes) -> Unit {
  let mut i = 0
  while i < data.length() {
    out.push(data[i])
    i = i + 1
  }
}

///|
/// Take a datastream apart into its `(type, payload)` chunks.
///
/// `Chunk::read` verifies each chunk's framing and CRC-32 while it walks, so any
/// stream that fails to split here is malformed by definition. The type travels
/// back as the four raw bytes the datastream spells them with, taken straight
/// from the buffer so the builders below can write them again.
fn split_chunks(data : Bytes) -> Array[(Bytes, Bytes)] raise {
  assert_true(@png_decode.is_png(data))
  let reader = @io_abstraction.ByteReader::new(data)
  reader.skip(8)
  let out : Array[(Bytes, Bytes)] = []
  let mut ended = false
  while !ended {
    let start = reader.position()
    let chunk = @png_decode.Chunk::read(reader)
    let kind : Array[Byte] = []
    let mut i = start + 4
    while i < start + 8 {
      kind.push(data[i])
      i = i + 1
    }
    out.push((Bytes::from_array(kind), chunk.data))
    if chunk.ctype == "IEND" {
      ended = true
    }
  }
  assert_eq(reader.remaining(), 0)
  out
}

///|
/// Assemble a datastream from an explicit chunk list, computing each trailing
/// CRC-32, so a test can build the unusual and malformed streams the encoder
/// would never emit.
fn build_datastream(chunks : Array[(Bytes, Bytes)]) -> Bytes {
  let out : Array[Byte] = []
  append_bytes(out, @png_decode.signature())
  let mut i = 0
  while i < chunks.length() {
    let (ctype, data) = chunks[i]
    let body = @io_abstraction.ByteWriter::new()
    body.write_bytes(ctype)
    body.write_bytes(data)
    let framed = @io_abstraction.ByteWriter::new()
    framed.write_u32be(data.length().reinterpret_as_uint())
    framed.write_bytes(ctype)
    framed.write_bytes(data)
    append_bytes(out, framed.to_bytes())
    let checksum = @io_abstraction.ByteWriter::new()
    checksum.write_u32be(@zlib.crc32(body.to_bytes()))
    append_bytes(out, checksum.to_bytes())
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
/// The payload of the first chunk of type `name`, or the empty payload when the
/// datastream does not carry that chunk.
fn chunk_payload(chunks : Array[(Bytes, Bytes)], name : Bytes) -> Bytes {
  let mut i = 0
  while i < chunks.length() {
    let (ctype, data) = chunks[i]
    if ctype == name {
      return data
    }
    i = i + 1
  }
  b""
}

///|
/// Swap every `IDAT` payload for `replacement`, keeping the rest of the
/// datastream as it was.
fn with_idat(
  chunks : Array[(Bytes, Bytes)],
  replacement : Bytes,
) -> Array[(Bytes, Bytes)] {
  let out : Array[(Bytes, Bytes)] = []
  let mut i = 0
  while i < chunks.length() {
    let (ctype, data) = chunks[i]
    if ctype == b"IDAT" {
      out.push((ctype, replacement))
    } else {
      out.push((ctype, data))
    }
    i = i + 1
  }
  out
}

///|
/// Swap the `IHDR` payload for `payload`, so a test can declare a header the
/// specification forbids while the rest of the datastream stays valid.
fn with_ihdr(
  chunks : Array[(Bytes, Bytes)],
  payload : Bytes,
) -> Array[(Bytes, Bytes)] {
  let out : Array[(Bytes, Bytes)] = []
  let mut i = 0
  while i < chunks.length() {
    let (ctype, data) = chunks[i]
    if ctype == b"IHDR" {
      out.push((ctype, payload))
    } else {
      out.push((ctype, data))
    }
    i = i + 1
  }
  out
}

///|
/// Serialise a 13-byte IHDR payload with every field under the caller's control.
fn ihdr_payload_of(
  width : Int,
  height : Int,
  depth : Int,
  color : Int,
  compression : Int,
  filter_method : Int,
  interlace : Int,
) -> Bytes {
  let payload = @io_abstraction.ByteWriter::new()
  payload.write_u32be(width.reinterpret_as_uint())
  payload.write_u32be(height.reinterpret_as_uint())
  payload.write_byte(depth.to_byte())
  payload.write_byte(color.to_byte())
  payload.write_byte(compression.to_byte())
  payload.write_byte(filter_method.to_byte())
  payload.write_byte(interlace.to_byte())
  payload.to_bytes()
}

///|
/// Collect the chunks of `chunks` whose type is not `skip`.
fn without_chunk(
  chunks : Array[(Bytes, Bytes)],
  skip : Bytes,
) -> Array[(Bytes, Bytes)] {
  let out : Array[(Bytes, Bytes)] = []
  let mut i = 0
  while i < chunks.length() {
    if chunks[i].0 != skip {
      out.push(chunks[i])
    }
    i = i + 1
  }
  out
}

///|
/// Assert that decoding `bytes` fails the way a malformed datastream should.
fn assert_rejected(bytes : Bytes) -> Unit raise {
  let caught = try {
    let _ = @png.decode(bytes)
    false
  } catch {
    @png_decode.PngDecodeError::BadChunk(_) => true
    _ => false
  }
  assert_true(caught)
}

///|
/// Hold an encoder output to the structure RFC 2083 and RFC 1950 prescribe: the
/// chunk order, the IHDR fields, the zlib framing of the IDAT payload, and the
/// Adler-32 the stream claims. Nothing here consults the decoder, so a mistake
/// the two codecs happen to share cannot hide behind a successful round trip.
fn assert_datastream_shape(bytes : Bytes, image : @image.Image) -> Unit raise {
  let chunks = split_chunks(bytes)
  let expected : Array[Bytes] = []
  expected.push(b"IHDR")
  if image.is_indexed() {
    expected.push(b"PLTE")
  }
  if image.transparency.length() > 0 {
    expected.push(b"tRNS")
  }
  expected.push(b"IDAT")
  expected.push(b"IEND")
  assert_eq(chunks.length(), expected.length())
  let mut i = 0
  while i < expected.length() {
    assert_eq(chunks[i].0, expected[i])
    i = i + 1
  }
  assert_eq(chunks[chunks.length() - 1].1.length(), 0)
  let ihdr = @io_abstraction.ByteReader::new(chunk_payload(chunks, b"IHDR"))
  assert_eq(ihdr.read_u32be(), image.width.reinterpret_as_uint())
  assert_eq(ihdr.read_u32be(), image.height.reinterpret_as_uint())
  assert_eq(ihdr.read_byte().to_int(), image.bit_depth)
  assert_eq(ihdr.read_byte().to_int(), image.color_type.code())
  assert_eq(ihdr.read_byte(), b'\x00')
  assert_eq(ihdr.read_byte(), b'\x00')
  assert_eq(ihdr.read_byte(), b'\x00')
  assert_eq(ihdr.remaining(), 0)
  if image.is_indexed() {
    assert_eq(chunk_payload(chunks, b"PLTE"), image.palette)
  }
  if image.transparency.length() > 0 {
    assert_eq(chunk_payload(chunks, b"tRNS"), image.transparency)
  }
  let idat = chunk_payload(chunks, b"IDAT")
  assert_true(idat.length() > 6)
  assert_eq(idat[0], b'\x78')
  assert_eq(idat[1], b'\x01')
  assert_eq(((idat[0].to_int() << 8) | idat[1].to_int()) % 31, 0)
  let inflated = @zlib.inflate_zlib(idat)
  assert_eq(inflated.length(), image.height * (image.row_bytes() + 1))
  let last = idat.length() - 4
  let claimed : UInt = (idat[last].to_uint() << 24) |
    (idat[last + 1].to_uint() << 16) |
    (idat[last + 2].to_uint() << 8) |
    idat[last + 3].to_uint()
  assert_eq(claimed, @zlib.adler32(inflated))
}

///|
test "the encoder emits a spec shaped datastream for every color layout" {
  let corpus : Array[Bytes] = [
    basn0g01, basn0g04, basn0g16, basn3p01, basn2c16, basn6a08, rgb24, rgba32,
  ]
  let mut i = 0
  while i < corpus.length() {
    let image = @png.decode(corpus[i])
    assert_datastream_shape(@png.encode(image), image)
    i = i + 1
  }
  let indexed = image_of(6, 2, 8, @image.ColorType::Indexed, [
      0, 1, 2, 0, 1, 2, 2, 1, 0, 1, 2, 0,
    ])
    .with_palette(b"\xff\x00\x00\x00\xff\x00\x00\x00\xff")
    .with_transparency(b"\x00\x40\x80")
  assert_datastream_shape(@png.encode(indexed), indexed)
}

///|
test "every embedded datastream survives decode and re-encode" {
  let corpus : Array[Bytes] = [
    basn0g01, basi0g01, basn0g04, basi0g04, basn0g16, basi0g16, basn3p01, basi3p01,
    basn2c16, basi2c16, basn6a08, basi6a08, rgb24, rgba32,
  ]
  let mut i = 0
  while i < corpus.length() {
    let original = @png.decode(corpus[i])
    let restored = @png.decode(@png.encode(original))
    assert_eq(restored.width, original.width)
    assert_eq(restored.height, original.height)
    assert_eq(restored.bit_depth, original.bit_depth)
    assert_eq(restored.color_type, original.color_type)
    assert_eq(restored.pixels, original.pixels)
    assert_eq(restored.palette, original.palette)
    assert_eq(restored.transparency, original.transparency)
    i = i + 1
  }
}

///|
test "re-encoding its own output is a fixed point" {
  let corpus : Array[Bytes] = [basn0g01, basn2c16, basn6a08, rgb24, rgba32]
  let mut i = 0
  while i < corpus.length() {
    let first = @png.encode(@png.decode(corpus[i]))
    let second = @png.encode(@png.decode(first))
    assert_eq(second, first)
    i = i + 1
  }
}

///|
test "interlaced and progressive datastreams encode to identical bytes" {
  let pairs : Array[(Bytes, Bytes)] = [
    (basn0g01, basi0g01),
    (basn0g04, basi0g04),
    (basn0g16, basi0g16),
    (basn3p01, basi3p01),
    (basn2c16, basi2c16),
    (basn6a08, basi6a08),
  ]
  let mut i = 0
  while i < pairs.length() {
    let progressive = @png.encode(@png.decode(pairs[i].0))
    let interlaced = @png.encode(@png.decode(pairs[i].1))
    assert_eq(interlaced, progressive)
    i = i + 1
  }
}

///|
test "degenerate geometries round trip" {
  let cases : Array[@image.Image] = [
    image_of(1, 1, 8, @image.ColorType::Truecolor, pattern(3, 8)),
    image_of(1, 200, 8, @image.ColorType::Grayscale, pattern(200, 8)),
    image_of(200, 1, 8, @image.ColorType::Grayscale, pattern(200, 8)),
    image_of(1, 1, 16, @image.ColorType::TruecolorAlpha, pattern(4, 16)),
  ]
  let mut i = 0
  while i < cases.length() {
    let encoded = @png.encode(cases[i])
    assert_datastream_shape(encoded, cases[i])
    assert_eq(@png.decode(encoded).pixels, cases[i].pixels)
    i = i + 1
  }
}

///|
test "a payload split across several IDAT chunks decodes the same" {
  let bytes = @png.encode(@png.decode(basn2c16))
  let chunks = split_chunks(bytes)
  let idat = chunk_payload(chunks, b"IDAT")
  assert_true(idat.length() >= 4)
  let half = idat.length() / 2
  let head : Array[Byte] = []
  let tail : Array[Byte] = []
  let mut at = 0
  while at < idat.length() {
    if at < half {
      head.push(idat[at])
    } else {
      tail.push(idat[at])
    }
    at = at + 1
  }
  let rebuilt : Array[(Bytes, Bytes)] = []
  let mut i = 0
  while i < chunks.length() {
    let (ctype, data) = chunks[i]
    if ctype == b"IDAT" {
      rebuilt.push((ctype, Bytes::from_array(head)))
      rebuilt.push((ctype, Bytes::from_array(tail)))
    } else {
      rebuilt.push((ctype, data))
    }
    i = i + 1
  }
  let restored = @png.decode(build_datastream(rebuilt))
  assert_eq(restored.pixels, @png.decode(bytes).pixels)
}

///|
test "an unknown ancillary chunk is skipped" {
  let bytes = @png.encode(@png.decode(basn6a08))
  let chunks = split_chunks(bytes)
  let rebuilt : Array[(Bytes, Bytes)] = []
  let mut i = 0
  while i < chunks.length() {
    let (ctype, data) = chunks[i]
    rebuilt.push((ctype, data))
    if ctype == b"IHDR" {
      rebuilt.push((b"tEXt", b"Comment\x00a chunk the decoder must skip"))
    }
    i = i + 1
  }
  let restored = @png.decode(build_datastream(rebuilt))
  assert_eq(restored.pixels, @png.decode(bytes).pixels)
}

///|
test "a corrupted Adler-32 trailer is rejected" {
  let bytes = @png.encode(@png.decode(basn2c16))
  let chunks = split_chunks(bytes)
  let tampered = chunk_payload(chunks, b"IDAT").to_array()
  let last = tampered.length() - 1
  tampered[last] = (tampered[last].to_int() ^ 0x01).to_byte()
  assert_rejected(
    with_idat(chunks, Bytes::from_array(tampered)) |> build_datastream,
  )
}

///|
test "a datastream that stops inside a chunk is rejected" {
  let full = @png.encode(@png.decode(basn2c16)).to_array()
  // Losing the tail of a payload leaves the chunk checksum disagreeing...
  let torn_payload : Array[Byte] = []
  let mut i = 0
  while i < full.length() - 20 {
    torn_payload.push(full[i])
    i = i + 1
  }
  assert_rejected(Bytes::from_array(torn_payload))
  // ...and losing the tail of a field leaves the chunk unreadable.
  let torn_field : Array[Byte] = []
  i = 0
  while i < full.length() - 3 {
    torn_field.push(full[i])
    i = i + 1
  }
  assert_rejected(Bytes::from_array(torn_field))
}

///|
test "a datastream that breaks the chunk contract is rejected" {
  let gray = split_chunks(@png.encode(@png.decode(basn0g16)))
  let indexed = split_chunks(@png.encode(@png.decode(basn3p01)))
  // IHDR has to open the datastream.
  assert_rejected(
    build_datastream([(b"IDAT", chunk_payload(gray, b"IDAT")), (b"IEND", b"")]),
  )
  // IHDR has to carry exactly the thirteen bytes of its payload.
  assert_rejected(
    build_datastream(with_ihdr(gray, b"\x00\x00\x00\x20\x00\x00\x00\x20")),
  )
  // The datastream has to end with IEND.
  assert_rejected(build_datastream(without_chunk(gray, b"IEND")))
  // It also has to carry at least one IDAT.
  assert_rejected(build_datastream(without_chunk(gray, b"IDAT")))
  // An indexed image has to declare the palette its samples index into.
  assert_rejected(build_datastream(without_chunk(indexed, b"PLTE")))
  // The header has to describe the samples the IDAT actually carries.
  assert_rejected(
    build_datastream(with_ihdr(gray, ihdr_payload_of(64, 64, 16, 0, 0, 0, 0))),
  )
}

///|
test "a header the spec forbids is rejected" {
  let base = @png.encode(@png.decode(basn2c16))
  let chunks = split_chunks(base)
  // width, height, depth, color type, compression, filter, interlace
  let rejected : Array[(Int, Int, Int, Int, Int, Int, Int)] = [
    (32, 32, 16, 1, 0, 0, 0),
    (32, 32, 3, 0, 0, 0, 0),
    (32, 32, 16, 2, 1, 0, 0),
    (32, 32, 16, 2, 0, 1, 0),
    (32, 32, 16, 2, 0, 0, 2),
    (0, 32, 16, 2, 0, 0, 0),
  ]
  let mut i = 0
  while i < rejected.length() {
    let (width, height, depth, color, compression, filter_method, interlace) = rejected[i]
    let payload = ihdr_payload_of(
      width, height, depth, color, compression, filter_method, interlace,
    )
    let caught = try {
      let _ = @png.decode(build_datastream(with_ihdr(chunks, payload)))
      false
    } catch {
      @png_decode.PngDecodeError::BadChunk(_) => true
      _ => false
    }
    assert_true(caught)
    i = i + 1
  }
}
