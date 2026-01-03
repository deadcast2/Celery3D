#------------------------------------------------------------------------------
# Makefile for Celery3D FPGA Project
# Targets KC705 (Kintex-7 XC7K325T)
#------------------------------------------------------------------------------

# Xilinx Vivado settings
VIVADO_SETTINGS := /opt/Xilinx/2025.2/Vivado/settings64.sh
VIVADO := source $(VIVADO_SETTINGS) && vivado

# Project paths
PROJECT_ROOT := $(shell pwd)
SCRIPTS_DIR := $(PROJECT_ROOT)/scripts
OUTPUT_DIR := $(PROJECT_ROOT)/output

# Output files
BITSTREAM := $(OUTPUT_DIR)/celery3d.bit

# RTL source files
RTL_FILES := $(wildcard rtl/*/*.sv)
XDC_FILES := $(wildcard constraints/*.xdc)

#------------------------------------------------------------------------------
# Default target
#------------------------------------------------------------------------------
.PHONY: all
all: build

#------------------------------------------------------------------------------
# Build bitstream
#------------------------------------------------------------------------------
.PHONY: build
build: $(BITSTREAM)

$(BITSTREAM): $(RTL_FILES) $(XDC_FILES) $(SCRIPTS_DIR)/build.tcl
	@echo "=============================================="
	@echo "Building Celery3D bitstream..."
	@echo "=============================================="
	@mkdir -p $(OUTPUT_DIR)
	@bash -c '$(VIVADO) -mode batch -source $(SCRIPTS_DIR)/build.tcl -notrace'

#------------------------------------------------------------------------------
# Program FPGA
#------------------------------------------------------------------------------
.PHONY: program
program: $(BITSTREAM)
	@echo "=============================================="
	@echo "Programming KC705..."
	@echo "=============================================="
	@bash -c '$(VIVADO) -mode batch -source $(SCRIPTS_DIR)/program.tcl -notrace'

#------------------------------------------------------------------------------
# Open Vivado GUI with project
#------------------------------------------------------------------------------
.PHONY: gui
gui:
	@echo "Opening Vivado GUI..."
	@bash -c '$(VIVADO) -mode gui $(OUTPUT_DIR)/vivado_project/celery3d.xpr &'

#------------------------------------------------------------------------------
# Synthesis only
#------------------------------------------------------------------------------
.PHONY: synth
synth: $(RTL_FILES) $(XDC_FILES)
	@echo "Running synthesis only..."
	@mkdir -p $(OUTPUT_DIR)
	@bash -c '$(VIVADO) -mode batch -source $(SCRIPTS_DIR)/synth_only.tcl -notrace'

#------------------------------------------------------------------------------
# Open hardware manager for interactive programming
#------------------------------------------------------------------------------
.PHONY: hwmgr
hwmgr:
	@echo "Opening Hardware Manager..."
	@bash -c '$(VIVADO) -mode gui -source $(SCRIPTS_DIR)/open_hwmgr.tcl &'

#------------------------------------------------------------------------------
# View reports
#------------------------------------------------------------------------------
.PHONY: reports
reports:
	@echo "Build Reports:"
	@echo "=============================================="
	@if [ -f $(OUTPUT_DIR)/timing_summary.rpt ]; then \
		echo "Timing Summary:"; \
		grep -A 5 "Design Timing Summary" $(OUTPUT_DIR)/timing_summary.rpt 2>/dev/null || true; \
		echo ""; \
	fi
	@if [ -f $(OUTPUT_DIR)/utilization.rpt ]; then \
		echo "Utilization Summary:"; \
		grep -A 10 "Slice Logic" $(OUTPUT_DIR)/utilization.rpt 2>/dev/null | head -15 || true; \
		echo ""; \
	fi

#------------------------------------------------------------------------------
# Clean build artifacts
#------------------------------------------------------------------------------
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(OUTPUT_DIR)/vivado_project
	rm -rf $(OUTPUT_DIR)/*.jou
	rm -rf $(OUTPUT_DIR)/*.log
	rm -rf .Xil
	rm -rf vivado*.jou vivado*.log

#------------------------------------------------------------------------------
# Clean everything including bitstream
#------------------------------------------------------------------------------
.PHONY: distclean
distclean: clean
	@echo "Removing all output files..."
	rm -rf $(OUTPUT_DIR)

#------------------------------------------------------------------------------
# Check RTL syntax (quick check without full synthesis)
#------------------------------------------------------------------------------
.PHONY: check
check:
	@echo "Checking RTL syntax..."
	@bash -c '$(VIVADO) -mode batch -source $(SCRIPTS_DIR)/check_syntax.tcl -notrace'

#------------------------------------------------------------------------------
# List source files
#------------------------------------------------------------------------------
.PHONY: list
list:
	@echo "RTL Source Files:"
	@for f in $(RTL_FILES); do echo "  $$f"; done
	@echo ""
	@echo "Constraint Files:"
	@for f in $(XDC_FILES); do echo "  $$f"; done

#------------------------------------------------------------------------------
# Help
#------------------------------------------------------------------------------
.PHONY: help
help:
	@echo "Celery3D Build System"
	@echo "=============================================="
	@echo ""
	@echo "Targets:"
	@echo "  make build    - Build bitstream (default)"
	@echo "  make program  - Program KC705 FPGA"
	@echo "  make gui      - Open Vivado GUI with project"
	@echo "  make synth    - Run synthesis only"
	@echo "  make reports  - View build reports"
	@echo "  make clean    - Clean build artifacts"
	@echo "  make distclean- Clean everything"
	@echo "  make check    - Check RTL syntax"
	@echo "  make list     - List source files"
	@echo "  make help     - Show this help"
	@echo ""
	@echo "Requirements:"
	@echo "  Vivado 2025.2 installed at: $(VIVADO_SETTINGS)"
	@echo ""
