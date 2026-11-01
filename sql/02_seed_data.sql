-- ============================================================================
-- SCRIPT: 02_seed_data.sql
-- PROJECT: Personal Expense Tracker
-- AUTHOR: Senior Database Architect & Professor of Computer Science
-- PURPOSE: Injects standardized initial domain datasets and budget allocations.
-- ============================================================================

SET DEFINE OFF;
SET FEEDBACK ON;

-- Clear previous seed data
DELETE FROM MONTHLY_BUDGETS;
DELETE FROM EXPENSES;
DELETE FROM PAYMENT_MODES;
DELETE FROM CATEGORIES;
COMMIT;

-- ----------------------------------------------------------------------------
-- 1. SEED CATEGORIES
-- ----------------------------------------------------------------------------
INSERT INTO CATEGORIES (category_name, category_type, description) 
VALUES ('Groceries & Essentials', 'VARIABLE', 'Daily sustenance, supermarket items, food supplies');

INSERT INTO CATEGORIES (category_name, category_type, description) 
VALUES ('Housing & Rent', 'FIXED', 'Residential rent, maintenance dues, home insurance');

INSERT INTO CATEGORIES (category_name, category_type, description) 
VALUES ('Utilities & Bills', 'FIXED', 'Electricity, water, piped gas, high-speed broadband');

INSERT INTO CATEGORIES (category_name, category_type, description) 
VALUES ('Dining & Entertainment', 'DISCRETIONARY', 'Restaurants, streaming subscriptions, leisure outings');

INSERT INTO CATEGORIES (category_name, category_type, description) 
VALUES ('Healthcare & Fitness', 'VARIABLE', 'Pharmaceuticals, diagnostic tests, gym memberships');

INSERT INTO CATEGORIES (category_name, category_type, description) 
VALUES ('Transportation & Fuel', 'VARIABLE', 'Petrol, metro transit passes, cab services');

INSERT INTO CATEGORIES (category_name, category_type, description) 
VALUES ('Education & Upskilling', 'INVESTMENT', 'Textbooks, university fees, online certifications');

INSERT INTO CATEGORIES (category_name, category_type, description) 
VALUES ('Mutual Funds & Stocks', 'INVESTMENT', 'Systematic Investment Plans (SIP), capital market assets');

-- ----------------------------------------------------------------------------
-- 2. SEED PAYMENT MODES
-- ----------------------------------------------------------------------------
INSERT INTO PAYMENT_MODES (mode_name, description) VALUES ('UPI / Instant Transfer', 'Unified Payments Interface, Google Pay, PhonePe, QR pay');
INSERT INTO PAYMENT_MODES (mode_name, description) VALUES ('Credit Card', 'Revolving credit instruments, contactless POS payments');
INSERT INTO PAYMENT_MODES (mode_name, description) VALUES ('Debit Card', 'Direct checking/savings account point-of-sale debits');
INSERT INTO PAYMENT_MODES (mode_name, description) VALUES ('Net Banking', 'NEFT, RTGS, IMPS internet banking transactions');
INSERT INTO PAYMENT_MODES (mode_name, description) VALUES ('Cash', 'Physical fiat currency transactions');

COMMIT;

-- ----------------------------------------------------------------------------
-- 3. SEED INITIAL MONTHLY BUDGETS (For Current Calendar Year)
-- ----------------------------------------------------------------------------
DECLARE
    v_curr_year NUMBER := EXTRACT(YEAR FROM SYSDATE);
    v_curr_month NUMBER := EXTRACT(MONTH FROM SYSDATE);
BEGIN
    FOR cat IN (SELECT category_id, category_name FROM CATEGORIES) LOOP
        INSERT INTO MONTHLY_BUDGETS (
            category_id, 
            budget_month, 
            budget_year, 
            allocated_amount, 
            total_spent, 
            status
        ) VALUES (
            cat.category_id,
            v_curr_month,
            v_curr_year,
            CASE 
                WHEN cat.category_name LIKE 'Housing%' THEN 25000.00
                WHEN cat.category_name LIKE 'Groceries%' THEN 12000.00
                WHEN cat.category_name LIKE 'Dining%' THEN 6000.00
                WHEN cat.category_name LIKE 'Utilities%' THEN 4500.00
                WHEN cat.category_name LIKE 'Transportation%' THEN 5000.00
                WHEN cat.category_name LIKE 'Healthcare%' THEN 4000.00
                WHEN cat.category_name LIKE 'Education%' THEN 8000.00
                ELSE 10000.00
            END,
            0.00,
            'ACTIVE'
        );
    END LOOP;
    COMMIT;
END;
/
