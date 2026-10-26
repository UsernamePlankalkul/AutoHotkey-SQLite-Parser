<div align="center">

# 🗄️ SQLite.ahk

### A complete SQLite library class for **AutoHotkey v2**
*Create · Manage · Query · Parse — one file, zero dependencies on Windows 10/11*

<br>

![AutoHotkey](https://img.shields.io/badge/AutoHotkey-v2.0%2B-brightgreen?style=for-the-badge&logo=autohotkey&logoColor=white)
![SQLite](https://img.shields.io/badge/SQLite-3.x-0F80CC?style=for-the-badge&logo=sqlite&logoColor=white)
![Platform](https://img.shields.io/badge/Windows-10%20%7C%2011-blue?style=for-the-badge&logo=windows&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)
![Single file](https://img.shields.io/badge/Single%20file-SQLite.ahk-orange?style=for-the-badge)

<br>

[🚀 Quick start](#-quick-start) ·
[📦 Installation](#-installation) ·
[🔌 Connecting](#-connecting) ·
[⚡ Running SQL](#-running-sql) ·
[🧱 Schema](#-schema-management) ·
[📤 Import / Export](#-import--export) ·
[📚 API reference](#-api-reference) ·
[🩺 Troubleshooting](#-troubleshooting)

</div>

---

## ✨ Features

| | Feature | What you get |
|:-:|---|---|
| 🟢 | **Zero setup** | Uses `sqlite3.dll` if present, otherwise the `winsqlite3.dll` built into Windows |
| 🔵 | **Safe queries** | Positional, array and **named** (`:name`) parameters, all bound, never concatenated |
| 🟣 | **Rich results** | `Table` objects with `ToText()`, `ToCSV()`, `ToJson()`, `ToMaps()`; row `Map`s; streaming `for` loops |
| 🟠 | **Transactions** | `Begin` / `Commit` / `Rollback`, savepoints, nested `Transaction(fn)` |
| 🟡 | **CRUD helpers** | `Insert`, `InsertMany`, `Update`, `Delete`, `Upsert`, `Count`, `Exists` |
| 🔴 | **Schema tools** | Create / alter / drop tables, indexes, views; introspection; `Migrate()` with `user_version` |
| 🩵 | **Maintenance** | `Pragma`, `Vacuum`, `IntegrityCheck`, WAL checkpoint, online **Backup / Restore** |
| 🩷 | **Parsing** | SQL script splitter (trigger aware), CSV parser/writer, full SQL **Dump** |
| ⚪ | **Extensible** | Register your own **SQL functions** written in AutoHotkey |
| ⚫ | **Typed** | Integer, Float, String, **BLOB** (`Buffer`) and `NULL` mapped correctly, UTF-8 throughout |

---

## 📦 Installation

1. Copy **`SQLite.ahk`** next to your script (or into a `Lib` folder).
2. Include it:

```autohotkey
#Requires AutoHotkey v2.0
#Include SQLite.ahk          ; or:  #Include <SQLite>   (when placed in \Lib)
```

### 🔎 Which DLL is used?

The library searches in this order and uses the **first one it finds**:

| # | Location |
|:-:|---|
| 1️⃣ | `<script folder>\sqlite3.dll` |
| 2️⃣ | `<script folder>\x64\sqlite3.dll` or `\x86\sqlite3.dll` (matches your AHK bitness) |
| 3️⃣ | `<script folder>\lib\sqlite3.dll` and `\lib\x64\...` / `\lib\x86\...` |
| 4️⃣ | `sqlite3.dll` on your `PATH` |
| 5️⃣ | `winsqlite3.dll` (**ships with Windows 10 / 11**, nothing to download) |

> [!TIP]
> Want the newest SQLite features? Download the official DLL from [sqlite.org/download](https://www.sqlite.org/download.html) (matching your AutoHotkey 32/64-bit) and drop it beside the script. To force a specific file: `SQLite.Load("C:\path\sqlite3.dll")` before opening a database.

> [!NOTE]
> Some SQL features need a recent SQLite: `DROP COLUMN` (3.35+), `VACUUM INTO` (3.27+), `UPSERT` (3.24+), `STRICT` tables (3.37+). Check yours with `SQLite.Version`.

---

## 🚀 Quick start

```autohotkey
#Requires AutoHotkey v2.0
#Include SQLite.ahk

try {
    db := SQLite("app.db", {WAL: true})        ; use ":memory:" for a temporary database

    db.CreateTable("users", [
        "id   INTEGER PRIMARY KEY AUTOINCREMENT",
        "name TEXT NOT NULL UNIQUE",
        "age  INTEGER"
    ])

    db.Insert("users", Map("name", "Ali", "age", 30))                    ; Map / object helper
    db.Run("INSERT INTO users(name, age) VALUES(?, ?)", "Sara", 25)      ; positional
    db.Run("INSERT INTO users(name, age) VALUES(:n, :a)", Map("n", "Reza", "a", 41))   ; named

    MsgBox db.GetTable("SELECT * FROM users ORDER BY age").ToText()

    for row in db.Each("SELECT name, age FROM users WHERE age > ?", 26)
        MsgBox row["name"] " is " row["age"]

    db.Close()
}
catch SQLiteError as e {
    MsgBox "SQLite error " e.Code ": " e.Message "`n`nSQL: " e.SQL
}
```

Output of `ToText()`:

```text
+----+------+-----+
| id | name | age |
+----+------+-----+
| 2  | Sara | 25  |
| 1  | Ali  | 30  |
| 3  | Reza | 41  |
+----+------+-----+
```

> [!TIP]
> Run `SQLite.ahk` **directly** (double-click it) to launch a built-in demo that exercises migrations, CRUD, custom functions, JSON output and a SQL dump.

---

## 🔌 Connecting

```autohotkey
db := SQLite("data\app.db")                          ; folder is created automatically
db := SQLite(":memory:")                             ; in-memory
db := SQLite("", {})                                 ; private temporary on-disk database
db := SQLite("file:app.db?mode=ro", {})              ; URI filenames are supported
db := SQLite("app.db", {ReadOnly: true})
db := SQLite("app.db", {WAL: true, ForeignKeys: true, BusyTimeout: 8000})
```

### ⚙️ Options (`Map` or object literal)

| Option | Default | Meaning |
|---|:-:|---|
| `ReadOnly` | `false` | Open read-only |
| `Create` | `true` | Create the file if it doesn't exist |
| `BusyTimeout` | `5000` | Milliseconds to wait when the database is locked |
| `ForeignKeys` | `true` | Runs `PRAGMA foreign_keys = ON` |
| `WAL` | `false` | Switches to write-ahead logging (better concurrency) |

### 🧾 Useful properties

```autohotkey
db.LastInsertId      db.Changes          db.TotalChanges
db.InTransaction     db.FileName         db.FileSize
db.IsOpen            db.ErrorMessage     db.UserVersion  ; get / set
db.ForeignKeys := true                    ; get / set
SQLite.Version                            ; e.g. "3.45.1"
SQLite.DllPath                            ; which DLL was loaded
```

---

## 🔁 Value mapping

| AutoHotkey value | ➜ | SQLite | ➜ | Returned as |
|---|:-:|---|:-:|---|
| `Integer` | ➜ | `INTEGER` (64-bit) | ➜ | `Integer` |
| `Float` | ➜ | `REAL` | ➜ | `Float` |
| `String` | ➜ | `TEXT` (UTF-8) | ➜ | `String` |
| `Buffer` | ➜ | `BLOB` | ➜ | `Buffer` |
| `SQLite.NULL` or *unset* | ➜ | `NULL` | ➜ | `db.NullValue` (default `""`) |

> [!IMPORTANT]
> NULL comes back as an empty string by default. If you need to tell **NULL** apart from **empty text**, set  
> `db.NullValue := SQLite.NULL` — then compare with `row["col"] == SQLite.NULL`.

> [!NOTE]
> A numeric-looking **string** such as `"42"` is stored as text. Columns declared `INTEGER` / `REAL` will convert it for you (SQLite type affinity). Pass a real number to be explicit.

---

## ⚡ Running SQL

### 🟢 Quick reference

| Method | Returns | Use it for |
|---|---|---|
| `db.Exec(sql)` | rows changed | Scripts with **many** statements, no parameters |
| `db.Run(sql, params*)` | rows changed | One statement with parameters (INSERT / UPDATE / DELETE / DDL) |
| `db.GetTable(sql, params*)` | `SQLite.Table` | Columns + rows, printable / exportable |
| `db.All(sql, params*)` | `Array` of `Map` | Every row as a case-insensitive `Map` |
| `db.Get(sql, params*)` | `Map` or `""` | First row only |
| `db.Scalar(sql, params*)` | value or `""` | Single value (`COUNT(*)`, `MAX(...)`) |
| `db.Column(sql, params*)` | `Array` | First column of every row |
| `db.Each(sql, params*)` | enumerable | **Streaming** loop for big result sets |
| `db.Prepare(sql)` | `SQLite.Statement` | Reuse one statement many times |

### 🧷 Passing parameters

```autohotkey
db.Run("UPDATE users SET age = ? WHERE name = ?", 31, "Ali")                 ; positional
db.Run("UPDATE users SET age = ? WHERE name = ?", [31, "Ali"])              ; one array
db.Run("UPDATE users SET age = :age WHERE name = :name"
     , Map("age", 31, "name", "Ali"))                                       ; named (Map)
db.Run("UPDATE users SET age = :age WHERE name = :name"
     , {age: 31, name: "Ali"})                                              ; named (object)
db.Run("UPDATE users SET bio = ? WHERE id = 1", SQLite.NULL)                ; NULL
```

Named keys may be written with or without the prefix: `"age"`, `":age"`, `"@age"` and `"$age"` all work.

> [!WARNING]
> **Never** build SQL by concatenating user input. Always bind values with `?` or `:name`.
> For identifiers (table / column names) use `SQLite.QuoteId(name)`; for rare literal cases use `SQLite.Quote(value)`.

### 📖 Reading results

```autohotkey
t := db.GetTable("SELECT id, name FROM users")
MsgBox t.Count " rows, columns: " t.Columns[1] ", " t.Columns[2]
MsgBox t.Rows[1][2]                 ; row 1, column 2
MsgBox t.Cell(1, "name")            ; same, by column name

for row in t                        ; rows as arrays
    MsgBox row[1] ": " row[2]

for i, row in db.Each("SELECT * FROM users")     ; streaming, rows as Maps
    MsgBox i ". " row["name"]

user := db.Get("SELECT * FROM users WHERE id = ?", 1)
if user
    MsgBox user["name"]

n := db.Scalar("SELECT COUNT(*) FROM users")
names := db.Column("SELECT name FROM users ORDER BY name")
```

### ♻️ Prepared statements

```autohotkey
stmt := db.Prepare("INSERT INTO users(name, age) VALUES(?, ?)")
stmt.Run("Neda", 28)
stmt.Run("Omid", 35)
stmt.Finalize()                      ; optional, happens automatically when released

q := db.Prepare("SELECT * FROM users WHERE age > :min")
q.Bind(Map("min", 30))
while q.Step()
    MsgBox q.Value(2)                ; 1-based column index
    ; or q.Row() (Map) / q.Values() (Array)
```

---

## 🔄 Transactions

```autohotkey
db.Begin()                           ; or "IMMEDIATE" / "EXCLUSIVE"
db.Run("UPDATE acct SET bal = bal - 100 WHERE id = 1")
db.Run("UPDATE acct SET bal = bal + 100 WHERE id = 2")
db.Commit()                          ; or db.Rollback()
```

The safer way, which commits on success and **rolls back automatically on any error**:

```autohotkey
db.Transaction((d) => (
    d.Run("UPDATE acct SET bal = bal - 100 WHERE id = 1"),
    d.Run("UPDATE acct SET bal = bal + 100 WHERE id = 2")
))

; multi-line version
Transfer(d) {
    d.Run("UPDATE acct SET bal = bal - 100 WHERE id = 1")
    d.Run("UPDATE acct SET bal = bal + 100 WHERE id = 2")
}
db.Transaction(Transfer)
```

> [!TIP]
> Calling `Transaction()` while a transaction is already open automatically uses a **savepoint**, so nested units of work roll back independently. Manual control: `Savepoint(name)`, `ReleaseSavepoint(name)`, `RollbackTo(name)`.

> [!TIP]
> Inserting thousands of rows? Wrap them in a transaction (or use `InsertMany`). It is typically **orders of magnitude** faster.

---

## 🧰 CRUD helpers

```autohotkey
id := db.Insert("users", Map("name", "Ali", "age", 30))          ; returns new rowid
db.Insert("users", {name: "Ali"}, "IGNORE")                       ; INSERT OR IGNORE
db.Insert("users", {name: "Ali"}, "REPLACE")                      ; INSERT OR REPLACE

n := db.InsertMany("users", [                                    ; one transaction
    {name: "Neda", age: 28},
    {name: "Omid", age: 35}
])

db.Update("users", Map("age", 99), "name = ?", "Omid")           ; returns rows changed
db.Delete("users", "age < ?", 18)

db.Upsert("users", Map("name", "Ali", "age", 31), "name")        ; needs UNIQUE/PK on "name"
db.Upsert("users", Map("name", "Ali", "age", 31), ["name"], ["age"])   ; choose update columns

db.Count("users")                                                ; 5
db.Count("users", "age > ?", 30)
db.Exists("users", "name = ?", "Ali")                            ; true / false
db.Clear("users", true)                                          ; delete all rows, reset AUTOINCREMENT
```

---

## 🧱 Schema management

### 🏗️ Create

```autohotkey
db.CreateTable("posts", [
    "id      INTEGER PRIMARY KEY",
    "user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE",
    "title   TEXT",
    ["created", "TEXT DEFAULT CURRENT_TIMESTAMP"]        ; [name, definition] pairs work too
], {IfNotExists: true, Strict: false})

db.CreateIndex("idx_posts_user", "posts", "user_id")
db.CreateIndex("idx_users_name", "users", ["name"], true)          ; UNIQUE
db.CreateView("adults", "SELECT * FROM users WHERE age >= 18")
```

**`CreateTable` options:** `IfNotExists` (default `true`) · `Temp` · `WithoutRowid` · `Strict` · `Constraints` (array of table constraints, e.g. `["UNIQUE(a,b)"]`)

> [!IMPORTANT]
> Columns are given as an **Array** on purpose. AutoHotkey `Map`s enumerate in *sorted key order*, which would shuffle your column order.

### ✏️ Alter / drop

```autohotkey
db.AddColumn("users", "email TEXT")
db.RenameColumn("users", "email", "mail")
db.RenameTable("users", "members")
db.DropColumn("members", "mail")
db.DropTable("posts")          db.DropView("adults")          db.DropIndex("idx_users_name")
```

### 🔍 Introspection

```autohotkey
db.Tables()                    ; ["posts", "users"]
db.Views()   db.Triggers()   db.Indexes()   db.Indexes("users")
db.TableExists("users")        ; true / false
db.ColumnNames("users")        ; ["id", "name", "age"]
db.Columns("users")            ; Maps: cid, name, type, notnull, dflt_value, pk
db.PrimaryKey("users")         ; ["id"]
db.ForeignKeyList("posts")
db.Schema()                    ; type / name / tbl_name / sql for everything
db.SchemaSQL("users")          ; the CREATE statement
```

### 🪜 Migrations

Each step runs **once**, in order, inside a transaction. Progress is stored in `PRAGMA user_version`.

```autohotkey
db.Migrate([
    "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);",                 ; v1
    "ALTER TABLE users ADD COLUMN age INTEGER; CREATE INDEX i_age ON users(age);",   ; v2 (many statements OK)
    (d) => d.Run("UPDATE users SET age = 0 WHERE age IS NULL")                ; v3 (a function)
])
MsgBox "Schema version: " db.UserVersion
```

---

## 🩺 Maintenance

```autohotkey
db.Pragma("journal_mode", "WAL")         ; set
mode := db.Pragma("journal_mode")        ; get (single values are returned directly)
db.Pragma("synchronous", "NORMAL")
db.ForeignKeys := true

db.Vacuum()                              ; compact the file
db.Vacuum("C:\backup\compact.db")        ; VACUUM INTO (SQLite 3.27+)
db.Analyze()    db.Optimize()
db.Checkpoint("TRUNCATE")                ; WAL checkpoint

ok := db.IntegrityCheck()                ; true, or a string describing the problems
```

### 💾 Backup & restore (online, safe while in use)

```autohotkey
db.Backup("backup\app-" A_YYYY A_MM A_DD ".db")

db.Backup("backup\big.db", (remaining, total) => ToolTip("Backup: " total - remaining "/" total), 50)

db.Restore("backup\app-20261026.db")     ; replaces the contents of this database
```

---

## 📤 Import / Export

### 🧾 SQL dump & scripts

```autohotkey
sql := db.Dump()                         ; schema + INSERT statements, as text
db.DumpToFile("dump.sql")
db.ExecFile("schema.sql")                ; run a .sql file

for stmt in SQLite.SplitStatements(FileRead("big.sql", "UTF-8"))
    MsgBox stmt                          ; trigger-aware splitting
```

### 📊 CSV

```autohotkey
db.ExportCSV("users", "users.csv")                                   ; table
db.ExportCSV("SELECT name, age FROM users WHERE age > ?", "old.csv", {Delimiter: ";"}, 30)

n := db.ImportCSV("people", "people.csv")                            ; creates TEXT columns if table is missing
db.ImportCSV("people", "p.csv", {Delimiter: ";", EmptyAsNull: true, Header: true})
```

| Option | Default | Applies to |
|---|:-:|---|
| `Delimiter` | `","` | both |
| `Header` | `true` | both |
| `Bom` | `true` | export (UTF-8 BOM so Excel opens it correctly) |
| `Create` | `true` | import (create missing table) |
| `EmptyAsNull` | `false` | import |
| `Encoding` | `"UTF-8"` | import |

Standalone helpers: `SQLite.ParseCSV(text, delim)` and `SQLite.ToCSV(arrayOfArrays, delim)`.

### 🧩 JSON / text output

```autohotkey
t := db.GetTable("SELECT name, age FROM users")
t.ToJson()            ; [{"name": "Ali", "age": 30}, ...]
t.ToJson(true)        ; one object per line
t.ToCSV(";")          ; CSV text
t.ToText()            ; aligned ASCII table
t.ToMaps()            ; Array of Maps
```

---

## 🧪 Custom SQL functions

Write SQL functions in AutoHotkey and call them from queries:

```autohotkey
db.CreateFunction("shout",   1, (s) => StrUpper(s) "!")
db.CreateFunction("add3",    3, (a, b, c) => a + b + c)
db.CreateFunction("maybe",   1, (x) => x = "" ? SQLite.NULL : x)    ; return SQLite.NULL for NULL
db.CreateFunction("argcount", -1, (args*) => args.Length)           ; -1 = variadic

MsgBox db.Scalar("SELECT shout(name) FROM users WHERE id = 1")      ; ALI!
```

> [!WARNING]
> A function **must return a value**. If it throws an error, the SQL statement fails with that message.

> [!CAUTION]
> Functions registered with `CreateFunction` keep a callback alive. **Call `db.Close()` explicitly** when you are done so the callback is released.

---

## 🚨 Error handling

Every failure throws a **`SQLiteError`** (a subclass of `Error`):

| Property | Meaning |
|---|---|
| `Message` | Human-readable text from SQLite |
| `Code` | Primary result code (`1` SQL error, `5` busy, `19` constraint, ...) |
| `ExtendedCode` | Detailed code (`2067` UNIQUE, `1299` NOT NULL, `787` FOREIGN KEY, ...) |
| `SQL` | The statement that failed |

```autohotkey
try {
    db.Insert("users", {name: "Ali"})        ; name is UNIQUE
}
catch SQLiteError as e {
    if e.ExtendedCode = 2067
        MsgBox "That user already exists."
    else
        MsgBox "Error " e.Code " (" e.ExtendedCode "): " e.Message "`nSQL: " e.SQL
}
```

```diff
- Error 19: UNIQUE constraint failed: users.name
+ Handled: caught by catch SQLiteError, transaction rolled back
```

---

## 📚 API reference

<details>
<summary><b>🟦 Class <code>SQLite</code> — static members</b></summary>

| Member | Description |
|---|---|
| `SQLite.Load([dllPath])` | Load the DLL (automatic on first use) |
| `SQLite.Version` | SQLite library version |
| `SQLite.DllPath` | Path of the loaded DLL |
| `SQLite.NULL` | Sentinel that represents SQL `NULL` |
| `SQLite.NullValue` | Default value NULL columns are returned as (`""`) |
| `SQLite.QuoteId(name)` | Quote an identifier: `"name"` |
| `SQLite.Quote(value)` | Convert a value to an SQL literal |
| `SQLite.SplitStatements(script)` | Split a script into complete statements |
| `SQLite.ParseCSV(text [, delim])` | CSV ➜ array of arrays (RFC 4180) |
| `SQLite.ToCSV(rows [, delim])` | Array of arrays ➜ CSV |

</details>

<details>
<summary><b>🟩 Instance — connection &amp; execution</b></summary>

| Method | Description |
|---|---|
| `SQLite(path := ":memory:", opts := "")` | Open / create a database |
| `Close()` | Close the connection |
| `Exec(sql)` | Run multiple statements |
| `Run(sql, params*)` | Run one statement, returns rows changed |
| `Prepare(sql)` | Create a `SQLite.Statement` |
| `GetTable / All / Get / Scalar / Column / Each` | Query helpers (see above) |
| `Begin([mode]) / Commit() / Rollback()` | Transactions |
| `Savepoint / ReleaseSavepoint / RollbackTo (name)` | Savepoints |
| `Transaction(fn [, mode])` | Atomic block with auto-rollback; nests via savepoints |
| `BusyTimeout(ms)` | Change the lock wait time |
| `Interrupt()` | Abort a running query |

</details>

<details>
<summary><b>🟨 Instance — CRUD</b></summary>

| Method | Description |
|---|---|
| `Insert(table, data [, onConflict])` | Returns the new rowid |
| `InsertMany(table, rows [, onConflict])` | Bulk insert in one transaction |
| `Update(table, data [, where, params*])` | Returns rows changed |
| `Delete(table [, where, params*])` | Returns rows changed |
| `Upsert(table, data, conflict [, updateCols])` | `INSERT ... ON CONFLICT DO UPDATE` |
| `Count(table [, where, params*])` | Row count |
| `Exists(table [, where, params*])` | `true` / `false` |
| `Clear(table [, resetSeq])` | Delete all rows |

</details>

<details>
<summary><b>🟥 Instance — schema</b></summary>

| Method | Description |
|---|---|
| `CreateTable(name, columns [, opts])` | Create a table |
| `CreateIndex(name, table, cols [, unique, where])` | Create an index (partial indexes via `where`) |
| `CreateView(name, selectSql [, ifNotExists])` | Create a view |
| `AddColumn / RenameColumn / RenameTable / DropColumn` | Alter tables |
| `DropTable / DropView / DropIndex (name [, ifExists])` | Drop objects |
| `Tables([includeSystem]) / Views() / Triggers() / Indexes([table])` | List objects |
| `TableExists(name)` | Existence check |
| `Columns(table) / ColumnNames(table) / PrimaryKey(table)` | Column info |
| `ForeignKeyList(table)` | Foreign keys |
| `Schema() / SchemaSQL(name)` | Raw schema |
| `Migrate(steps)` | Versioned migrations |

</details>

<details>
<summary><b>🟪 Instance — maintenance, import / export, functions</b></summary>

| Method | Description |
|---|---|
| `Pragma(name [, value])` | Get / set any PRAGMA |
| `UserVersion`, `ForeignKeys` | Get / set properties |
| `Vacuum([intoFile])`, `Analyze()`, `Optimize()`, `Checkpoint([mode])` | Maintenance |
| `IntegrityCheck([quick])` | `true` or problem text |
| `Backup(dest [, progress, pagesPerStep])` / `Restore(src ...)` | Online backup |
| `Dump()` / `DumpToFile(path)` | SQL dump |
| `ExecFile(path [, encoding])` | Run a `.sql` file |
| `ExportCSV(source, path [, opts, params*])` | Table or query ➜ CSV |
| `ImportCSV(table, path [, opts])` | CSV ➜ table |
| `CreateFunction(name, nArgs, fn [, deterministic])` | Register a SQL function |

</details>

<details>
<summary><b>🟧 <code>SQLite.Statement</code></b></summary>

| Member | Description |
|---|---|
| `Bind(params*)` | Reset and bind positional / array / named parameters |
| `BindAt(index, value)` | Bind one value (1-based) |
| `Step()` | `true` when a row is available, `false` when done |
| `Reset()` | Rewind (bindings are kept) |
| `Run(params*)` | Bind + execute, returns rows changed |
| `All(params*)` | Bind + collect into a `Table` |
| `Value(i) / Values() / Row()` | Current row as value / Array / Map |
| `ColumnNames`, `DeclTypes`, `ColumnCount`, `ParamCount`, `ReadOnly`, `SQL` | Metadata |
| `Finalize()` | Release the statement |
| `for row in stmt` / `for i, row in stmt` | Iterate rows as Maps |

</details>

<details>
<summary><b>⬜ <code>SQLite.Table</code></b></summary>

| Member | Description |
|---|---|
| `Columns`, `Rows`, `Types` | Column names, array-of-arrays rows, declared types |
| `Count`, `ColumnCount` | Sizes |
| `ColumnIndex(name)`, `Column(nameOrIndex)`, `Cell(row, col)` | Accessors |
| `ToMaps()`, `ToCSV([delim, header])`, `ToJson([pretty])`, `ToText()` | Converters |
| `table[i]`, `for row in table`, `for i, row in table` | Indexing / iteration |

</details>

---

## 🩺 Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| 🔴 `Unable to load sqlite3.dll or winsqlite3.dll` | Very old Windows, or wrong-bitness DLL | Put a matching `sqlite3.dll` (32/64-bit like your AHK) beside the script |
| 🔴 `SQLite function not available in this DLL` | Stripped-down DLL build | Use the official `sqlite3.dll` from sqlite.org |
| 🟠 `database is locked` (code `5`) | Another connection is writing | Raise `BusyTimeout`, enable `{WAL: true}`, keep transactions short |
| 🟠 `no such column` / `no such table` | Typo, or double quotes treated as an identifier | Use single quotes for text literals, or bind with `?` |
| 🟡 `FOREIGN KEY constraint failed` (787) | Parent row missing | Insert the parent first, or check `db.ForeignKeys` |
| 🟡 `UNIQUE constraint failed` (2067) | Duplicate value | Use `Upsert`, `Insert(..., "IGNORE")`, or catch the error |
| 🟡 `near "DROP": syntax error` on `DropColumn` | SQLite older than 3.35 | Use the official DLL, or rebuild the table |
| 🔵 Columns appear in the wrong order | Used a `Map` for columns | Pass an **Array** to `CreateTable` |
| 🔵 NULL looks like `""` | Default `NullValue` | `db.NullValue := SQLite.NULL` |
| 🔵 Database object is never released | `CreateFunction` was used (the callback keeps it alive) | Call `db.Close()` explicitly when finished |

---

## 🧭 Good practices

- ✅ Use **parameters** (`?`, `:name`) for every value.
- ✅ Wrap bulk writes in `Transaction()` or use `InsertMany`.
- ✅ Use `{WAL: true}` for apps that read and write at the same time.
- ✅ Keep `ForeignKeys` on (the default) and declare `REFERENCES` in your schema.
- ✅ Use `Each()` instead of `All()` / `GetTable()` for very large result sets.
- ✅ Call `db.Close()` when finished, and always if you registered functions.
- ❌ Don't concatenate user input into SQL.
- ❌ Don't start a second query on the same `db` from a hotkey or timer while another one is still being stepped through; finish (or `Finalize()`) the first one.

---

<div align="center">


⭐ *If this library helped you, give the repo a star!* ⭐

</div>
