"""
Database Access Layer (DAL) for Personal Expense Tracker
Interfacing Python (Streamlit) with Oracle PL/SQL Engine via python-oracledb.

Architectural Highlights:
- Compliant with Python DB-API 2.0 (PEP 249)
- Operates in Thin Mode (pure Python implementation of the Oracle Net/TNS protocol)
- Safe Parameter Binding to eliminate SQL Injection (CWE-89)
- Explicit Transaction Management (ACID boundary enforcement)
- Out-parameter marshalling for PL/SQL Stored Procedures
"""

import os
from typing import Any, Dict, List, Optional, Tuple
import pandas as pd

# Graceful import check for oracledb
try:
    import oracledb
    # Default to Thin mode: zero Oracle Instant Client or C-binaries required
    ORACLEDB_AVAILABLE = True
except ImportError:
    oracledb = None
    ORACLEDB_AVAILABLE = False


class OracleDatabaseManager:
    """
    Encapsulates connection lifecycle, cursor management, and PL/SQL invocation
    for the Oracle Expense Tracker schema.
    """

    def __init__(
        self,
        user: str = "EXPENSE_APP",
        password: str = "ExpensePass123#",
        host: str = "localhost",
        port: int = 1521,
        service_name: str = "XEPDB1",
    ):
        self.user = os.getenv("ORACLE_USER", user)
        self.password = os.getenv("ORACLE_PASSWORD", password)
        self.host = os.getenv("ORACLE_HOST", host)
        self.port = int(os.getenv("ORACLE_PORT", port))
        self.service_name = os.getenv("ORACLE_SERVICE", service_name)

    def is_driver_installed(self) -> bool:
        """Returns True if python-oracledb is installed in the current environment."""
        return ORACLEDB_AVAILABLE

    def get_connection(self):
        """
        Instantiates a physical connection to the Oracle Database over TCP.
        Uses Thin mode by default.
        """
        if not ORACLEDB_AVAILABLE:
            raise RuntimeError(
                "The 'oracledb' package is not installed in your Python environment.\n"
                "Install it using: /home/abhimanyu/myenv/bin/pip install oracledb"
            )

        return oracledb.connect(
            user=self.user,
            password=self.password,
            host=self.host,
            port=self.port,
            service_name=self.service_name,
        )

    def test_connection(self) -> Tuple[bool, str]:
        """
        Performs a diagnostic probe against Oracle Database.
        Returns (success_flag, status_message).
        """
        if not ORACLEDB_AVAILABLE:
            return False, "Driver 'oracledb' is not installed in the virtual environment."

        try:
            with self.get_connection() as conn:
                with conn.cursor() as cursor:
                    cursor.execute("SELECT banner_full FROM v$version")
                    row = cursor.fetchone()
                    version = row[0] if row else "Unknown Oracle Version"
                    return True, f"Connected Successfully! Banner: {version}"
        except Exception as e:
            return False, f"Connection Failed: {str(e)}"

    def get_categories(self) -> pd.DataFrame:
        """Retrieves active expenditure categories."""
        query = """
            SELECT category_id, category_name, category_type, description
            FROM CATEGORIES
            WHERE is_active = 'Y'
            ORDER BY category_name ASC
        """
        with self.get_connection() as conn:
            return pd.read_sql(query, conn)

    def get_payment_modes(self) -> pd.DataFrame:
        """Retrieves active payment instruments."""
        query = """
            SELECT mode_id, mode_name, description
            FROM PAYMENT_MODES
            WHERE is_active = 'Y'
            ORDER BY mode_name ASC
        """
        with self.get_connection() as conn:
            return pd.read_sql(query, conn)

    def get_monthly_budgets(self, month: int, year: int) -> pd.DataFrame:
        """
        Retrieves allocated budget vs. actual total spent per category
        for a given month and year.
        """
        query = """
            SELECT 
                b.budget_id,
                c.category_id,
                c.category_name,
                c.category_type,
                b.budget_month,
                b.budget_year,
                b.allocated_amount,
                b.total_spent,
                (b.allocated_amount - b.total_spent) AS remaining_budget,
                ROUND(CASE 
                    WHEN b.allocated_amount > 0 THEN (b.total_spent / b.allocated_amount) * 100 
                    ELSE 0 
                END, 2) AS utilization_pct,
                b.status,
                b.last_updated
            FROM MONTHLY_BUDGETS b
            JOIN CATEGORIES c ON b.category_id = c.category_id
            WHERE b.budget_month = :p_month AND b.budget_year = :p_year
            ORDER BY b.total_spent DESC
        """
        with self.get_connection() as conn:
            return pd.read_sql(query, conn, params={"p_month": month, "p_year": year})

    def get_expenses_view(
        self,
        month: Optional[int] = None,
        year: Optional[int] = None,
        category_id: Optional[int] = None,
    ) -> pd.DataFrame:
        """
        Queries the analytical VW_EXPENSE_DETAILS view with dynamic predicate filtering.
        Utilizes strict bind variables to preserve cursor cache efficiency.
        """
        conditions = ["1 = 1"]
        params: Dict[str, Any] = {}

        if month is not None:
            conditions.append("expense_month = :p_month")
            params["p_month"] = month

        if year is not None:
            conditions.append("expense_year = :p_year")
            params["p_year"] = year

        if category_id is not None:
            conditions.append("category_id = :p_cat_id")
            params["p_cat_id"] = category_id

        where_clause = " AND ".join(conditions)
        query = f"""
            SELECT 
                expense_id,
                TO_CHAR(expense_date, 'YYYY-MM-DD') AS expense_date,
                category_name,
                category_type,
                mode_name,
                amount,
                merchant_name,
                description,
                created_at
            FROM VW_EXPENSE_DETAILS
            WHERE {where_clause}
            ORDER BY expense_date DESC, expense_id DESC
        """
        with self.get_connection() as conn:
            return pd.read_sql(query, conn, params=params)

    def record_expense(
        self,
        category_id: int,
        mode_id: int,
        amount: float,
        expense_date,
        description: str,
        merchant_name: str,
    ) -> Tuple[bool, Optional[int], str, str]:
        """
        Executes the PL/SQL Stored Procedure `SP_RECORD_EXPENSE`.
        Marshals IN parameters, allocates bind variables for OUT parameters,
        and manages the transaction commit boundary.

        Returns:
            (success: bool, expense_id: Optional[int], status_code: str, status_message: str)
        """
        with self.get_connection() as conn:
            with conn.cursor() as cursor:
                # Declare OUT bind variables
                out_expense_id = cursor.var(oracledb.NUMBER)
                out_status_code = cursor.var(oracledb.STRING)
                out_status_message = cursor.var(oracledb.STRING)

                # Invoke Stored Procedure using PL/SQL positional parameter mapping
                cursor.callproc(
                    "SP_RECORD_EXPENSE",
                    [
                        category_id,
                        mode_id,
                        amount,
                        expense_date,
                        description,
                        merchant_name,
                        out_expense_id,
                        out_status_code,
                        out_status_message,
                    ],
                )

                # Commit transaction on success
                conn.commit()

                exp_id = out_expense_id.getvalue()
                status_code = out_status_code.getvalue()
                status_msg = out_status_message.getvalue()

                success = status_code in ("SUCCESS", "BUDGET_WARNING", "BUDGET_EXCEEDED")
                return success, int(exp_id) if exp_id is not None else None, status_code, status_msg

    def set_budget(
        self, category_id: int, month: int, year: int, allocated_amount: float
    ) -> Tuple[bool, str]:
        """
        Calls `PKG_EXPENSE_MGMT.SP_SET_MONTHLY_BUDGET` to adjust spending caps.
        """
        with self.get_connection() as conn:
            with conn.cursor() as cursor:
                out_status_message = cursor.var(oracledb.STRING)
                cursor.callproc(
                    "PKG_EXPENSE_MGMT.SP_SET_MONTHLY_BUDGET",
                    [category_id, month, year, allocated_amount, out_status_message],
                )
                conn.commit()
                return True, out_status_message.getvalue()

    def delete_expense(self, expense_id: int) -> Tuple[bool, str]:
        """
        Deletes an expense row. The database trigger TRG_MAINTAIN_MONTHLY_BUDGET
        automatically fires to deduct the expenditure from MONTHLY_BUDGETS.
        """
        with self.get_connection() as conn:
            with conn.cursor() as cursor:
                cursor.execute(
                    "DELETE FROM EXPENSES WHERE expense_id = :p_id",
                    {"p_id": expense_id},
                )
                if cursor.rowcount == 0:
                    return False, f"Expense ID {expense_id} not found."
                conn.commit()
                return True, f"Expense #{expense_id} successfully deleted. Budget updated by trigger."

    def get_audit_logs(self, limit: int = 50) -> pd.DataFrame:
        """Retrieves recent entries from the immutable EXPENSE_AUDIT_LOG table."""
        query = """
            SELECT 
                audit_id,
                expense_id,
                action_type,
                performed_by,
                TO_CHAR(performed_at, 'YYYY-MM-DD HH24:MI:SS') AS timestamp,
                old_amount,
                new_amount,
                remarks
            FROM EXPENSE_AUDIT_LOG
            ORDER BY audit_id DESC
            FETCH FIRST :p_limit ROWS ONLY
        """
        with self.get_connection() as conn:
            return pd.read_sql(query, conn, params={"p_limit": limit})
