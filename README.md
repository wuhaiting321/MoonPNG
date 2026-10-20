# MoonPNG

**纯 MoonBit 实现的 PNG 编解码器与 Baseline JPEG 解码器，零 FFI 依赖。**

一份源码同时面向 Native、WebAssembly 与 JavaScript 编译，可在 WASI 沙箱内不请求
任何宿主能力地独立运行；对外收敛为 `decode` / `encode` / `jpeg.decode` 三个入口。

[![CI](https://github.com/wuhaiting321/MoonPNG/actions/workflows/ci.yml/badge.svg)](https://github.com/wuhaiting321/MoonPNG/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](./LICENSE)

---

## 一、项目基本信息

| 项目 | 内容 |
| --- | --- |
| 项目名称 | MoonPNG |
| 参赛者 | 吴海婷 |
| 联系方式 | 19177746962@163.com |
| GitHub 仓库 | <https://github.com/wuhaiting321/MoonPNG> |
| 项目方向 | 图像编解码基础库 / PNG 与 JPEG |
| 是否为移植项目 | 否，原创项目 |
| 模块名 | `wuhaiting321/moonpng`（遵循 mooncakes.io 的 `<author>/<module>` 命名规范） |
| 代码规模 | 2854 行库源码 + 1124 行测试 + 71 行可运行示例，24 个 `.mbt` 文件，合计 4049 行 |
| 测试状态 | `moon test` 全部通过（45 个用例，0 失败）；行覆盖率 921 / 1040 |
| 构建状态 | 默认目标与 `moon check --target all --deny-warn` 均零错误、零告警 |
| 开源许可证 | Apache-2.0 |

## 二、项目简介

图片是 Web 与终端应用最通用的输入输出，而 PNG 是其中唯一同时具备**无损、
透明度与真彩**的格式：截图、图标、设计稿、日志图都默认存成 PNG。与此同时，
JPEG 仍是照片分发的实际标准，任何"读取用户给的图片"的场景都绕不开它。

**MoonBit 生态目前缺少这一环。** 现成的图像能力要么经由 C/Rust 绑定，要么依赖
宿主平台自身的解码器；前者破坏 WASM 沙箱的可移植性，后者在 WASI 中根本不可用。
MoonPNG 用于补齐这块空白：从字节流到像素阵列的全部工作——DEFLATE 解压、
逐行反滤波、Adam7 反交错、Huffman 熵解码、反量化与 IDCT——都由 MoonBit 自身完成。

**与现有能力的本质区别**

- 与 FFI 封装相比：不做任何 C/Rust 绑定，`moon check --target all` 在四个后端上
  通过，产物可直接放进 WASI 沙箱，宿主无需提供 zlib、libjpeg 或文件系统。
- 与平台解码器相比：不请求宿主能力，输入是不可信的字节流时，暴露面收敛在
  `Bytes` 与显式错误类型上，而不是一张隐式的全局解码器状态。
- 与"只解不编"的示例代码相比：解码与编码互为逆运算，测试用同一套语料双向验证，
  编码器还须接受 Pillow 的外部复核，避免"自己验证自己"。

## 三、典型使用场景

三个场景都由 [examples/main.mbt](./examples/main.mbt) 用同一份代码真实跑通，
输入是仓库内嵌的字节流，不读取文件、不请求宿主能力。

### 3.1 在 WASI 沙箱里读取 PNG 截图或图标

- **输入**：PNG 字节流（示例内嵌 4×4、8 bit 真彩 PNG）
- **调用**：`@png.decode(bytes) -> @image.Image`
- **输出**：`4x4, 8-bit, 3 channel(s)`；首个像素 `(10, 20, 200)`
- **要点**：签名、CRC-32、inflate 与反滤波全部在 MoonBit 内完成，
  不链接 libpng，也不触碰宿主文件系统。

### 3.2 把内存中的图像写回 PNG

- **输入**：上一步得到的 `Image`
- **调用**：`@png.encode(image) -> Bytes`
- **输出**：79 字节 PNG（原始文件 157 字节）；再次解码后样本逐字节一致
- **要点**：编码器自行选择滤波并做 LZ77 + 固定 Huffman 压缩，
  产物可被 Pillow 等外部解码器读取。

### 3.3 读取用户上传的 JPEG 照片

- **输入**：Baseline JPEG 字节流（示例内嵌 8×8 灰度）
- **调用**：`@png_jpeg.decode(bytes) -> @image.Image`
- **输出**：`8x8, 1 channel(s)`；灰度样本均值 127
- **要点**：Huffman 熵解码、反量化、IDCT 与色彩还原同样零 FFI；
  解出的 `Image` 与 PNG 解码结果同构，后续处理只需一套代码。

在仓库根目录运行（`--target wasm` 使用 MoonBit 自带的 WASI 运行时）：

```bash
moon run examples --target wasm
```

实际输出：

```text
PNG header: 4x4, 8-bit, 3 channel(s)
first pixel: (10, 20, 200)
encoded PNG: 79 bytes
round trip: samples identical
decoded JPEG: 8x8, 1 channel(s)
gray samples: first=255, last=255, mean=127
```

## 四、核心功能范围

- **PNG 解码**：Signature 校验、`IHDR` / `PLTE` / `tRNS` / `IDAT` / `IEND` 解析、
  每 chunk 的 CRC-32 校验、未知 ancillary chunk 按规范跳过。
- **全部合法位深**：1 / 2 / 4 / 8 / 16；**全部颜色类型**：灰度、真彩、索引、
  灰度 + Alpha、真彩 + Alpha。
- **全部 5 种滤波**：None / Sub / Up / Average / Paeth，按位深与通道数计算 `bpp`
  后逐行重建。
- **Adam7 隔行**：七个 pass 各自解析、反交错后合并为渐进式样本流。
- **完整 DEFLATE 解码**：stored、固定 Huffman、动态 Huffman 三种块类型，
  含 code-length 表的游程展开与 32K 回溯窗口。
- **PNG 编码**：组帧 Signature / IHDR / PLTE / tRNS / IDAT / IEND，长度与 CRC-32
  均为大端序；逐行在 5 种滤波器中按残差代价择优，平局取更小编号。
- **真正的压缩**：IDAT 使用 LZ77 滑动窗口 + 固定 Huffman，经 zlib 包裹
  （2 字节头 + Adler-32），而非 stored 块直出。
- **Baseline JPEG 解码**：SOI / DQT / SOF0 / DHT / DRI / SOS / EOI 解析，
  canonical Huffman、DC 差分 + AC 游程、符号扩展、重启间隔 RSTn、
  zig-zag 反重排、反量化、可分离 IDCT、YCbCr→RGB 与最近邻色度上采样。
- **明确的拒绝路径**：非 PNG/JPEG 输入、CRC 不符、数据截断、非法位深、
  索引图缺调色板、渐进式 JPEG、算术编码、未定义的量化/Huffman 表，
  一律抛出具名错误而不是返回半成品。
- **三端统一 API**：`@png.decode(Bytes) -> Image`、`@png.encode(Image) -> Bytes`、
  `@png_jpeg.decode(Bytes) -> Image`，Native / Wasm / WasmGC / JS 共享同一实现。

## 五、安装方式与快速开始

### 5.1 前置要求

| 依赖 | 版本要求 | 说明 |
| --- | --- | --- |
| MoonBit 工具链 | `moonc` ≥ 0.10.13 | 项目以 MoonBit 为唯一实现语言；CI 每次安装官方发布的最新工具链验证 |
| 编译器后端 | 任一 `moon check --target` 支持的平台 | 纯逻辑实现，无需 gcc/Node.js，也不链接任何系统库 |

安装 MoonBit 工具链（Linux / macOS）：

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
export PATH="$HOME/.moon/bin:$PATH"
moon version --all          # 应显示 moonc v0.10.13 或更高
```

Windows 安装包见 <https://www.moonbitlang.com/download/>。

### 5.2 获取项目

```bash
git clone https://github.com/wuhaiting321/MoonPNG.git
cd MoonPNG
```

### 5.3 运行示例

```bash
moon run examples --target wasm   # 无需 gcc 或 Node.js，使用自带的 WASI 运行时
```

输出与第三节列出的六个场景结果一致；示例只读取内嵌字节，可离线重复运行。

### 5.4 构建与验证

```bash
moon check --deny-warn               # 默认目标，零告警
moon check --target all --deny-warn  # Native / Wasm / WasmGC / JS
moon test                            # 45 个用例
moon test --enable-coverage
moon coverage report -f summary      # 921 / 1040
```

仓库是**库**，`examples/` 只是演示三个入口的主包，不提供通用命令行工具；
验证方式是类型检查、测试套件与示例本身，测试语料（PngSuite 片段、
Pillow 生成的 JPEG）已内嵌在 `test/` 与 `examples/` 中，离线可跑。

### 5.5 作为依赖安装

模块名遵循 mooncakes.io 的 `<author>/<module>` 规范：

```bash
moon add wuhaiting321/moonpng
```

最小使用示例（`moon.pkg` 中声明依赖后）：

```moonbit
import {
  "wuhaiting321/moonpng/src/png",
  "wuhaiting321/moonpng/src/png_jpeg",
}
```

```moonbit
fn round_trip(bytes : Bytes) -> Bytes raise {
  let image = @png.decode(bytes)
  @png.encode(image)
}

fn load_photo(bytes : Bytes) -> @image.Image raise {
  @png_jpeg.decode(bytes)
}
```

## 六、技术亮点与实现说明

### 6.1 包结构与职责

| 包 | 职责 | 源码规模 |
| --- | --- | --- |
| `src/image` | `ColorType`、`Image` 与派生几何（通道数、行字节数、样本总数） | 146 行 |
| `src/io_abstraction` | `Reader` / `Writer` trait 与内存后端，集中处理字节序与越界 | 208 行 |
| `src/zlib` | Adler-32、CRC-32 与完整 DEFLATE 解码器 | 435 行 |
| `src/png_decode` | chunk 解析、CRC 校验、inflate、反滤波、Adam7 反交错 | 572 行 |
| `src/png_encode` | chunk 组帧、滤波择优、LZ77 + 固定 Huffman 编码（含白盒测试） | 615 行 |
| `src/png` | 门面：`decode` / `encode` / `version` | 24 行 |
| `src/png_jpeg` | marker 解析、Huffman、反量化、IDCT、色彩还原 | 854 行 |

依赖方向单向：`png → png_decode / png_encode → { image, io_abstraction, zlib }`，
`png_jpeg → image`，底层三包互不依赖，不存在环。上表合计 2854 行，另有 1124 行
测试代码与 71 行可运行示例（`examples/`，独立主包），总计 4049 行，
低于 5000 行的项目硬约束。

### 6.2 核心技术实现

1. **IO 抽象与图像模型。** `Reader` / `Writer` 两个 trait 把"读几个字节、
   按大端取 16/32 位、越界报错"集中到一处；内存后端 `ByteReader` / `ByteWriter`
   是唯一实现。编解码器因此不直接触碰 `Bytes` 下标运算，三端行为一致，
   也给后续接入宿主文件后端留下接缝。`Image` 只保存宽高、位深、色彩类型、
   像素流与可选的调色板 / tRNS，所有几何量（`channels`、`row_bytes`、
   `sample_count`）都由这四个字段推导，避免两份真相。
2. **DEFLATE 解码器（`zlib`）。** 按 RFC 1951 实现三种块类型：stored 块直接搬运；
   固定 Huffman 用 288 / 30 的码表；动态 Huffman 先读 code-length 表，
   按 16 / 17 / 18 三种游程符号展开，再构建 literal/length 与 distance 两张表。
   码表构建复用同一段 canonical 分配逻辑，并对"长度越界、码集过订、
   重复游程越过表尾"显式报错，而不是猜一个符号继续。
3. **PNG 解码管线（`png_decode`）。** 先校验 8 字节签名，再以
   `length / type / payload / CRC-32` 的节奏走完 chunk；`IHDR` 的位深与色彩类型
   组合按 RFC 2083 表校验，`PLTE` 与 `tRNS` 缓存进 `Image`，多段 `IDAT` 拼接后
   一次性 inflate。反滤波把上一行的原始字节留在缓冲区里，Sub / Average / Paeth
   都按 `bpp`（向上取整到整字节）取左邻；隔行图先按七个 pass 各自的宽高
   重建子图，再按 `(x, y)` 落回完整栅格。
4. **PNG 编码器与压缩（`png_encode`）。** 先把 `Image` 校验成可编码的形态
   （位深合法、像素流长度匹配、索引图必须有调色板、Alpha 色型不得再叠 tRNS），
   然后逐行试五种滤波，取"残差绝对值和"最小者。压缩端用 3 字节哈希链找
   至少 3 字节的重复串，命中则发 length/distance 对，否则发 literal，
   码流统一用固定 Huffman，最后加 zlib 头与 Adler-32。相比 stored 块直出，
   这一层让 IDAT 真正变小，而不只是"格式正确"。
5. **Baseline JPEG 解码器（`png_jpeg`）。** marker 走查只认 SOF0 帧与单次
   顺序扫描，把采样因子、量化表与 Huffman 表读进状态；熵解码的位读取器
   按 MSB-first 组装码字，遇到 `FF 00` 视为填充并跳过，遇到真 marker 就停在
   原地交给上层。每个块先解 DC 差分（预测器按分量保存、按重启间隔清零），
   再按 run/size 解 AC 游程；系数经 zig-zag 反重排与反量化后做可分离 IDCT。
   基函数以常量表硬编码（`C(u)cos((2x+1)uπ/16)/2`），不调用平台 `cos`，
   保证四个后端逐位一致。最后按 `max_h / h`、`max_v / v` 做最近邻上采样，
   按 JFIF 权重还原 YCbCr，或识别 `R/G/B` 分量标识直接直通。
6. **错误模型。** 每个包导出自己的 suberror：`PngDecodeError`（签名、chunk、
   CRC、截断）、`InflateError`、`PngEncodeError`（非法位深、长度不符、缺调色板）、
   `JpegDecodeError`（`NotJpeg` 与带原因的 `BadData`）。错误信息带具体原因
   （如"the frame type 0xC2 is not baseline sequential"），而不是统一的
   "解析失败"，便于定位是哪一段数据越过了本实现的边界。
7. **零 FFI 与三端一致。** 全部代码只依赖 `moonbitlang/core`，不出现任何
   `extern "c"` / `extern "js"`；浮点只在 IDCT 与色彩转换中出现，且输入是
   整数系数与常量表，四舍五入在转字节前一次性完成。因此同一份源码在
   Native、Wasm、WasmGC、JS 上的输出一致，也不需要宿主提供 zlib/libjpeg。

### 6.3 数据流

```
PNG 解码
Bytes ─► Signature ─► chunk 走查 + CRC-32 ─► IHDR / PLTE / tRNS / IDAT ─► IEND
      ─► inflate（stored / 固定 / 动态 Huffman）
      ─► 逐行反滤波（None / Sub / Up / Average / Paeth）
      ─► Adam7 反交错 ─► Image
```

```
PNG 编码
Image ─► 参数校验 ─► 逐行滤波择优 ─► LZ77 + 固定 Huffman
      ─► zlib 包裹（头 + Adler-32） ─► IHDR / PLTE / tRNS / IDAT / IEND
```

```
JPEG 解码
Bytes ─► SOI ─► DQT / SOF0 / DHT / DRI ─► SOS ─► MCU 扫描（Huffman + 游程）
      ─► 反量化 ─► 可分离 IDCT ─► 色度上采样 ─► YCbCr→RGB ─► Image
```

### 6.4 验证与质量保障

- **CI 门禁**：GitHub Actions 在 Linux / macOS / Windows 上并行执行
  `moon check`、`moon check --target all`、`moon test`，并在 native 目标上
  输出覆盖率摘要。
- **测试规模**：45 个用例，覆盖 IO 往返与越界、图像几何、色彩类型编码往返、
  CRC-32 / Adler-32 标准向量、PngSuite 语料解码、Adam7 反交错、编码器往返与
  全部拒绝路径、JPEG marker / Huffman / IDCT / 重启 / 错误路径。
- **覆盖率**：`moon test --enable-coverage` + `moon coverage report -f summary`
  为 921 / 1040。
- **示例实跑**：`moon run examples --target wasm` 在 WASI 运行时上真实执行，
  一次跑通解码、编码往返与 JPEG 解码，输出见第三节。
- **外部参照**：PngSuite `basn*` 语料的样本流 CRC-32 取自独立的 CPython
  预言机，而不是本项目自身的实现，避免"自己验证自己"。
- **PNG 互操作**：本编码器产出的数据流经 Python Pillow 11.1.0 解码，
  gray1 / gray8 / gray16 / rgb8 / rgba8 / rgba16 / ga8 共 7 条语料逐样本一致。
- **JPEG 互操作**：Pillow 生成的 6 条语料由本解码器还原，与 Pillow 的 RGB 输出
  对比（容差体现 IDCT 末位与色度插值方式差异）：

  | 语料 | 场景 | 最大通道误差 |
  | --- | --- | --- |
  | gray8 | 灰度 8×8 | 0 |
  | rgb444 | 4:4:4 | 2 |
  | rgb422 | 4:2:2 | 7 |
  | rgb420 | 4:2:0 | 13 |
  | rgb420rst | 4:2:0 + 每个 MCU 重启 | 13，且像素与不重启版本完全一致 |
  | rgb420odd | 4:2:0，13×9 非整 MCU | 13 |

### 6.5 移植或参考说明

| 项目 | 内容 |
| --- | --- |
| 原项目名称 | 无，本项目为原创实现，不是移植项目 |
| 原项目链接 | 无 |
| 原项目许可证 | 不适用 |
| 本项目许可证 | Apache License 2.0 |

规范依据为 RFC 2083（PNG）、RFC 1950 / 1951（zlib 与 DEFLATE）与 ITU T.81（JPEG），
测试语料包括 Willem van Schaik 的 PngSuite 与 Pillow 现场生成的 JPEG。
实现代码与文档均为原创，不包含来源不明的代码、私有代码、闭源代码或商业代码；
仅依赖 Apache-2.0 授权的 MoonBit 官方标准库 `moonbitlang/core`。

仓库的包划分方式、`moon.pkg` 配置写法与测试命名风格参考了公开 MoonBit 项目
[moonbit-dwarfscope](https://github.com/wuhaiting321/moonbit-dwarfscope) 的
**工程组织方式**，未复制其任何业务逻辑或文档内容。

与原项目相比，本项目会做以下简化和重新设计：

- **只做编解码核心**：不提供命令行工具、不读写文件、不做色彩管理；文件 I/O 交给
  调用方，库本身只处理 `Bytes`。
- **编码器只写渐进式 PNG**：不生成 Adam7 隔行图，也不做调色板量化，
  以此把编码路径压缩到可审计的规模。
- **JPEG 只解不编**：仅接受 8 位 Baseline sequential 的 1 / 3 分量帧；
  渐进式、算术编码、12 位精度、CMYK 与 EXIF / ICC 均显式拒绝。
- **色度上采样用最近邻**：实现最省且三端结果一致，代价是与插值型解码器在色度
  边缘存在若干级差异，这一差异已在测试中以容差显式记录，而不是假装不存在。
- **IDCT 使用硬编码浮点基函数**：不调用平台 `cos`，避免各后端最后一位不一致。
- **解码器只缓存必要状态**：不保留未知 chunk 内容，不提供流式增量输入，
  一次调用对应一个完整图像。

开发过程中使用 AI 编程助手辅助代码生成、测试补全与文档撰写；项目的技术路径、
质量边界、验证方式与开源合规由作者负责，所有代码均经过本地编译与单元测试验证。

## 七、后续计划

- [x] 工程骨架、IO 抽象层与图像模型
- [x] PNG 解码器（全位深 / 全色型 / 全滤波 / Adam7 / 完整 DEFLATE）
- [x] PNG 编码器（chunk 组帧、滤波择优、LZ77 + Huffman、zlib 包裹）
- [x] 面向 PngSuite 语料与 Pillow 的交叉验证
- [x] Baseline JPEG 解码器（marker / Huffman / IDCT / 重启 / 色彩还原）
- [x] 可运行示例与三个典型使用场景
- [ ] 在剩余行数预算内补充更精细的色度插值

---

## 许可证

Copyright 2026 wuhaiting321.

本项目采用 [Apache License 2.0](./LICENSE) 分发。
