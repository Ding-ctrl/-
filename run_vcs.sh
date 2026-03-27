#!/bin/bash
#===============================================================================
# run_vcs.sh - VCS Mixed-Language Compilation Script
#
# Compiles VHDL, Verilog, and SystemVerilog files using Synopsys VCS
# Generates simv executable and simv.daidir debug directory
#
# Usage:
#   ./run_vcs.sh                          # Use default filelists
#   ./run_vcs.sh -top <module>            # Specify top module
#   ./run_vcs.sh -run                     # Compile and run simulation
#   ./run_vcs.sh -clean                   # Clean generated files
#   ./run_vcs.sh -help                    # Show help
#===============================================================================

set -e

#--------------------------------------------------------------
# Helper Functions
#--------------------------------------------------------------
has_source_files() {
    [[ -f "$1" ]] && grep -qvE '^\s*(#|$)' "$1" 2>/dev/null
}

#--------------------------------------------------------------
# Default Configuration
#--------------------------------------------------------------
TOP_MODULE="tb_top"
VHDL_FILELIST="filelist/vhdl.f"
VLOG_FILELIST="filelist/verilog.f"
SV_FILELIST="filelist/sv.f"
RUN_SIM=0
CLEAN=0
TIMESCALE="1ns/1ps"

#--------------------------------------------------------------
# Parse Arguments
#--------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -top)
            TOP_MODULE="$2"
            shift 2
            ;;
        -vhdl_f)
            VHDL_FILELIST="$2"
            shift 2
            ;;
        -vlog_f)
            VLOG_FILELIST="$2"
            shift 2
            ;;
        -sv_f)
            SV_FILELIST="$2"
            shift 2
            ;;
        -timescale)
            TIMESCALE="$2"
            shift 2
            ;;
        -run)
            RUN_SIM=1
            shift
            ;;
        -clean)
            CLEAN=1
            shift
            ;;
        -help|--help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -top <module>       Top module name (default: tb_top)"
            echo "  -vhdl_f <file>      VHDL filelist (default: filelist/vhdl.f)"
            echo "  -vlog_f <file>      Verilog filelist (default: filelist/verilog.f)"
            echo "  -sv_f <file>        SystemVerilog filelist (default: filelist/sv.f)"
            echo "  -timescale <ts>     Timescale (default: 1ns/1ps)"
            echo "  -run                Run simulation after compilation"
            echo "  -clean              Clean generated files and exit"
            echo "  -help               Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

#--------------------------------------------------------------
# Clean
#--------------------------------------------------------------
if [[ $CLEAN -eq 1 ]]; then
    echo "Cleaning generated files..."
    rm -rf simv simv.daidir csrc WORK AN.DB
    rm -rf ucli.key vc_hdrs.h
    rm -rf compile.log run.log
    rm -rf *.fsdb *.vpd inter.vpd
    rm -rf DVEfiles
    rm -rf novas.* verdiLog
    rm -rf .vlogansetup.args .vlogansetup.env
    echo "Clean complete."
    exit 0
fi

echo "========================================================"
echo " VCS Mixed-Language Compilation"
echo " Top Module : $TOP_MODULE"
echo " Timescale  : $TIMESCALE"
echo "========================================================"

#--------------------------------------------------------------
# Step 1: Analyze VHDL files
#--------------------------------------------------------------
if has_source_files "$VHDL_FILELIST"; then
    echo ""
    echo "[Step 1/4] Analyzing VHDL files..."
    vhdlan -full64 \
           -work WORK \
           -f "$VHDL_FILELIST"
    echo "VHDL analysis complete."
else
    echo ""
    echo "[Step 1/4] No VHDL files found, skipping..."
fi

#--------------------------------------------------------------
# Step 2: Analyze Verilog files
#--------------------------------------------------------------
if has_source_files "$VLOG_FILELIST"; then
    echo ""
    echo "[Step 2/4] Analyzing Verilog files..."
    vlogan -full64 \
           -work WORK \
           -timescale="$TIMESCALE" \
           -f "$VLOG_FILELIST"
    echo "Verilog analysis complete."
else
    echo ""
    echo "[Step 2/4] No Verilog files found, skipping..."
fi

#--------------------------------------------------------------
# Step 3: Analyze SystemVerilog files
#--------------------------------------------------------------
if has_source_files "$SV_FILELIST"; then
    echo ""
    echo "[Step 3/4] Analyzing SystemVerilog files..."
    vlogan -full64 \
           -work WORK \
           -sverilog \
           -timescale="$TIMESCALE" \
           -f "$SV_FILELIST"
    echo "SystemVerilog analysis complete."
else
    echo ""
    echo "[Step 3/4] No SystemVerilog files found, skipping..."
fi

#--------------------------------------------------------------
# Step 4: Elaborate with VCS
#--------------------------------------------------------------
echo ""
echo "[Step 4/4] Elaborating design with VCS..."
vcs -full64 \
    -sverilog \
    -debug_access+all \
    -lca \
    -kdb \
    -timescale="$TIMESCALE" \
    +lint=TFIPC-L \
    -top "$TOP_MODULE" \
    -o simv \
    -l compile.log \
    "$TOP_MODULE"

echo ""
echo "========================================================"
echo " Compilation successful!"
echo " Generated: simv (executable)"
echo " Generated: simv.daidir (debug directory)"
echo "========================================================"

#--------------------------------------------------------------
# Run simulation (optional)
#--------------------------------------------------------------
if [[ $RUN_SIM -eq 1 ]]; then
    echo ""
    echo "Running simulation..."
    ./simv -l run.log +fsdb+autoflush
    echo "Simulation complete. See run.log for details."
fi
