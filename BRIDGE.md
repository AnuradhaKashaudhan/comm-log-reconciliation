# Target Base Reconciliation Bridge

**Goal:** Reconcile the initial naive count of `communication_log` sends down to the finance target of **22** for merchant 501 in October 2026.

| Step | Description | Result | Reason |
|---|---|---|---|
| 0 | Naive `SELECT COUNT(*)` on `communication_log` | 30 | Starting point. All 30 rows in the raw dataset fall within the basic scope (merchant 501, type 2, Oct 2026). |
