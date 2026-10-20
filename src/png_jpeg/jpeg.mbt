// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Error raised when a byte stream cannot be decoded as a JPEG image.
pub suberror JpegDecodeError {
  ///
  /// The two-byte JPEG start-of-image marker is missing.
  NotJpeg
  ///
  /// A segment, table, or entropy-coded block is malformed or uses a mode this
  /// baseline decoder deliberately rejects.
  BadData(reason~ : String)
} derive(Debug, Eq)

///|
/// Whether `data` opens with the start-of-image marker SOI (ITU T.81, B.2.1).
pub fn is_jpeg(data : Bytes) -> Bool {
  data.length() >= 2 && data[0] == b'\xff' && data[1] == b'\xd8'
}

///|
/// One frame component: the sampling factors that place its blocks in an MCU,
/// the quantisation and Huffman tables it refers to, the coefficients still
/// being accumulated, and the plane its decoded samples land in.
priv struct Component {
  id : Int
  h : Int
  v : Int
  tq : Int
  mut td : Int
  mut ta : Int
  mut dc : Int
  mut plane : Array[Byte]
  mut stride : Int
  mut rows : Int
}

///|
/// Everything the decoder learns from the marker segments, plus the cursor that
/// walks them (ITU T.81, section B.1.1).
priv struct JpegState {
  data : Bytes
  mut pos : Int
  mut frame_seen : Bool
  mut width : Int
  mut height : Int
  mut max_h : Int
  mut max_v : Int
  mut components : Array[Component]
  quant : Array[Int]
  quant_defined : Array[Bool]
  dc_tables : Array[HuffmanTable]
  ac_tables : Array[HuffmanTable]
  dc_defined : Array[Bool]
  ac_defined : Array[Bool]
  mut restart_interval : Int
}

///|
fn JpegState::new(data : Bytes) -> JpegState {
  {
    data,
    pos: 0,
    frame_seen: false,
    width: 0,
    height: 0,
    max_h: 1,
    max_v: 1,
    components: [],
    quant: Array::make(4 * 64, 0),
    quant_defined: Array::make(4, false),
    dc_tables: Array::make(4, HuffmanTable::empty()),
    ac_tables: Array::make(4, HuffmanTable::empty()),
    dc_defined: Array::make(4, false),
    ac_defined: Array::make(4, false),
    restart_interval: 0,
  }
}

///|
fn be16(data : Bytes, offset : Int) -> Int {
  (data[offset].to_int() << 8) | data[offset + 1].to_int()
}

///|
/// Copy `data[start..end)` into a fresh byte array.
fn slice_bytes(data : Bytes, start : Int, end : Int) -> Bytes {
  let out : Array[Byte] = []
  let mut i = start
  while i < end {
    out.push(data[i])
    i = i + 1
  }
  Bytes::from_array(out)
}

///|
/// Advance to the next marker and return its code, or -1 when the data ends
/// (ITU T.81, section B.1.1.2). Stuffed 0xFF 0x00 pairs belong to scan data and
/// fill 0xFF bytes carry no meaning, so both are skipped.
fn next_marker(state : JpegState) -> Int {
  while state.pos < state.data.length() {
    if state.data[state.pos].to_int() == 0xFF {
      if state.pos + 1 >= state.data.length() {
        return -1
      }
      let code = state.data[state.pos + 1].to_int()
      if code == 0x00 {
        state.pos = state.pos + 2
        continue
      }
      if code == 0xFF {
        state.pos = state.pos + 1
        continue
      }
      state.pos = state.pos + 2
      return code
    }
    state.pos = state.pos + 1
  }
  -1
}

///|
/// Read the payload of a marker segment, whose two-byte length counts itself.
fn read_segment(state : JpegState) -> Bytes raise JpegDecodeError {
  if state.pos + 2 > state.data.length() {
    raise BadData(reason="a segment length runs past the end of the data")
  }
  let length = be16(state.data, state.pos)
  if length < 2 {
    raise BadData(reason="a segment declares a length below the minimum")
  }
  let start = state.pos + 2
  let end = state.pos + length
  if end > state.data.length() {
    raise BadData(reason="a segment payload runs past the end of the data")
  }
  state.pos = end
  slice_bytes(state.data, start, end)
}

///|
/// Parse DQT: one or more tables, each introduced by a byte that names its
/// precision and destination, followed by 64 steps in zig-zag order.
fn parse_dqt(state : JpegState, payload : Bytes) -> Unit raise JpegDecodeError {
  let mut i = 0
  while i < payload.length() {
    let spec = payload[i].to_int()
    i = i + 1
    let precision = spec >> 4
    let id = spec & 15
    if precision > 1 || id > 3 {
      raise BadData(reason="the DQT segment declares an illegal table")
    }
    let mut k = 0
    while k < 64 {
      if precision == 0 {
        if i >= payload.length() {
          raise BadData(reason="the DQT segment ends inside a table")
        }
        state.quant[id * 64 + k] = payload[i].to_int()
        i = i + 1
      } else {
        if i + 1 >= payload.length() {
          raise BadData(reason="the DQT segment ends inside a table")
        }
        state.quant[id * 64 + k] = be16(payload, i)
        i = i + 2
      }
      k = k + 1
    }
    state.quant_defined[id] = true
  }
}

///|
/// Parse DHT: one or more tables, each introduced by a byte that names its
/// class and destination, followed by sixteen code counts and their symbols.
fn parse_dht(state : JpegState, payload : Bytes) -> Unit raise JpegDecodeError {
  let mut i = 0
  while i < payload.length() {
    let spec = payload[i].to_int()
    i = i + 1
    let class = spec >> 4
    let id = spec & 15
    if class > 1 || id > 3 {
      raise BadData(reason="the DHT segment declares an illegal table")
    }
    if i + 16 > payload.length() {
      raise BadData(reason="the DHT segment ends inside its code counts")
    }
    let counts : Array[Int] = Array::make(17, 0)
    let mut total = 0
    let mut length = 1
    while length <= 16 {
      counts[length] = payload[i].to_int()
      total = total + counts[length]
      i = i + 1
      length = length + 1
    }
    if total > 256 || i + total > payload.length() {
      raise BadData(reason="the DHT segment ends inside its symbol list")
    }
    let symbols : Array[Int] = []
    let mut k = 0
    while k < total {
      symbols.push(payload[i].to_int())
      i = i + 1
      k = k + 1
    }
    let table = HuffmanTable::build(counts, symbols)
    if class == 0 {
      state.dc_tables[id] = table
      state.dc_defined[id] = true
    } else {
      state.ac_tables[id] = table
      state.ac_defined[id] = true
    }
  }
}

///|
/// Parse SOF0, the baseline frame header: the geometry, then the sampling
/// factors and quantisation table of each component.
fn parse_sof(state : JpegState, payload : Bytes) -> Unit raise JpegDecodeError {
  if payload.length() < 6 {
    raise BadData(reason="the SOF0 segment is truncated")
  }
  if payload[0].to_int() != 8 {
    raise BadData(reason="only eight-bit sample precision is supported")
  }
  let height = be16(payload, 1)
  let width = be16(payload, 3)
  let count = payload[5].to_int()
  if width == 0 || height == 0 {
    raise BadData(reason="the frame declares an empty image")
  }
  if count != 1 && count != 3 {
    raise BadData(reason="only one and three component frames are supported")
  }
  if payload.length() < 6 + count * 3 {
    raise BadData(reason="the SOF0 segment ends inside its component list")
  }
  let components : Array[Component] = []
  let mut max_h = 1
  let mut max_v = 1
  let mut i = 0
  while i < count {
    let id = payload[6 + i * 3].to_int()
    let factors = payload[7 + i * 3].to_int()
    let tq = payload[8 + i * 3].to_int()
    let h = factors >> 4
    let v = factors & 15
    if h < 1 || h > 4 || v < 1 || v > 4 {
      raise BadData(reason="a component declares an illegal sampling factor")
    }
    if tq > 3 {
      raise BadData(reason="a component names an unknown quantisation table")
    }
    if h > max_h {
      max_h = h
    }
    if v > max_v {
      max_v = v
    }
    components.push({
      id,
      h,
      v,
      tq,
      td: 0,
      ta: 0,
      dc: 0,
      plane: [],
      stride: 0,
      rows: 0,
    })
    i = i + 1
  }
  state.width = width
  state.height = height
  state.max_h = max_h
  state.max_v = max_v
  state.components = components
  state.frame_seen = true
}

///|
/// Locate the component a scan refers to by its identifier.
fn component_index(state : JpegState, id : Int) -> Int {
  let mut index = -1
  let mut i = 0
  while i < state.components.length() {
    if state.components[i].id == id {
      index = i
    }
    i = i + 1
  }
  index
}

///|
/// Decode one 8x8 block: the DC difference and the run-length coded AC
/// coefficients (ITU T.81, section F.2.2), then dequantise and invert it into
/// the component plane at `origin_x`, `origin_y`.
fn decode_block(
  state : JpegState,
  reader : BitReader,
  comp : Component,
  origin_x : Int,
  origin_y : Int,
) -> Unit raise JpegDecodeError {
  if !state.quant_defined[comp.tq] {
    raise BadData(reason="a block refers to an undefined quantisation table")
  }
  if !state.dc_defined[comp.td] {
    raise BadData(reason="a block refers to an undefined DC Huffman table")
  }
  if !state.ac_defined[comp.ta] {
    raise BadData(reason="a block refers to an undefined AC Huffman table")
  }
  let coeffs : Array[Int] = Array::make(64, 0)
  let category = state.dc_tables[comp.td].decode(reader)
  if category > 11 {
    raise BadData(reason="a DC difference declares more than eleven bits")
  }
  comp.dc = comp.dc + receive_extend(reader.read_bits(category), category)
  coeffs[0] = comp.dc
  let mut k = 1
  while k < 64 {
    let symbol = state.ac_tables[comp.ta].decode(reader)
    let size = symbol & 15
    let run = symbol >> 4
    if size == 0 {
      if run == 15 {
        k = k + 16
      } else {
        break
      }
    } else {
      k = k + run
      if k > 63 {
        raise BadData(reason="an AC coefficient runs past the end of its block")
      }
      coeffs[k] = receive_extend(reader.read_bits(size), size)
      k = k + 1
    }
  }
  let natural = dequantise(coeffs, state.quant, comp.tq * 64)
  let block = idct_block(natural)
  let mut row = 0
  while row < 8 {
    let dest = (origin_y + row) * comp.stride + origin_x
    let mut col = 0
    while col < 8 {
      comp.plane[dest + col] = block[row * 8 + col]
      col = col + 1
    }
    row = row + 1
  }
}

///|
/// Decode the single sequential scan of a baseline frame, walking MCU by MCU in
/// raster order and restarting the DC predictors at every restart interval.
fn decode_scan(
  state : JpegState,
  payload : Bytes,
) -> Unit raise JpegDecodeError {
  if !state.frame_seen {
    raise BadData(reason="the scan appears before the frame header")
  }
  if payload.length() < 1 {
    raise BadData(reason="the SOS segment is truncated")
  }
  let count = payload[0].to_int()
  if count != state.components.length() {
    raise BadData(reason="the scan does not cover every component of the frame")
  }
  if payload.length() < 1 + count * 2 + 3 {
    raise BadData(reason="the SOS segment is truncated")
  }
  let order : Array[Int] = []
  let mut i = 0
  while i < count {
    let id = payload[1 + i * 2].to_int()
    let tables = payload[2 + i * 2].to_int()
    let index = component_index(state, id)
    if index < 0 {
      raise BadData(reason="the scan names the unknown component \{id}")
    }
    let td = tables >> 4
    let ta = tables & 15
    if td > 3 || ta > 3 {
      raise BadData(reason="the scan names an unknown Huffman table")
    }
    state.components[index].td = td
    state.components[index].ta = ta
    order.push(index)
    i = i + 1
  }
  let spectral_start = payload[1 + count * 2].to_int()
  let spectral_end = payload[2 + count * 2].to_int()
  if spectral_start != 0 || spectral_end != 63 {
    raise BadData(reason="only sequential scans are supported")
  }
  let mcus_x = (state.width + 8 * state.max_h - 1) / (8 * state.max_h)
  let mcus_y = (state.height + 8 * state.max_v - 1) / (8 * state.max_v)
  let mut c = 0
  while c < state.components.length() {
    let comp = state.components[c]
    comp.stride = mcus_x * comp.h * 8
    comp.rows = mcus_y * comp.v * 8
    comp.plane = Array::make(comp.stride * comp.rows, b'\x00')
    comp.dc = 0
    c = c + 1
  }
  let reader = BitReader::new(state.data, state.pos)
  let total = mcus_x * mcus_y
  let mut mcu = 0
  while mcu < total {
    if state.restart_interval > 0 &&
      mcu > 0 &&
      mcu % state.restart_interval == 0 {
      reader.restart()
      let mut r = 0
      while r < state.components.length() {
        state.components[r].dc = 0
        r = r + 1
      }
    }
    let mcu_x = mcu % mcus_x
    let mcu_y = mcu / mcus_x
    let mut s = 0
    while s < order.length() {
      let comp = state.components[order[s]]
      let mut block_y = 0
      while block_y < comp.v {
        let mut block_x = 0
        while block_x < comp.h {
          decode_block(
            state,
            reader,
            comp,
            (mcu_x * comp.h + block_x) * 8,
            (mcu_y * comp.v + block_y) * 8,
          )
          block_x = block_x + 1
        }
        block_y = block_y + 1
      }
      s = s + 1
    }
    mcu = mcu + 1
  }
  state.pos = reader.pos
}

///|
/// Decode a baseline JPEG datastream into an `Image`.
///
/// The marker segments are read in order: the quantisation tables, the frame
/// header, the Huffman tables, and the restart interval. The single sequential
/// scan is then entropy-decoded block by block, dequantised, inverse
/// transformed, resampled to the full resolution, and converted from YCbCr (or
/// passed through when the frame is already RGB). Modes outside baseline
/// sequential, such as progressive or arithmetic coding, are rejected.
pub fn decode(data : Bytes) -> @image.Image raise JpegDecodeError {
  if !is_jpeg(data) {
    raise NotJpeg
  }
  let state = JpegState::new(data)
  state.pos = 2
  let mut image : @image.Image? = None
  while true {
    let marker = next_marker(state)
    if marker < 0 {
      break
    }
    if marker == 0xD9 {
      break
    }
    if marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7) {
      continue
    }
    let payload = read_segment(state)
    if marker == 0xDB {
      parse_dqt(state, payload)
    } else if marker == 0xC4 {
      parse_dht(state, payload)
    } else if marker == 0xC0 {
      parse_sof(state, payload)
    } else if marker == 0xDD {
      if payload.length() < 2 {
        raise BadData(reason="the DRI segment is truncated")
      }
      state.restart_interval = be16(payload, 0)
    } else if marker == 0xDA {
      decode_scan(state, payload)
      image = Some(render_image(state))
    } else if marker >= 0xC0 && marker <= 0xCF {
      raise BadData(
        reason="the frame type 0x\{marker} is not baseline sequential",
      )
    }
  }
  match image {
    Some(value) => value
    None => raise BadData(reason="the datastream carries no scan")
  }
}
