// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Compute the Adler-32 checksum of `bytes` (RFC 1950, section 9).
///
/// The zlib wrapper that surrounds every PNG `IDAT` stream carries this
/// checksum, so the decoder uses it to reject corrupted compressed data.
pub fn adler32(bytes : Bytes) -> UInt {
  let modulus = 65521U
  let mut a : UInt = 1U
  let mut b : UInt = 0U
  for i = 0; i < bytes.length(); i = i + 1 {
    a = (a + bytes[i].to_uint()) % modulus
    b = (b + a) % modulus
  }
  (b << 16) | a
}

///|
/// Compute the CRC-32 checksum of `bytes` (ISO 3309 / ITU-T V.42).
///
/// Every PNG chunk ends with the CRC-32 of its type and data fields, so this
/// covers the integrity check required by RFC 2083 section 3.3.
pub fn crc32(bytes : Bytes) -> UInt {
  let mut crc : UInt = 0xFFFFFFFFU
  let mut i = 0
  while i < bytes.length() {
    crc = crc ^ bytes[i].to_uint()
    let mut bit = 0
    while bit < 8 {
      if (crc & 1U) != 0U {
        crc = (crc >> 1) ^ 0xEDB88320U
      } else {
        crc = crc >> 1
      }
      bit = bit + 1
    }
    i = i + 1
  }
  crc ^ 0xFFFFFFFFU
}
