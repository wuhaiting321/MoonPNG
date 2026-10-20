// Copyright 2026 wuhaiting321
// Apache License 2.0

///|
/// Read the sample of `comp` that covers pixel `(x, y)` of the full image.
///
/// A component whose sampling factors are below the frame maximum occupies one
/// sample for every `max_h / h` columns of the output, so the nearest sample is
/// the one at the scaled coordinate. Replication is the cheapest resampling
/// that keeps every output pixel backed by decoded data.
fn sample_at(
  comp : Component,
  x : Int,
  y : Int,
  max_h : Int,
  max_v : Int,
) -> Int {
  let sx = x * comp.h / max_h
  let sy = y * comp.v / max_v
  comp.plane[sy * comp.stride + sx].to_int()
}

///|
/// Round a colour channel to the nearest byte, clamping what the conversion
/// pushes outside the representable range.
fn clamp_channel(value : Double) -> Byte {
  let rounded = (value + 0.5).to_int()
  if rounded < 0 {
    b'\x00'
  } else if rounded > 255 {
    b'\xff'
  } else {
    rounded.to_byte()
  }
}

///|
/// Turn the decoded component planes into an `Image`.
///
/// A single-component frame is grayscale and needs no conversion. A
/// three-component frame is either stored as RGB directly, which the component
/// identifiers R, G, B announce, or as the YCbCr triple the JFIF convention
/// assumes, which the standard luma and chroma weights convert back.
fn render_image(state : JpegState) -> @image.Image {
  let width = state.width
  let height = state.height
  let components = state.components
  if components.length() == 1 {
    let comp = components[0]
    let out : Array[Byte] = Array::make(width * height, b'\x00')
    let mut y = 0
    while y < height {
      let mut x = 0
      while x < width {
        out[y * width + x] = sample_at(comp, x, y, state.max_h, state.max_v).to_byte()
        x = x + 1
      }
      y = y + 1
    }
    return @image.Image::new(
      width,
      height,
      8,
      @image.ColorType::Grayscale,
      Bytes::from_array(out),
    )
  }
  let stored_as_rgb = components[0].id == 82 &&
    components[1].id == 71 &&
    components[2].id == 66
  let out : Array[Byte] = Array::make(width * height * 3, b'\x00')
  let mut y = 0
  while y < height {
    let mut x = 0
    while x < width {
      let first = sample_at(components[0], x, y, state.max_h, state.max_v)
      let second = sample_at(components[1], x, y, state.max_h, state.max_v)
      let third = sample_at(components[2], x, y, state.max_h, state.max_v)
      let (red, green, blue) = if stored_as_rgb {
        (first.to_double(), second.to_double(), third.to_double())
      } else {
        let luma = first.to_double()
        let cb = second.to_double() - 128.0
        let cr = third.to_double() - 128.0
        (
          luma + 1.402 * cr,
          luma - 0.344136 * cb - 0.714136 * cr,
          luma + 1.772 * cb,
        )
      }
      let at = (y * width + x) * 3
      out[at] = clamp_channel(red)
      out[at + 1] = clamp_channel(green)
      out[at + 2] = clamp_channel(blue)
      x = x + 1
    }
    y = y + 1
  }
  @image.Image::new(
    width,
    height,
    8,
    @image.ColorType::Truecolor,
    Bytes::from_array(out),
  )
}
