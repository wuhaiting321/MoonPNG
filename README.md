# 2026 MoonBit Hackathon 十月赛 · 项目申报书

2026 年 10 月 20 日修改

[![CI](https://github.com/wuhaiting321/MoonPNG/actions/workflows/ci.yml/badge.svg)](https://github.com/wuhaiting321/MoonPNG/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

## MoonPNG 项目申报书

### 基本信息

| 项目 | 内容 |
| --- | --- |
| 项目名称 | MoonPNG |
| 参赛者 | wuhaiting321 |
| 联系方式 | wuhaiting321@users.noreply.github.com |
| GitHub 仓库链接 | <https://github.com/wuhaiting321/MoonPNG> |
| 项目方向 | 图像编解码基础库（PNG 与 JPEG Baseline） |
| 是否为移植项目 | 否，纯 MoonBit 原生实现 |

### 项目简介

MoonPNG 是一个**纯 MoonBit 实现、零 FFI 依赖**的图像编解码库。它按 RFC 2083
实现完整的 PNG 解码器与编码器，并在同一模块内提供 ITU T.81 的 Baseline JPEG
解码器；从同一份源码同时面向 Native、WebAssembly 与 JavaScript 编译，可在
WASI 沙箱内不请求任何宿主能力地独立运行。

对外只有三个顶层函数：

```moonbit
let image = @png.decode(bytes)        // PNG 字节流 -> @image.Image
let bytes = @png.encode(image)        // @image.Image -> PNG 字节流
let photo = @png_jpeg.decode(bytes)   // Baseline JPEG -> @image.Image
```

选择这一方向的理由：

- 图片是 Web 与终端应用最通用的输入输出，而 PNG 是其中唯一同时具备无损、
  透明度与真彩的格式，社区长期缺少干净的原生 MoonBit 实现。
- 难度分布适合展示语言能力：位打包（1/2/4 位样本）、大端序、逐行反滤波、
  Adam7 隔行，以及包裹在 IDAT 里的完整 DEFLATE 解码器。
- 不依赖任何 C/Rust 绑定，因此天然适合在受限环境中解压不可信图片，
  WASI 沙箱化是这一实现的差异化亮点。

### 核心功能范围

#### 1. 分层结构

| 包 | 职责 |
| --- | --- |
| `src/io_abstraction` | `Reader` / `Writer` 接口与内存后端，屏蔽字节序与越界 |
| `src/image` | `ColorType`、`Image` 与派生几何（通道数、行字节数、样本总数） |
| `src/zlib` | Adler-32、CRC-32 与完整 DEFLATE 解码器 |
| `src/png_decode` | chunk 解析、CRC 校验、inflate、逐行反滤波、Adam7 反交错 |
| `src/png_encode` | chunk 组帧、逐行滤波择优、LZ77 + 固定 Huffman 的 DEFLATE 编码 |
| `src/png` | PNG 门面：`decode` / `encode` / `version` |
| `src/png_jpeg` | Baseline JPEG 解码器：marker 解析、Huffman、反量化、IDCT、色彩还原 |

#### 2. PNG 解码器

- 全部合法位深：1 / 2 / 4 / 8 / 16；全部颜色类型：灰度、真彩、索引、
  灰度 + Alpha、真彩 + Alpha。
- 全部 5 种滤波方法：None / Sub / Up / Average / Paeth。
- Adam7 隔行解码，PngSuite `basi*` / `basn*` 语料反交错后逐字节一致。
- 完整 DEFLATE：stored、固定 Huffman、动态 Huffman 三种块类型。
- 每个 chunk 校验 CRC-32；签名不匹配、CRC 错误、数据截断均抛
  `PngDecodeError`；未知 ancillary chunk 按规范跳过。

#### 3. PNG 编码器

- 组帧 Signature / IHDR / PLTE / tRNS / IDAT / IEND，长度与 CRC-32 均为大端序。
- 逐行在 5 种滤波器中按残差代价择优，平局取更小编号。
- IDAT 使用 LZ77 滑动窗口 + 固定 Huffman 压缩，经 zlib 包裹（2 字节头 +
  Adler-32），不再退化为 stored 块。
- 非法位深、像素流长度不符、索引图缺调色板、Alpha 色型叠加 tRNS 均显式拒绝。

#### 4. JPEG Baseline 解码器

- marker 解析：SOI / DQT / SOF0 / DHT / DRI / SOS / EOI，跳过填充与 `FF 00`
  字节填充；渐进式、算术编码等非 baseline 帧型直接报错。
- 熵解码：canonical Huffman（MSB-first）、DC 差分 + AC 游程、符号扩展、
  重启间隔 RSTn 与重新对齐。
- 重建：zig-zag 反重排、反量化、可分离浮点 IDCT（基函数硬编码，
  保证三端比特一致）、YCbCr→RGB 与 RGB 直通、最近邻色度上采样。
- 支持 8 位精度、1 个或 3 个分量、任意整数采样因子（4:4:4 / 4:2:2 / 4:2:0 等）。

#### 5. 规模与质量

| 指标 | 数值 |
| --- | --- |
| `src/` 生产代码 | 2854 行（其中 JPEG 854 行） |
| 测试代码 | 1124 行 |
| 合计 | 3978 行（约束上限 5000 行） |
| 测试用例 | 45 个，全部通过 |
| 行覆盖率 | 921 / 1011（约 91%） |

### 验证与质量保障

- **CI 门禁**：`moon check`、`moon check --target all`、`moon test`，并在 Native
  目标上启用覆盖率统计；本地开发另加 `--deny-warn` 保证零告警。
- **测试覆盖**：IO 抽象层往返与越界、图像几何、色彩类型编码往返、
  CRC-32 / Adler-32 标准向量、PngSuite 语料解码、Adam7 反交错、编码器往返与
  拒绝路径、JPEG marker / Huffman / IDCT / 重启 / 错误路径。
- **外部参照**：PngSuite `basn*` 语料的样本流 CRC-32 取自独立的 CPython
  预言机，而非本项目自身的实现，避免「自己验证自己」。
- **外部互操作**：本编码器产出的 PNG 由 Python Pillow 11.1.0 解码，7/7 语料
  逐样本一致；Pillow 生成的 6 条 Baseline JPEG 语料由本解码器还原，
  灰度与 4:4:4 最大误差分别为 0 与 2，4:2:2 / 4:2:0（含逐 MCU 重启、
  13×9 非整 MCU 尺寸）最大误差均在 13 以内。
- **CI 三平台**：GitHub Actions 在 macOS、Windows、Linux 上并行执行上述门禁。

### 使用方式

```text
import {
  "wuhaiting321/moonpng/src/png",
  "wuhaiting321/moonpng/src/png_jpeg",
}

fn round_trip(bytes : Bytes) -> Bytes raise {
  let image = @png.decode(bytes)
  @png.encode(image)
}
```

本地构建与验证：

```bash
moon check --deny-warn
moon check --target all --deny-warn
moon test
moon test --enable-coverage
moon coverage report -f summary
```

### 移植或参考说明

| 项目 | 内容 |
| --- | --- |
| 原项目名称 | 无，本项目不是移植项目 |
| 原项目链接 | 无 |
| 原项目许可证 | 不适用 |
| 本项目许可证 | Apache License 2.0 |

规范依据为 RFC 2083（PNG）、RFC 1950 / 1951（zlib 与 DEFLATE）、
ITU T.81（JPEG），以及 PngSuite 测试语料的公开说明；实现代码与文档均为原创，
未复制任何既有项目的业务逻辑。

与原项目相比，本项目在范围上做了以下简化和取舍：

- **只做编解码核心**：不提供命令行工具、不读写文件、不做色彩管理；
  文件 I/O 交给调用方，库本身只处理 `Bytes`。
- **编码器只写渐进式 PNG**：不生成 Adam7 隔行图，也不做调色板量化，
  以此把编码路径压缩到可审计的规模。
- **JPEG 只解不编**：仅支持 8 位 Baseline sequential 的 1 / 3 分量帧；
  渐进式、算术编码、12 位精度、CMYK 与 EXIF / ICC 均不接受。
- **色度上采样用最近邻**：实现最省且三端结果一致，代价是与插值型解码器在
  色度边缘存在若干级差异，已在测试中以容差显式记录。
- **IDCT 采用硬编码浮点基函数**：不调用平台 `cos`，避免各后端最后一位不一致。
- **解码器只缓存必要状态**：不保留未知 chunk 内容，不做流式增量输入。

### 后续计划

- [x] 工程骨架、IO 抽象层与图像模型
- [x] PNG 解码器（全位深 / 全色型 / 全滤波 / Adam7 / 完整 DEFLATE）
- [x] PNG 编码器（chunk 组帧、滤波择优、LZ77 + Huffman、zlib 包裹）
- [x] 面向 PngSuite 语料与 Pillow 的交叉验证
- [x] Baseline JPEG 解码器（marker / Huffman / IDCT / 重启 / 色彩还原）
- [ ] 在剩余行数预算内补充更精细的色度插值

### 许可

Apache License 2.0，详见 [LICENSE](LICENSE)。
