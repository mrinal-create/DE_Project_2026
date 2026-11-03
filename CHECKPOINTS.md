# Checkpoints: Blinkit Grocery Delivery Database

**Final submission: Monday 23 November 2026, 11:59 PM.** **Individual analysis (CP5): Wed 25 and Thu 26 November 2026, in class time.** Evaluation runs 25 Nov – 2 Dec 2026.

Progress is checked automatically from GitHub every few hours. A checkpoint counts as done when its files
exist in your repository **on the default branch**, with real content, by the due date. Every member must
have commits; the tracker shows commit counts per author.

## Your two repositories

| Repo | What goes in it | Where it lives |
|------|-----------------|----------------|
| **DE repo** | This project, cloned from `edusatyaki/DBMS-Blinkit-Grocery-Delivery` and done phase by phase (`README.md`) | The DE repo your team already submitted in the form (usually `DE_Project_2026`) |
| **AP repo** | Normalization, ER diagram, tables and query timings for the app you are building in AP | The `*_AP_2026` repo your team already submitted |

### Set up the DE repo (CP0)
Clone this project and push it into **your team's own DE repo** (the DE repo link your team submitted in the
form, usually named `DE_Project_2026`). The tracker reads that repo, so do not create a new one, and do not fork.

```bash
git clone https://github.com/edusatyaki/DBMS-Blinkit-Grocery-Delivery.git
cd DBMS-Blinkit-Grocery-Delivery
git remote rename origin project
git remote add origin https://github.com/mrinal-create/DE_Project_2026.git
git push -u origin main
```

If the push is rejected because your DE repo already has a README or other commits, run
`git pull origin main --allow-unrelated-histories`, keep both sets of files, commit, and push again.

Then:
1. Add the other members as collaborators on your DE repo (Settings → Collaborators). Every member must commit.
2. Commit `team.json` (format in `README.md`, *Repository structure*) and fill the team table in `README.md`.
3. Unzip `seed_data.zip` locally and never commit the CSV files (`.gitignore` already excludes them).
4. If faculty update this project repo, get the changes with `git pull project main`.

## Checkpoint dates

| # | Due | Checkpoint | DE repo must contain | AP repo must contain |
|---|-----|------------|----------------------------------|----------------------|
| **CP0** | Tue 3 Nov 2026 | Setup | `queries/workload_30.sql`<br>`benchmarks/run_benchmark.sh`<br>`team.json` | — |
| **CP1** | Mon 16 Nov 2026 | Schema & normalization | `docs/01_problem_understanding.md`<br>`docs/02_schema_design.md`<br>`sql/01_schema.sql`<br>`sql/02_load_data.sql`<br>`diagrams/er_diagram.*` | `dbms/01_normalization.md` |
| **CP2** | Tue 17 Nov 2026 | Baseline timings | `docs/03_baseline_timings.md`<br>`benchmarks/results/baseline/summary.csv` | `dbms/02_er_diagram.*`<br>`dbms/03_schema.sql` |
| **CP3** | Thu 19 Nov 2026 | Optimization | `sql/05_indexes.sql`<br>`sql/06_optimized_queries.sql`<br>`docs/04_optimization_report.md`<br>`benchmarks/results/optimized/summary.csv` | `dbms/04_queries.sql` |
| **CP4** | Mon 23 Nov 2026 | Final submission | `docs/05_scalability_report.md`<br>`sql/08_partitioning.sql`<br>`benchmarks/results/large/summary.csv` | `dbms/05_query_timings.md`<br>`dbms/plans/` |
| **CP5** | Wed 25 – Thu 26 Nov 2026 | Individual analysis, in class time | — | — |

`*` means any image or PDF (`.png`, `.jpg`, `.svg`, `.pdf`). A folder entry means at least one file inside it.

## How to time queries (both repos)

- Run every query with `EXPLAIN (ANALYZE, BUFFERS)` in PostgreSQL and read the `Execution Time` line.
- Run each query **3 times** and report the **average** of the three times.
- Run write queries inside `BEGIN; … ROLLBACK;` so the data does not change.
- In the DE repo, `./benchmarks/run_benchmark.sh <database> baseline` does this for you and writes
  `summary.csv` with `avg_ms` for every query, plus the raw plans of all 3 runs.

## AP repo: what to submit (folder `dbms/`)

| File | Content |
|------|---------|
| `dbms/01_normalization.md` | The data of your AP app taken through **1NF → 2NF → 3NF**, and **BCNF** where possible (BCNF is optional). Show the tables and the functional dependencies at each step. |
| `dbms/02_er_diagram.png` | ER diagram: entities, attributes, primary and foreign keys, cardinality. |
| `dbms/03_schema.sql` | `CREATE TABLE` statements for the final tables, with keys and constraints. It must run on PostgreSQL. |
| `dbms/04_queries.sql` | Every SQL query your app uses, using JOINs where possible. Mark each one `-- READ` or `-- WRITE` and give it an id (`R1`, `R2`, … `W1`, …). |
| `dbms/05_query_timings.md` | The timing table below, one row per query. |
| `dbms/plans/` | The `EXPLAIN (ANALYZE, BUFFERS)` output of each run, one file per query. |

Timing table format for `dbms/05_query_timings.md`:

| Query | Type | What it does | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Scan type |
|-------|------|--------------|-----------:|-----------:|-----------:|-------------:|-----------|
| R1 | READ | Login by email | | | | | Index Scan |
| W1 | WRITE | Create order | | | | | — |

## Marks (evaluation matrix, 100)

| Category | Criteria | Marks |
|----------|----------|------:|
| AP Projects | Normalization 5 · ER diagram 5 · All SQL queries used 5 · Query analysis 5 | 20 |
| DE Projects | Query execution 10 · Code optimization 30 · Individual analysis 40 | 80 |
