#!/bin/bash
# =============================================================================
# Startup Script: Personal Expense Tracker (Streamlit + Oracle PL/SQL)
# =============================================================================

PROJECT_DIR="/home/abhimanyu/PLSQL projects for SEMS 1"
VENV_BIN="/home/abhimanyu/myenv/bin"

echo "=================================================================="
echo " Personal Expense Tracker (Oracle PL/SQL + Python Streamlit)      "
echo "=================================================================="

# Check if oracledb is installed
if ! "$VENV_BIN/python" -c "import oracledb" &>/dev/null; then
    echo "[NOTICE] 'oracledb' driver is not detected in $VENV_BIN."
    echo "To install the official lightweight driver, please execute:"
    echo "  $VENV_BIN/pip install oracledb"
    echo ""
fi

echo "Starting Streamlit GUI Server on port 8501..."
cd "$PROJECT_DIR"
"$VENV_BIN/streamlit" run "$PROJECT_DIR/src/app.py" --server.port 8501 --server.address 0.0.0.0
