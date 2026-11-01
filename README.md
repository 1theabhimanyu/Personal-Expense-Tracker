# Personal Expense Tracker: An Enterprise 3-Tier Database System
### Oracle Database 21c (PL/SQL Backend) & Python Streamlit (Reactive GUI Frontend)

**Course:** Advanced Database Management Systems (Semester Project)  
**Academic Role:** Senior Database Architect & Professor of Computer Science  
**Workspace Directory:** `/home/abhimanyu/PLSQL projects for SEMS 1`  
**Virtual Environment:** `/home/abhimanyu/myenv/bin`  

---

## 1. Executive Abstract & System Overview

Modern enterprise transaction systems demand a clear separation of concerns between the **Presentation Tier**, the **Business Logic Tier**, and the **Data Integrity Tier**. In many naive web applications, data validation and domain constraints are deferred to the application layer (e.g., Python, JavaScript). This architecture introduces critical vulnerabilities: data integrity can be compromised by rogue API calls, uncoordinated concurrent updates, or multiple disparate client applications modifying the database without uniform rules.

This semester project implements a **Personal Expense Tracker** designed under the strict architectural philosophy of **Database-Centric Integrity and Active Database Systems (ECA Paradigm)**.

### Architectural Tiers
1. **Presentation Tier (Python Streamlit):** Provides a reactive, immediate-mode Graphical User Interface (GUI) for interactive financial analytics, transactional data entry, and budget cap adjustments.
2. **Connectivity Tier (python-oracledb Thin Driver):** Implements the Python DB-API 2.0 (PEP 249) standard over pure TCP/IP, transmitting Oracle Net (TNS) packets directly to the database without requiring client-side native binary libraries.
3. **Database & Logic Tier (Oracle 21c PL/SQL):** Encapsulates the entire domain logic inside compiled Stored Procedures (`SP_RECORD_EXPENSE`), maintains materialized monthly aggregates via declarative Row-Level Active Triggers (`TRG_MAINTAIN_MONTHLY_BUDGET`), and audits mutations via `AUTONOMOUS_TRANSACTION` routines.

```
+-------------------------------------------------------------------------+
|                       PRESENTATION TIER (Client)                        |
|   Streamlit Reactive UI (app.py) <---> Browser WebSocket / DOM Events   |
+------------------------------------+------------------------------------+
                                     |
                                     | Python DB-API 2.0 (oracledb Thin)
                                     v
+-------------------------------------------------------------------------+
|                       DATA ACCESS LAYER (db.py)                         |
|   TCP Connection (Port 1521) | SQL Parameter Binding | Cursor Pooling    |
+------------------------------------+------------------------------------+
                                     |
                                     | Oracle Net / TNS Protocol
                                     v
+-------------------------------------------------------------------------+
|                  BACKEND ENGINE: ORACLE DATABASE 21c                    |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  | PL/SQL Stored Procedure (PKG_EXPENSE_MGMT.SP_RECORD_EXPENSE)      |  |
|  | - Parameter Assertion (Amount > 0, Active Category, Valid Mode)    |  |
|  | - Atomic DML Ingestion (INSERT INTO EXPENSES ... RETURNING ID)    |  |
|  +---------------------------------+---------------------------------+  |
|                                    |                                    |
|                                    | Fires Event-Condition-Action (ECA) |
|                                    v                                    |
|  +-------------------------------------------------------------------+  |
|  | Active Database Trigger (TRG_MAINTAIN_MONTHLY_BUDGET)             |  |
|  | - AFTER INSERT/UPDATE/DELETE FOR EACH ROW                         |  |
|  | - Synchronizes MONTHLY_BUDGETS.total_spent                        |  |
|  | - Dynamically Transitions Status: ACTIVE -> WARNING -> EXCEEDED   |  |
|  +---------------------------------+---------------------------------+  |
|                                    |                                    |
|                                    | Calls Isolated Sub-Transaction     |
|                                    v                                    |
|  +-------------------------------------------------------------------+  |
|  | Autonomous Audit Trail (EXPENSE_AUDIT_LOG)                        |  |
|  | - PRAGMA AUTONOMOUS_TRANSACTION; Independent Commit               |  |
|  +-------------------------------------------------------------------+  |
|                                                                         |
|  +-------------------------------------------------------------------+  |
|  | Relational Storage: CATEGORIES, PAYMENT_MODES, MONTHLY_BUDGETS,   |  |
|  |                     EXPENSES, EXPENSE_AUDIT_LOG (BCNF Normalized) |  |
|  +-------------------------------------------------------------------+  |
+-------------------------------------------------------------------------+
```

---

## 2. Foundational Basics & Formal Academic Definitions

To satisfy academic rigor, the fundamental theoretical concepts governing this project are formally defined:

### 2.1 Active Database Systems (The ECA Paradigm)
> **Definition:** An **Active Database Management System (ADBMS)** is a database system that automatically executes defined operations in response to the occurrence of specific internal or external events, following the **Event-Condition-Action (ECA)** paradigm, without requiring manual invocation from an external application client.
- **Event:** A database modification (e.g., `INSERT`, `UPDATE`, `DELETE` on the `EXPENSES` table) or temporal schedule.
- **Condition:** A predicate evaluated when the event occurs (e.g., verifying whether `:NEW.amount > 0` or evaluating current budget utilization thresholds).
- **Action:** An executable sequence of database operations (e.g., adjusting `MONTHLY_BUDGETS.total_spent` and recalculating state flags).
*Contrast:* A **Passive DBMS** only executes queries and updates when explicitly commanded by external application programs.

### 2.2 Stored Procedures and Procedural Abstraction
> **Definition:** A **Stored Procedure** is a named, precompiled collection of procedural SQL statements and procedural control structures (PL/SQL) stored directly within the database data dictionary.
- **Advantages:**
  1. **Reduction in Network Latency:** Multiple discrete SQL statements are batched and executed within the database server's local memory space (SGA/PGA), eliminating multiple network round-trips over client-server sockets.
  2. **Security Boundary & Least Privilege:** External clients are granted `EXECUTE` privileges on procedures while `INSERT`/`UPDATE` privileges on raw base tables are revoked, preventing direct unauthorized table mutations and SQL injection.
  3. **Compilation & Plan Caching:** Stored procedures are parsed, validated, and compiled into bytecode (M-code) upon creation, generating cached execution plans that bypass runtime parsing overhead.

### 2.3 GUI Frameworks & Reactive Immediate-Mode Architecture
> **Definition:** A **Graphical User Interface (GUI) Framework** provides abstractions for windowing, user input dispatching, and state visualization.
- **Streamlit** utilizes an **Immediate-Mode Execution Model**: rather than maintaining long-lived mutable widget trees in client memory (as in Retained-Mode frameworks like JavaFX or Qt), Streamlit re-executes the Python script from top to bottom whenever user interaction alters the application state. High performance is maintained through session-state caching and memoization (`@st.cache_data`).

### 2.4 Database Drivers: `cx_Oracle` vs. `python-oracledb` (Thin vs. Thick Mode)
> **Definition:** A **Database Driver** is a client-side software module implementing an Application Programming Interface (API) to serialize application queries into vendor-specific network wire protocols.
- **cx_Oracle (Legacy Thick Mode):** Relied on native C dynamic libraries (`libclntsh.so` / Oracle Instant Client) installed on the host operating system, communicating through Oracle Net.
- **python-oracledb (Modern Thin Mode):** A 100% pure Python implementation of the Oracle Net / TNS protocol. It communicates directly over standard TCP/IP sockets to port 1521 without requiring any native C binaries or client installations, simplifying containerized and virtualized deployments.

---

## 3. Relational Schema Architecture & Normalization

The schema has been decomposed into **Boyce-Codd Normal Form (BCNF)** to guarantee zero insertion, update, or deletion anomalies.

### Mathematical Normalization Proof:
- **Relation: `CATEGORIES(category_id, category_name, category_type, description, is_active, created_at)`**
  - Functional Dependencies: `category_id -> {category_name, category_type, description, is_active, created_at}`; `category_name -> {category_id, ...}`.
  - Candidate Keys: `category_id`, `category_name`.
  - In every functional dependency $X \rightarrow Y$, $X$ is a superkey. Therefore, the relation is in **BCNF**.
- **Relation: `PAYMENT_MODES(mode_id, mode_name, description, is_active)`**
  - Candidate Keys: `mode_id`, `mode_name`. In BCNF.
- **Relation: `MONTHLY_BUDGETS(budget_id, category_id, budget_month, budget_year, allocated_amount, total_spent, status, created_at, last_updated)`**
  - Candidate Keys: `budget_id`, Composite: `{category_id, budget_month, budget_year}`.
  - Every determinant is a superkey. No partial or transitive dependencies exist. In BCNF.
- **Relation: `EXPENSES(expense_id, category_id, mode_id, amount, expense_date, description, merchant_name, created_at)`**
  - Candidate Key: `expense_id`.
  - Non-key attributes depend solely on the primary key `expense_id`. In BCNF.

---

## 4. Complete Project Directory Structure

```
/home/abhimanyu/PLSQL projects for SEMS 1/
│
├── README.md                      # Comprehensive Academic Project Documentation
├── requirements.txt               # Python package dependencies
├── run_app.sh                     # Virtual environment launcher script (Executable)
│
├── sql/
│   ├── 01_schema_ddl.sql          # BCNF DDL for Tables, Constraints, Indexes, Views
│   ├── 02_seed_data.sql           # Canonical Seed Records (Categories, Payment Modes, Budgets)
│   ├── 03_stored_procedures.sql   # PL/SQL Package PKG_EXPENSE_MGMT & SP_RECORD_EXPENSE
│   ├── 04_triggers.sql            # Active DB Trigger: TRG_MAINTAIN_MONTHLY_BUDGET
│   └── 05_test_scenarios.sql      # Autonomous Academic Verification & Test Harness
│
├── src/
│   ├── __init__.py                # Python package marker
│   ├── db.py                      # Data Access Layer (DAL) interfacing with Oracle
│   └── app.py                     # Streamlit Reactive Web Application
│
└── tests/
    └── test_db_connection.py      # Diagnostic CLI script for testing Oracle TCP handshake
```

---

## 5. End-to-End Dataflow Walkthrough

When a user records an expense of **₹ 1,500.00** for **Groceries & Essentials** via the Streamlit interface and clicks **"Execute Stored Procedure: SP_RECORD_EXPENSE"**, the following deterministic execution sequence occurs across the architectural stack:

```
[User Browser]
      | (1) User clicks 'Execute Stored Procedure'
      v
[Streamlit Server Event Loop (app.py)]
      | (2) Form inputs validated (amount > 0)
      | (3) Invokes db.record_expense(cat_id, mode_id, 1500, date, desc, merchant)
      v
[Data Access Layer (db.py)]
      | (4) Obtains Oracle TCP connection over port 1521
      | (5) Allocates out-bind variables: cursor.var(oracledb.NUMBER), cursor.var(oracledb.STRING)
      | (6) Serializes call: cursor.callproc('SP_RECORD_EXPENSE', [args...])
      v
[Oracle Net Wire Protocol (TNS Packets over TCP/IP)]
      v
[Oracle RDBMS 21c (Server Process)]
      | (7) Soft Parse: Shared Pool verifies cached bytecode for SP_RECORD_EXPENSE
      | (8) PL/SQL Engine executes SP_RECORD_EXPENSE:
      |     - Asserts business invariants (amount > 0, active category)
      |     - Acquires row-level exclusive locks (TX Enqueue)
      |     - Executes INSERT INTO EXPENSES (...) RETURNING expense_id INTO :out_id
      | (9) Active Database Event: INSERT triggers TRG_MAINTAIN_MONTHLY_BUDGET
      |     - Trigger calculates period (month, year)
      |     - Executes UPDATE MONTHLY_BUDGETS SET total_spent = total_spent + 1500
      |     - Reevaluates status: (total_spent > allocated) ? 'EXCEEDED' : 'ACTIVE'
      |     - Executes PRAGMA AUTONOMOUS_TRANSACTION: inserts entry into EXPENSE_AUDIT_LOG
      | (10) Procedure reads updated status from MONTHLY_BUDGETS into OUT parameters
      v
[Oracle Net Response Packets]
      | (11) Out-bind values returned to Python client
      v
[Data Access Layer (db.py)]
      | (12) conn.commit() commits the transaction (ACID durability guaranteed in Redo Log)
      | (13) Returns success flag, generated expense_id, status_code, and status_message
      v
[Streamlit Reactive Engine]
      | (14) UI rerenders: Displays success banner / budget utilization warnings
      | (15) KPIs and visual charts update dynamically to reflect the new ₹ 1,500 expense
```

---

## 6. Execution & Setup Instructions

### Step 1: Verify Oracle Database Container
The Oracle Database 21c Express Edition container runs under Docker:
```bash
# Verify the Oracle container is up and running on port 1521
docker ps
```
The project utilizes the Pluggable Database **`XEPDB1`** with user **`EXPENSE_APP`** (password: `ExpensePass123#`).

### Step 2: Install Python Driver (Thin Mode)
Activate your virtual environment and install the required driver:
```bash
/home/abhimanyu/myenv/bin/pip install oracledb
```
*(Note: `oracledb` Thin Mode connects directly to Oracle over TCP without requiring Oracle Instant Client binaries).*

### Step 3: Test Connectivity via CLI Diagnostic Script
Run the automated test probe:
```bash
/home/abhimanyu/myenv/bin/python "/home/abhimanyu/PLSQL projects for SEMS 1/tests/test_db_connection.py"
```

### Step 4: Launch the Streamlit Frontend GUI
Launch the web interface using the provided runner script:
```bash
bash "/home/abhimanyu/PLSQL projects for SEMS 1/run_app.sh"
```
Or directly:
```bash
cd "/home/abhimanyu/PLSQL projects for SEMS 1"
/home/abhimanyu/myenv/bin/streamlit run src/app.py
```
Open your browser at `http://localhost:8501`.

---

## 7. Master's Level Examination Preparation & Academic Practice

Below are two advanced examination problems designed for Master of Science / M.Tech / MCA level university examinations in Advanced Database Systems and Enterprise Systems Architecture.

---

### Question 1: Active Database Concurrency, The Mutating Table Problem (ORA-04091), and Transaction Isolation

#### Examination Question:
> **(a)** In the context of the Oracle RDBMS active database engine, define the **Mutating Table Problem** (`ORA-04091`). Under what precise relational and execution conditions does the Oracle kernel raise this error?  
> **(b)** In our Personal Expense Tracker system, explain why the trigger `TRG_MAINTAIN_MONTHLY_BUDGET` (defined `AFTER INSERT OR UPDATE OR DELETE ON EXPENSES FOR EACH ROW`) can safely modify the `MONTHLY_BUDGETS` table **without** encountering `ORA-04091`, whereas an equivalent row-level trigger attempting to aggregate `SELECT SUM(amount) FROM EXPENSES` would fail immediately.  
> **(c)** Compare and evaluate two architectural solutions to resolve the Mutating Table constraint when dynamic cross-row validation on the triggering table is mandatory: (i) Oracle 11g+ **Compound Triggers**, versus (ii) **Deferred Constraint Triggers with Temporary Staging Tables**.

---

#### Comprehensive Solution & Grading Rubric:

#### (a) Definition and Conditions of the Mutating Table Problem:
A **mutating table** is a table that is currently in the process of being modified by an active DML statement (such as `INSERT`, `UPDATE`, or `DELETE`), or a table that might be updated by the effects of a declarative `DELETE CASCADE` referential constraint.

The Oracle kernel raises exception **`ORA-04091: table string.string is mutating, trigger/function may not see it`** under the following strict conditions:
1. A **Row-Level Trigger** (`FOR EACH ROW`) is executing.
2. The code within the body of this row-level trigger attempts to execute a `SELECT`, `INSERT`, `UPDATE`, or `DELETE` on the **same table** that caused the trigger to fire, or on a table linked by a direct referential integrity constraint with `ON DELETE CASCADE`.
3. **Underlying Theoretical Rationale:** The relational engine enforces the **Statement-Level Read Consistency** model (Multiversion Concurrency Control / MVCC). During row-by-row processing of a set-based DML statement, the triggering table is in an intermediate, temporally inconsistent state. If a row-level trigger were permitted to read the entire table, different rows within the same statement would observe different aggregate snapshots of the table, violating the relational model's assertion that an entire SQL statement sees the database as of a single point in logical time (the System Commit Number / SCN at statement launch).

#### (b) Analysis of `TRG_MAINTAIN_MONTHLY_BUDGET`:
In our Expense Tracker implementation:
- The trigger is defined on table `EXPENSES`.
- The target of the trigger's DML statements is `MONTHLY_BUDGETS` and `EXPENSE_AUDIT_LOG`.
- **Reason for Absence of ORA-04091:** `MONTHLY_BUDGETS` is a distinct relational entity with its own storage segments, blocks, and lock structures. `EXPENSES` has a foreign key referencing `CATEGORIES`, but **not** a foreign key referencing `MONTHLY_BUDGETS`. Because the trigger performs an in-place accumulation on `MONTHLY_BUDGETS` using only the values present in the pseudorecords (`:NEW.amount`, `:OLD.amount`, `:NEW.category_id`) and **never executes a query against `EXPENSES` itself**, the Oracle engine does not detect a mutation conflict.
- Conversely, if the trigger had executed `SELECT SUM(amount) INTO v_total FROM EXPENSES WHERE category_id = :NEW.category_id;`, the Oracle kernel would detect that `EXPENSES` is currently mutating and immediately raise `ORA-04091`.

#### (c) Evaluation of Architectural Solutions:
1. **Compound Triggers (`FOR COMPOUND TRIGGER`):**
   - *Mechanics:* Introduced in Oracle 11g, a Compound Trigger combines all four timing points (`BEFORE STATEMENT`, `BEFORE EACH ROW`, `AFTER EACH ROW`, `AFTER STATEMENT`) within a single declarative block sharing a common stateful memory context.
   - *Implementation:* During the `AFTER EACH ROW` phase, the trigger does not query the table; instead, it simply appends the affected keys (`:NEW.expense_id`, `:NEW.category_id`) to a PL/SQL associative array (in-memory collection). Once the DML operation finishes all row modifications, the `AFTER STATEMENT` section fires. At this point, the table is no longer mutating; the trigger inspects the memory collection and executes the set-based query or validation across the entire table safely.
   - *Trade-off:* Highly performant, requires minimal code, but consumes Program Global Area (PGA) memory proportional to the number of rows modified in bulk DML.
2. **Deferred Constraints with Staging Tables:**
   - *Mechanics:* A row-level trigger writes modified keys into a temporary global scratch table (`GLOBAL TEMPORARY TABLE`). A deferred constraint (`DEFERRABLE INITIALLY DEFERRED`) or an explicit package check procedure executes just prior to transaction `COMMIT`.
   - *Trade-off:* Fully decoupled and transaction-safe, but introduces physical disk/redo overhead for staging tables and shifts error detection from statement-execution time to commit time, complicating client-side error handling.

---

### Question 2: Architectural Trade-Offs in Multi-Tier Systems: Thin vs. Thick Drivers, Logic Placement, and Connection Pooling

#### Examination Question:
> In enterprise systems engineering, architects must balance the trade-offs between **Database-Side Business Logic** (PL/SQL Stored Procedures and Triggers) and **Application-Side Business Logic** (Python/Streamlit/FastAPI Services), as well as connection management strategies.
> 
> **(a)** Critically analyze the architectural trade-offs between implementing business invariants (e.g., budget threshold calculation and validation) inside **PL/SQL Stored Procedures** versus implementing them inside the **Python Application Layer**. Evaluate with respect to: (i) Network Round Trips and Latency, (ii) System Scalability and CPU Utilization, (iii) Polyglot Client Consistency, and (iv) Unit Testing and CI/CD pipelines.  
> **(b)** Analyze the operational mechanics of the **python-oracledb Thin Mode** driver versus the legacy **Thick Mode (OCI)** driver. How does Thin mode achieve high throughput without the Oracle Call Interface (OCI) C libraries?  
> **(c)** In a high-concurrency deployment where multiple users concurrently interact with the Streamlit dashboard, explain the catastrophic impact of creating a new physical TCP database connection per user click versus implementing an **Oracle Session Pool (`oracledb.create_pool`)**. Support your answer with details of Oracle Server Process architecture (PGA, Server Process forking, Listener Handshake, and Two-Task architecture).

---

#### Comprehensive Solution & Grading Rubric:

#### (a) Trade-Off Analysis: Database-Centric vs. Application-Centric Logic

| Architectural Dimension | Database-Side (PL/SQL Procedures & Triggers) | Application-Side (Python/Streamlit Service Layer) |
| :--- | :--- | :--- |
| **(i) Network Latency & Round Trips** | **Superior:** Complex multi-step operations execute locally in the Oracle SGA/PGA at memory-bus speeds. A single network call (`callproc`) initiates validation, DML, trigger updates, and audit logging. | **Inferior:** Requires multiple network hops (e.g., query category, query budget, insert expense, update budget), amplifying latency over WAN or cloud boundaries. |
| **(ii) Scalability & CPU Utilization** | **Limited Scalability:** Database CPU cores and licenses are expensive. Offloading heavy procedural math to the DB can saturate the database server, which is hard to scale horizontally without Oracle RAC. | **Superior Scalability:** Application servers are stateless and easily scale horizontally behind load balancers (Kubernetes, AWS ECS) using inexpensive compute nodes. |
| **(iii) Polyglot Client Consistency** | **Absolute Consistency:** Guarantees that whether a mutation originates from Streamlit, a mobile app (Kotlin/Swift), an ETL pipeline, or a DBA using SQL*Plus, the identical business rules are enforced. | **Inconsistent:** Business rules must be reimplemented and synchronized across multiple languages and client codebases, risking rule divergence. |
| **(iv) Unit Testing & CI/CD** | **Challenging:** Requires specialized frameworks (e.g., utPLSQL), test databases, and schema migrations (Flyway/Liquibase). Dockerized integration pipelines are required. | **Highly Agile:** Standard testing frameworks (PyTest, Mock), linting, and rapid automated container CI/CD pipelines. |

#### (b) Mechanics of `python-oracledb` Thin Mode:
- **Legacy Thick Mode:** Applications called Python bindings which called the C-based **Oracle Call Interface (OCI)** library (`libclntsh.so`). OCI handled SQL translation, security negotiation, data marshaling, and network communication via the proprietary TNS protocol.
- **Modern Thin Mode:** The driver authors implemented the complete **Two-Task / Transparent Network Substrate (TNS) protocol specification entirely in native Python**. 
- **Operational Flow:**
  1. Opens a raw Python TCP socket directly to the Oracle Listener port (1521).
  2. Directly negotiates the Oracle Advanced Networking Option (ANO) packet exchange, character set conversions (`AL32UTF8`), authentication protocols, and cryptographic handshakes in Python.
  3. Packages SQL statements, bind variables, and RPC commands into raw TNS Data (TNS_DATA) packets.
- **Throughput Advantage:** Eliminates the C Foreign Function Interface (FFI) boundary overhead (ctypes/Cython), provides cross-platform portability across ARM/x86 architectures, and avoids complex OS library search path configurations (`LD_LIBRARY_PATH`).

#### (c) Concurrency, Connection Costs, and Oracle Session Pooling:

##### 1. The Catastrophic Overhead of Connection-per-Click:
In Oracle Database's dedicated server architecture, establishing a new physical TCP connection requires the following sequence:
- **OS Socket Handshake:** 3-way TCP handshake (SYN, SYN-ACK, ACK).
- **Listener Negotiation:** The Oracle Listener process on port 1521 receives the connection, inspects the service name (`XEPDB1`), and forks a new operating system **Oracle Server Process**.
- **Memory Allocation:** The OS assigns address space and allocates private memory structures for the **Program Global Area (PGA)**, including the User Session Duration, Stack Space, and Sort Area.
- **Authentication Handshake:** Multiple round trips to negotiate encryption, authentication tokens, session context, and NLS parameters.
- If 100 users submit expenses simultaneously, the operating system experiences a storm of 100 process forks, resulting in severe CPU context-switching, thread exhaustion, PGA memory thrashing, and database crashes with `ORA-12519: TNS:no appropriate service handler found`.

##### 2. The Solution: Oracle Session Pooling (`oracledb.create_pool`):
- **Mechanism:** The application initializes a pool of pre-warmed, authenticated physical server connections during startup (`min=4, max=20`).
- **Connection Checkout:** When a Streamlit thread handles a user request, it borrows an idle connection from the pool in sub-millisecond time.
- **Execution & Return:** The thread performs the PL/SQL call, commits the transaction, and immediately returns the connection back to the pool.
- **System Impact:** The number of Oracle server processes remains bounded, eliminating process creation overhead and allowing the database to operate at peak CPU throughput with optimal memory footprint.

---
# Personal-Expense-Tracker
