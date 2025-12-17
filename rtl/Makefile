# Celery3D GPU - RTL Build System
# Uses Verilator for simulation

VERILATOR = verilator
VERILATOR_FLAGS = --cc --exe --build -Wall -Wno-fatal --trace

# Source files
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

# Testbench
TB_SRC = sim/tb_rasterizer.cpp

# Output directory
OBJ_DIR = obj_dir

# Top module
TOP = rasterizer_top

.PHONY: all sim clean lint wave help synth impl timing

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

# ==============================================================================
# Vivado Synthesis & Implementation
# ==============================================================================
VIVADO = vivado
VIVADO_FLAGS = -mode batch -nojournal -nolog

# Build directory for Vivado outputs
BUILD_DIR = build

# Synthesis only (fast, for checking resource usage)
synth:
	@echo "Running Vivado synthesis..."
	@mkdir -p $(BUILD_DIR)
	$(VIVADO) $(VIVADO_FLAGS) -source scripts/synth_rasterizer.tcl 2>&1 | tee $(BUILD_DIR)/vivado.log
	@echo "Synthesis complete. Check $(BUILD_DIR)/post_synth_*.rpt"

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
	@echo "  lint  - Run Verilator linting"
	@echo "  wave  - Open waveform viewer"
	@echo ""
	@echo "Synthesis (Vivado):"
	@echo "  synth - Run synthesis and implementation"
	@echo "  timing- Show timing summary"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean       - Remove Verilator artifacts"
	@echo "  clean-vivado- Remove Vivado artifacts"
	@echo ""
	@echo "  help  - Show this message"
