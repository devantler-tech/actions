package main

import (
	"bytes"
	"fmt"
	"path"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

type finding struct {
	line uint
	flag string
}

func scanSource(name string, source []byte) ([]finding, error) {
	file, err := syntax.NewParser(syntax.KeepComments(true)).Parse(bytes.NewReader(source), name)
	if err != nil {
		return nil, fmt.Errorf("invalid shell syntax (source omitted)")
	}
	allowed := map[uint]bool{}
	allowFile := false
	var directiveErr error
	syntax.Walk(file, func(node syntax.Node) bool {
		comment, ok := node.(*syntax.Comment)
		if !ok {
			return true
		}
		text := strings.TrimSpace(comment.Text)
		if !strings.HasPrefix(text, "pipefail-grep-guard:") {
			return true
		}
		fields := strings.Fields(strings.TrimPrefix(text, "pipefail-grep-guard:"))
		if len(fields) < 2 || (fields[0] != "allow" && fields[0] != "allow-file") {
			directiveErr = fmt.Errorf("line %d: invalid pipefail-grep-guard exception; use allow or allow-file followed by a reason", comment.Pos().Line())
			return true
		}
		if fields[0] == "allow-file" {
			allowFile = true
		} else {
			allowed[comment.Pos().Line()] = true
		}
		return true
	})
	if directiveErr != nil {
		return nil, directiveErr
	}
	var findings []finding
	syntax.Walk(file, func(node syntax.Node) bool {
		pipe, ok := node.(*syntax.BinaryCmd)
		if !ok || (pipe.Op != syntax.Pipe && pipe.Op != syntax.PipeAll) {
			return true
		}
		call := receivingCall(pipe.Y)
		if call == nil || allowFile {
			return true
		}
		for line := call.Pos().Line(); line <= call.End().Line(); line++ {
			if allowed[line] {
				return true
			}
		}
		if flag := earlyExitFlag(grepArgs(call.Args)); flag != "" {
			findings = append(findings, finding{call.Pos().Line(), flag})
		}
		return true
	})
	return findings, nil
}

// Only a single receiving command is resolved through grouping. General shell
// control flow, functions, and runtime command/argument expansion are not evaluated.
func receivingCall(stmt *syntax.Stmt) *syntax.CallExpr {
	switch cmd := stmt.Cmd.(type) {
	case *syntax.CallExpr:
		return cmd
	case *syntax.Subshell:
		if len(cmd.Stmts) == 1 {
			return receivingCall(cmd.Stmts[0])
		}
	case *syntax.Block:
		if len(cmd.Stmts) == 1 {
			return receivingCall(cmd.Stmts[0])
		}
	}
	return nil
}

// A literal is assembled without invoking shell expansion. Unknown words remain
// unknown, including dollar quoting, parameters, substitutions, and globs.
func literal(word *syntax.Word) (string, bool) { return literalParts(word.Parts, false) }
func literalParts(parts []syntax.WordPart, quoted bool) (string, bool) {
	var out strings.Builder
	for _, part := range parts {
		switch p := part.(type) {
		case *syntax.Lit:
			for i := 0; i < len(p.Value); i++ {
				c := p.Value[i]
				if c == '\\' && i+1 < len(p.Value) {
					next := p.Value[i+1]
					if !quoted || strings.ContainsRune("$`\"\\\n", rune(next)) {
						i++
						if next != '\n' {
							out.WriteByte(next)
						}
						continue
					}
				}
				if !quoted && strings.ContainsRune("*?[~", rune(c)) {
					return "", false
				}
				out.WriteByte(c)
			}
		case *syntax.SglQuoted:
			if p.Dollar {
				return "", false
			}
			out.WriteString(p.Value)
		case *syntax.DblQuoted:
			if p.Dollar {
				return "", false
			}
			text, ok := literalParts(p.Parts, true)
			if !ok {
				return "", false
			}
			out.WriteString(text)
		default:
			return "", false
		}
	}
	return out.String(), true
}

// Unwrap ordinary command and env invocations; query modes and unsupported env
// grammars (notably --split-string) cannot be treated as executable grep calls.
func grepArgs(args []*syntax.Word) []*syntax.Word {
	for len(args) > 0 {
		name, ok := literal(args[0])
		if !ok {
			return nil
		}
		args = args[1:]
		switch path.Base(name) {
		case "grep":
			return args
		case "command":
			for len(args) > 0 {
				option, ok := literal(args[0])
				if !ok {
					return nil
				}
				if option == "--" {
					args = args[1:]
					break
				}
				if option == "-p" {
					args = args[1:]
					continue
				}
				if strings.HasPrefix(option, "-") {
					return nil
				}
				break
			}
		case "env":
			for len(args) > 0 {
				option, ok := literal(args[0])
				if !ok {
					return nil
				}
				if option == "--" {
					args = args[1:]
					break
				}
				if option == "-i" || option == "--ignore-environment" || option == "-" || strings.Contains(option, "=") && !strings.HasPrefix(option, "-") {
					args = args[1:]
					continue
				}
				if option == "-u" || option == "--unset" || option == "-C" || option == "--chdir" {
					if len(args) < 2 {
						return nil
					}
					args = args[2:]
					continue
				}
				if strings.HasPrefix(option, "--unset=") || strings.HasPrefix(option, "--chdir=") {
					args = args[1:]
					continue
				}
				if strings.HasPrefix(option, "-") {
					return nil
				}
				break
			}
		default:
			return nil
		}
	}
	return nil
}

func earlyExitFlag(args []*syntax.Word) string {
	for i := 0; i < len(args); i++ {
		arg, ok := literal(args[i])
		if !ok {
			continue
		}
		if arg == "--" {
			return ""
		}
		if strings.HasPrefix(arg, "--") {
			option, value, hasValue := strings.Cut(arg, "=")
			switch option {
			case "--quiet", "--silent", "--files-with-matches":
				return option
			case "--max-count":
				if !hasValue && i+1 < len(args) {
					i++
					value, _ = literal(args[i])
				}
				if value != "-1" {
					return option
				}
			case "--regexp", "--file", "--after-context", "--before-context", "--context", "--binary-files", "--devices", "--directories", "--label", "--include", "--exclude", "--exclude-from", "--exclude-dir":
				if !hasValue {
					i++
				}
			}
			continue
		}
		if !strings.HasPrefix(arg, "-") || arg == "-" {
			continue
		}
		for j := 1; j < len(arg); j++ {
			switch arg[j] {
			case 'q', 'l':
				return "-" + string(arg[j])
			case 'm', 'e', 'f', 'A', 'B', 'C', 'd', 'D':
				value := arg[j+1:]
				if value == "" && i+1 < len(args) {
					i++
					value, _ = literal(args[i])
				}
				if arg[j] == 'm' && value != "-1" {
					return "-m"
				}
				j = len(arg)
			}
		}
	}
	return ""
}
