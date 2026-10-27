---
name: prd-to-silver
description: "Evaluate a PRD (product requirements document) and produce a structured change plan for a target Dynamic Table. Use when the user has a requirements file (XLSX, CSV, or markdown) describing new sources, column mappings, or business rules that need to be translated into a Dynamic Table update. Triggers: 'PRD to silver', 'evaluate PRD', 'new source onboarding', 'translate requirements to DT', 'apply PRD to pipeline'."
---

# PRD-to-Silver Evaluator

Turn a PRD-style requirements file into a reviewable, structured change plan for a target Dynamic Table.

## When to Use

- A business team delivers a requirements document (XLSX, CSV, or markdown) describing new sources, field mappings, or business rules
- You need to translate those requirements into a concrete Dynamic Table modification plan
- You want consistent output shape across multiple PRD evaluations so plans are comparable

## Inputs

| Parameter | Required | Description |
|-----------|----------|-------------|
| `prd_path` | Yes | Path to the PRD file (XLSX, CSV, or markdown). May be multiple files. |
| `target_dynamic_table` | Yes | Fully qualified name of the target DT (e.g., `COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES`) |

## Workflow

### Step 1: Read and Parse the PRD

**Goal:** Extract structured requirements from the file(s).

**Actions:**
1. Read the file at `prd_path` (support XLSX, CSV, and markdown)
2. For XLSX: read all sheets; look for tabs named like "Column Mapping", "Business Rules", "Source Onboarding"
3. Identify and categorize content into:
   - **Source systems** being added or modified
   - **Column mappings** (source column → Silver target column, transforms)
   - **Business rules** (status normalization, dedup logic, filters, etc.)
   - **Operational notes** (refresh timing, data arrival, contacts)

**Output:** A structured internal representation of all requirements.

### Step 2: Inspect the Current Dynamic Table

**Goal:** Understand the existing DT schema so the plan shows a delta, not a rebuild.

**Actions:**
1. Run `SELECT GET_DDL('DYNAMIC_TABLE', '<target_dynamic_table>')` to get current DDL
2. Run `DESCRIBE DYNAMIC TABLE <target_dynamic_table>` to get current columns
3. Run a proof query: `SELECT SOURCE_SYSTEM, COUNT(*) FROM <target_dynamic_table> GROUP BY SOURCE_SYSTEM`

**Output:** Current schema baseline for comparison.

### Step 3: Generate the Change Plan

**Goal:** Produce a structured, reviewable plan.

**Actions:**
1. Compare PRD requirements against current DT state
2. For each new source: draft the UNION ALL branch with column aliases and transforms
3. For each business rule: specify the SQL implementation (CASE, QUALIFY, etc.)
4. Identify columns being added, removed, or transformed
5. Flag anything that requires a DT recreation vs. a simple ALTER

**CRITICAL — Assumptions vs. Decisions:**
- If the PRD is explicit → implement as stated
- If the PRD is ambiguous or contradictory → surface as an **Open Question** (never guess)
- If a reasonable default exists but isn't confirmed → surface as an **Assumption** with the default stated

### Step 4: Propose Validation Queries

**Goal:** Give the reviewer queries to verify the update worked.

**Actions:**
1. Row count by SOURCE_SYSTEM (before and after expected counts)
2. Distinct value checks for any normalized columns (e.g., APPROVAL_STATUS)
3. Null/orphan checks for required fields
4. Dedup verification if applicable

---

## Stopping Points

**After Step 3:** Present the full change plan to the user. Do NOT execute any DDL until the user explicitly approves.

**After Step 4:** Offer to execute the approved plan or save it as a SQL file.

---

## Output

Every invocation MUST return these five sections in this order:

### 1. Summary of Requested Changes
- New sources being added
- Existing sources being modified
- Business rules being introduced or changed

### 2. Source-to-Silver Mapping
A table for each new/modified source:

| Source Column | Silver Column | Type | Transform | Notes |
|---------------|---------------|------|-----------|-------|

### 3. Open Questions and Assumptions

**Open Questions** (require a human decision before implementation):
- List each ambiguity with context and options

**Assumptions** (reasonable defaults that will be used unless overridden):
- List each assumption with the default chosen and rationale

### 4. DDL Delta Plan
- Show the complete updated CREATE OR REPLACE DYNAMIC TABLE statement
- Highlight what changed vs. the current DDL (new UNION ALL branches, new CASE logic, etc.)
- Note if this requires a full DT recreation (it almost always does for schema changes)

### 5. Validation Queries
- SQL queries to verify correctness after implementation
- Expected results for each query

---

## Best Practices: Assumptions vs. Guessing

The most important principle in this skill: **never silently resolve ambiguity.**

| Situation | Correct Behavior |
|-----------|-----------------|
| PRD says "normalize status" but doesn't list all mappings | Open Question: "What should status X map to?" |
| PRD says "drop system columns" but doesn't list them | Assumption: "Dropping columns with source-specific prefixes (BAN_, WD_, etc.) — override if incorrect" |
| PRD has conflicting rules in two sections | Open Question: "Rule X says A, but Rule Y implies B — which takes precedence?" |
| PRD omits a field that exists in the source | Assumption: "Field Z not mentioned — assuming DROP at Silver. Override if it should be kept." |
| PRD uses vague language ("handle appropriately") | Open Question: "What does 'handle appropriately' mean for field X? Options: [A], [B], [C]" |

---

## Example Usage

```
$prd-to-silver
Context:
- prd_path: sample_business_requirements_column_mapping.csv
- target_dynamic_table: COCO_WORKSHOP.PIPELINE_LAB.SILVER_AP_INVOICES
```

Expected output: a structured plan showing Baan and Workday UNION ALL branches, status normalization CASE statements, Baan dedup QUALIFY logic, dropped columns, open questions about payment terms normalization, and validation queries proving 50 total rows after implementation.
