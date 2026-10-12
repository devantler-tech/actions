package fixture

import (
	"context"
	"database/sql"
	"errors"
	"net/url"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
	_ "github.com/jackc/pgx/v5/stdlib"
)

func fixtureDB(t *testing.T, key, role string) *sql.DB {
	t.Helper()
	raw := os.Getenv(key)
	u, err := url.Parse(raw)
	if err != nil || u == nil || u.User == nil {
		t.Fatal("explicit disposable database URL is required")
	}
	password, ok := u.User.Password()
	if u.Scheme != "postgres" || (u.Host != "127.0.0.1:5432" && u.Host != "127.0.0.1:55444") ||
		u.Path != "/ci_fixture_workflow_test" || u.User.Username() != role ||
		!ok || password != "fixture-only" || u.RawQuery != "sslmode=disable" || u.Fragment != "" {
		t.Fatal("database is not the explicitly isolated CI fixture")
	}
	db, err := sql.Open("pgx", raw)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return db
}

func TestNativeFixtureAndRoleBoundaries(t *testing.T) {
	if Value() != 42 {
		t.Fatal("native Go fixture result is wrong")
	}
	ctx, cancel := context.WithTimeout(t.Context(), 20*time.Second)
	defer cancel()
	migrator := fixtureDB(t, "CI_FIXTURE_TEST_MIGRATION_DATABASE_URL", "ci_fixture_migrator")
	runtime := fixtureDB(t, "CI_FIXTURE_TEST_DATABASE_URL", "ci_fixture_runtime")
	if err := migrator.PingContext(ctx); err != nil {
		t.Fatal(err)
	}
	if err := runtime.PingContext(ctx); err != nil {
		t.Fatal(err)
	}
	var user string
	if err := migrator.QueryRowContext(ctx, "SELECT current_user").Scan(&user); err != nil || user != "ci_fixture_migrator" {
		t.Fatalf("migration identity was not preserved: %v", err)
	}
	if _, err := migrator.ExecContext(ctx, "CREATE TABLE fixture_probe (id integer PRIMARY KEY, value text NOT NULL)"); err != nil {
		t.Fatal(err)
	}
	if _, err := migrator.ExecContext(ctx, "GRANT SELECT, INSERT ON fixture_probe TO ci_fixture_runtime"); err != nil {
		t.Fatal(err)
	}
	if _, err := runtime.ExecContext(ctx, "INSERT INTO fixture_probe VALUES (42, 'fictional fixture')"); err != nil {
		t.Fatal(err)
	}
	var value string
	if err := runtime.QueryRowContext(ctx, "SELECT value FROM fixture_probe WHERE id=42").Scan(&value); err != nil || value != "fictional fixture" {
		t.Fatalf("actual runtime read failed: %v", err)
	}
	for _, db := range []*sql.DB{migrator, runtime} {
		var superuser, createdb, createrole, inherit, bypass bool
		if err := db.QueryRowContext(ctx, "SELECT rolsuper, rolcreatedb, rolcreaterole, rolinherit, rolbypassrls FROM pg_roles WHERE rolname=current_user").
			Scan(&superuser, &createdb, &createrole, &inherit, &bypass); err != nil {
			t.Fatal(err)
		}
		if superuser || createdb || createrole || inherit || bypass {
			t.Fatal("fixture acquired privileged role capabilities")
		}
	}
	for _, statement := range []string{
		"ALTER TABLE fixture_probe ADD COLUMN forbidden integer",
		"CREATE TABLE forbidden_schema_write (id integer)",
		"CREATE ROLE forbidden_role",
		"CREATE DATABASE forbidden_database",
	} {
		_, err := runtime.ExecContext(ctx, statement)
		var denied *pgconn.PgError
		if !errors.As(err, &denied) || denied.Code != "42501" {
			t.Fatalf("expected an actual permission refusal, not operational failure: %v", err)
		}
	}
}
