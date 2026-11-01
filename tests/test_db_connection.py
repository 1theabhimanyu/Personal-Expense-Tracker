#!/usr/bin/env python3
"""
Diagnostic Connection Probe for Personal Expense Tracker.
Tests connectivity between Python and Oracle XE Database.
"""

import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "src"))

try:
    import oracledb
    print("[SUCCESS] Found 'oracledb' module (Version:", oracledb.__version__, ")")
except ImportError:
    print("[ERROR] 'oracledb' module is NOT installed.")
    print("Please run: /home/abhimanyu/myenv/bin/pip install oracledb")
    sys.exit(1)

from db import OracleDatabaseManager

def main():
    print("-" * 60)
    print("ORACLE DATABASE CONNECTIVITY DIAGNOSTIC SUITE")
    print("-" * 60)

    mgr = OracleDatabaseManager(
        user=os.getenv("ORACLE_USER", "EXPENSE_APP"),
        password=os.getenv("ORACLE_PASSWORD", "ExpensePass123#"),
        host=os.getenv("ORACLE_HOST", "localhost"),
        port=int(os.getenv("ORACLE_PORT", "1521")),
        service_name=os.getenv("ORACLE_SERVICE", "XEPDB1"),
    )

    print(f"Target Endpoint: {mgr.user}@{mgr.host}:{mgr.port}/{mgr.service_name}")
    print("Initiating TCP handshake and session authentication...")

    ok, msg = mgr.test_connection()
    if ok:
        print("[SUCCESS] Connection Established!")
        print(f"Server Response: {msg}")

        # Test categories
        cats = mgr.get_categories()
        print(f"[SUCCESS] Retrieved {len(cats)} categories from CATEGORIES table.")
        for _, row in cats.head(3).iterrows():
            print(f"  - [{row['CATEGORY_ID']}] {row['CATEGORY_NAME']} ({row['CATEGORY_TYPE']})")

        print("-" * 60)
        print("ALL CONNECTIVITY CHECKS PASSED.")
        print("-" * 60)
    else:
        print("[FAILURE] Could not establish connection.")
        print(f"Reason: {msg}")
        sys.exit(1)

if __name__ == "__main__":
    main()
