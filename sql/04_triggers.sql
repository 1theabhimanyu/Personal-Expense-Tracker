-- ============================================================================
-- SCRIPT: 04_triggers.sql
-- PROJECT: Personal Expense Tracker
-- AUTHOR: Senior Database Architect & Professor of Computer Science
-- PURPOSE: Active Database System (ECA Paradigm) - Automatic Budget Synchronization
-- ============================================================================

SET DEFINE OFF;
SET FEEDBACK ON;

-- ----------------------------------------------------------------------------
-- TRIGGER: TRG_MAINTAIN_MONTHLY_BUDGET
-- Type: AFTER ROW TRIGGER on EXPENSES
-- ECA Specification:
--   - Event: INSERT, UPDATE, or DELETE on EXPENSES table
--   - Condition: Row-level execution (FOR EACH ROW)
--   - Action: Atomically aggregate total_spent in MONTHLY_BUDGETS,
--             reevaluate budget constraint statuses (ACTIVE/WARNING/EXCEEDED),
--             and invoke autonomous audit logging.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER TRG_MAINTAIN_MONTHLY_BUDGET
AFTER INSERT OR UPDATE OR DELETE ON EXPENSES
FOR EACH ROW
DECLARE
    v_old_m NUMBER;
    v_old_y NUMBER;
    v_new_m NUMBER;
    v_new_y NUMBER;
BEGIN
    -- ------------------------------------------------------------------------
    -- CASE 1: INSERTION OF AN EXPENSE
    -- ------------------------------------------------------------------------
    IF INSERTING THEN
        v_new_m := EXTRACT(MONTH FROM :NEW.expense_date);
        v_new_y := EXTRACT(YEAR FROM :NEW.expense_date);

        -- Attempt in-place atomic accumulation of expenditure
        UPDATE MONTHLY_BUDGETS
        SET total_spent = total_spent + :NEW.amount,
            status = CASE 
                WHEN (total_spent + :NEW.amount) > allocated_amount THEN 'EXCEEDED'
                WHEN (total_spent + :NEW.amount) >= (0.85 * allocated_amount) THEN 'WARNING'
                ELSE 'ACTIVE'
            END,
            last_updated = CURRENT_TIMESTAMP
        WHERE category_id = :NEW.category_id
          AND budget_month = v_new_m
          AND budget_year  = v_new_y;

        -- If no budget allocation existed for this category/period, dynamically initialize one
        IF SQL%ROWCOUNT = 0 THEN
            INSERT INTO MONTHLY_BUDGETS (
                category_id,
                budget_month,
                budget_year,
                allocated_amount,
                total_spent,
                status
            ) VALUES (
                :NEW.category_id,
                v_new_m,
                v_new_y,
                10000.00, -- Default baseline allocation
                :NEW.amount,
                CASE 
                    WHEN :NEW.amount > 10000.00 THEN 'EXCEEDED'
                    WHEN :NEW.amount >= 8500.00 THEN 'WARNING'
                    ELSE 'ACTIVE'
                END
            );
        END IF;

        -- Record immutable audit log entry
        PKG_EXPENSE_MGMT.SP_LOG_AUDIT(
            p_expense_id => :NEW.expense_id,
            p_action     => 'INSERT',
            p_old_amt    => NULL,
            p_new_amt    => :NEW.amount,
            p_cat_id     => :NEW.category_id,
            p_remarks    => 'Ledger insertion: ' || NVL(:NEW.description, 'No remarks')
        );

    -- ------------------------------------------------------------------------
    -- CASE 2: DELETION OF AN EXPENSE
    -- ------------------------------------------------------------------------
    ELSIF DELETING THEN
        v_old_m := EXTRACT(MONTH FROM :OLD.expense_date);
        v_old_y := EXTRACT(YEAR FROM :OLD.expense_date);

        UPDATE MONTHLY_BUDGETS
        SET total_spent = GREATEST(0, total_spent - :OLD.amount),
            status = CASE 
                WHEN GREATEST(0, total_spent - :OLD.amount) > allocated_amount THEN 'EXCEEDED'
                WHEN GREATEST(0, total_spent - :OLD.amount) >= (0.85 * allocated_amount) THEN 'WARNING'
                ELSE 'ACTIVE'
            END,
            last_updated = CURRENT_TIMESTAMP
        WHERE category_id = :OLD.category_id
          AND budget_month = v_old_m
          AND budget_year  = v_old_y;

        PKG_EXPENSE_MGMT.SP_LOG_AUDIT(
            p_expense_id => :OLD.expense_id,
            p_action     => 'DELETE',
            p_old_amt    => :OLD.amount,
            p_new_amt    => NULL,
            p_cat_id     => :OLD.category_id,
            p_remarks    => 'Ledger revocation: ' || NVL(:OLD.description, 'Deleted')
        );

    -- ------------------------------------------------------------------------
    -- CASE 3: MODIFICATION OF AN EXPENSE
    -- ------------------------------------------------------------------------
    ELSIF UPDATING THEN
        v_old_m := EXTRACT(MONTH FROM :OLD.expense_date);
        v_old_y := EXTRACT(YEAR FROM :OLD.expense_date);
        v_new_m := EXTRACT(MONTH FROM :NEW.expense_date);
        v_new_y := EXTRACT(YEAR FROM :NEW.expense_date);

        -- If temporal period or category remains unchanged, apply delta
        IF (v_old_m = v_new_m AND v_old_y = v_new_y AND :OLD.category_id = :NEW.category_id) THEN
            UPDATE MONTHLY_BUDGETS
            SET total_spent = GREATEST(0, total_spent + (:NEW.amount - :OLD.amount)),
                status = CASE 
                    WHEN GREATEST(0, total_spent + (:NEW.amount - :OLD.amount)) > allocated_amount THEN 'EXCEEDED'
                    WHEN GREATEST(0, total_spent + (:NEW.amount - :OLD.amount)) >= (0.85 * allocated_amount) THEN 'WARNING'
                    ELSE 'ACTIVE'
                END,
                last_updated = CURRENT_TIMESTAMP
            WHERE category_id = :NEW.category_id
              AND budget_month = v_new_m
              AND budget_year  = v_new_y;
        ELSE
            -- Cross-period or cross-category reclassification: Deduct from old, add to new
            UPDATE MONTHLY_BUDGETS
            SET total_spent = GREATEST(0, total_spent - :OLD.amount),
                status = CASE 
                    WHEN GREATEST(0, total_spent - :OLD.amount) > allocated_amount THEN 'EXCEEDED'
                    WHEN GREATEST(0, total_spent - :OLD.amount) >= (0.85 * allocated_amount) THEN 'WARNING'
                    ELSE 'ACTIVE'
                END,
                last_updated = CURRENT_TIMESTAMP
            WHERE category_id = :OLD.category_id
              AND budget_month = v_old_m
              AND budget_year  = v_old_y;

            UPDATE MONTHLY_BUDGETS
            SET total_spent = total_spent + :NEW.amount,
                status = CASE 
                    WHEN (total_spent + :NEW.amount) > allocated_amount THEN 'EXCEEDED'
                    WHEN (total_spent + :NEW.amount) >= (0.85 * allocated_amount) THEN 'WARNING'
                    ELSE 'ACTIVE'
                END,
                last_updated = CURRENT_TIMESTAMP
            WHERE category_id = :NEW.category_id
              AND budget_month = v_new_m
              AND budget_year  = v_new_y;
        END IF;

        PKG_EXPENSE_MGMT.SP_LOG_AUDIT(
            p_expense_id => :NEW.expense_id,
            p_action     => 'UPDATE',
            p_old_amt    => :OLD.amount,
            p_new_amt    => :NEW.amount,
            p_cat_id     => :NEW.category_id,
            p_remarks    => 'Ledger modification: ' || NVL(:NEW.description, 'Updated')
        );

    END IF;
END TRG_MAINTAIN_MONTHLY_BUDGET;
/
