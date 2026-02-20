Review the code in $ARGUMENTS against the engineering principles in this project.

Check for violations of:

**Clean Architecture**
- Do any handlers import `pgx`, `repository` structs, or perform DB calls directly?
- Do any `internal/engine/` or `internal/worker/` files import `gin` or HTTP types?
- Are concrete types being wired together anywhere other than `cmd/api/main.go`?

**SOLID**
- Does each file have a single clear responsibility?
- Are there any concrete type dependencies where an interface should be used?
- Are repositories defined as interfaces in the consuming package?

**Security (OWASP)**
- Are all DB queries parameterised? Any string-concatenated SQL?
- Is ownership checked on every route that accesses user data?
- Are any secrets or tokens being logged?
- Is input validated and sanitised at the HTTP boundary?

**12-Factor**
- Is any config hardcoded that should come from an env var?
- Is anything being logged to a file instead of stdout?
- Are migrations being run inside the app instead of as a one-off process?

**General**
- Is there raw SQL in a handler file?
- Are errors wrapped with context (`fmt.Errorf("package: operation: %w", err)`)?
- Is `fmt.Println` used anywhere in a production code path?

Report each violation with the file path, line number, and a short explanation of what rule it breaks and how to fix it.
