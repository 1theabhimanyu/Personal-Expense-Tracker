-- ============================================================================
-- SCRIPT: 01_schema_ddl.sql
-- PROJECT: Personal Expense Tracker (Enterprise PL/SQL Architecture)
-- AUTHOR: Senior Database Architect & Professor of Computer Science
-- TARGET RDBMS: Oracle Database 19c / 21c (Pluggable Database: XEPDB1)
-- NORMALIZATION: BCNF / 3NF Compliant Relational Schema
-- ============================================================================

SET SQLBLANKLINES ON;
SET FEEDBACK ON;

-- ----------------------------------------------------------------------------
-- 1. DROP EXISTING OBJECTS (Idempotent Setup)
-- ----------------------------------------------------------------------------
BEGIN
    FOR rec IN (
        SELECT table_name FROM user_tables 
        WHERE table_name IN ('EXPENSE_AUDIT_LOG', 'EXPENSES', 'MONTHLY_BUDGETS', 'PAYMENT_MODES', 'CATEGORIES')
    ) LOOP
        EXECUTE IMMEDIATE 'DROP TABLE ' || rec.table_name || ' CASCADE CONSTRAINTS PURGE';
    END LOOP;
END;
/

-- ----------------------------------------------------------------------------
-- 2. DOMAIN TABLE: CATEGORIES
-- Captures the functional taxonomy of expenses.
-- Normal Form: Boyce-Codd Normal Form (BCNF)
-- ----------------------------------------------------------------------------
CREATE TABLE CATEGORIES (
    category_id     NUMBER GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1),
    category_name   VARCHAR2(50)   NOT NULL,
    category_type   VARCHAR2(20)   DEFAULT 'DISCRETIONARY' NOT NULL,
    description     VARCHAR2(255),
    is_active       CHAR(1)        DEFAULT 'Y' NOT NULL,
    created_at      TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT pk_categories PRIMARY KEY (category_id),
    CONSTRAINT uq_categories_name UNIQUE (category_name),
    CONSTRAINT ck_categories_type CHECK (category_type IN ('FIXED', 'VARIABLE', 'DISCRETIONARY', 'INVESTMENT')),
    CONSTRAINT ck_categories_active CHECK (is_active IN ('Y', 'N'))
);

COMMENT ON TABLE CATEGORIES IS 'Master catalog of financial expenditure classifications.';
COMMENT ON COLUMN CATEGORIES.category_type IS 'Economic classification: FIXED (rent), VARIABLE (groceries), DISCRETIONARY (dining), INVESTMENT (stocks).';

-- ----------------------------------------------------------------------------
-- 3. DOMAIN TABLE: PAYMENT_MODES
-- Captures payment instruments (Cash, Credit Card, UPI, Net Banking, Debit Card).
-- ----------------------------------------------------------------------------
CREATE TABLE PAYMENT_MODES (
    mode_id         NUMBER GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1),
    mode_name       VARCHAR2(30)   NOT NULL,
    description     VARCHAR2(100),
    is_active       CHAR(1)        DEFAULT 'Y' NOT NULL,
    CONSTRAINT pk_payment_modes PRIMARY KEY (mode_id),
    CONSTRAINT uq_payment_modes_name UNIQUE (mode_name),
    CONSTRAINT ck_payment_modes_active CHECK (is_active IN ('Y', 'N'))
);

COMMENT ON TABLE PAYMENT_MODES IS 'Financial instruments and settlement conduits utilized for transactions.';

-- ----------------------------------------------------------------------------
-- 4. STATE TABLE: MONTHLY_BUDGETS
-- Maintains pre-allocated spending caps and materialized aggregations per category per month.
-- Maintained automatically via Active Database Triggers.
-- ----------------------------------------------------------------------------
CREATE TABLE MONTHLY_BUDGETS (
    budget_id        NUMBER GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1),
    category_id      NUMBER         NOT NULL,
    budget_month     NUMBER(2)      NOT NULL,
    budget_year      NUMBER(4)      NOT NULL,
    allocated_amount NUMBER(12, 2)  NOT NULL,
    total_spent      NUMBER(12, 2)  DEFAULT 0.00 NOT NULL,
    status           VARCHAR2(20)   DEFAULT 'ACTIVE' NOT NULL,
    created_at       TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    last_updated     TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT pk_monthly_budgets PRIMARY KEY (budget_id),
    CONSTRAINT fk_budgets_category FOREIGN KEY (category_id) REFERENCES CATEGORIES(category_id) ON DELETE CASCADE,
    CONSTRAINT uq_budgets_cat_period UNIQUE (category_id, budget_month, budget_year),
    CONSTRAINT ck_budgets_month CHECK (budget_month BETWEEN 1 AND 12),
    CONSTRAINT ck_budgets_year CHECK (budget_year BETWEEN 2000 AND 2099),
    CONSTRAINT ck_budgets_allocated CHECK (allocated_amount >= 0),
    CONSTRAINT ck_budgets_spent CHECK (total_spent >= 0),
    CONSTRAINT ck_budgets_status CHECK (status IN ('ACTIVE', 'WARNING', 'EXCEEDED', 'CLOSED'))
);

COMMENT ON TABLE MONTHLY_BUDGETS IS 'Aggregated expenditure caps and live materialized spend tracking per period.';

-- ----------------------------------------------------------------------------
-- 5. TRANSACTION TABLE: EXPENSES
-- Atomic transactional journal of individual financial outflows.
-- ----------------------------------------------------------------------------
CREATE TABLE EXPENSES (
    expense_id      NUMBER GENERATED ALWAYS AS IDENTITY (START WITH 1001 INCREMENT BY 1),
    category_id     NUMBER         NOT NULL,
    mode_id         NUMBER         NOT NULL,
    amount          NUMBER(12, 2)  NOT NULL,
    expense_date    DATE           DEFAULT SYSDATE NOT NULL,
    description     VARCHAR2(255),
    merchant_name   VARCHAR2(100),
    created_at      TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT pk_expenses PRIMARY KEY (expense_id),
    CONSTRAINT fk_expenses_category FOREIGN KEY (category_id) REFERENCES CATEGORIES(category_id),
    CONSTRAINT fk_expenses_mode FOREIGN KEY (mode_id) REFERENCES PAYMENT_MODES(mode_id),
    CONSTRAINT ck_expenses_amount CHECK (amount > 0.00)
);

COMMENT ON TABLE EXPENSES IS 'Atomic ledger recording individual financial disbursements.';

-- ----------------------------------------------------------------------------
-- 6. AUDIT JOURNAL: EXPENSE_AUDIT_LOG
-- Autonomous ledger recording DML operations for governance and forensic integrity.
-- ----------------------------------------------------------------------------
CREATE TABLE EXPENSE_AUDIT_LOG (
    audit_id         NUMBER GENERATED ALWAYS AS IDENTITY (START WITH 1 INCREMENT BY 1),
    expense_id       NUMBER,
    action_type      VARCHAR2(10)   NOT NULL,
    performed_by     VARCHAR2(50)   NOT NULL,
    performed_at     TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    old_amount       NUMBER(12, 2),
    new_amount       NUMBER(12, 2),
    category_id      NUMBER,
    remarks          VARCHAR2(255),
    CONSTRAINT pk_audit_log PRIMARY KEY (audit_id),
    CONSTRAINT ck_audit_action CHECK (action_type IN ('INSERT', 'UPDATE', 'DELETE'))
);

COMMENT ON TABLE EXPENSE_AUDIT_LOG IS 'Immutable audit trace capturing all DML lifecycle events on expense records.';

-- ----------------------------------------------------------------------------
-- 7. PERFORMANCE TUNING: B-TREE INDEXES
-- Optimize foreign key joins, range queries, and period aggregations.
-- ----------------------------------------------------------------------------
CREATE INDEX idx_expenses_category_date ON EXPENSES(category_id, expense_date);
CREATE INDEX idx_expenses_mode ON EXPENSES(mode_id);
CREATE INDEX idx_expenses_date ON EXPENSES(expense_date);
CREATE INDEX idx_budgets_period ON MONTHLY_BUDGETS(budget_year, budget_month);

-- ----------------------------------------------------------------------------
-- 8. ANALYTICAL REPORTING VIEW
-- Denormalized semantic layer for direct presentation queries.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_EXPENSE_DETAILS AS
SELECT 
    e.expense_id,
    e.expense_date,
    TO_CHAR(e.expense_date, 'YYYY-MM') AS expense_period,
    EXTRACT(MONTH FROM e.expense_date) AS expense_month,
    EXTRACT(YEAR FROM e.expense_date)  AS expense_year,
    c.category_id,
    c.category_name,
    c.category_type,
    m.mode_id,
    m.mode_name,
    e.amount,
    e.merchant_name,
    e.description,
    e.created_at
FROM EXPENSES e
JOIN CATEGORIES c ON e.category_id = c.category_id
JOIN PAYMENT_MODES m ON e.mode_id = m.mode_id;

COMMIT;
