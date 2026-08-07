package migrations

import "embed"

// migrationFiles contains immutable, versioned schema migrations.
//
//go:embed *.sql
var migrationFiles embed.FS
