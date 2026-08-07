package main

import (
	"context"
	"log"
	"os"

	"porkhelper/server/internal/config"
	"porkhelper/server/internal/mysqlstore"
	"porkhelper/server/migrations"
)

func main() {
	ctx := context.Background()
	cfg, err := config.Load(os.LookupEnv)
	if err != nil {
		log.Fatal(err)
	}
	if cfg.MySQLDSN == "" {
		log.Fatal("config: POKER_COACH_MYSQL_DSN is required to run migrations")
	}

	db, err := mysqlstore.Open(ctx, cfg.MySQLDSN)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	if err := migrations.Apply(ctx, db); err != nil {
		log.Fatal(err)
	}
}
