"""
Personal Expense Tracker - Frontend Application
Streamlit Graphical User Interface integrating with Oracle PL/SQL Engine.

Author: Senior Database Architect & Professor of Computer Science
Course: Advanced Database Management Systems / Mini-Semester Project
"""

import datetime
import streamlit as st
import pandas as pd
from db import OracleDatabaseManager, ORACLEDB_AVAILABLE

# -----------------------------------------------------------------------------
# 1. PAGE CONFIGURATION & THEME
# -----------------------------------------------------------------------------
st.set_page_config(
    page_title="Personal Expense Tracker | Oracle PL/SQL + Streamlit",
    page_icon="💳",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Custom Styling for Academic Presentation
st.markdown(
    """
    <style>
    .main-header {
        font-size: 2.2rem;
        font-weight: 700;
        color: #1E3A8A;
        margin-bottom: 0.2rem;
    }
    .sub-header {
        font-size: 1.05rem;
        color: #4B5563;
        margin-bottom: 1.5rem;
    }
    .metric-card {
        background-color: #F8FAFC;
        border: 1px solid #E2E8F0;
        border-radius: 8px;
        padding: 16px;
        text-align: center;
    }
    .badge-ok { background-color: #DEF7EC; color: #03543F; padding: 4px 8px; border-radius: 4px; font-weight: 600; }
    .badge-warn { background-color: #FEF08A; color: #713F12; padding: 4px 8px; border-radius: 4px; font-weight: 600; }
    .badge-exceed { background-color: #FDE8E8; color: #9B1C1C; padding: 4px 8px; border-radius: 4px; font-weight: 600; }
    </style>
    """,
    unsafe_allow_html=True,
)

# -----------------------------------------------------------------------------
# 2. SIDEBAR CONFIGURATION & DATABASE SETTINGS
# -----------------------------------------------------------------------------
st.sidebar.image("https://img.icons8.com/color/96/oracle-logo.png", width=64)
st.sidebar.title("System Controls")
st.sidebar.markdown("**DBMS Backend:** Oracle 21c (Docker)")

# Database Credentials
with st.sidebar.expander("🔌 Database Credentials", expanded=False):
    db_host = st.text_input("Host", value="localhost")
    db_port = st.number_input("Port", value=1521)
    db_service = st.text_input("Service / PDB", value="XEPDB1")
    db_user = st.text_input("Schema User", value="EXPENSE_APP")
    db_password = st.text_input("Password", value="ExpensePass123#", type="password")

# Instantiate DB Manager
db = OracleDatabaseManager(
    user=db_user,
    password=db_password,
    host=db_host,
    port=int(db_port),
    service_name=db_service,
)

# Check Driver Installation
if not ORACLEDB_AVAILABLE:
    st.sidebar.error("⚠️ `oracledb` Python driver missing!")
    st.sidebar.info(
        "To connect to Oracle, run:\n"
        "```bash\n/home/abhimanyu/myenv/bin/pip install oracledb\n```"
    )
else:
    test_btn = st.sidebar.button("Test DB Connection")
    if test_btn:
        ok, msg = db.test_connection()
        if ok:
            st.sidebar.success("Connection Healthy!")
            st.sidebar.caption(msg)
        else:
            st.sidebar.error(f"Connection Failed: {msg}")

# Temporal Scope Selector
st.sidebar.markdown("---")
st.sidebar.subheader("📅 Temporal Filter")
current_date = datetime.date.today()
selected_year = st.sidebar.selectbox("Year", options=[2024, 2025, 2026, 2027], index=2)
selected_month = st.sidebar.selectbox(
    "Month",
    options=list(range(1, 13)),
    index=current_date.month - 1,
    format_func=lambda m: datetime.date(2000, m, 1).strftime("%B"),
)

# -----------------------------------------------------------------------------
# 3. HEADER & ARCHITECTURAL SUMMARY
# -----------------------------------------------------------------------------
st.markdown('<div class="main-header">💳 Personal Expense Tracker</div>', unsafe_allow_html=True)
st.markdown(
    '<div class="sub-header">Tiered 3-Tier Enterprise Application | '
    '<b>Presentation:</b> Python Streamlit | <b>Logic & Integrity:</b> Oracle PL/SQL & Active DB Triggers</div>',
    unsafe_allow_html=True,
)

if not ORACLEDB_AVAILABLE:
    st.warning(
        "### ⚠️ Oracle Python Client Library Required\n"
        "The frontend is running, but the database driver `oracledb` is not installed in `/home/abhimanyu/myenv`.\n\n"
        "Please execute the following command in your terminal to enable live queries:\n"
        "```bash\n"
        "/home/abhimanyu/myenv/bin/pip install oracledb\n"
        "```\n"
        "*(Note: `python-oracledb` is Oracle's official successor to `cx_Oracle` and runs in pure Python Thin mode without needing Oracle Instant Client).* "
    )
    st.stop()

# -----------------------------------------------------------------------------
# 4. TAB NAVIGATION
# -----------------------------------------------------------------------------
tab_dashboard, tab_record, tab_budgets, tab_ledger, tab_architecture = st.tabs(
    [
        "📊 Dashboard & KPIs",
        "➕ Record Expense (PL/SQL)",
        "🎯 Budget Allocations",
        "📜 Transaction Ledger",
        "🏛️ Architecture & Audit",
    ]
)

# =============================================================================
# TAB 1: DASHBOARD & KPIS
# =============================================================================
with tab_dashboard:
    st.subheader(f"Financial Summary: {datetime.date(2000, selected_month, 1).strftime('%B')} {selected_year}")
    
    try:
        budgets_df = db.get_monthly_budgets(selected_month, selected_year)
        expenses_df = db.get_expenses_view(selected_month, selected_year)

        total_allocated = float(budgets_df["ALLOCATED_AMOUNT"].sum()) if not budgets_df.empty else 0.0
        total_spent = float(budgets_df["TOTAL_SPENT"].sum()) if not budgets_df.empty else 0.0
        net_balance = total_allocated - total_spent
        overall_utilization = (total_spent / total_allocated * 100) if total_allocated > 0 else 0.0

        # KPI Metrics Display
        col1, col2, col3, col4 = st.columns(4)
        col1.metric("Total Budget Allocated", f"₹ {total_allocated:,.2f}")
        col2.metric("Actual Expenditure", f"₹ {total_spent:,.2f}", delta=f"{overall_utilization:.1f}% used")
        col3.metric("Remaining Balance", f"₹ {net_balance:,.2f}", delta_color="inverse" if net_balance < 0 else "normal")
        col4.metric("Logged Transactions", f"{len(expenses_df)} records")

        st.markdown("---")

        # Visual Analytics
        if not budgets_df.empty and total_spent > 0:
            c1, c2 = st.columns([1, 1])

            with c1:
                st.markdown("#### Budget vs. Actual Expenditure")
                chart_data = budgets_df[["CATEGORY_NAME", "ALLOCATED_AMOUNT", "TOTAL_SPENT"]].copy()
                chart_data = chart_data.melt(
                    id_vars=["CATEGORY_NAME"],
                    value_vars=["ALLOCATED_AMOUNT", "TOTAL_SPENT"],
                    var_name="Metric",
                    value_name="Amount",
                )
                chart_data["Metric"] = chart_data["Metric"].replace(
                    {"ALLOCATED_AMOUNT": "Allocated Budget", "TOTAL_SPENT": "Actual Spent"}
                )
                st.bar_chart(data=chart_data, x="CATEGORY_NAME", y="Amount", color="Metric", stack=False)

            with c2:
                st.markdown("#### Spending Distribution by Category")
                pie_data = budgets_df[budgets_df["TOTAL_SPENT"] > 0][["CATEGORY_NAME", "TOTAL_SPENT"]].set_index("CATEGORY_NAME")
                st.bar_chart(pie_data, horizontal=True)

        elif budgets_df.empty:
            st.info("No budget entries found for this calendar month. Use the 'Budget Allocations' tab to set targets.")
        else:
            st.info("Zero expenditures recorded for this month so far. Add an expense using the 'Record Expense' tab!")

        # Detailed Breakdown Table
        st.markdown("#### Category-Wise Budget Health (Maintained by PL/SQL Trigger)")
        if not budgets_df.empty:
            display_b_df = budgets_df[[
                "CATEGORY_NAME", "CATEGORY_TYPE", "ALLOCATED_AMOUNT", "TOTAL_SPENT", 
                "REMAINING_BUDGET", "UTILIZATION_PCT", "STATUS", "LAST_UPDATED"
            ]].copy()
            st.dataframe(
                display_b_df.style.format({
                    "ALLOCATED_AMOUNT": "₹ {:,.2f}",
                    "TOTAL_SPENT": "₹ {:,.2f}",
                    "REMAINING_BUDGET": "₹ {:,.2f}",
                    "UTILIZATION_PCT": "{:.1f} %",
                }),
                use_container_width=True,
            )

    except Exception as e:
        st.error(f"Error querying dashboard metrics: {str(e)}")

# =============================================================================
# TAB 2: RECORD EXPENSE (PL/SQL STORED PROCEDURE)
# =============================================================================
with tab_record:
    st.subheader("📝 Record New Transaction via Stored Procedure")
    st.caption("Submitting this form invokes `SP_RECORD_EXPENSE`, triggering active integrity assertions.")

    try:
        categories_df = db.get_categories()
        modes_df = db.get_payment_modes()

        if categories_df.empty or modes_df.empty:
            st.warning("Master categories or payment modes are empty. Run `02_seed_data.sql` in Oracle.")
        else:
            cat_options = {
                f"{row['CATEGORY_NAME']} ({row['CATEGORY_TYPE']})": row["CATEGORY_ID"]
                for _, row in categories_df.iterrows()
            }
            mode_options = {
                row["MODE_NAME"]: row["MODE_ID"]
                for _, row in modes_df.iterrows()
            }

            with st.form("frm_expense_entry", clear_on_submit=True):
                col_a, col_b = st.columns(2)
                with col_a:
                    selected_cat_label = st.selectbox("Category", options=list(cat_options.keys()))
                    amount_input = st.number_input("Amount (INR)", min_value=1.0, value=500.0, step=50.0)
                    merchant_input = st.text_input("Merchant / Beneficiary", placeholder="e.g. Swiggy, DMart, Shell Petrol")

                with col_b:
                    selected_mode_label = st.selectbox("Payment Instrument", options=list(mode_options.keys()))
                    expense_date_input = st.date_input("Transaction Date", value=datetime.date.today())
                    desc_input = st.text_input("Description / Notes", placeholder="e.g. Weekly family grocery run")

                submit_btn = st.form_submit_button("⚡ Execute Stored Procedure: SP_RECORD_EXPENSE")

                if submit_btn:
                    cat_id = cat_options[selected_cat_label]
                    m_id = mode_options[selected_mode_label]

                    with st.spinner("Invoking Oracle PL/SQL Engine..."):
                        success, exp_id, status_code, status_msg = db.record_expense(
                            category_id=cat_id,
                            mode_id=m_id,
                            amount=float(amount_input),
                            expense_date=expense_date_input,
                            description=desc_input,
                            merchant_name=merchant_input,
                        )

                    if success:
                        if status_code == "BUDGET_EXCEEDED":
                            st.error(f"🚨 **{status_code}**: {status_msg}")
                        elif status_code == "BUDGET_WARNING":
                            st.warning(f"⚠️ **{status_code}**: {status_msg}")
                        else:
                            st.success(f"✅ **{status_code}**: {status_msg}")
                        st.balloons()
                    else:
                        st.error(f"❌ Execution Failure: {status_msg}")

    except Exception as e:
        st.error(f"Application Fault: {str(e)}")

# =============================================================================
# TAB 3: BUDGET ALLOCATIONS
# =============================================================================
with tab_budgets:
    st.subheader(f"🎯 Target Spending Allocations ({datetime.date(2000, selected_month, 1).strftime('%B')} {selected_year})")
    st.caption("Modifies `MONTHLY_BUDGETS` via `PKG_EXPENSE_MGMT.SP_SET_MONTHLY_BUDGET`.")

    try:
        categories_df = db.get_categories()
        existing_budgets = db.get_monthly_budgets(selected_month, selected_year)

        # Merge for complete display
        with st.form("frm_set_budget"):
            st.markdown("##### Update Category Budget Cap")
            col_b1, col_b2 = st.columns(2)
            with col_b1:
                b_cat = st.selectbox(
                    "Target Category",
                    options=categories_df["CATEGORY_NAME"].tolist(),
                )
                cat_id_sel = categories_df[categories_df["CATEGORY_NAME"] == b_cat]["CATEGORY_ID"].values[0]

            with col_b2:
                # Find current allocation if exists
                cur_val = 10000.0
                if not existing_budgets.empty:
                    m = existing_budgets[existing_budgets["CATEGORY_ID"] == cat_id_sel]
                    if not m.empty:
                        cur_val = float(m["ALLOCATED_AMOUNT"].values[0])
                new_allocation = st.number_input("New Monthly Cap (INR)", min_value=0.0, value=cur_val, step=500.0)

            save_budget_btn = st.form_submit_button("Update Allocation")
            if save_budget_btn:
                ok, msg = db.set_budget(int(cat_id_sel), selected_month, selected_year, float(new_allocation))
                if ok:
                    st.success(msg)
                    st.rerun()
                else:
                    st.error(msg)

    except Exception as e:
        st.error(f"Error loading budget manager: {str(e)}")

# =============================================================================
# TAB 4: TRANSACTION LEDGER
# =============================================================================
with tab_ledger:
    st.subheader(f"📜 Detailed Transaction Journal ({datetime.date(2000, selected_month, 1).strftime('%B')} {selected_year})")

    try:
        ledger_df = db.get_expenses_view(selected_month, selected_year)

        if ledger_df.empty:
            st.info("No recorded transactions found for the selected month.")
        else:
            st.dataframe(
                ledger_df.style.format({"AMOUNT": "₹ {:,.2f}"}),
                use_container_width=True,
            )

            # Deletion Harness to demonstrate Trigger Back-propagation
            st.markdown("---")
            st.markdown("##### 🗑️ Revoke / Delete Transaction")
            st.caption("Demonstrates the `AFTER DELETE` Trigger: Automatically reverts the spent sum in `MONTHLY_BUDGETS`.")

            del_col1, del_col2 = st.columns([2, 1])
            with del_col1:
                selected_del_id = st.selectbox(
                    "Select Expense Record to Delete",
                    options=ledger_df["EXPENSE_ID"].tolist(),
                    format_func=lambda x: f"ID #{x} - ₹ {ledger_df[ledger_df['EXPENSE_ID']==x]['AMOUNT'].values[0]:,.2f} ({ledger_df[ledger_df['EXPENSE_ID']==x]['CATEGORY_NAME'].values[0]} - {ledger_df[ledger_df['EXPENSE_ID']==x]['MERCHANT_NAME'].values[0]})"
                )
            with del_col2:
                st.write("")
                st.write("")
                if st.button("Confirm Deletion", type="secondary"):
                    ok, msg = db.delete_expense(selected_del_id)
                    if ok:
                        st.success(msg)
                        st.rerun()
                    else:
                        st.error(msg)

    except Exception as e:
        st.error(f"Error retrieving transaction journal: {str(e)}")

# =============================================================================
# TAB 5: ARCHITECTURE & AUDIT
# =============================================================================
with tab_architecture:
    st.subheader("🏛️ Enterprise Multi-Tier Architecture & Active System Traces")
    
    st.markdown(
        """
        ```
        +-------------------------------------------------------------+
        |                 PRESENTATION TIER (Python)                  |
        |  Streamlit Event Loop -> Session State -> UI Input Forms    |
        +------------------------------+------------------------------+
                                       | PEP-249 DB-API Driver
                                       | python-oracledb (Thin Mode)
                                       v
        +-------------------------------------------------------------+
        |                  DATA ACCESS LAYER (db.py)                  |
        |  TCP Socket on Port 1521 -> Two-Task TNS Wire Protocol      |
        +------------------------------+------------------------------+
                                       |
                                       v
        +-------------------------------------------------------------+
        |                ORACLE RDBMS ENGINE (Container)              |
        |  1. SGA Shared Pool -> Bytecode Parsing (Cached Cursor)     |
        |  2. Execution Engine -> SP_RECORD_EXPENSE                   |
        |  3. Active Database Engine -> TRG_MAINTAIN_MONTHLY_BUDGET   |
        |  4. Autonomous Transaction -> EXPENSE_AUDIT_LOG Commit      |
        |  5. Buffer Cache & Redo Log Buffer -> ACID Persistence      |
        +-------------------------------------------------------------+
        ```
        """
    )

    st.markdown("#### 🔒 Live Autonomous Audit Trail (EXPENSE_AUDIT_LOG)")
    try:
        audit_df = db.get_audit_logs(limit=25)
        if audit_df.empty:
            st.info("Audit log is currently empty.")
        else:
            st.dataframe(audit_df, use_container_width=True)
    except Exception as e:
        st.error(f"Unable to read audit logs: {str(e)}")
