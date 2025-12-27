# Celery3D GPU - RTL Build System
# Uses Verilator for simulation

VERILATOR = verilator
VERILATOR_FLAGS = --cc --exe --build -Wall -Wno-fatal --trace

# Source files - Rasterizer core
RTL_SRCS = \
    core/celery_pkg.sv \
    core/edge_eval.sv \
    core/triangle_setup.sv \
    core/rasterizer.sv \
    core/perspective_correct.sv \
    core/texture_unit.sv \
    core/depth_buffer.sv \
    core/alpha_blend.sv \
    core/framebuffer.sv \
    core/rasterizer_top.sv

# Source files - HDMI video output
HDMI_SRCS = \
    core/celery_pkg.sv \
    video/video_pkg.sv \
    video/video_timing_gen.sv \
    video/test_pattern_gen.sv \
    video/rgb_to_ycbcr.sv \
    video/i2c_master.sv \
    video/adv7511_init.sv \
    video/hdmi_top.sv

# Testbenches
TB_SRC = sim/tb_rasterizer.cpp
TB_CUBE_SRC = sim/tb_cube_animation.cpp
TB_HDMI_SRC = sim/tb_hdmi.cpp

# Output directory
OBJ_DIR = obj_dir

# Top module
TOP = rasterizer_top

.PHONY: all sim cube hdmi clean lint wave help synth synth-hdmi program-hdmi synth-ddr3 program-ddr3 impl timing

all: sim

# Build and run simulation
sim: $(OBJ_DIR)/V$(TOP)
	@echo "Running simulation..."
	./$(OBJ_DIR)/V$(TOP)

# Build simulation executable
$(OBJ_DIR)/V$(TOP): $(RTL_SRCS) $(TB_SRC)
	@echo "Building Verilator simulation..."
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module $(TOP) \
		-I./core \
		$(RTL_SRCS) \
		$(TB_SRC) \
		-o V$(TOP)

# Build and run 3D cube animation
cube: $(OBJ_DIR)/V$(TOP)_cube
	@echo "Running 3D cube animation..."
	./$(OBJ_DIR)/V$(TOP)_cube
	@echo ""
	@echo "To create animated GIF:"
	@echo "  convert -delay 3 -loop 0 frame_*.ppm cube_animation.gif"

# Build cube animation executable
$(OBJ_DIR)/V$(TOP)_cube: $(RTL_SRCS) $(TB_CUBE_SRC)
	@echo "Building cube animation testbench..."
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module $(TOP) \
		-I./core \
		$(RTL_SRCS) \
		$(TB_CUBE_SRC) \
		-o V$(TOP)_cube

# Build and run HDMI test pattern simulation
hdmi: $(OBJ_DIR)/Vhdmi_top
	@echo "Running HDMI simulation..."
	./$(OBJ_DIR)/Vhdmi_top
	@echo ""
	@echo "Output saved to hdmi_output.ppm"

# Build HDMI testbench executable
$(OBJ_DIR)/Vhdmi_top: $(HDMI_SRCS) $(TB_HDMI_SRC)
	@echo "Building HDMI testbench..."
	$(VERILATOR) $(VERILATOR_FLAGS) \
		--top-module hdmi_top \
		-I./core \
		-I./video \
		$(HDMI_SRCS) \
		$(TB_HDMI_SRC) \
		-o Vhdmi_top

# Lint check (no simulation, just syntax/style check)
lint:
	@echo "Linting RTL..."
	$(VERILATOR) --lint-only -Wall -Wno-fatal \
		--top-module $(TOP) \
		-I./core \
		$(RTL_SRCS)

# View waveforms
wave: rasterizer.vcd
	gtkwave rasterizer.vcd &

# Clean build artifacts
clean:
	rm -rf $(OBJ_DIR)
	rm -f rasterizer.vcd
	rm -f rasterizer_output.ppm
	rm -f frame_*.ppm
	rm -f cube_animation.gif
	rm -f output_*.ppm
	rm -f hdmi.vcd
	rm -f hdmi_output.ppm

# ==============================================================================
# Vivado Synthesis & Implementation
# ==============================================================================
VIVADO = vivado
VIVADO_FLAGS = -mode batch -nojournal -nolog

# Build directory for Vivado outputs
BUILD_DIR = build

# Synthesis only (fast, for checking resource usage)
synth:
	@echo "Running Vivado synthesis (rasterizer)..."
	@mkdir -p $(BUILD_DIR)
	$(VIVADO) $(VIVADO_FLAGS) -source scripts/synth_rasterizer.tcl 2>&1 | tee $(BUILD_DIR)/vivado.log
	@echo "Synthesis complete. Check $(BUILD_DIR)/post_synth_*.rpt"

# HDMI synthesis and bitstream generation
synth-hdmi:
	@echo "Running Vivado synthesis (HDMI)..."
	@mkdir -p build_hdmi
	$(VIVADO) $(VIVADO_FLAGS) -source scripts/synth_hdmi.tcl 2>&1 | tee build_hdmi/vivado.log
	@echo ""
	@echo "Build complete. Check build_hdmi/hdmi_test.bit"

# Program HDMI bitstream to KC705 via JTAG
program-hdmi: build_hdmi/hdmi_test.bit
	@echo "Programming KC705..."
	$(VIVADO) $(VIVADO_FLAGS) -source scripts/program_hdmi.tcl

# DDR3 memory test synthesis and bitstream generation
synth-ddr3:
	@echo "Running Vivado build (DDR3 test)..."
	@mkdir -p build_ddr3
	$(VIVADO) $(VIVADO_FLAGS) -source scripts/synth_ddr3_test.tcl 2>&1 | tee build_ddr3/vivado.log
	@echo ""
	@echo "Build complete. Check build_ddr3/ddr3_test.bit"

# Program DDR3 test bitstream to KC705 via JTAG
program-ddr3: build_ddr3/ddr3_test.bit
	@echo "Programming KC705 with DDR3 test..."
	$(VIVADO) $(VIVADO_FLAGS) -source scripts/program_ddr3.tcl

# Full implementation (synthesis + place + route)
impl: synth

# Quick timing check (shows timing summary)
timing:
	@if [ -f $(BUILD_DIR)/post_route_timing_summary.rpt ]; then \
		cat $(BUILD_DIR)/post_route_timing_summary.rpt; \
	elif [ -f $(BUILD_DIR)/post_synth_timing_summary.rpt ]; then \
		cat $(BUILD_DIR)/post_synth_timing_summary.rpt; \
	else \
		echo "No timing reports found. Run 'make synth' first."; \
	fi

# Clean Vivado artifacts
clean-vivado:
	rm -rf $(BUILD_DIR)
	rm -rf build_hdmi
	rm -rf build_ddr3
	rm -rf .Xil
	rm -f vivado*.log vivado*.jou
	rm -f *.dcp

# Help
help:
	@echo "Celery3D RTL Build System"
	@echo ""
	@echo "Simulation (Verilator):"
	@echo "  all   - Build and run simulation (default)"
	@echo "  sim   - Build and run simulation"
	@echo "  cube  - Render 3D cube animation (60 frames)"
	@echo "  hdmi  - Simulate HDMI output (test pattern)"
	@echo "  lint  - Run Verilator linting"
	@echo "  wave  - Open waveform viewer"
	@echo ""
	@echo "Synthesis (Vivado):"
	@echo "  synth        - Run rasterizer synthesis"
	@echo "  synth-hdmi   - Build HDMI bitstream (full flow)"
	@echo "  program-hdmi - Program KC705 with HDMI test"
	@echo "  synth-ddr3   - Build DDR3 test bitstream"
	@echo "  program-ddr3 - Program KC705 with DDR3 test"
	@echo "  timing       - Show timing summary"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean       - Remove Verilator artifacts"
	@echo "  clean-vivado- Remove Vivado artifacts"
	@echo ""
	@echo "  help  - Show this message"
