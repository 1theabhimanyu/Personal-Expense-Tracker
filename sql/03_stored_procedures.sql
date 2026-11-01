-- ============================================================================
-- SCRIPT: 03_stored_procedures.sql
-- PROJECT: Personal Expense Tracker
-- AUTHOR: Senior Database Architect & Professor of Computer Science
-- PURPOSE: Enterprise PL/SQL Business Logic Layer (Encapsulation and Security)
-- ============================================================================

SET DEFINE OFF;
SET FEEDBACK ON;

-- ----------------------------------------------------------------------------
-- 1. PACKAGE SPECIFICATION: PKG_EXPENSE_MGMT
-- Declares the public API for transactional expense mutations and budget management.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE PKG_EXPENSE_MGMT AS
    -- User-defined Application Exceptions
    e_invalid_amount    EXCEPTION;
    e_category_inactive EXCEPTION;
    e_mode_inactive     EXCEPTION;
    e_future_date       EXCEPTION;
    
    PRAGMA EXCEPTION_INIT(e_invalid_amount, -20001);
    PRAGMA EXCEPTION_INIT(e_category_inactive, -20002);
    PRAGMA EXCEPTION_INIT(e_mode_inactive, -20003);
    PRAGMA EXCEPTION_INIT(e_future_date, -20004);

    -- Core Procedure: Ingest and Validate New Expense
    PROCEDURE SP_RECORD_EXPENSE (
        p_category_id      IN  NUMBER,
        p_mode_id          IN  NUMBER,
        p_amount           IN  NUMBER,
        p_expense_date     IN  DATE DEFAULT SYSDATE,
        p_description      IN  VARCHAR2 DEFAULT NULL,
        p_merchant_name    IN  VARCHAR2 DEFAULT NULL,
        p_expense_id       OUT NUMBER,
        p_status_code      OUT VARCHAR2,
        p_status_message   OUT VARCHAR2
    );

    -- Administrative Procedure: Upsert Monthly Budget Allocation
    PROCEDURE SP_SET_MONTHLY_BUDGET (
        p_category_id      IN  NUMBER,
        p_month            IN  NUMBER,
        p_year             IN  NUMBER,
        p_allocated_amount IN  NUMBER,
        p_status_message   OUT VARCHAR2
    );

    -- Autonomous Audit Logging Mechanism
    PROCEDURE SP_LOG_AUDIT (
        p_expense_id   IN NUMBER,
        p_action       IN VARCHAR2,
        p_old_amt      IN NUMBER,
        p_new_amt      IN NUMBER,
        p_cat_id       IN NUMBER,
        p_remarks      IN VARCHAR2
    );

END PKG_EXPENSE_MGMT;
/

-- ----------------------------------------------------------------------------
-- 2. PACKAGE BODY: PKG_EXPENSE_MGMT
-- Encapsulates compiled bytecode, procedural logic, and ACID transaction boundaries.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PACKAGE BODY PKG_EXPENSE_MGMT AS

    -- ------------------------------------------------------------------------
    -- AUTONOMOUS AUDIT LOGGING
    -- Executes in an isolated transaction context to guarantee audit permanence
    -- even if the outer parent transaction experiences a rollback.
    -- ------------------------------------------------------------------------
    PROCEDURE SP_LOG_AUDIT (
        p_expense_id   IN NUMBER,
        p_action       IN VARCHAR2,
        p_old_amt      IN NUMBER,
        p_new_amt      IN NUMBER,
        p_cat_id       IN NUMBER,
        p_remarks      IN VARCHAR2
    ) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO EXPENSE_AUDIT_LOG (
            expense_id,
            action_type,
            performed_by,
            performed_at,
            old_amount,
            new_amount,
            category_id,
            remarks
        ) VALUES (
            p_expense_id,
            p_action,
            NVL(SYS_CONTEXT('USERENV', 'SESSION_USER'), 'SYSTEM'),
            CURRENT_TIMESTAMP,
            p_old_amt,
            p_new_amt,
            p_cat_id,
            p_remarks
        );
        COMMIT; -- Independent commit boundary
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK; -- Protect audit boundary
    END SP_LOG_AUDIT;

    -- ------------------------------------------------------------------------
    -- RECORD EXPENSE PROCEDURE
    -- Atomic execution path: Validates -> Inserts -> Propagates to Active Triggers
    -- ------------------------------------------------------------------------
    PROCEDURE SP_RECORD_EXPENSE (
        p_category_id      IN  NUMBER,
        p_mode_id          IN  NUMBER,
        p_amount           IN  NUMBER,
        p_expense_date     IN  DATE DEFAULT SYSDATE,
        p_description      IN  VARCHAR2 DEFAULT NULL,
        p_merchant_name    IN  VARCHAR2 DEFAULT NULL,
        p_expense_id       OUT NUMBER,
        p_status_code      OUT VARCHAR2,
        p_status_message   OUT VARCHAR2
    ) IS
        v_cat_exists NUMBER;
        v_mode_exists NUMBER;
        v_eff_date   DATE;
        v_exp_month  NUMBER;
        v_exp_year   NUMBER;
        v_spent      NUMBER;
        v_allocated  NUMBER;
        v_b_status   VARCHAR2(20);
    BEGIN
        -- Phase A: Foundational Precondition Assertions
        IF p_amount IS NULL OR p_amount <= 0 THEN
            RAISE_APPLICATION_ERROR(-20001, 'Constraint Violation: Expense amount must be strictly positive.');
        END IF;

        v_eff_date := NVL(p_expense_date, TRUNC(SYSDATE));
        IF v_eff_date > (TRUNC(SYSDATE) + 1) THEN
            RAISE_APPLICATION_ERROR(-20004, 'Temporal Invalidation: Future-dated expense postings are restricted.');
        END IF;

        -- Verify Category validity and active lifecycle state
        SELECT COUNT(*) INTO v_cat_exists 
        FROM CATEGORIES 
        WHERE category_id = p_category_id AND is_active = 'Y';
        
        IF v_cat_exists = 0 THEN
            RAISE_APPLICATION_ERROR(-20002, 'Referential Integrity Error: Category ID ' || p_category_id || ' is inactive or non-existent.');
        END IF;

        -- Verify Payment Mode validity and active state
        SELECT COUNT(*) INTO v_mode_exists 
        FROM PAYMENT_MODES 
        WHERE mode_id = p_mode_id AND is_active = 'Y';
        
        IF v_mode_exists = 0 THEN
            RAISE_APPLICATION_ERROR(-20003, 'Referential Integrity Error: Payment Mode ID ' || p_mode_id || ' is invalid or disabled.');
        END IF;

        -- Phase B: Atomic DML Ingestion
        INSERT INTO EXPENSES (
            category_id,
            mode_id,
            amount,
            expense_date,
            description,
            merchant_name
        ) VALUES (
            p_category_id,
            p_mode_id,
            ROUND(p_amount, 2),
            v_eff_date,
            TRIM(p_description),
            TRIM(p_merchant_name)
        )
        RETURNING expense_id INTO p_expense_id;

        -- Phase C: Post-DML Inspection (Trigger has maintained MONTHLY_BUDGETS)
        v_exp_month := EXTRACT(MONTH FROM v_eff_date);
        v_exp_year  := EXTRACT(YEAR FROM v_eff_date);

        BEGIN
            SELECT total_spent, allocated_amount, status 
            INTO v_spent, v_allocated, v_b_status
            FROM MONTHLY_BUDGETS
            WHERE category_id = p_category_id 
              AND budget_month = v_exp_month 
              AND budget_year = v_exp_year;

            IF v_b_status = 'EXCEEDED' THEN
                p_status_code := 'BUDGET_EXCEEDED';
                p_status_message := 'Recorded successfully (ID: ' || p_expense_id || '). WARNING: Monthly budget exceeded! Spent: Rs ' || v_spent || ' / Cap: Rs ' || v_allocated;
            ELSIF v_b_status = 'WARNING' THEN
                p_status_code := 'BUDGET_WARNING';
                p_status_message := 'Recorded successfully (ID: ' || p_expense_id || '). Notice: Budget utilization above 85%! Spent: Rs ' || v_spent || ' / Cap: Rs ' || v_allocated;
            ELSE
                p_status_code := 'SUCCESS';
                p_status_message := 'Expense transaction logged successfully. Internal ID: ' || p_expense_id;
            END IF;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                p_status_code := 'SUCCESS';
                p_status_message := 'Expense recorded successfully (ID: ' || p_expense_id || '). No pre-allocated budget found for period.';
        END;

    EXCEPTION
        WHEN OTHERS THEN
            p_expense_id := NULL;
            p_status_code := 'ERROR';
            p_status_message := 'PL/SQL Execution Aborted [ORA' || SQLCODE || ']: ' || SQLERRM;
            RAISE;
    END SP_RECORD_EXPENSE;

    -- ------------------------------------------------------------------------
    -- SET / ADJUST MONTHLY BUDGET
    -- ------------------------------------------------------------------------
    PROCEDURE SP_SET_MONTHLY_BUDGET (
        p_category_id      IN  NUMBER,
        p_month            IN  NUMBER,
        p_year             IN  NUMBER,
        p_allocated_amount IN  NUMBER,
        p_status_message   OUT VARCHAR2
    ) IS
    BEGIN
        IF p_allocated_amount < 0 THEN
            RAISE_APPLICATION_ERROR(-20005, 'Budget allocation cannot be negative.');
        END IF;

        MERGE INTO MONTHLY_BUDGETS b
        USING (SELECT p_category_id AS cat_id, p_month AS b_month, p_year AS b_year FROM DUAL) src
        ON (b.category_id = src.cat_id AND b.budget_month = src.b_month AND b.budget_year = src.b_year)
        WHEN MATCHED THEN
            UPDATE SET 
                b.allocated_amount = p_allocated_amount,
                b.status = CASE 
                    WHEN b.total_spent > p_allocated_amount THEN 'EXCEEDED'
                    WHEN b.total_spent >= (0.85 * p_allocated_amount) THEN 'WARNING'
                    ELSE 'ACTIVE'
                END,
                b.last_updated = CURRENT_TIMESTAMP
        WHEN NOT MATCHED THEN
            INSERT (category_id, budget_month, budget_year, allocated_amount, total_spent, status)
            VALUES (p_category_id, p_month, p_year, p_allocated_amount, 0.00, 'ACTIVE');

        p_status_message := 'Budget successfully synchronized for period ' || p_year || '-' || LPAD(p_month, 2, '0');
    END SP_SET_MONTHLY_BUDGET;

END PKG_EXPENSE_MGMT;
/

-- ----------------------------------------------------------------------------
-- 3. STANDALONE CALLABLE WRAPPER
-- Provides direct procedure interface as required by standard specifications.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE SP_RECORD_EXPENSE (
    p_category_id      IN  NUMBER,
    p_mode_id          IN  NUMBER,
    p_amount           IN  NUMBER,
    p_expense_date     IN  DATE DEFAULT SYSDATE,
    p_description      IN  VARCHAR2 DEFAULT NULL,
    p_merchant_name    IN  VARCHAR2 DEFAULT NULL,
    p_expense_id       OUT NUMBER,
    p_status_code      OUT VARCHAR2,
    p_status_message   OUT VARCHAR2
) AS
BEGIN
    PKG_EXPENSE_MGMT.SP_RECORD_EXPENSE(
        p_category_id    => p_category_id,
        p_mode_id        => p_mode_id,
        p_amount         => p_amount,
        p_expense_date   => p_expense_date,
        p_description    => p_description,
        p_merchant_name  => p_merchant_name,
        p_expense_id     => p_expense_id,
        p_status_code    => p_status_code,
        p_status_message => p_status_message
    );
END SP_RECORD_EXPENSE;
/
