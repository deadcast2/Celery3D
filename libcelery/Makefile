# Celery3D Graphics Library - Build System
#
# Builds libcelery with the simulation backend and demo programs.

# Directories
RTL_DIR = ../rtl
OBJ_DIR = obj_dir
INCLUDE_DIR = include
SRC_DIR = src
DEMO_DIR = demos

# Tools
VERILATOR = verilator
CXX = g++
CXXFLAGS = -std=c++17 -O2 -Wall -I$(INCLUDE_DIR)

# RTL sources (relative to RTL_DIR)
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

# Add RTL_DIR prefix
RTL_PATHS = $(addprefix $(RTL_DIR)/,$(RTL_SRCS))

# Top module
TOP = rasterizer_top

# Verilator output library
VERILATOR_LIB = $(OBJ_DIR)/V$(TOP)__ALL.a

# Verilator include paths (set after verilating)
VERILATOR_INCLUDE = $(shell pkg-config --cflags verilator 2>/dev/null || echo "-I/usr/share/verilator/include")
VERILATOR_ROOT = $(shell verilator --getenv VERILATOR_ROOT)

.PHONY: all cube clean help verilate

all: cube

# Step 1: Verilate the RTL (generates C++ model)
verilate: $(OBJ_DIR)/V$(TOP).h

$(OBJ_DIR)/V$(TOP).h: $(RTL_PATHS)
	@echo "Verilating RTL..."
	$(VERILATOR) --cc -Wall -Wno-fatal \
		--Mdir $(OBJ_DIR) \
		--top-module $(TOP) \
		-I$(RTL_DIR)/core \
		$(RTL_PATHS)
	@echo "Building Verilator model..."
	$(MAKE) -C $(OBJ_DIR) -f V$(TOP).mk

# Step 2: Build the cube demo (links libcelery simulation backend)
cube: $(OBJ_DIR)/cube_demo
	@echo ""
	@echo "Running cube demo..."
	cd $(OBJ_DIR) && ./cube_demo
	@echo ""
	@echo "To create animated GIF:"
	@echo "  cd $(OBJ_DIR) && convert -delay 3 -loop 0 frame_*.ppm cube_animation.gif"

$(OBJ_DIR)/cube_demo: $(OBJ_DIR)/V$(TOP).h $(SRC_DIR)/celery_sim.cpp $(DEMO_DIR)/cube_demo.cpp
	@echo "Building cube demo..."
	$(CXX) $(CXXFLAGS) \
		-I$(OBJ_DIR) \
		-I$(VERILATOR_ROOT)/include \
		-I$(VERILATOR_ROOT)/include/vltstd \
		$(SRC_DIR)/celery_sim.cpp \
		$(DEMO_DIR)/cube_demo.cpp \
		$(VERILATOR_ROOT)/include/verilated.cpp \
		$(OBJ_DIR)/V$(TOP)__ALL.a \
		-o $@

# Clean
clean:
	rm -rf $(OBJ_DIR)
	rm -f frame_*.ppm
	rm -f cube_animation.gif

# Help
help:
	@echo "Celery3D Graphics Library Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all      - Build and run cube demo (default)"
	@echo "  cube     - Build and run cube demo"
	@echo "  verilate - Generate Verilator model only"
	@echo "  clean    - Remove build artifacts"
	@echo "  help     - Show this message"
	@echo ""
	@echo "Output:"
	@echo "  $(OBJ_DIR)/cube_demo - Cube demo executable"
	@echo "  $(OBJ_DIR)/frame_*.ppm - Animation frames"
