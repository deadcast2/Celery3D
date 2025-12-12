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
    core/rasterizer_top.sv

# Testbench
TB_SRC = sim/tb_rasterizer.cpp

# Output directory
OBJ_DIR = obj_dir

# Top module
TOP = rasterizer_top

.PHONY: all sim clean lint wave help

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

# Help
help:
	@echo "Celery3D RTL Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all   - Build and run simulation (default)"
	@echo "  sim   - Build and run simulation"
	@echo "  lint  - Run Verilator linting"
	@echo "  wave  - Open waveform viewer"
	@echo "  clean - Remove build artifacts"
	@echo "  help  - Show this message"
