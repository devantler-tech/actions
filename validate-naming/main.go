package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

func run(args []string, out, errOut io.Writer) int {
	flags := flag.NewFlagSet("validate-naming", flag.ContinueOnError)
	flags.SetOutput(errOut)
	root := flags.String("root", ".", "repository directory to validate")
	configuration := flags.String("config", "", "configuration file, relative to root or absolute")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if *configuration == "" || flags.NArg() != 0 {
		return reportError(errOut, "usage: validate-naming --config <file> [--root <repository>]\n")
	}
	absolute, err := filepath.Abs(*root)
	if err != nil {
		return reportError(errOut, "cannot resolve repository directory\n")
	}
	configPath := *configuration
	if !filepath.IsAbs(configPath) {
		configPath = filepath.Join(absolute, configPath)
	}
	cfg, err := loadConfig(configPath)
	if err != nil {
		return reportError(errOut, "Configuration error: %v\n", err)
	}
	violations, err := validate(absolute, cfg)
	if err != nil {
		return reportError(errOut, "Validation error: %v\n", err)
	}
	for _, v := range violations {
		if _, err := fmt.Fprintf(out, "%q [%s]: %q\n", v.Path, v.Rule, v.Message); err != nil {
			return 2
		}
	}
	if len(violations) != 0 {
		if _, err := fmt.Fprintf(out, "%d naming violation(s).\n", len(violations)); err != nil {
			return 2
		}
		return 1
	}
	if _, err := fmt.Fprintln(out, "All manifest naming conventions satisfied."); err != nil {
		return 2
	}
	return 0
}

func reportError(out io.Writer, format string, args ...any) int {
	if _, err := fmt.Fprintf(out, format, args...); err != nil {
		return 2 // A broken diagnostic stream must still leave the CLI unsuccessful.
	}
	return 2
}

func main() { os.Exit(run(os.Args[1:], os.Stdout, os.Stderr)) }
