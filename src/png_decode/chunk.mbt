// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// A PNG chunk as framed by RFC 2083 section 3.2: a four-byte type, a payload
/// of the length declared ahead of it, and a trailing CRC-32 computed over the
/// type and payload fields.
pub(all) struct Chunk {
  ctype : String
  data : Bytes
} derive(Debug, Eq)

///|
/// Render a four-byte chunk type as its ASCII spelling.
fn chunk_type_name(bytes : Bytes) -> String {
  let chars : Array[Char] = []
  let mut i = 0
  while i < bytes.length() {
    chars.push(bytes[i].to_char())
    i = i + 1
  }
  String::from_array(chars)
}

///|
/// Read `len` bytes, turning a bounds failure into [PngDecodeError].
fn take(
  reader : @io_abstraction.ByteReader,
  len : Int,
) -> Bytes raise PngDecodeError {
  let outcome : Result[Bytes, Unit] = Ok(reader.read_bytes(len)) catch {
    @io_abstraction.IoError::OutOfBounds(_) => Err(())
  }
  match outcome {
    Ok(bytes) => bytes
    Err(_) =>
      raise BadChunk(reason="a chunk field runs past the end of the datastream")
  }
}

///|
/// Skip `len` bytes, turning a bounds failure into [PngDecodeError].
fn skip(
  reader : @io_abstraction.ByteReader,
  len : Int,
) -> Unit raise PngDecodeError {
  let outcome : Result[Unit, Unit] = Ok(reader.skip(len)) catch {
    @io_abstraction.IoError::OutOfBounds(_) => Err(())
  }
  match outcome {
    Ok(_) => ()
    Err(_) =>
      raise BadChunk(reason="the datastream ended before its first chunk")
  }
}

///|
/// Read a big-endian 32-bit field, turning a bounds failure into
/// [PngDecodeError].
fn take_u32(reader : @io_abstraction.ByteReader) -> UInt raise PngDecodeError {
  let outcome : Result[UInt, Unit] = Ok(reader.read_u32be()) catch {
    @io_abstraction.IoError::OutOfBounds(_) => Err(())
  }
  match outcome {
    Ok(word) => word
    Err(_) =>
      raise BadChunk(reason="a chunk field runs past the end of the datastream")
  }
}

///|
/// Read the next chunk and verify its CRC-32.
///
/// A chunk is rejected when its declared length does not fit in the remaining
/// datastream or when the stored checksum disagrees with the one computed over
/// the type and payload fields.
pub fn Chunk::read(
  reader : @io_abstraction.ByteReader,
) -> Chunk raise PngDecodeError {
  let length = take_u32(reader).reinterpret_as_int()
  if length < 0 {
    raise BadChunk(
      reason="a chunk declares a length outside the addressable range",
    )
  }
  let ctype_bytes = take(reader, 4)
  let payload = take(reader, length)
  let stored = take_u32(reader)
  let sink = @io_abstraction.ByteWriter::new()
  sink.write_bytes(ctype_bytes)
  sink.write_bytes(payload)
  let computed = @zlib.crc32(sink.to_bytes())
  if computed != stored {
    raise BadChunk(
      reason="CRC-32 mismatch in \{chunk_type_name(ctype_bytes)} chunk",
    )
  }
  { ctype: chunk_type_name(ctype_bytes), data: payload, }
}
