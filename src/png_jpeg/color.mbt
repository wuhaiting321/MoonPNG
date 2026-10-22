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
/// Combine one ink with the black plate, matching the subtractive model libjpeg
/// and Pillow use when they expose CMYK data as RGB.
fn cmyk_channel(ink : Int, black : Int) -> Byte {
  (((255 - ink) * (255 - black) + 127) / 255).to_byte()
}

///|
/// Turn the decoded component planes into an `Image`.
///
/// A single-component frame is grayscale. Two components carry no colour
/// transform in T.81, so they are exposed as gray plus alpha. A
/// three-component frame is either stored as RGB directly, which the component
/// identifiers R, G, B announce, or as the YCbCr triple the JFIF convention
/// assumes. Four components form a CMYK frame, or YCCK when APP14 announces
/// transform 2; both are converted to RGB.
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
  if components.length() == 2 {
    let out : Array[Byte] = Array::make(width * height * 2, b'\x00')
    let mut y = 0
    while y < height {
      let mut x = 0
      while x < width {
        let at = (y * width + x) * 2
        out[at] = sample_at(components[0], x, y, state.max_h, state.max_v).to_byte()
        out[at + 1] = sample_at(
          components[1],
          x,
          y,
          state.max_h,
          state.max_v,
        ).to_byte()
        x = x + 1
      }
      y = y + 1
    }
    return @image.Image::new(
      width,
      height,
      8,
      @image.ColorType::GrayscaleAlpha,
      Bytes::from_array(out),
    )
  }
  if components.length() == 4 {
    // An Adobe CMYK or YCCK frame stores the ink amounts inverted: a sample of
    // zero means full ink. Transform 2 additionally stores the three colour
    // plates as YCbCr, so they go through the luma/chroma matrix before the ink
    // model applies.
    let inverted = state.adobe_transform == 0 || state.adobe_transform == 2
    let out : Array[Byte] = Array::make(width * height * 3, b'\x00')
    let mut y = 0
    while y < height {
      let mut x = 0
      while x < width {
        let first = sample_at(components[0], x, y, state.max_h, state.max_v)
        let second = sample_at(components[1], x, y, state.max_h, state.max_v)
        let third = sample_at(components[2], x, y, state.max_h, state.max_v)
        let fourth = sample_at(components[3], x, y, state.max_h, state.max_v)
        let (cyan, magenta, yellow) = if state.adobe_transform == 2 {
          let luma = first.to_double()
          let cb = second.to_double() - 128.0
          let cr = third.to_double() - 128.0
          let red = clamp_channel(luma + 1.402 * cr).to_int()
          let green = clamp_channel(luma - 0.344136 * cb - 0.714136 * cr).to_int()
          let blue = clamp_channel(luma + 1.772 * cb).to_int()
          (255 - red, 255 - green, 255 - blue)
        } else if inverted {
          (255 - first, 255 - second, 255 - third)
        } else {
          (first, second, third)
        }
        let black = if inverted { 255 - fourth } else { fourth }
        let at = (y * width + x) * 3
        out[at] = cmyk_channel(cyan, black)
        out[at + 1] = cmyk_channel(magenta, black)
        out[at + 2] = cmyk_channel(yellow, black)
        x = x + 1
      }
      y = y + 1
    }
    return @image.Image::new(
      width,
      height,
      8,
      @image.ColorType::Truecolor,
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
