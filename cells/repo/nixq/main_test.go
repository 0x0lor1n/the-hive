package main

import (
	"bytes"
	"strings"
	"testing"
	"time"
)

func run(t *testing.T, in string) string {
	t.Helper()
	var out bytes.Buffer
	f := newFilter(&out)
	f.Run(strings.NewReader(in))
	f.Summary(1500 * time.Millisecond)
	return out.String()
}

const noise = `these 2 derivations will be built:
  /nix/store/aaaa-foo.drv
  /nix/store/bbbb-bar.drv
these 3 paths will be fetched (1.20 MiB download, 5.00 MiB unpacked):
  /nix/store/cccc-baz
  /nix/store/dddd-qux
  /nix/store/eeee-quux
copying path '/nix/store/cccc-baz' from 'https://cache.nixos.org'...
copying path '/nix/store/dddd-qux' from 'https://cache.nixos.org'...
building '/nix/store/aaaa-foo.drv'...
building '/nix/store/bbbb-bar.drv'...
`

func TestSuccessCollapsesToSummary(t *testing.T) {
	got := run(t, noise)
	want := "nixq: built 2, fetched 2, 1.5s\n"
	if got != want {
		t.Fatalf("got %q\nwant %q", got, want)
	}
}

func TestBuildFailureIsVerbatim(t *testing.T) {
	fail := `error: builder for '/nix/store/aaaa-foo.drv' failed with exit code 1;
       last 3 log lines:
       > gcc: error: missing.c: No such file or directory
       > make: *** [Makefile:12: foo] Error 1
       > copying path '/nix/store/decoy' — looks like noise, must survive
       For full logs, run 'nix log /nix/store/aaaa-foo.drv'.
error: 1 dependencies of derivation '/nix/store/bbbb-bar.drv' failed to build
`
	got := run(t, noise+fail)
	if !strings.HasSuffix(got, fail+"nixq: built 2, fetched 2, 1.5s\n") {
		t.Fatalf("error body altered:\n%s", got)
	}
	if strings.Contains(got, "these 2 derivations") {
		t.Fatal("plan header leaked into output")
	}
}

func TestEvalErrorWithTrace(t *testing.T) {
	in := `evaluating file '/nix/store/xxxx-source/flake.nix'
trace: warning: option foo is deprecated
error:
       … while evaluating the attribute 'config'
         at /nix/store/xxxx-source/default.nix:12:3:
           11|
           12|   config = {
             |   ^
       error: attribute 'missing' missing
`
	got := run(t, in)
	want := strings.Join(strings.Split(in, "\n")[1:], "\n") + "nixq: built 0, fetched 0, 1.5s\n"
	if got != want {
		t.Fatalf("got:\n%s\nwant:\n%s", got, want)
	}
}

func TestWarningsAndUnknownLinesSurvive(t *testing.T) {
	in := `warning: Git tree '/home/x/repo' is dirty
copying path '/nix/store/cccc-baz' from 'https://cache.nixos.org'...
some line nixq has never seen before
`
	got := run(t, in)
	for _, s := range []string{"warning: Git tree", "some line nixq has never seen"} {
		if !strings.Contains(got, s) {
			t.Fatalf("lost %q in:\n%s", s, got)
		}
	}
	if strings.Contains(got, "copying path") {
		t.Fatal("copying line not dropped")
	}
}

func TestCarriageReturnProgress(t *testing.T) {
	in := "[1/0/2 built] building foo\r[2/0/2 built] building bar\rerror: boom\n"
	got := run(t, in)
	if !strings.HasPrefix(got, "error: boom\n") {
		t.Fatalf("got %q", got)
	}
}

func TestQuietWhenNothingDropped(t *testing.T) {
	if got := run(t, "warning: only this\n"); got != "warning: only this\n" {
		t.Fatalf("got %q", got)
	}
}

func TestFilteredSubcommands(t *testing.T) {
	cases := map[string]bool{
		"build .#x":             true,
		"--log-format raw eval": true,
		"flake check":           true,
		"run .#x":               false,
		"develop":               false,
		"shell nixpkgs#hello":   false,
		"repl":                  false,
		"log /nix/store/x":      false,
		"":                      false,
	}
	for args, want := range cases {
		if got := filtered(strings.Fields(args)); got != want {
			t.Errorf("filtered(%q) = %v, want %v", args, got, want)
		}
	}
}
