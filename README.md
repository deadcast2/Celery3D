# Celery3D

A custom 3D graphics card inspired by the 3dfx Voodoo 1, implemented on an FPGA with PCIe interface and a Glide-style graphics API. Made by me and my good friend Claude.

## Project Goals

Build a functional retro-style GPU that can render textured, Gouraud-shaded 3D graphics at 640x480 resolution. The design philosophy follows the original Voodoo 1: CPU handles vertex transformation (T&L), GPU handles rasterization and texturing.

## Target Specifications

| Specification | Target | Notes |
|---------------|--------|-------|
| Resolution | 640x480 @ 60Hz | 800x600 stretch goal |
| Color Depth | 16-bit (RGB565) | Authentic to era |
| Texture Format | RGB565, up to 256x256 | Single TMU |
| Features | Gouraud shading, depth buffer, bilinear filtering, alpha blending | Fixed-function pipeline |
| Interface | PCIe x4 Gen2 | ~2 GB/s bandwidth |
| Fill Rate | ~50 MPixels/sec | Voodoo 1 equivalent |

## Hardware Platform

**Target Board:** [AMD/Xilinx Kintex-7 KC705 Evaluation Kit](https://www.xilinx.com/products/boards-and-kits/ek-k7-kc705-g.html)

| Feature | Specification |
|---------|---------------|
| FPGA | Xilinx Kintex-7 XC7K325T-2FFG900C |
| Logic | 326K cells, 840 DSPs, 16Mb BRAM |
| Memory | 1GB DDR3 SODIMM, 128MB BPI Flash |
| PCIe | x4 Gen2 (5 Gb/s per lane) |
| Video Output | HDMI |
| Network | 1x SFP+, Gigabit Ethernet |
| Expansion | FMC HPC + FMC LPC connectors |

This board plugs directly into a PC's PCIe slot, enabling the GPU to communicate with the host via DMA while outputting video over HDMI. Just like a real graphics card!

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         HOST PC (CPU)                           │
│   - Vertex transformation (model/view/projection)               │
│   - Sends screen-space triangles to GPU via PCIe                │
└─────────────────────────────────────────────────────────────────┘
                              │ PCIe
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      CELERY3D GPU (FPGA)                        │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   Command    │───▶│   Triangle   │───▶│  Rasterizer  │       │
│  │   Processor  │    │    Setup     │    │              │       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
│         ▲                                       │               │
│         │                                       ▼               │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │    Video     │◀───│  Framebuffer │◀───│   Texture    │       │
│  │   Output     │    │  Controller  │    │  Mapping Unit│       │
│  └──────────────┘    └──────────────┘    └──────────────┘       │
│         │                   │                                   │
│         ▼                   ▼                                   │
│      [HDMI]            [DDR3 VRAM]                              │
└─────────────────────────────────────────────────────────────────┘
```

### GPU Pipeline Stages

1. **Command Processor** - Reads commands from PCIe ring buffer, decodes draw calls
2. **Triangle Setup** - Computes edge equations and attribute gradients
3. **Rasterizer** - Scan converts triangles to fragments using edge equations
4. **Texture Mapping Unit** - Fetches texels, performs bilinear filtering
5. **Pixel Operations** - Depth test, alpha blend, fog, write to framebuffer
6. **Framebuffer Controller** - Arbitrates DDR3 access between rasterizer and video output
7. **Video Output** - Generates HDMI timing, streams framebuffer to display

## Software Stack

```
┌─────────────────────────────┐
│     Application (Game)      │
├─────────────────────────────┤
│   libcelery (Glide-style)   │  ← User-space graphics API
├─────────────────────────────┤
│   celery.ko (Linux driver)  │  ← PCIe driver, memory management
├─────────────────────────────┤
│         Linux Kernel        │
└─────────────────────────────┘
```

### API Style (Glide-inspired)

```c
// Initialize
CeleryContext* ctx = celeryInit();

// Load texture
CeleryTexture* tex = celeryTextureCreate(ctx, 256, 256, CELERY_FORMAT_RGB565);
celeryTextureUpload(tex, pixels);

// Render
celeryBufferClear(ctx, CELERY_CLEAR_COLOR | CELERY_CLEAR_DEPTH);
celeryTextureBind(ctx, tex);

CeleryVertex tri[3] = {
    { .x = 320, .y = 100, .z = 0.5f, .u = 0.5f, .v = 0.0f, .color = 0xFFFFFF },
    { .x = 200, .y = 380, .z = 0.5f, .u = 0.0f, .v = 1.0f, .color = 0xFFFFFF },
    { .x = 440, .y = 380, .z = 0.5f, .u = 1.0f, .v = 1.0f, .color = 0xFFFFFF },
};
celeryDrawTriangle(ctx, tri);

celeryBufferSwap(ctx);
```

## Project Structure

```
celery3d/
├── rtl/                    # Verilog/SystemVerilog source
│   ├── core/              # GPU core modules
│   ├── memory/            # DDR3 and framebuffer controllers
│   ├── video/             # HDMI output
│   ├── pcie/              # PCIe interface
│   └── tb/                # Testbenches
├── sim/
│   └── reference/         # Software reference renderer (C + SDL2)
├── driver/                # Linux kernel driver
├── libcelery/             # User-space API library
├── demos/                 # Demo applications
└── docs/                  # Documentation
```

## Design Decisions

### Why Fixed-Function Pipeline?
The Voodoo 1 had no programmable shaders, just configurable texture and blend modes. This dramatically simplifies the hardware while still enabling impressive 3D graphics. Shaders can be a future enhancement.

### Why RGB565?
- Authentic to the Voodoo era
- Half the bandwidth of RGB888
- 64K colors is plenty for retro aesthetics
- Simplifies DDR3 burst alignment

### Why CPU-side T&L?
- Matches original Voodoo architecture
- Reduces GPU complexity significantly
- CPU is fast enough for vertex math
- GPU focuses on what it does best: pixel pushing

### Why Fixed-Point Arithmetic?
- Deterministic timing (important for FPGA)
- No floating-point IP cores needed
- Sufficient precision for 640x480
- Authentic to original hardware

### Why PCIe over USB/Ethernet?
- Direct memory-mapped I/O
- Low latency command submission
- DMA for efficient texture uploads
- Real graphics card experience

## Building

### Software Reference Renderer

```bash
cd sim/reference
mkdir build && cd build
cmake ..
make
./celery_ref
```

**Dependencies:** SDL2, CMake, C compiler

**Controls:**
- `ESC` - Quit
- `T` - Toggle texturing
- `G` - Toggle Gouraud shading

### RTL Simulation & Synthesis

**Dependencies:** Verilator, Vivado ML Edition (2024.1+ recommended)

```bash
cd rtl

# Run Verilator simulation (outputs rasterizer_output.ppm)
make sim

# View the rendered output
eog rasterizer_output.ppm  # or any image viewer

# Run Verilator linting only
make lint

# Open waveform viewer (after simulation)
make wave
```

**Vivado Synthesis (requires Kintex-7 license or 30-day eval):**

```bash
# Source Vivado environment first
source /opt/Xilinx/2025.2/Vivado/settings64.sh

# Run synthesis + timing analysis (target: 50 MHz)
make synth

# View timing summary
make timing

# Clean Vivado build artifacts
make clean-vivado
```

**Target Device:** Xilinx Kintex-7 XC7K325T-2FFG900C (KC705 Evaluation Kit)

## Implementation Phases

- [x] **Phase 1:** Software reference renderer
- [ ] **Phase 2:** Video output (HDMI test pattern)
- [ ] **Phase 3:** DDR3 framebuffer controller
- [x] **Phase 4:** Rasterization pipeline (Gouraud shading, perspective correction, texture mapping, depth buffer)
- [ ] **Phase 5:** PCIe integration
- [ ] **Phase 6:** Linux driver
- [ ] **Phase 7:** Graphics API library
- [ ] **Phase 8:** Demos and polish

### Texture Filtering Comparison

The texture unit supports both nearest-neighbor and bilinear filtering modes, selectable at runtime. Bilinear filtering samples 4 texels and interpolates between them for smoother results when textures are magnified. The implementation uses dual-port BRAMs with even/odd column interleaving to fetch all 4 texels in a single cycle.

| Nearest Neighbor | Bilinear Filtering |
|:----------------:|:------------------:|
| ![Nearest](docs/texture_nearest.png) | ![Bilinear](docs/texture_bilinear.png) |
| Sharp texel boundaries, blocky when magnified | Smooth interpolation between texels |

### Depth Buffer

The depth buffer provides hardware Z-buffering with Glide-compatible comparison functions. The 640x480 depth buffer matches the framebuffer resolution and uses a 3-stage pipeline with BRAM-based storage.

**Features:**
- 16-bit depth precision (640x480 resolution)
- 8 comparison functions (GR_CMP_NEVER, LESS, EQUAL, LEQUAL, GREATER, NOTEQUAL, GEQUAL, ALWAYS)
- Independent depth test enable and depth write enable
- Hardware clear support

**Depth Test Comparison:**

The demo renders 6 overlapping colored triangles front-to-back (closest first). With depth testing enabled, closer triangles correctly occlude farther ones. With depth testing disabled, the last-rendered triangles overwrite everything regardless of depth.

| GR_CMP_LESS (Correct) | Depth Disabled (Wrong) | GR_CMP_GREATER |
|:---------------------:|:----------------------:|:--------------:|
| ![Depth Less](docs/depth_less.png) | ![Depth Disabled](docs/depth_disabled.png) | ![Depth Greater](docs/depth_greater.png) |
| Closer triangles in front | Draw order overwrites depth | Farther triangles in front |

### Alpha Blending

The alpha blend unit provides hardware-accelerated transparency with Glide-compatible blend factors. The 5-stage pipeline reads the destination color from the framebuffer, blends with the source fragment, and writes back the result.

**Features:**
- 12 Glide blend factors (ZERO, ONE, SRC_ALPHA, ONE_MINUS_SRC_ALPHA, DST_ALPHA, etc.)
- Multiple alpha sources (texture, vertex, constant, one)
- Standard blend equation: `result = src * src_factor + dst * dst_factor`
- Proper pipeline timing to handle 2-cycle framebuffer read latency

**Blend Mode Examples:**

| SRC_ALPHA Blend | Additive Blend (ONE, ONE) |
|:---------------:|:-------------------------:|
| ![Alpha Blend](docs/alpha_blend.png) | ![Additive Blend](docs/additive_blend.png) |
| Semi-transparent triangles over white | RGB glows mixing to yellow/cyan/magenta |

The left image shows classic alpha blending: 50% transparent red and blue triangles over a white background, producing pink and light blue with purple in the overlap. The right image shows additive blending for light/glow effects: red, green, and blue triangles that add together to create yellow, cyan, magenta, and white where they overlap.

### 3D Cube Animation (RTL Simulation)

The full rasterization pipeline running in Verilator simulation, rendering a rotating 3D cube with Gouraud-shaded faces:

![Cube Animation](docs/cube_animation.gif)

This animation demonstrates the complete GPU pipeline working together:
- **Triangle Setup** computes edge equations and gradients for each of the 12 triangles (6 faces × 2)
- **Rasterizer** scan-converts triangles to fragments
- **Perspective Correction** ensures proper attribute interpolation
- **Texture Unit** applies checkerboard texture with bilinear filtering
- **Depth Buffer** handles occlusion between faces (GR_CMP_LESS)
- **Framebuffer** accumulates the final image

The cube rotates around both Y and X axes, with each face having a distinct color (light red, green, blue, yellow, magenta, cyan) modulated by the checkerboard texture. 60 frames rendered at 64×64 resolution via RTL simulation.

```bash
# Generate the animation yourself:
cd rtl
make cube
convert -delay 3 -loop 0 frame_*.ppm cube_animation.gif
```

### Synthesis Results (Kintex-7 XC7K325T)

Post-synthesis timing at 50 MHz target clock:

| Metric | Value | Status |
|--------|-------|--------|
| Setup Slack (WNS) | +5.236ns | Pass |
| Setup Margin | 26% headroom | |
| Critical Path | Triangle setup DSP chain | |
| BRAM Usage | 2x dual-port (texture) | |
| DSP Usage | Multipliers for interpolation | |

The bilinear texture unit meets timing with comfortable margin. Dual-port BRAMs are inferred correctly for the even/odd column interleaved texture memory, enabling 4-texel parallel fetch for bilinear sampling.

## Resources

- [3dfx Glide SDK Documentation](https://3dfx.retropc.se/reference.html)
- [A Trip Through the Graphics Pipeline](https://fgiesen.wordpress.com/2011/07/09/a-trip-through-the-graphics-pipeline-2011-index/)
- [Project F FPGA Graphics Tutorials](https://projectf.io/)
- [Scratchapixel Rasterization](https://www.scratchapixel.com/lessons/3d-basic-rendering/rasterization-practical-implementation/overview-rasterization-algorithm.html)

## License

This project uses dual licensing to appropriately cover hardware and software:

| Component | License | File |
|-----------|---------|------|
| Hardware (RTL, FPGA) | CERN-OHL-P-2.0 | [LICENSE-HARDWARE](LICENSE-HARDWARE) |
| Software (driver, API) | Apache-2.0 | [LICENSE-SOFTWARE](LICENSE-SOFTWARE) |

Both licenses are permissive and require attribution. You are free to use,
study, modify, and distribute this project, provided you retain copyright
notices. See [LICENSING.md](LICENSING.md) for details.

## Acknowledgments

- 3dfx Interactive for the Voodoo 1 inspiration
- The FuryGPU project for proving hobbyist GPUs are possible
- Project F for excellent FPGA graphics tutorials