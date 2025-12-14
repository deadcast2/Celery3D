Celery3D GPU - Dual License

Copyright (c) 2025 Caleb Cohoon

This project uses a dual licensing model to appropriately cover both
hardware and software components:

Hardware (RTL, FPGA designs)
--------------------------------------------------------------------------------
All hardware description files (Verilog, SystemVerilog, constraints, etc.)
located in the rtl/ directory are licensed under:

    CERN Open Hardware Licence Version 2 - Permissive (CERN-OHL-P-2.0)

See LICENSE-HARDWARE for the full license text.

This includes:
  - rtl/core/         (GPU core modules)
  - rtl/memory/       (DDR3 and framebuffer controllers)
  - rtl/video/        (HDMI output)
  - rtl/pcie/         (PCIe interface)
  - rtl/constraints/  (FPGA constraints)
  - rtl/sim/          (Testbenches - note: C++ testbenches are Apache 2.0)


Software (drivers, libraries, tools)
--------------------------------------------------------------------------------
All software source code is licensed under:

    Apache License, Version 2.0

See LICENSE-SOFTWARE for the full license text.

This includes:
  - driver/           (Linux kernel driver)
  - libcelery/        (User-space graphics API library)
  - sim/reference/    (Software reference renderer)
  - demos/            (Demo applications)
  - Any C, C++, Python, or other software source files


Attribution
--------------------------------------------------------------------------------
Both licenses require that you retain copyright notices and attribution when
redistributing or creating derivative works. If you build a product using
this design, please acknowledge the Celery3D project and its contributors.
