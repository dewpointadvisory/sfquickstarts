✓  SQL_EXECUTE  Proof query: counts by source system
  Connection: demo
  SQL Result (2 rows × 4 cols)
  ┌─────┬───────────────┬───────────┬──────────────┬──────────────────┐
  │   # │ SOURCE_SYSTEM │ ROW_COUNT │ TOTAL_AMOUNT │ DISTINCT_VENDORS │
  ├─────┼───────────────┼───────────┼──────────────┼──────────────────┤
  │   1 │ ORACLE        │ 15        │ 589900.00    │ 8                │
  │   2 │ SAP           │ 15        │ 334601.25    │ 8                │
  └─────┴───────────────┴───────────┴──────────────┴──────────────────┘

* SELECT SOURCE_SYSTEM,
           COUNT(*)                  AS ROW_COUNT,
           SUM(INVOICE_AMOUNT)       AS TOTAL_AMOUNT,
           COUNT(DISTINCT VENDOR_ID) AS DISTINCT_VENDORS
    FROM   COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
    GROUP BY SOURCE_SYSTEM
    ORDER BY SOURCE_SYSTEM;

  ┌───────────────┬───────────┬──────────────┬──────────────────┐
  │ SOURCE_SYSTEM │ ROW_COUNT │ TOTAL_AMOUNT │ DISTINCT_VENDORS │
  ├───────────────┼───────────┼──────────────┼──────────────────┤
  │ ORACLE        │ 15        │ 589,900.00   │ 8                │
  ├───────────────┼───────────┼──────────────┼──────────────────┤
  │ SAP           │ 15        │ 334,601.25   │ 8                │
  └───────────────┴───────────┴──────────────┴──────────────────┘

  Re-run after adding Baan/Workday or modifying mappings — expect new rows in the result and totals to change predictably.
 › Authenticating to demo via https://login.microsoftonline.com/f7820606-70d7-4d6a-97df-4617a35883b8/saml2