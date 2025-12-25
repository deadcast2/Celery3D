# KC705 Board Test Build

VIVADO = vivado
VIVADO_FLAGS = -mode batch -nojournal

.PHONY: all bitstream program clean

all: bitstream

# Generate bitstream
bitstream:
	@echo "Building KC705 LED test bitstream..."
	$(VIVADO) $(VIVADO_FLAGS) -source build_board_test.tcl 2>&1 | tee build/vivado.log
	@echo ""
	@echo "Done! Bitstream at: build/kc705_board_test.bit"

# Program the board (requires hardware manager)
program:
	@if [ ! -f build/kc705_board_test.bit ]; then \
		echo "Error: Bitstream not found. Run 'make bitstream' first."; \
		exit 1; \
	fi
	@echo "Programming KC705 board..."
	$(VIVADO) $(VIVADO_FLAGS) -source program_board.tcl

clean:
	rm -rf build .Xil
	rm -f vivado*.log vivado*.jou *.dcp
