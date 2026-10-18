# MoonPNG

[![CI](https://github.com/wuhaiting321/MoonPNG/actions/workflows/ci.yml/badge.svg)](https://github.com/wuhaiting321/MoonPNG/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

MoonPNG is a pure MoonBit PNG encoder and decoder with zero FFI dependencies.
It targets Native, WebAssembly, and JavaScript from a single source tree, and it
runs inside a WASI sandbox without requesting any host capability.

## Status

The library is under active construction:

- [x] Engineering skeleton, IO abstraction layer, and image model.
- [ ] PNG decoder (all bit depths, color types, filter methods, Adam7).
- [ ] PNG encoder (filter selection and a pure MoonBit DEFLATE stage).
- [ ] Integration test suite against a standard image corpus.
- [ ] Optional JPEG Baseline decoder (stretch goal).

## Package layout

| Package | Purpose |
| --- | --- |
| `src/io_abstraction` | `Reader` / `Writer` traits and in-memory backends |
| `src/image` | `ColorType`, `Image`, and derived geometry |
| `src/zlib` | Adler-32, CRC-32, and the DEFLATE codec |
| `src/png_decode` | PNG chunk parsing, inflate, and filter reconstruction |
| `src/png_encode` | PNG chunk writing, filter selection, and deflate |
| `src/png` | Facade exposing `png.decode` and `png.encode` |
| `src/png_jpeg` | Optional JPEG Baseline decoder (stretch goal) |

## Requirements

- MoonBit toolchain `0.1.20260915` or newer.
- A native C toolchain only when running native tests or native coverage.

## Library usage

```text
import {
  "wuhaiting321/moonpng/src/png",
}

fn round_trip(bytes : Bytes) -> Bytes raise {
  let image = @png.decode(bytes)
  @png.encode(image)
}
```

## Building and testing

```bash
moon fmt --check
moon check --deny-warn
moon check --target all --deny-warn
moon test
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
