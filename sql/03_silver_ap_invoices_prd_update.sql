✓  SQL_EXECUTE  Create updated SILVER_AP_INVOICES with all 4 sources
  Connection: demo
  SQL Result (1 rows × 1 cols)
  ┌─────┬────────────────────────────────┐
  │   # │ status                         │
  ├─────┼────────────────────────────────┤
  │   1 │ Dynamic table SILVER_AP_INV... │
  └─────┴────────────────────────────────┘

* Now running validation.

✓  SQL_EXECUTE  Status normalization check
  Connection: demo
  SQL Result (2 rows × 1 cols)
  ┌─────┬─────────────────┐
  │   # │ APPROVAL_STATUS │
  ├─────┼─────────────────┤
  │   1 │ APPROVED        │
  │   2 │ PENDING         │
  └─────┴─────────────────┘

✓  SQL_EXECUTE  Baan dedup check
  Connection: demo
  0 row(s) affected.

✓  SQL_EXECUTE  Row counts by source
  Connection: demo
  SQL Result (4 rows × 3 cols) [ctrl+t to navigate]
  ┌─────┬───────────────┬───────────┬──────────────┐
  │   # │ SOURCE_SYSTEM │ ROW_COUNT │ TOTAL_AMOUNT │
  ├─────┼───────────────┼───────────┼──────────────┤
  │   1 │ BAAN          │ 10        │ 257600.00    │
  │   2 │ ORACLE        │ 15        │ 589900.00    │
  │   3 │ SAP           │ 15        │ 334601.25    │
  └─────┴───────────────┴───────────┴──────────────┘
  Rows 1-3/4

✓  SQL_EXECUTE  Null violations check
  Connection: demo
  0 row(s) affected.

* All validations pass. Here's the complete summary:

  ────────────────────────────────────────

  Updated Dynamic Table SQL

    CREATE OR REPLACE DYNAMIC TABLE COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
      TARGET_LAG = DOWNSTREAM
      WAREHOUSE = COCO_WORKSHOP_WH
    AS
    -- SAP
    SELECT
        INVOICE_ID, INVOICE_NUMBER, VENDOR_ID, VENDOR_NAME,
        INVOICE_DATE, DUE_DATE, INVOICE_AMOUNT, CURRENCY_CODE,
        PAYMENT_TERMS, PO_NUMBER, LINE_DESCRIPTION, GL_ACCOUNT,
        COST_CENTER, APPROVAL_STATUS, CREATED_AT,
        'SAP' AS SOURCE_SYSTEM
    FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_SAP_AP_INVOICES

    UNION ALL

    -- Oracle (VALIDATED→APPROVED)
    SELECT
        INV_ID, INV_NUM, SUPPLIER_ID, SUPPLIER_NAME,
        INV_DATE, PAYMENT_DUE_DATE, TOTAL_AMOUNT, CURRENCY,
        TERMS_CODE, PURCHASE_ORDER, DESCRIPTION, ACCOUNT_CODE,
        DEPT_CODE,
        CASE WHEN STATUS = 'VALIDATED' THEN 'APPROVED' ELSE STATUS END,
        CREATION_DATE, 'ORACLE'
    FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_ORACLE_AP_INVOICES

    UNION ALL

    -- Baan (POSTED→APPROVED, dedup on BAN_INVOICE_REF)
    SELECT
        BAN_INVOICE_ID, BAN_INVOICE_REF, BAN_VENDOR_CODE, BAN_VENDOR_DESC,
        BAN_INV_DATE, BAN_PAY_DATE, BAN_AMOUNT, BAN_CURR,
        BAN_PAY_TERMS, BAN_PO_REF, BAN_LINE_DESC, BAN_GL_CODE,
        BAN_COST_CTR,
        CASE WHEN BAN_STATUS = 'POSTED' THEN 'APPROVED' ELSE BAN_STATUS END,
        BAN_CREATED, 'BAAN'
    FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_BAAN_AP_INVOICES
    QUALIFY ROW_NUMBER() OVER (PARTITION BY BAN_INVOICE_REF ORDER BY BAN_CREATED DESC) = 1

    UNION ALL

    -- Workday (In Review→PENDING, Approved→APPROVED)
    SELECT
        WD_INVOICE_ID, WD_INVOICE_NUM, WD_SUPPLIER_ID, WD_SUPPLIER_NAME,
        WD_INVOICE_DATE, WD_DUE_DATE, WD_AMOUNT, WD_CURRENCY,
        WD_PAY_TERMS, WD_PO_NUMBER, WD_MEMO, WD_LEDGER_ACCOUNT,
        WD_COST_CENTER,
        CASE WHEN WD_APPROVAL_STATUS = 'In Review' THEN 'PENDING'
             ELSE UPPER(WD_APPROVAL_STATUS) END,
        WD_CREATED_DATE, 'WORKDAY'
    FROM COCO_WORKSHOP.SOURCE_DATA.BRONZE_WORKDAY_AP_INVOICES;

  ────────────────────────────────────────

  How the New Sources Map into the Common Schema

  Both Baan and Workday map 1:1 into the existing 16-column Silver schema:

  ┌──────────────────┬────────────────────────────────────────────────────┬──────────────────────────────────────┐
  │ Concept          │ Baan                                               │ Workday                              │
  ├──────────────────┼────────────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Invoice ID       │ BAN_INVOICE_ID                                     │ WD_INVOICE_ID                        │
  ├──────────────────┼────────────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Vendor           │ BAN_VENDOR_CODE / _DESC                            │ WD_SUPPLIER_ID / _NAME               │
  ├──────────────────┼────────────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Amounts          │ BAN_AMOUNT (negatives = credit memos)              │ WD_AMOUNT (positive only)            │
  ├──────────────────┼────────────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Status           │ POSTED→APPROVED, else pass-through                 │ Approved→APPROVED, In Review→PENDING │
  ├──────────────────┼────────────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Dropped cols     │ BAN_COMPANY (entity code)                          │ WD_TENANT_ID (US/London indicator)   │
  ├──────────────────┼────────────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Special handling │ Dedup on BAN_INVOICE_REF (known duplicate extract) │ None required                        │
  └──────────────────┴────────────────────────────────────────────────────┴──────────────────────────────────────┘

  ────────────────────────────────────────

  Assumptions Requiring Engineering Review

  1. Payment terms left as-is (BR-005). Silver now contains 4 formats: NET30, N30, N30, Net 30. If downstream reports group by payment terms, they will split what is logically the same term. A Gold-layer normalization
  or Silver CASE statement is needed once the decision is finalized.
  2. Baan dedup uses BAN_INVOICE_REF (not BAN_INVOICE_ID). The PRD states duplicates share the same BAN_INVOICE_REF but different BAN_INVOICE_ID values. We partition by BAN_INVOICE_REF and keep the latest BAN_CREATED.
  If dedup should use a different key, this needs correction.
  3. Workday UPPER() normalization. Workday sends mixed-case values (Approved). We apply UPPER() to all non-In Review values. If Workday introduces other statuses (e.g., Rejected), they will appear as REJECTED in Silver
   — confirm this is acceptable.
  4. No entity/org column in Silver. BAN_COMPANY and WD_TENANT_ID are dropped. If Finance later needs entity-level reporting, the join-back path is INVOICE_ID + SOURCE_SYSTEM → Bronze. Confirm this is sufficient.

  ────────────────────────────────────────

  Validation Results (all passing)

  ┌─────────────────┬───────────────────────────────────────────────────┐
  │ Check           │ Result                                            │
  ├─────────────────┼───────────────────────────────────────────────────┤
  │ Row counts      │ SAP=15, ORACLE=15, BAAN=10, WORKDAY=10 (50 total) │
  ├─────────────────┼───────────────────────────────────────────────────┤
  │ Status values   │ Only APPROVED and PENDING                         │
  ├─────────────────┼───────────────────────────────────────────────────┤
  │ Baan duplicates │ 0 (dedup working)                                 │
  ├─────────────────┼───────────────────────────────────────────────────┤
  │ Null violations │ 0 (all required fields populated)                 │
  └─────────────────┴───────────────────────────────────────────────────┘

  Validation queries to rerun after future changes:

    -- 1. Row counts by source
    SELECT SOURCE_SYSTEM, COUNT(*) AS ROW_COUNT, SUM(INVOICE_AMOUNT) AS TOTAL_AMOUNT
    FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
    GROUP BY SOURCE_SYSTEM ORDER BY SOURCE_SYSTEM;

    -- 2. Status normalization (expect only APPROVED, PENDING)
    SELECT DISTINCT APPROVAL_STATUS
    FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES ORDER BY 1;

    -- 3. Baan dedup (expect 0 rows)
    SELECT INVOICE_NUMBER, COUNT(*)
    FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
    WHERE SOURCE_SYSTEM = 'BAAN'
    GROUP BY INVOICE_NUMBER HAVING COUNT(*) > 1;

    -- 4. Required fields not null (expect 0 rows)
    SELECT SOURCE_SYSTEM, COUNT(*) AS NULL_VIOLATIONS
    FROM COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
    WHERE INVOICE_ID IS NULL OR VENDOR_ID IS NULL
       OR INVOICE_DATE IS NULL OR INVOICE_AMOUNT IS NULL
    GROUP BY SOURCE_SYSTEM;

  The pipeline is now live with all 4 sources producing 50 harmonized rows.