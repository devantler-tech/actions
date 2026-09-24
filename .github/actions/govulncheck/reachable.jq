# Govulncheck JSON protocol v1.0.0. A symbol in the first trace frame means
# reachable; module/package findings alone must not block callers.
# https://pkg.go.dev/golang.org/x/vuln/internal/govulncheck
def nonempty_string: type == "string" and length > 0;
def valid_finding:
  (.osv | type == "string" and test("^GO-[0-9]{4}-[0-9]+$")) and
  (.trace | type == "array" and length > 0) and
  all(.trace[];
    type == "object" and (.module | nonempty_string) and
    ((has("function") | not) or (.function | nonempty_string)));

if length == 0 or
   .[0].config.protocol_version != "v1.0.0" or
   .[0].config.scan_level != "symbol" or
   .[0].config.scan_mode != "source" or
   ([.[] | select(has("config"))] | length) != 1 or
   (all(.[];
     type == "object" and length == 1 and
     ((keys[0] == "config") or (keys[0] == "progress") or
      (keys[0] == "SBOM") or (keys[0] == "osv") or
      (keys[0] == "finding" and (.finding | valid_finding)))) | not)
then error("invalid or unsupported govulncheck stream")
else [.[] | select(has("finding")) | .finding |
      select(.trace[0].function != null) | .osv] | unique
end
