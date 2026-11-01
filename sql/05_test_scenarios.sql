-- ============================================================================
-- SCRIPT: 05_test_scenarios.sql
-- PROJECT: Personal Expense Tracker
-- AUTHOR: Senior Database Architect & Professor of Computer Science
-- PURPOSE: Automated Academic Test Suite & Verification Harness
-- ============================================================================

SET DEFINE OFF;
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_exp_id_1       NUMBER;
    v_status_code    VARCHAR2(50);
    v_status_msg     VARCHAR2(400);
    v_spent_before   NUMBER;
    v_spent_after    NUMBER;
    v_budget_status  VARCHAR2(20);
    v_groceries_id   NUMBER;
    v_upi_id         NUMBER;
    v_curr_month     NUMBER := EXTRACT(MONTH FROM SYSDATE);
    v_curr_year      NUMBER := EXTRACT(YEAR FROM SYSDATE);
    v_audit_count    NUMBER;
BEGIN
    DBMS_OUTPUT.PUT_LINE('================================================================');
    DBMS_OUTPUT.PUT_LINE('STARTING PL/SQL AUTOMATED VERIFICATION TEST HARNESS');
    DBMS_OUTPUT.PUT_LINE('================================================================');

    -- Resolve FK references
    SELECT category_id INTO v_groceries_id FROM CATEGORIES WHERE category_name LIKE 'Groceries%' AND ROWNUM = 1;
    SELECT mode_id INTO v_upi_id FROM PAYMENT_MODES WHERE mode_name LIKE 'UPI%' AND ROWNUM = 1;

    -- Query initial state of budget
    SELECT total_spent INTO v_spent_before 
    FROM MONTHLY_BUDGETS 
    WHERE category_id = v_groceries_id AND budget_month = v_curr_month AND budget_year = v_curr_year;

    DBMS_OUTPUT.PUT_LINE('[TEST 1] Initial Budget Spent for Groceries: Rs. ' || v_spent_before);

    -- Execute Procedure to record an expense of Rs 1,500.00
    SP_RECORD_EXPENSE(
        p_category_id    => v_groceries_id,
        p_mode_id        => v_upi_id,
        p_amount         => 1500.00,
        p_expense_date   => SYSDATE,
        p_description    => 'Supermarket weekly provision run',
        p_merchant_name  => 'Nature Fresh Mart',
        p_expense_id     => v_exp_id_1,
        p_status_code    => v_status_code,
        p_status_message => v_status_msg
    );

    DBMS_OUTPUT.PUT_LINE('[TEST 1 RESULT] Expense Logged ID: ' || v_exp_id_1 || ' | Status: ' || v_status_code);
    DBMS_OUTPUT.PUT_LINE('[TEST 1 MSG] ' || v_status_msg);

    -- Query budget state post-insertion to verify Trigger execution
    SELECT total_spent, status INTO v_spent_after, v_budget_status 
    FROM MONTHLY_BUDGETS 
    WHERE category_id = v_groceries_id AND budget_month = v_curr_month AND budget_year = v_curr_year;

    DBMS_OUTPUT.PUT_LINE('[TEST 2] Verifying Trigger Budget Synchronization:');
    DBMS_OUTPUT.PUT_LINE('   - Expected Spent: Rs. ' || (v_spent_before + 1500.00));
    DBMS_OUTPUT.PUT_LINE('   - Actual Spent:   Rs. ' || v_spent_after);
    DBMS_OUTPUT.PUT_LINE('   - Budget Status:  ' || v_budget_status);

    IF v_spent_after = (v_spent_before + 1500.00) THEN
        DBMS_OUTPUT.PUT_LINE('   >>> TEST 2 PASSED: Trigger maintained budget table flawlessly.');
    ELSE
        DBMS_OUTPUT.PUT_LINE('   >>> TEST 2 FAILED: Discrepancy detected in trigger aggregation.');
    END IF;

    -- Verify Audit Trail
    SELECT COUNT(*) INTO v_audit_count FROM EXPENSE_AUDIT_LOG WHERE expense_id = v_exp_id_1;
    DBMS_OUTPUT.PUT_LINE('[TEST 3] Audit Trail Verification: Found ' || v_audit_count || ' audit record(s).');
    IF v_audit_count > 0 THEN
        DBMS_OUTPUT.PUT_LINE('   >>> TEST 3 PASSED: Autonomous audit log verified.');
    END IF;

    -- Negative Test 1: Negative Amount Validation
    DBMS_OUTPUT.PUT_LINE('[TEST 4] Negative Testing: Attempting insertion with negative amount (-500)...');
    BEGIN
        SP_RECORD_EXPENSE(
            p_category_id    => v_groceries_id,
            p_mode_id        => v_upi_id,
            p_amount         => -500.00,
            p_expense_date   => SYSDATE,
            p_description    => 'Invalid entry test',
            p_merchant_name  => 'None',
            p_expense_id     => v_exp_id_1,
            p_status_code    => v_status_code,
            p_status_message => v_status_msg
        );
        DBMS_OUTPUT.PUT_LINE('   >>> TEST 4 FAILED: Negative amount was incorrectly permitted.');
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('   >>> TEST 4 PASSED: Expected exception trapped -> ' || SQLERRM);
    END;

    DBMS_OUTPUT.PUT_LINE('================================================================');
    DBMS_OUTPUT.PUT_LINE('ALL VERIFICATION HARNESS TESTS EXECUTED SUCCESSFULLY');
    DBMS_OUTPUT.PUT_LINE('================================================================');
    
    COMMIT;
END;
/
