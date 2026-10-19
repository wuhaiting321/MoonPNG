// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Wrap `data` in a zlib stream (RFC 1950) whose DEFLATE payload is a sequence
/// of stored blocks (RFC 1951 section 3.2.4).
///
/// Stored blocks keep the encoder free of a windowed match finder while still
/// producing a stream that any compliant inflater accepts, so the format itself
/// stays the only thing the decoder and encoder have to agree on.
fn zlib_compress(data : Bytes) -> Bytes {
  let out : Array[Byte] = [b'\x78', b'\x01']
  let mut offset = 0
  while offset < data.length() {
    let remaining = data.length() - offset
    let len = if remaining > 65535 { 65535 } else { remaining }
    let last = offset + len >= data.length()
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
  let adler = @zlib.adler32(data)
  out.push(((adler >> 24) & 0xFF).to_byte())
  out.push(((adler >> 16) & 0xFF).to_byte())
  out.push(((adler >> 8) & 0xFF).to_byte())
  out.push((adler & 0xFF).to_byte())
  Bytes::from_array(out)
}
