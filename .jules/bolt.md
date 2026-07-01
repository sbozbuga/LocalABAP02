## 2024-05-30 - Initial
## 2024-05-30 - Redundant COUNT(*) before SELECT
**Learning:** Checking for row existence using `SELECT COUNT(*)` before a `SELECT ... INTO TABLE` with the same `WHERE` condition is redundant and doubles database work. The internal table will naturally be empty and `sy-subrc` will be non-zero if no records exist.
**Action:** Always check if a preceeding `SELECT COUNT(*)` is truly necessary, or if its logic can be handled by evaluating the result of the main `SELECT` query.
