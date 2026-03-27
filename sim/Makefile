#===============================================================================
# Makefile for VCS Mixed-Language Compilation (VHDL + Verilog + SystemVerilog)
#
# Usage:
#   make compile    - Compile design and generate simv / simv.daidir
#   make run        - Run simulation
#   make all        - Compile and run
#   make clean      - Remove generated files
#   make verdi      - Open Verdi waveform viewer
#===============================================================================

#--------------------------------------------------------------
# Tool Configuration
#--------------------------------------------------------------
VCS       = vcs
VHDLAN    = vhdlan
VLOGAN    = vlogan
SIMV      = ./simv

#--------------------------------------------------------------
# File Lists
#--------------------------------------------------------------
VHDL_FILELIST = ../filelist/vhdl.f
VLOG_FILELIST = ../filelist/verilog.f
SV_FILELIST   = ../filelist/sv.f

#--------------------------------------------------------------
# Top Module (modify to match your design)
#--------------------------------------------------------------
TOP_MODULE = tb_top

#--------------------------------------------------------------
# Common Options
#--------------------------------------------------------------
# -full64         : 64-bit mode
# -timescale      : default timescale
# -Mdir           : intermediate object directory
COMMON_OPTS = -full64 \
              -timescale=1ns/1ps \
              -Mdir=csrc

#--------------------------------------------------------------
# VHDL Analysis Options (vhdlan)
#--------------------------------------------------------------
VHDLAN_OPTS = -full64 \
              -work WORK

#--------------------------------------------------------------
# Verilog/SV Analysis Options (vlogan)
#--------------------------------------------------------------
VLOGAN_OPTS = -full64 \
              -work WORK \
              -timescale=1ns/1ps

#--------------------------------------------------------------
# VCS Elaboration/Compilation Options
#--------------------------------------------------------------
VCS_OPTS = $(COMMON_OPTS) \
           -sverilog \
           -debug_access+all \
           -lca \
           -kdb \
           +lint=TFIPC-L \
           -o $(SIMV) \
           -top $(TOP_MODULE) \
           -l compile.log

#--------------------------------------------------------------
# Simulation Run Options
#--------------------------------------------------------------
RUN_OPTS = -l run.log \
           +fsdb+autoflush

#--------------------------------------------------------------
# Targets
#--------------------------------------------------------------

.PHONY: all compile analyze_vhdl analyze_vlog analyze_sv elaborate run clean verdi help

all: compile run

help:
	@echo "==============================================="
	@echo " VCS Mixed-Language Compilation Makefile"
	@echo "==============================================="
	@echo " make compile   - Compile the design"
	@echo " make run       - Run the simulation"
	@echo " make all       - Compile and run"
	@echo " make clean     - Remove generated files"
	@echo " make verdi     - Open Verdi waveform viewer"
	@echo " make help      - Show this help message"
	@echo "==============================================="

#--- Step 1: Analyze VHDL files with vhdlan ---
analyze_vhdl:
	@if grep -qvE '^\s*(#|$$)' $(VHDL_FILELIST) 2>/dev/null; then \
		echo "========================================"; \
		echo " Analyzing VHDL files..."; \
		echo "========================================"; \
		$(VHDLAN) $(VHDLAN_OPTS) -f $(VHDL_FILELIST); \
	else \
		echo " No VHDL files in filelist, skipping..."; \
	fi

#--- Step 2: Analyze Verilog files with vlogan ---
analyze_vlog:
	@if grep -qvE '^\s*(#|$$)' $(VLOG_FILELIST) 2>/dev/null; then \
		echo "========================================"; \
		echo " Analyzing Verilog files..."; \
		echo "========================================"; \
		$(VLOGAN) $(VLOGAN_OPTS) -f $(VLOG_FILELIST); \
	else \
		echo " No Verilog files in filelist, skipping..."; \
	fi

#--- Step 3: Analyze SystemVerilog files with vlogan -sverilog ---
analyze_sv:
	@if grep -qvE '^\s*(#|$$)' $(SV_FILELIST) 2>/dev/null; then \
		echo "========================================"; \
		echo " Analyzing SystemVerilog files..."; \
		echo "========================================"; \
		$(VLOGAN) $(VLOGAN_OPTS) -sverilog -f $(SV_FILELIST); \
	else \
		echo " No SystemVerilog files in filelist, skipping..."; \
	fi

#--- Step 4: Elaborate with VCS (generates simv and simv.daidir) ---
elaborate:
	@echo "========================================"
	@echo " Elaborating with VCS..."
	@echo "========================================"
	$(VCS) $(VCS_OPTS) $(TOP_MODULE)
	@echo "========================================"
	@echo " simv and simv.daidir generated."
	@echo "========================================"

#--- Compile: Full flow (Analyze + Elaborate) ---
compile: analyze_vhdl analyze_vlog analyze_sv elaborate

#--- Run Simulation ---
run:
	@echo "========================================"
	@echo " Running simulation..."
	@echo "========================================"
	$(SIMV) $(RUN_OPTS)

#--- Open Verdi ---
verdi:
	verdi -dbdir simv.daidir &

#--- Clean generated files ---
clean:
	rm -rf simv simv.daidir csrc
	rm -rf WORK AN.DB
	rm -rf ucli.key vc_hdrs.h
	rm -rf compile.log run.log
	rm -rf *.fsdb *.vpd
	rm -rf DVEfiles inter.vpd
	rm -rf novas.* verdiLog
	rm -rf .vlogansetup.args .vlogansetup.env
