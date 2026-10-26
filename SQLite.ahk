#Requires AutoHotkey v2.0
; =============================================================================
;  SQLite.ahk  -  complete SQLite library class for AutoHotkey v2
; -----------------------------------------------------------------------------
;  Engine : sqlite3.dll (next to the script, in \lib, \x64 / \x86, or on PATH)
;           falls back to winsqlite3.dll which ships with Windows 10/11, so no
;           download is required.
;
;  Quick start
;     db := SQLite("app.db", {WAL: true})            ; or SQLite(":memory:")
;     db.CreateTable("users", ["id INTEGER PRIMARY KEY AUTOINCREMENT"
;                            , "name TEXT NOT NULL", "age INTEGER"])
;     db.Insert("users", Map("name", "Ali", "age", 30))
;     db.Run("INSERT INTO users(name, age) VALUES(?, ?)", "Sara", 25)
;     db.Run("INSERT INTO users(name, age) VALUES(:n, :a)", Map("n","Reza","a",41))
;     MsgBox db.GetTable("SELECT * FROM users").ToText()
;     for row in db.Each("SELECT * FROM users WHERE age > ?", 26)
;         MsgBox row["name"]
;
;  Value mapping
;     AHK -> SQLite : Integer->INTEGER, Float->REAL, String->TEXT, Buffer->BLOB,
;                     SQLite.NULL or unset -> NULL
;     SQLite -> AHK : INTEGER->Integer, REAL->Float, TEXT->String, BLOB->Buffer,
;                     NULL-> db.NullValue ("" by default; set db.NullValue :=
;                     SQLite.NULL to keep NULL distinct from empty text)
; =============================================================================

class SQLite {
    ; ---- result codes / open flags ------------------------------------------
    static OK := 0, ROW := 100, DONE := 101
    static OPEN_READONLY := 0x1, OPEN_READWRITE := 0x2, OPEN_CREATE := 0x4, OPEN_URI := 0x40

    ; ---- library state ------------------------------------------------------
    static _h := 0
    static _dll := ""
    static _fn := Map()
    static NULL := Object()          ; sentinel for SQL NULL
    static NullValue := ""           ; what NULL columns are returned as
    static _Names := ["sqlite3_open_v2", "sqlite3_close_v2", "sqlite3_errmsg", "sqlite3_errcode"
        , "sqlite3_extended_errcode", "sqlite3_extended_result_codes", "sqlite3_prepare_v2"
        , "sqlite3_step", "sqlite3_reset", "sqlite3_finalize", "sqlite3_clear_bindings"
        , "sqlite3_bind_parameter_count", "sqlite3_bind_parameter_index", "sqlite3_bind_null"
        , "sqlite3_bind_int64", "sqlite3_bind_double", "sqlite3_bind_text", "sqlite3_bind_blob"
        , "sqlite3_bind_zeroblob", "sqlite3_column_count", "sqlite3_column_name"
        , "sqlite3_column_decltype", "sqlite3_column_type", "sqlite3_column_int64"
        , "sqlite3_column_double", "sqlite3_column_text", "sqlite3_column_blob"
        , "sqlite3_column_bytes", "sqlite3_changes", "sqlite3_total_changes"
        , "sqlite3_last_insert_rowid", "sqlite3_busy_timeout", "sqlite3_libversion"
        , "sqlite3_get_autocommit", "sqlite3_interrupt", "sqlite3_db_filename"
        , "sqlite3_stmt_readonly", "sqlite3_backup_init", "sqlite3_backup_step"
        , "sqlite3_backup_finish", "sqlite3_backup_remaining", "sqlite3_backup_pagecount"
        , "sqlite3_complete", "sqlite3_create_function_v2", "sqlite3_value_type"
        , "sqlite3_value_int64", "sqlite3_value_double", "sqlite3_value_text"
        , "sqlite3_value_blob", "sqlite3_value_bytes", "sqlite3_result_null"
        , "sqlite3_result_int64", "sqlite3_result_double", "sqlite3_result_text"
        , "sqlite3_result_blob", "sqlite3_result_zeroblob", "sqlite3_result_error"]

    ; Load the DLL (called automatically). Pass a path to force a specific DLL.
    static Load(dllPath := "") {
        if this._h
            return this._dll
        list := []
        if dllPath != "" {
            list.Push(dllPath)
        } else {
            arch := A_PtrSize = 8 ? "x64" : "x86"
            list.Push(A_ScriptDir "\sqlite3.dll"
                , A_ScriptDir "\" arch "\sqlite3.dll"
                , A_ScriptDir "\lib\sqlite3.dll"
                , A_ScriptDir "\lib\" arch "\sqlite3.dll"
                , "sqlite3.dll"
                , "winsqlite3.dll")
        }
        for path in list {
            if InStr(path, "\") && !FileExist(path)
                continue
            h := DllCall("LoadLibrary", "str", path, "ptr")
            if h {
                this._h := h
                this._dll := path
                break
            }
        }
        if !this._h
            throw SQLiteError("Unable to load sqlite3.dll or winsqlite3.dll", -1)
        for name in this._Names
            this._fn[name] := DllCall("GetProcAddress", "ptr", this._h, "astr", name, "ptr")
        return this._dll
    }

    static _P(name) {
        if !this._h
            this.Load()
        p := this._fn.Get(name, 0)
        if !p
            throw SQLiteError("SQLite function not available in this DLL: " name, -1)
        return p
    }

    static _Call(name, args*) => DllCall(this._P(name), args*)

    ; SQLite library version string, e.g. "3.45.1"
    static Version => StrGet(SQLite._Call("sqlite3_libversion", "Cdecl ptr"), "UTF-8")
    static DllPath => (SQLite.Load(), SQLite._dll)

    ; ---- generic helpers ----------------------------------------------------
    static _U8(s) {
        n := StrPut(s, "UTF-8")
        b := Buffer(n)
        StrPut(s, b, "UTF-8")
        return b
    }

    static _Opt(o, k, d) {
        if !IsObject(o)
            return d
        if o is Map
            return o.Get(k, d)
        return o.HasOwnProp(k) ? o.%k% : d
    }

    static _IsNull(v?) => !IsSet(v) || (IsObject(v) && v == SQLite.NULL)

    static _Join(arr, sep := ", ") {
        s := ""
        for v in arr
            s .= (A_Index > 1 ? sep : "") v
        return s
    }

    static _Rep(ch, n) {
        s := ""
        loop Max(n, 0)
            s .= ch
        return s
    }

    static _Hex(buf) {
        s := ""
        loop buf.Size
            s .= Format("{:02X}", NumGet(buf, A_Index - 1, "UChar"))
        return s
    }

    static _Pairs(data) {
        keys := [], vals := []
        if data is Map {
            for k, v in data {
                keys.Push(k)
                vals.Push(v)
            }
        } else {
            for k, v in data.OwnProps() {
                keys.Push(k)
                vals.Push(v)
            }
        }
        return [keys, vals]
    }

    static _QuoteList(arr) {
        q := []
        for c in arr
            q.Push(SQLite.QuoteId(c))
        return SQLite._Join(q)
    }

    ; "name" -> "\"name\""  (safe identifier)
    static QuoteId(name) => '"' StrReplace(name, '"', '""') '"'

    ; Value -> SQL literal (numbers raw, text '..' escaped, blob X'..', NULL)
    static Quote(v?) {
        if SQLite._IsNull(v?)
            return "NULL"
        if v is Number
            return String(v)
        if v is Buffer
            return "X'" SQLite._Hex(v) "'"
        return "'" StrReplace(String(v), "'", "''") "'"
    }

    ; Split a SQL script into complete statements (trigger-aware, uses sqlite3_complete)
    static SplitStatements(script) {
        out := [], acc := ""
        parts := StrSplit(script, ";")
        for i, piece in parts {
            acc .= piece
            if i < parts.Length {
                acc .= ";"
                if SQLite._Call("sqlite3_complete", "ptr", SQLite._U8(acc), "Cdecl int") {
                    if Trim(acc, " `t`r`n;") != ""
                        out.Push(Trim(acc, " `t`r`n"))
                    acc := ""
                }
            }
        }
        if Trim(acc, " `t`r`n") != ""
            out.Push(Trim(acc, " `t`r`n"))
        return out
    }

    ; RFC-4180 CSV parser -> Array of Arrays
    static ParseCSV(text, delim := ",") {
        rows := [], row := [], field := "", inQ := false
        i := 1, n := StrLen(text)
        if SubStr(text, 1, 1) = Chr(0xFEFF)
            i := 2
        while i <= n {
            c := SubStr(text, i, 1)
            if inQ {
                if c == '"' {
                    if SubStr(text, i + 1, 1) == '"' {
                        field .= '"'
                        i += 2
                        continue
                    }
                    inQ := false
                } else {
                    field .= c
                }
            } else if c == '"' && field = "" {
                inQ := true
            } else if c == delim {
                row.Push(field)
                field := ""
            } else if c == "`r" || c == "`n" {
                if c == "`r" && SubStr(text, i + 1, 1) == "`n"
                    i++
                row.Push(field)
                field := ""
                if !(row.Length = 1 && row[1] = "")
                    rows.Push(row)
                row := []
            } else {
                field .= c
            }
            i++
        }
        if field != "" || row.Length {
            row.Push(field)
            rows.Push(row)
        }
        return rows
    }

    ; Array of Arrays -> CSV text
    static ToCSV(rows, delim := ",") {
        lines := []
        for row in rows {
            f := []
            for v in row
                f.Push(SQLite._CsvField(v, delim))
            lines.Push(SQLite._Join(f, delim))
        }
        return SQLite._Join(lines, "`r`n") "`r`n"
    }

    static _CsvField(v, d) {
        s := SQLite._Disp(v, false)
        if InStr(s, d) || InStr(s, '"') || InStr(s, "`n") || InStr(s, "`r")
            return '"' StrReplace(s, '"', '""') '"'
        return s
    }

    static _Disp(v, forText := true) {
        if SQLite._IsNull(v)
            return ""
        if v is Buffer
            return forText ? "<BLOB " v.Size ">" : SQLite._Hex(v)
        s := String(v)
        if forText
            s := StrReplace(StrReplace(s, "`r`n", " "), "`n", " ")
        return s
    }

    static _JsonStr(s) {
        s := StrReplace(s, "\", "\\")
        s := StrReplace(s, '"', '\"')
        s := StrReplace(s, "`n", "\n")
        s := StrReplace(s, "`r", "\r")
        s := StrReplace(s, "`t", "\t")
        s := StrReplace(s, "`b", "\b")
        s := StrReplace(s, "`f", "\f")
        return '"' s '"'
    }

    static _JsonVal(v) {
        if SQLite._IsNull(v)
            return "null"
        if v is Number
            return String(v)
        if v is Buffer
            return '"' SQLite._Hex(v) '"'
        return SQLite._JsonStr(String(v))
    }

    ; =========================================================================
    ;  Instance: connection
    ; =========================================================================
    ; opts (Map or object): ReadOnly, Create(true), BusyTimeout(5000),
    ;                       ForeignKeys(true), WAL(false)
    __New(path := ":memory:", opts := "") {
        SQLite.Load()
        this._db := 0
        this._sp := 0
        this._funcs := Map()
        this.Path := path
        this.NullValue := SQLite.NullValue

        ro := SQLite._Opt(opts, "ReadOnly", false)
        create := SQLite._Opt(opts, "Create", true)
        flags := ro ? 0x1 : (create ? 0x6 : 0x2)
        isUri := SubStr(path, 1, 5) = "file:"
        if isUri
            flags |= 0x40
        if !isUri && path != "" && path != ":memory:" && !ro && create {
            SplitPath(path, , &dir)
            if dir != "" && !DirExist(dir)
                DirCreate(dir)
        }

        buf := SQLite._U8(path)
        db := 0
        rc := DllCall(SQLite._P("sqlite3_open_v2"), "ptr", buf, "ptr*", &db, "int", flags, "ptr", 0, "Cdecl int")
        if rc {
            msg := db ? StrGet(SQLite._Call("sqlite3_errmsg", "ptr", db, "Cdecl ptr"), "UTF-8") : "out of memory"
            if db
                SQLite._Call("sqlite3_close_v2", "ptr", db, "Cdecl int")
            throw SQLiteError("Cannot open database '" path "': " msg, rc)
        }
        this._db := db
        SQLite._Call("sqlite3_extended_result_codes", "ptr", db, "int", 1, "Cdecl int")
        SQLite._Call("sqlite3_busy_timeout", "ptr", db, "int", SQLite._Opt(opts, "BusyTimeout", 5000), "Cdecl int")
        if SQLite._Opt(opts, "ForeignKeys", true)
            this.Exec("PRAGMA foreign_keys = ON")
        if SQLite._Opt(opts, "WAL", false) && !ro
            this.Exec("PRAGMA journal_mode = WAL")
    }

    __Delete() {
        this.Close()
    }

    Close() {
        if !this._db
            return false
        SQLite._Call("sqlite3_close_v2", "ptr", this._db, "Cdecl int")
        this._db := 0
        for key, cb in this._funcs
            CallbackFree(cb)
        this._funcs := Map()
        return true
    }

    _Live() {
        if !this._db
            throw SQLiteError("Database is closed", 21)
    }

    _Throw(rc, sql := "") {
        ext := this._db ? SQLite._Call("sqlite3_extended_errcode", "ptr", this._db, "Cdecl int") : rc
        throw SQLiteError(this.ErrorMessage, rc, sql, ext)
    }

    ; ---- connection properties ----------------------------------------------
    Ptr => this._db
    IsOpen => !!this._db
    ErrorMessage => this._db ? StrGet(SQLite._Call("sqlite3_errmsg", "ptr", this._db, "Cdecl ptr"), "UTF-8") : "Database is closed"
    ErrorCode => this._db ? SQLite._Call("sqlite3_errcode", "ptr", this._db, "Cdecl int") : 0
    LastInsertId => SQLite._Call("sqlite3_last_insert_rowid", "ptr", this._db, "Cdecl int64")
    Changes => SQLite._Call("sqlite3_changes", "ptr", this._db, "Cdecl int")
    TotalChanges => SQLite._Call("sqlite3_total_changes", "ptr", this._db, "Cdecl int")
    InTransaction => !SQLite._Call("sqlite3_get_autocommit", "ptr", this._db, "Cdecl int")
    FileName {
        get {
            p := SQLite._Call("sqlite3_db_filename", "ptr", this._db, "astr", "main", "Cdecl ptr")
            return p ? StrGet(p, "UTF-8") : ""
        }
    }
    FileSize => (f := this.FileName) != "" && FileExist(f) ? FileGetSize(f) : 0

    UserVersion {
        get => Integer(this.Pragma("user_version"))
        set => this.Pragma("user_version", value)
    }
    ForeignKeys {
        get => Integer(this.Pragma("foreign_keys")) = 1
        set => this.Pragma("foreign_keys", value ? 1 : 0)
    }

    BusyTimeout(ms) {
        this._Live()
        SQLite._Call("sqlite3_busy_timeout", "ptr", this._db, "int", ms, "Cdecl int")
    }

    Interrupt() {
        if this._db
            SQLite._Call("sqlite3_interrupt", "ptr", this._db, "Cdecl int")
    }

    ; =========================================================================
    ;  Executing SQL
    ; =========================================================================
    Prepare(sql) {
        this._Live()
        buf := SQLite._U8(sql)
        stmt := 0, tail := 0
        rc := DllCall(SQLite._P("sqlite3_prepare_v2"), "ptr", this._db, "ptr", buf, "int", buf.Size - 1
            , "ptr*", &stmt, "ptr*", &tail, "Cdecl int")
        if rc
            this._Throw(rc, sql)
        if !stmt
            throw SQLiteError("SQL text contains no statement", 21, sql)
        return SQLite.Statement(this, stmt, sql)
    }

    ; Execute one or many ';' separated statements (no parameters). Returns rows changed.
    Exec(sql) {
        this._Live()
        buf := SQLite._U8(sql)
        p := buf.Ptr
        endp := buf.Ptr + buf.Size - 1
        before := this.TotalChanges
        while p < endp {
            stmt := 0, tail := 0
            rc := DllCall(SQLite._P("sqlite3_prepare_v2"), "ptr", this._db, "ptr", p, "int", endp - p
                , "ptr*", &stmt, "ptr*", &tail, "Cdecl int")
            if rc
                this._Throw(rc, sql)
            if stmt {
                try {
                    loop {
                        rc := SQLite._Call("sqlite3_step", "ptr", stmt, "Cdecl int")
                        if rc != 100
                            break
                    }
                    if rc != 101
                        this._Throw(rc, sql)
                } finally {
                    SQLite._Call("sqlite3_finalize", "ptr", stmt, "Cdecl int")
                }
            }
            if tail <= p
                break
            p := tail
        }
        return this.TotalChanges - before
    }

    ; Run one statement with parameters (positional, array, or named Map/object).
    ; Returns the number of rows changed (0 for SELECT).
    Run(sql, params*) {
        stmt := this.Prepare(sql)
        try {
            if params.Length
                stmt.Bind(params*)
            while stmt.Step() {
            }
            return stmt.ReadOnly ? 0 : this.Changes
        } finally {
            stmt.Finalize()
        }
    }

    ; Result as SQLite.Table (Columns, Rows = Array of Arrays)
    GetTable(sql, params*) {
        stmt := this.Prepare(sql)
        try {
            if params.Length
                stmt.Bind(params*)
            rows := []
            while stmt.Step()
                rows.Push(stmt.Values())
            return SQLite.Table(stmt.ColumnNames, rows, stmt.DeclTypes)
        } finally {
            stmt.Finalize()
        }
    }

    ; All rows as an Array of Maps (case-insensitive column keys)
    All(sql, params*) {
        stmt := this.Prepare(sql)
        try {
            if params.Length
                stmt.Bind(params*)
            rows := []
            while stmt.Step()
                rows.Push(stmt.Row())
            return rows
        } finally {
            stmt.Finalize()
        }
    }

    ; First row as Map, or "" if there is none
    Get(sql, params*) {
        stmt := this.Prepare(sql)
        try {
            if params.Length
                stmt.Bind(params*)
            if stmt.Step()
                return stmt.Row()
            return ""
        } finally {
            stmt.Finalize()
        }
    }

    ; First column of first row, or ""
    Scalar(sql, params*) {
        stmt := this.Prepare(sql)
        try {
            if params.Length
                stmt.Bind(params*)
            if stmt.Step()
                return stmt.Value(1)
            return ""
        } finally {
            stmt.Finalize()
        }
    }

    ; First column of every row as an Array
    Column(sql, params*) {
        stmt := this.Prepare(sql)
        try {
            if params.Length
                stmt.Bind(params*)
            out := []
            while stmt.Step()
                out.Push(stmt.Value(1))
            return out
        } finally {
            stmt.Finalize()
        }
    }

    ; Streaming iteration:  for row in db.Each(sql, args*)   /   for i, row in ...
    Each(sql, params*) {
        stmt := this.Prepare(sql)
        if params.Length
            stmt.Bind(params*)
        return stmt
    }

    ; =========================================================================
    ;  Transactions
    ; =========================================================================
    Begin(mode := "") {
        this.Exec("BEGIN " mode)
    }

    Commit() {
        this.Exec("COMMIT")
    }

    Rollback() {
        this.Exec("ROLLBACK")
    }

    Savepoint(name) {
        this.Exec("SAVEPOINT " SQLite.QuoteId(name))
    }

    ReleaseSavepoint(name) {
        this.Exec("RELEASE " SQLite.QuoteId(name))
    }

    RollbackTo(name) {
        this.Exec("ROLLBACK TO " SQLite.QuoteId(name))
    }

    ; Run fn(db) atomically. Commits on success, rolls back and rethrows on error.
    ; Nested calls automatically use savepoints.
    Transaction(fn, mode := "IMMEDIATE") {
        if this.InTransaction {
            this._sp += 1
            name := "sp_" this._sp
            this.Exec("SAVEPOINT " name)
            try {
                fn(this)
            } catch as e {
                this.Exec("ROLLBACK TO " name)
                this.Exec("RELEASE " name)
                throw e
            }
            this.Exec("RELEASE " name)
        } else {
            this.Begin(mode)
            try {
                fn(this)
            } catch as e {
                try {
                    this.Rollback()
                }
                throw e
            }
            this.Commit()
        }
        return true
    }

    ; =========================================================================
    ;  CRUD helpers (data = Map or object: column -> value)
    ; =========================================================================
    ; onConflict: "", "REPLACE", "IGNORE", "ABORT", "FAIL", "ROLLBACK". Returns rowid.
    Insert(table, data, onConflict := "") {
        kv := SQLite._Pairs(data)
        verb := onConflict != "" ? "INSERT OR " onConflict : "INSERT"
        if !kv[1].Length {
            this.Run(verb " INTO " SQLite.QuoteId(table) " DEFAULT VALUES")
        } else {
            ph := []
            loop kv[1].Length
                ph.Push("?")
            this.Run(verb " INTO " SQLite.QuoteId(table) " (" SQLite._QuoteList(kv[1]) ") VALUES ("
                SQLite._Join(ph) ")", kv[2])
        }
        return this.LastInsertId
    }

    ; Insert many rows (Array of Map/object) inside one transaction. Returns count.
    InsertMany(table, rows, onConflict := "") {
        if !rows.Length
            return 0
        keys := SQLite._Pairs(rows[1])[1]
        ph := []
        loop keys.Length
            ph.Push("?")
        verb := onConflict != "" ? "INSERT OR " onConflict : "INSERT"
        stmt := this.Prepare(verb " INTO " SQLite.QuoteId(table) " (" SQLite._QuoteList(keys)
            ") VALUES (" SQLite._Join(ph) ")")
        own := !this.InTransaction
        if own
            this.Begin("IMMEDIATE")
        n := 0
        try {
            for r in rows {
                vals := []
                for k in keys {
                    if r is Map
                        vals.Push(r.Get(k, SQLite.NULL))
                    else
                        vals.Push(r.HasOwnProp(k) ? r.%k% : SQLite.NULL)
                }
                stmt.Bind(vals)
                while stmt.Step() {
                }
                n += 1
            }
        } catch as e {
            if own {
                try {
                    this.Rollback()
                }
            }
            stmt.Finalize()
            throw e
        }
        stmt.Finalize()
        if own
            this.Commit()
        return n
    }

    ; UPDATE table SET <data> [WHERE where] ; extra args bind to ? in where. Returns rows changed.
    Update(table, data, where := "", params*) {
        kv := SQLite._Pairs(data)
        sets := []
        for k in kv[1]
            sets.Push(SQLite.QuoteId(k) " = ?")
        vals := kv[2]
        for p in params
            vals.Push(p)
        sql := "UPDATE " SQLite.QuoteId(table) " SET " SQLite._Join(sets)
        if where != ""
            sql .= " WHERE " where
        return this.Run(sql, vals)
    }

    Delete(table, where := "", params*) {
        sql := "DELETE FROM " SQLite.QuoteId(table)
        if where != ""
            sql .= " WHERE " where
        return this.Run(sql, params)
    }

    ; INSERT ... ON CONFLICT(conflict) DO UPDATE. conflict = column name or Array of names.
    ; updateCols (optional Array): columns to update on conflict (default: all non-conflict columns)
    Upsert(table, data, conflict, updateCols := "") {
        kv := SQLite._Pairs(data)
        confl := conflict is Array ? conflict : [conflict]
        ph := []
        loop kv[1].Length
            ph.Push("?")
        sql := "INSERT INTO " SQLite.QuoteId(table) " (" SQLite._QuoteList(kv[1]) ") VALUES ("
            . SQLite._Join(ph) ") ON CONFLICT (" SQLite._QuoteList(confl) ")"
        cols := []
        if IsObject(updateCols) {
            cols := updateCols
        } else {
            for k in kv[1] {
                isKey := false
                for c in confl {
                    if k = c
                        isKey := true
                }
                if !isKey
                    cols.Push(k)
            }
        }
        if cols.Length {
            sets := []
            for c in cols
                sets.Push(SQLite.QuoteId(c) " = excluded." SQLite.QuoteId(c))
            sql .= " DO UPDATE SET " SQLite._Join(sets)
        } else {
            sql .= " DO NOTHING"
        }
        this.Run(sql, kv[2])
        return this.LastInsertId
    }

    Count(table, where := "", params*) {
        sql := "SELECT COUNT(*) FROM " SQLite.QuoteId(table)
        if where != ""
            sql .= " WHERE " where
        return this.Scalar(sql, params*)
    }

    Exists(table, where := "", params*) {
        sql := "SELECT 1 FROM " SQLite.QuoteId(table)
        if where != ""
            sql .= " WHERE " where
        return this.Scalar(sql " LIMIT 1", params*) == 1
    }

    ; =========================================================================
    ;  Schema management
    ; =========================================================================
    ; columns: Array of "name TYPE ..." strings or [name, definition] pairs
    ; opts: IfNotExists(true), Temp, WithoutRowid, Strict, Constraints (Array of strings)
    CreateTable(name, columns, opts := "") {
        defs := []
        if columns is Array {
            for c in columns
                defs.Push(c is Array ? SQLite.QuoteId(c[1]) " " c[2] : c)
        } else {
            defs.Push(String(columns))
        }
        for c in SQLite._Opt(opts, "Constraints", [])
            defs.Push(c)
        sql := "CREATE " (SQLite._Opt(opts, "Temp", false) ? "TEMP " : "") "TABLE "
            . (SQLite._Opt(opts, "IfNotExists", true) ? "IF NOT EXISTS " : "")
            . SQLite.QuoteId(name) " (" SQLite._Join(defs) ")"
        tail := []
        if SQLite._Opt(opts, "WithoutRowid", false)
            tail.Push("WITHOUT ROWID")
        if SQLite._Opt(opts, "Strict", false)
            tail.Push("STRICT")
        if tail.Length
            sql .= " " SQLite._Join(tail)
        return this.Exec(sql)
    }

    CreateIndex(name, table, cols, unique := false, where := "") {
        cl := cols is Array ? SQLite._QuoteList(cols) : SQLite.QuoteId(cols)
        sql := "CREATE " (unique ? "UNIQUE " : "") "INDEX IF NOT EXISTS " SQLite.QuoteId(name)
            . " ON " SQLite.QuoteId(table) " (" cl ")"
        if where != ""
            sql .= " WHERE " where
        return this.Exec(sql)
    }

    CreateView(name, selectSql, ifNotExists := true) {
        return this.Exec("CREATE VIEW " (ifNotExists ? "IF NOT EXISTS " : "") SQLite.QuoteId(name) " AS " selectSql)
    }

    AddColumn(table, definition) {
        return this.Exec("ALTER TABLE " SQLite.QuoteId(table) " ADD COLUMN " definition)
    }

    RenameTable(oldName, newName) {
        return this.Exec("ALTER TABLE " SQLite.QuoteId(oldName) " RENAME TO " SQLite.QuoteId(newName))
    }

    RenameColumn(table, oldName, newName) {
        return this.Exec("ALTER TABLE " SQLite.QuoteId(table) " RENAME COLUMN " SQLite.QuoteId(oldName)
            . " TO " SQLite.QuoteId(newName))
    }

    DropColumn(table, column) {
        return this.Exec("ALTER TABLE " SQLite.QuoteId(table) " DROP COLUMN " SQLite.QuoteId(column))
    }

    DropTable(name, ifExists := true) {
        return this.Exec("DROP TABLE " (ifExists ? "IF EXISTS " : "") SQLite.QuoteId(name))
    }

    DropView(name, ifExists := true) {
        return this.Exec("DROP VIEW " (ifExists ? "IF EXISTS " : "") SQLite.QuoteId(name))
    }

    DropIndex(name, ifExists := true) {
        return this.Exec("DROP INDEX " (ifExists ? "IF EXISTS " : "") SQLite.QuoteId(name))
    }

    ; Delete all rows (and reset AUTOINCREMENT counter when resetSeq)
    Clear(table, resetSeq := false) {
        n := this.Run("DELETE FROM " SQLite.QuoteId(table))
        if resetSeq && this.TableExists("sqlite_sequence")
            this.Run("DELETE FROM sqlite_sequence WHERE name = ?", table)
        return n
    }

    ; ---- introspection ------------------------------------------------------
    Tables(includeSystem := false) {
        sql := "SELECT name FROM sqlite_master WHERE type = 'table'"
        if !includeSystem
            sql .= " AND name NOT LIKE 'sqlite\_%' ESCAPE '\'"
        return this.Column(sql " ORDER BY name")
    }

    Views() => this.Column("SELECT name FROM sqlite_master WHERE type = 'view' ORDER BY name")
    Triggers() => this.Column("SELECT name FROM sqlite_master WHERE type = 'trigger' ORDER BY name")

    Indexes(table := "") {
        if table = ""
            return this.Column("SELECT name FROM sqlite_master WHERE type = 'index' ORDER BY name")
        return this.Column("SELECT name FROM pragma_index_list(?) ORDER BY name", table)
    }

    TableExists(name) => this.Scalar("SELECT 1 FROM sqlite_master WHERE type IN ('table','view') AND name = ? COLLATE NOCASE", name) == 1

    ; Array of Maps: cid, name, type, notnull, dflt_value, pk
    Columns(table) => this.All("PRAGMA table_info(" SQLite.QuoteId(table) ")")

    ColumnNames(table) {
        out := []
        for c in this.Columns(table)
            out.Push(c["name"])
        return out
    }

    PrimaryKey(table) {
        pk := []
        for c in this.Columns(table) {
            if c["pk"] > 0
                pk.Push([c["pk"], c["name"]])
        }
        out := []
        loop pk.Length {
            for p in pk {
                if p[1] = A_Index
                    out.Push(p[2])
            }
        }
        return out
    }

    ForeignKeyList(table) => this.All("PRAGMA foreign_key_list(" SQLite.QuoteId(table) ")")

    ; Array of Maps: type, name, tbl_name, sql
    Schema() => this.All("SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name")

    ; CREATE statement of a table/view/index/trigger
    SchemaSQL(name) => this.Scalar("SELECT sql FROM sqlite_master WHERE name = ? COLLATE NOCASE", name)

    ; Apply ordered migrations tracked in PRAGMA user_version.
    ; steps: Array of SQL strings (may hold many statements) or functions fn(db).
    Migrate(steps) {
        current := this.UserVersion
        applied := 0
        for i, step in steps {
            if i <= current
                continue
            this.Transaction(SQLite._MigStep.Bind(SQLite, step, i))
            applied += 1
        }
        return applied
    }

    static _MigStep(step, ver, db) {
        if IsObject(step)
            step(db)
        else
            db.Exec(step)
        db.Pragma("user_version", ver)
    }

    ; =========================================================================
    ;  PRAGMA / maintenance
    ; =========================================================================
    ; Pragma("journal_mode")  or  Pragma("journal_mode", "WAL")
    ; (string values are passed verbatim - quote them yourself if needed)
    Pragma(name, value?) {
        sql := "PRAGMA " name
        if IsSet(value)
            sql .= " = " value
        t := this.GetTable(sql)
        if t.Count = 1 && t.ColumnCount = 1
            return t.Rows[1][1]
        if t.Count = 0
            return ""
        return t
    }

    Vacuum(into := "") {
        return this.Exec(into = "" ? "VACUUM" : "VACUUM INTO " SQLite.Quote(into))
    }

    Analyze() => this.Exec("ANALYZE")
    Optimize() => this.Exec("PRAGMA optimize")
    Checkpoint(mode := "PASSIVE") => this.GetTable("PRAGMA wal_checkpoint(" mode ")")

    ; Returns true when the database is healthy, otherwise a string of problems.
    IntegrityCheck(quick := false) {
        res := this.Column("PRAGMA " (quick ? "quick_check" : "integrity_check"))
        if res.Length = 1 && res[1] = "ok"
            return true
        return SQLite._Join(res, "`n")
    }

    ; Online backup to a file. progress(remainingPages, totalPages) is optional.
    Backup(destPath, progress := "", pagesPerStep := 100) {
        dest := SQLite(destPath, {ForeignKeys: false})
        try {
            SQLite._Copy(this, dest, progress, pagesPerStep)
        } finally {
            dest.Close()
        }
        return true
    }

    ; Replace the content of this database with a backup file.
    Restore(srcPath, progress := "", pagesPerStep := 100) {
        src := SQLite(srcPath, {ReadOnly: true, ForeignKeys: false})
        try {
            SQLite._Copy(src, this, progress, pagesPerStep)
        } finally {
            src.Close()
        }
        return true
    }

    static _Copy(src, dst, progress, pages) {
        b := DllCall(SQLite._P("sqlite3_backup_init"), "ptr", dst._db, "astr", "main", "ptr", src._db
            , "astr", "main", "Cdecl ptr")
        if !b
            dst._Throw(dst.ErrorCode)
        loop {
            rc := SQLite._Call("sqlite3_backup_step", "ptr", b, "int", pages, "Cdecl int")
            if IsObject(progress) {
                progress(SQLite._Call("sqlite3_backup_remaining", "ptr", b, "Cdecl int")
                    , SQLite._Call("sqlite3_backup_pagecount", "ptr", b, "Cdecl int"))
            }
            if rc = 101
                break
            if rc = 0
                continue
            if rc = 5 || rc = 6 {
                Sleep(50)
                continue
            }
            SQLite._Call("sqlite3_backup_finish", "ptr", b, "Cdecl int")
            dst._Throw(rc)
        }
        SQLite._Call("sqlite3_backup_finish", "ptr", b, "Cdecl int")
    }

    ; =========================================================================
    ;  Import / export / scripts
    ; =========================================================================
    ; Full SQL dump (schema + data) as text
    Dump() {
        lines := ["PRAGMA foreign_keys=OFF;", "BEGIN TRANSACTION;"]
        skip := " AND name NOT LIKE 'sqlite\_%' ESCAPE '\'"
        tables := this.All("SELECT name, sql FROM sqlite_master WHERE type = 'table' AND sql IS NOT NULL" skip " ORDER BY rowid")
        for t in tables
            lines.Push(t["sql"] ";")
        for t in tables {
            name := t["name"]
            exprs := []
            for c in this.ColumnNames(name)
                exprs.Push("quote(" SQLite.QuoteId(c) ")")
            if !exprs.Length
                continue
            q := "SELECT 'INSERT INTO " StrReplace(SQLite.QuoteId(name), "'", "''") " VALUES(' || "
                . SQLite._Join(exprs, " || ',' || ") " || ');' FROM " SQLite.QuoteId(name)
            st := this.Prepare(q)
            try {
                while st.Step()
                    lines.Push(st.Value(1))
            } finally {
                st.Finalize()
            }
        }
        others := this.All("SELECT sql FROM sqlite_master WHERE type <> 'table' AND sql IS NOT NULL" skip
            . " ORDER BY CASE type WHEN 'index' THEN 0 WHEN 'view' THEN 1 ELSE 2 END, rowid")
        for o in others
            lines.Push(o["sql"] ";")
        lines.Push("COMMIT;")
        return SQLite._Join(lines, "`n") "`n"
    }

    DumpToFile(path) {
        f := FileOpen(path, "w", "UTF-8-RAW")
        f.Write(this.Dump())
        f.Close()
    }

    ; Execute a .sql script file
    ExecFile(path, encoding := "UTF-8") => this.Exec(FileRead(path, encoding))

    ; source = table name or a SELECT/WITH/PRAGMA statement. opts: Delimiter, Header(true), Bom(true)
    ExportCSV(source, path, opts := "", params*) {
        delim := SQLite._Opt(opts, "Delimiter", ",")
        if RegExMatch(source, "i)^\s*(SELECT|WITH|PRAGMA|VALUES)\b")
            t := this.GetTable(source, params*)
        else
            t := this.GetTable("SELECT * FROM " SQLite.QuoteId(source))
        text := t.ToCSV(delim, SQLite._Opt(opts, "Header", true))
        f := FileOpen(path, "w", SQLite._Opt(opts, "Bom", true) ? "UTF-8" : "UTF-8-RAW")
        f.Write(text)
        f.Close()
        return t.Count
    }

    ; opts: Delimiter(","), Header(true), Create(true), EmptyAsNull(false), Encoding("UTF-8")
    ImportCSV(table, path, opts := "") {
        delim := SQLite._Opt(opts, "Delimiter", ",")
        header := SQLite._Opt(opts, "Header", true)
        create := SQLite._Opt(opts, "Create", true)
        emptyNull := SQLite._Opt(opts, "EmptyAsNull", false)
        rows := SQLite.ParseCSV(FileRead(path, SQLite._Opt(opts, "Encoding", "UTF-8")), delim)
        if !rows.Length
            return 0
        if header {
            cols := rows.RemoveAt(1)
            for i, c in cols
                cols[i] := Trim(c)
        } else {
            cols := this.ColumnNames(table)
        }
        if create && !this.TableExists(table) {
            defs := []
            for c in cols
                defs.Push([c, "TEXT"])
            this.CreateTable(table, defs)
        }
        ph := []
        loop cols.Length
            ph.Push("?")
        stmt := this.Prepare("INSERT INTO " SQLite.QuoteId(table) " (" SQLite._QuoteList(cols) ") VALUES ("
            SQLite._Join(ph) ")")
        own := !this.InTransaction
        if own
            this.Begin("IMMEDIATE")
        n := 0
        try {
            for row in rows {
                vals := []
                loop cols.Length {
                    v := row.Has(A_Index) ? row[A_Index] : SQLite.NULL
                    if emptyNull && !IsObject(v) && v = ""
                        v := SQLite.NULL
                    vals.Push(v)
                }
                stmt.Bind(vals)
                while stmt.Step() {
                }
                n += 1
            }
        } catch as e {
            if own {
                try {
                    this.Rollback()
                }
            }
            stmt.Finalize()
            throw e
        }
        stmt.Finalize()
        if own
            this.Commit()
        return n
    }

    ; =========================================================================
    ;  User-defined SQL functions
    ; =========================================================================
    ; db.CreateFunction("reverse", 1, (s) => ...)   -> SELECT reverse(name) FROM ...
    ; fn receives the SQL arguments and MUST return a value (use SQLite.NULL for NULL).
    ; nArgs = -1 for variadic. Call Close() explicitly when you registered functions.
    CreateFunction(name, nArgs, fn, deterministic := true) {
        this._Live()
        cb := CallbackCreate((ctx, argc, argv) => SQLite._FuncThunk(ctx, argc, argv, fn), "C", 3)
        flags := 1 | (deterministic ? 0x800 : 0)
        nb := SQLite._U8(name)
        rc := DllCall(SQLite._P("sqlite3_create_function_v2"), "ptr", this._db, "ptr", nb, "int", nArgs
            , "int", flags, "ptr", 0, "ptr", cb, "ptr", 0, "ptr", 0, "ptr", 0, "Cdecl int")
        if rc {
            CallbackFree(cb)
            this._Throw(rc)
        }
        key := StrLower(name) ":" nArgs
        if this._funcs.Has(key)
            CallbackFree(this._funcs[key])
        this._funcs[key] := cb
    }

    static _FuncThunk(ctx, argc, argv, fn) {
        argc &= 0xFFFFFFFF
        args := []
        loop argc
            args.Push(SQLite._ValueGet(NumGet(argv, (A_Index - 1) * A_PtrSize, "ptr")))
        try {
            r := fn(args*)
        } catch as e {
            msg := SQLite._U8(e.Message)
            SQLite._Call("sqlite3_result_error", "ptr", ctx, "ptr", msg, "int", msg.Size - 1, "Cdecl int")
            return 0
        }
        SQLite._SetResult(ctx, r)
        return 0
    }

    static _ValueGet(p) {
        switch SQLite._Call("sqlite3_value_type", "ptr", p, "Cdecl int") {
            case 1: return SQLite._Call("sqlite3_value_int64", "ptr", p, "Cdecl int64")
            case 2: return SQLite._Call("sqlite3_value_double", "ptr", p, "Cdecl double")
            case 3:
                tp := SQLite._Call("sqlite3_value_text", "ptr", p, "Cdecl ptr")
                n := SQLite._Call("sqlite3_value_bytes", "ptr", p, "Cdecl int")
                return n ? StrGet(tp, n, "UTF-8") : ""
            case 4:
                bp := SQLite._Call("sqlite3_value_blob", "ptr", p, "Cdecl ptr")
                n := SQLite._Call("sqlite3_value_bytes", "ptr", p, "Cdecl int")
                b := Buffer(n)
                if n
                    DllCall("RtlMoveMemory", "ptr", b, "ptr", bp, "ptr", n)
                return b
            default: return SQLite.NullValue
        }
    }

    static _SetResult(ctx, v?) {
        if SQLite._IsNull(v?) {
            SQLite._Call("sqlite3_result_null", "ptr", ctx, "Cdecl int")
        } else if v is Integer {
            SQLite._Call("sqlite3_result_int64", "ptr", ctx, "int64", v, "Cdecl int")
        } else if v is Float {
            SQLite._Call("sqlite3_result_double", "ptr", ctx, "double", v, "Cdecl int")
        } else if v is Buffer {
            if v.Size
                SQLite._Call("sqlite3_result_blob", "ptr", ctx, "ptr", v.Ptr, "int", v.Size, "ptr", -1, "Cdecl int")
            else
                SQLite._Call("sqlite3_result_zeroblob", "ptr", ctx, "int", 0, "Cdecl int")
        } else {
            b := SQLite._U8(String(v))
            SQLite._Call("sqlite3_result_text", "ptr", ctx, "ptr", b, "int", b.Size - 1, "ptr", -1, "Cdecl int")
        }
    }

    ; =========================================================================
    ;  Prepared statement
    ; =========================================================================
    class Statement {
        __New(db, ptr, sql) {
            this.DB := db
            this.Ptr := ptr
            this.SQL := sql
            this._names := ""
            this._types := ""
        }

        __Delete() {
            this.Finalize()
        }

        _Live() {
            if !this.Ptr
                throw SQLiteError("Statement has been finalized", 21, this.SQL)
        }

        Finalize() {
            if this.Ptr {
                SQLite._Call("sqlite3_finalize", "ptr", this.Ptr, "Cdecl int")
                this.Ptr := 0
            }
        }

        ParamCount => SQLite._Call("sqlite3_bind_parameter_count", "ptr", this.Ptr, "Cdecl int")
        ColumnCount => SQLite._Call("sqlite3_column_count", "ptr", this.Ptr, "Cdecl int")
        ReadOnly => !!SQLite._Call("sqlite3_stmt_readonly", "ptr", this.Ptr, "Cdecl int")

        ColumnNames {
            get {
                if !IsObject(this._names) {
                    a := []
                    loop this.ColumnCount {
                        p := SQLite._Call("sqlite3_column_name", "ptr", this.Ptr, "int", A_Index - 1, "Cdecl ptr")
                        a.Push(p ? StrGet(p, "UTF-8") : "")
                    }
                    this._names := a
                }
                return this._names
            }
        }

        DeclTypes {
            get {
                if !IsObject(this._types) {
                    a := []
                    loop this.ColumnCount {
                        p := SQLite._Call("sqlite3_column_decltype", "ptr", this.Ptr, "int", A_Index - 1, "Cdecl ptr")
                        a.Push(p ? StrGet(p, "UTF-8") : "")
                    }
                    this._types := a
                }
                return this._types
            }
        }

        Reset() {
            this._Live()
            SQLite._Call("sqlite3_reset", "ptr", this.Ptr, "Cdecl int")
            return this
        }

        ; Bind positional values, a single Array, or a single Map/object of named parameters
        Bind(params*) {
            this._Live()
            this.Reset()
            SQLite._Call("sqlite3_clear_bindings", "ptr", this.Ptr, "Cdecl int")
            if !params.Length
                return this
            if params.Length = 1 && params.Has(1) && IsObject(params[1]) && !SQLite._IsNull(params[1]) && !(params[1] is Buffer) {
                p := params[1]
                if p is Array {
                    params := p
                } else {
                    this._BindNamed(p)
                    return this
                }
            }
            loop params.Length {
                if params.Has(A_Index)
                    this.BindAt(A_Index, params[A_Index])
                else
                    this.BindAt(A_Index)
            }
            return this
        }

        _BindNamed(p) {
            if p is Map {
                for k, v in p
                    this._BindKey(k, v)
            } else {
                for k, v in p.OwnProps()
                    this._BindKey(k, v)
            }
        }

        _BindKey(k, v) {
            if IsInteger(k) {
                this.BindAt(k, v)
                return
            }
            idx := 0
            for pre in ["", ":", "@", "$"] {
                b := SQLite._U8(pre k)
                idx := SQLite._Call("sqlite3_bind_parameter_index", "ptr", this.Ptr, "ptr", b, "Cdecl int")
                if idx
                    break
            }
            if !idx
                throw SQLiteError("No such SQL parameter: " k, 25, this.SQL)
            this.BindAt(idx, v)
        }

        ; Bind one value to 1-based parameter index i
        BindAt(i, v?) {
            this._Live()
            stmt := this.Ptr
            if SQLite._IsNull(v?) {
                rc := SQLite._Call("sqlite3_bind_null", "ptr", stmt, "int", i, "Cdecl int")
            } else if v is Integer {
                rc := SQLite._Call("sqlite3_bind_int64", "ptr", stmt, "int", i, "int64", v, "Cdecl int")
            } else if v is Float {
                rc := SQLite._Call("sqlite3_bind_double", "ptr", stmt, "int", i, "double", v, "Cdecl int")
            } else if v is Buffer {
                if v.Size
                    rc := SQLite._Call("sqlite3_bind_blob", "ptr", stmt, "int", i, "ptr", v.Ptr, "int", v.Size, "ptr", -1, "Cdecl int")
                else
                    rc := SQLite._Call("sqlite3_bind_zeroblob", "ptr", stmt, "int", i, "int", 0, "Cdecl int")
            } else if IsObject(v) {
                throw TypeError("Cannot bind an object of type " Type(v) " to an SQL parameter")
            } else {
                b := SQLite._U8(String(v))
                rc := SQLite._Call("sqlite3_bind_text", "ptr", stmt, "int", i, "ptr", b, "int", b.Size - 1, "ptr", -1, "Cdecl int")
            }
            if rc
                this.DB._Throw(rc, this.SQL)
            return this
        }

        ; true when a row is available, false when finished
        Step() {
            this._Live()
            rc := SQLite._Call("sqlite3_step", "ptr", this.Ptr, "Cdecl int")
            if rc = 100
                return true
            if rc = 101
                return false
            this.DB._Throw(rc, this.SQL)
        }

        ; Reset + bind + run to completion. Returns rows changed.
        Run(params*) {
            this.Bind(params*)
            while this.Step() {
            }
            return this.ReadOnly ? 0 : this.DB.Changes
        }

        ; Reset + bind + collect everything as a SQLite.Table
        All(params*) {
            this.Bind(params*)
            rows := []
            while this.Step()
                rows.Push(this.Values())
            return SQLite.Table(this.ColumnNames, rows, this.DeclTypes)
        }

        ; Value of 1-based column i in the current row
        Value(i) {
            stmt := this.Ptr
            c := i - 1
            switch SQLite._Call("sqlite3_column_type", "ptr", stmt, "int", c, "Cdecl int") {
                case 1: return SQLite._Call("sqlite3_column_int64", "ptr", stmt, "int", c, "Cdecl int64")
                case 2: return SQLite._Call("sqlite3_column_double", "ptr", stmt, "int", c, "Cdecl double")
                case 3:
                    p := SQLite._Call("sqlite3_column_text", "ptr", stmt, "int", c, "Cdecl ptr")
                    n := SQLite._Call("sqlite3_column_bytes", "ptr", stmt, "int", c, "Cdecl int")
                    return n ? StrGet(p, n, "UTF-8") : ""
                case 4:
                    p := SQLite._Call("sqlite3_column_blob", "ptr", stmt, "int", c, "Cdecl ptr")
                    n := SQLite._Call("sqlite3_column_bytes", "ptr", stmt, "int", c, "Cdecl int")
                    b := Buffer(n)
                    if n
                        DllCall("RtlMoveMemory", "ptr", b, "ptr", p, "ptr", n)
                    return b
                default:
                    return this.DB.NullValue
            }
        }

        Values() {
            a := []
            loop this.ColumnCount
                a.Push(this.Value(A_Index))
            return a
        }

        Row() {
            names := this.ColumnNames
            m := Map()
            m.CaseSense := "Off"
            loop names.Length
                m[names[A_Index]] := this.Value(A_Index)
            return m
        }

        ; for row in stmt   /   for i, row in stmt
        __Enum(n) {
            this.Reset()
            if n = 1
                return (&r) => this.Step() ? (r := this.Row(), true) : false
            i := 0
            return (&k, &r) => this.Step() ? (k := ++i, r := this.Row(), true) : false
        }
    }

    ; =========================================================================
    ;  Result table
    ; =========================================================================
    class Table {
        __New(cols, rows, types := "") {
            this.Columns := cols
            this.Rows := rows
            this.Types := types
        }

        Count => this.Rows.Length
        ColumnCount => this.Columns.Length

        __Item[r] => this.Rows[r]

        ColumnIndex(name) {
            for i, c in this.Columns {
                if c = name
                    return i
            }
            return 0
        }

        ; All values of a column (by name or 1-based index)
        Column(col) {
            idx := IsInteger(col) ? col : this.ColumnIndex(col)
            if !idx
                throw ValueError("No such column: " col)
            out := []
            for row in this.Rows
                out.Push(row[idx])
            return out
        }

        Cell(r, col) => this.Rows[r][IsInteger(col) ? col : this.ColumnIndex(col)]

        ToMaps() {
            out := []
            for row in this.Rows {
                m := Map()
                m.CaseSense := "Off"
                loop this.Columns.Length
                    m[this.Columns[A_Index]] := row[A_Index]
                out.Push(m)
            }
            return out
        }

        ToCSV(delim := ",", header := true) {
            rows := []
            if header
                rows.Push(this.Columns)
            for row in this.Rows
                rows.Push(row)
            return SQLite.ToCSV(rows, delim)
        }

        ; JSON array of objects. pretty = one object per line
        ToJson(pretty := false) {
            items := []
            for row in this.Rows {
                parts := []
                loop this.Columns.Length
                    parts.Push(SQLite._JsonStr(this.Columns[A_Index]) ": " SQLite._JsonVal(row[A_Index]))
                items.Push("{" SQLite._Join(parts) "}")
            }
            if pretty
                return "[`n  " SQLite._Join(items, ",`n  ") "`n]"
            return "[" SQLite._Join(items, ",") "]"
        }

        ; Aligned ASCII table
        ToText() {
            n := this.Columns.Length
            w := []
            loop n
                w.Push(StrLen(this.Columns[A_Index]))
            cells := []
            for row in this.Rows {
                r := []
                loop n {
                    s := SQLite._Disp(row[A_Index])
                    r.Push(s)
                    if StrLen(s) > w[A_Index]
                        w[A_Index] := StrLen(s)
                }
                cells.Push(r)
            }
            line := "+"
            loop n
                line .= SQLite._Rep("-", w[A_Index] + 2) "+"
            out := line "`n|"
            loop n
                out .= " " this.Columns[A_Index] SQLite._Rep(" ", w[A_Index] - StrLen(this.Columns[A_Index])) " |"
            out .= "`n" line "`n"
            for r in cells {
                out .= "|"
                loop n
                    out .= " " r[A_Index] SQLite._Rep(" ", w[A_Index] - StrLen(r[A_Index])) " |"
                out .= "`n"
            }
            return out line
        }

        __Enum(n) {
            i := 0
            rows := this.Rows
            if n = 1
                return (&r) => ++i <= rows.Length ? (r := rows[i], true) : false
            return (&k, &r) => ++i <= rows.Length ? (k := i, r := rows[i], true) : false
        }
    }
}

; -----------------------------------------------------------------------------
class SQLiteError extends Error {
    ; Code = primary result code, ExtendedCode = extended code, SQL = offending SQL
    __New(message, code := 0, sql := "", ext := 0) {
        super.__New(message, -2)
        this.Code := code
        this.ExtendedCode := ext ? ext : code
        this.SQL := sql
    }
}

; =============================================================================
;  Demo - runs only when this file is executed directly
; =============================================================================
if (A_LineFile = A_ScriptFullPath) {
    try {
        db := SQLite(":memory:")
        out := "SQLite " SQLite.Version " via " SQLite.DllPath "`n`n"

        db.Migrate([
            "CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, age INTEGER, bio BLOB);"
            . "CREATE INDEX idx_users_age ON users(age);",
            "CREATE TABLE posts (id INTEGER PRIMARY KEY, user_id INTEGER REFERENCES users(id) ON DELETE CASCADE, title TEXT);"
        ])

        db.Insert("users", Map("name", "Joe", "age", 30))
        db.Run("INSERT INTO users(name, age) VALUES(?, ?)", "Sara", 25)
        db.Run("INSERT INTO users(name, age) VALUES(:n, :a)", Map("n", "Alfred", "a", 41))
        db.InsertMany("users", [{name: "Neda", age: 28}, {name: "Omid", age: 35}])
        db.Upsert("users", Map("name", "Ali", "age", 31), "name")
        db.Insert("posts", Map("user_id", 1, "title", "Hello `"world`""))

        db.CreateFunction("shout", 1, (s) => StrUpper(s) "!")
        out .= db.GetTable("SELECT id, name, shout(name) AS loud, age FROM users ORDER BY age DESC").ToText() "`n"

        out .= "Count: " db.Count("users", "age > ?", 26) "`n"
        out .= "Tables: " SQLite._Join(db.Tables()) "`n"
        out .= "Users columns: " SQLite._Join(db.ColumnNames("users")) "`n"
        out .= "Scalar avg(age): " db.Scalar("SELECT AVG(age) FROM users") "`n"
        out .= "JSON: " db.GetTable("SELECT name, age FROM users LIMIT 2").ToJson() "`n"

        db.Transaction((d) => d.Update("users", Map("age", 99), "name = ?", "Omid"))
        out .= "Omid age: " db.Scalar("SELECT age FROM users WHERE name = 'Omid'") "`n"
        out .= "Integrity: " db.IntegrityCheck() "   user_version: " db.UserVersion "`n`n"
        out .= "Dump:`n" db.Dump()
        MsgBox(out, "SQLite.ahk demo")
        db.Close()
    } catch as e {
        MsgBox("Error: " e.Message "`nCode: " (e.HasProp("Code") ? e.Code : "") "`nSQL: " (e.HasProp("SQL") ? e.SQL : "") "`nLine: " e.Line, "SQLite.ahk", 16)
    }
}
