// nixq is a PATH shim named "nix" for agent shells. It runs the real nix
// with stdin/stdout untouched and squeezes the progress noise out of stderr:
// "copying path ...", "building ...", store-path lists. It never drops
// diagnostics: from the first "error" line onward everything is passed
// through verbatim, warnings and traces always survive, and unknown lines
// are kept (fail-open).
//
// Humans are not affected: when stderr is a TTY, or NIXQ=off, nixq execs the
// real nix directly. Subcommands that run programs (run, shell, develop,
// repl, log) are also exec'd directly — their stderr belongs to the program.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

func main() {
	real, err := realNix()
	if err != nil {
		fmt.Fprintln(os.Stderr, "nixq:", err)
		os.Exit(127)
	}
	args := os.Args[1:]

	if os.Getenv("NIXQ") == "off" || isTerminal(os.Stderr) || !filtered(args) {
		if err := syscall.Exec(real, append([]string{"nix"}, args...), os.Environ()); err != nil {
			fmt.Fprintln(os.Stderr, "nixq: exec:", err)
			os.Exit(127)
		}
	}

	start := time.Now()
	cmd := exec.Command(real, args...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	pr, pw := io.Pipe()
	cmd.Stderr = pw

	f := newFilter(os.Stderr)
	done := make(chan struct{})
	go func() {
		f.Run(pr)
		close(done)
	}()

	runErr := cmd.Run()
	pw.Close()
	<-done
	f.Summary(time.Since(start))

	if runErr != nil {
		if ee, ok := runErr.(*exec.ExitError); ok {
			os.Exit(ee.ExitCode())
		}
		fmt.Fprintln(os.Stderr, "nixq:", runErr)
		os.Exit(1)
	}
}

// realNix is $NIXQ_REAL_NIX, else the first "nix" on PATH that is not us.
func realNix() (string, error) {
	if p := os.Getenv("NIXQ_REAL_NIX"); p != "" {
		return p, nil
	}
	self, _ := os.Executable()
	self, _ = filepath.EvalSymlinks(self)
	for _, dir := range filepath.SplitList(os.Getenv("PATH")) {
		cand := filepath.Join(dir, "nix")
		res, err := filepath.EvalSymlinks(cand)
		if err != nil || res == self {
			continue
		}
		if st, err := os.Stat(res); err == nil && !st.IsDir() && st.Mode()&0o111 != 0 {
			return res, nil
		}
	}
	return "", fmt.Errorf("real nix not found; set NIXQ_REAL_NIX")
}

// filtered reports whether stderr of this invocation is progress we may
// compress. Anything that hands the terminal to a program is left alone.
func filtered(args []string) bool {
	for i := 0; i < len(args); i++ {
		a := args[i]
		if strings.HasPrefix(a, "-") {
			// Global options that consume following words.
			switch a {
			case "--log-format", "--max-jobs", "-j", "--cores", "--store", "--eval-store":
				i++
			case "--option":
				i += 2
			}
			continue
		}
		switch a {
		case "build", "eval", "flake", "path-info", "copy", "store",
			"realisation", "derivation", "hash", "why-depends":
			return true
		}
		return false
	}
	return false
}

func isTerminal(f *os.File) bool {
	st, err := f.Stat()
	return err == nil && st.Mode()&os.ModeCharDevice != 0
}

// filter is the stderr state machine. Once verbatim is set nothing is dropped.
type filter struct {
	w        io.Writer
	verbatim bool
	inList   bool // inside a "these N derivations will be built:" block
	built    int
	fetched  int
	dropped  int
}

func newFilter(w io.Writer) *filter { return &filter{w: w} }

func (f *filter) Run(r io.Reader) {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 8*1024*1024)
	for sc.Scan() {
		// Progress bars redraw with \r; keep only the final segment.
		line := sc.Text()
		if i := strings.LastIndexByte(line, '\r'); i >= 0 {
			line = line[i+1:]
		}
		f.line(line)
	}
}

func (f *filter) line(line string) {
	if f.verbatim {
		fmt.Fprintln(f.w, line)
		return
	}
	trim := strings.TrimSpace(line)

	switch {
	case strings.HasPrefix(trim, "error"):
		// "error:" and "error (ignored):"; multi-line bodies follow indented.
		f.verbatim = true
		fmt.Fprintln(f.w, line)
		return
	case strings.HasPrefix(trim, "warning:"), strings.HasPrefix(trim, "trace:"),
		strings.HasPrefix(trim, "note:"):
		f.inList = false
		fmt.Fprintln(f.w, line)
		return
	}

	// Plan header + its indented store-path list.
	if (strings.HasPrefix(trim, "these ") || strings.HasPrefix(trim, "this ")) &&
		strings.Contains(trim, " will be ") {
		f.inList = true
		f.dropped++
		return
	}
	if f.inList {
		if strings.HasPrefix(line, " ") && strings.HasPrefix(trim, "/nix/store/") {
			f.dropped++
			return
		}
		f.inList = false
	}

	switch {
	case strings.HasPrefix(trim, "copying path "):
		f.fetched++
		f.dropped++
	case strings.HasPrefix(trim, "building '/nix/store/"):
		f.built++
		f.dropped++
	case strings.HasPrefix(trim, "querying info about "),
		strings.HasPrefix(trim, "downloading "),
		strings.HasPrefix(trim, "fetching "),
		strings.HasPrefix(trim, "unpacking "),
		strings.HasPrefix(trim, "evaluating file "),
		strings.HasPrefix(trim, "waiting for lock on "),
		strings.HasPrefix(trim, "waiting for a machine to build"),
		strings.HasPrefix(trim, "checking outputs of "),
		strings.HasPrefix(trim, "building '"),
		strings.HasPrefix(trim, "substituting "),
		trim == "":
		f.dropped++
	default:
		// Unknown: keep. Better a stray line than a lost one.
		fmt.Fprintln(f.w, line)
	}
}

// Summary prints one line accounting for what was dropped, so the reader
// knows work happened and roughly how much. Silent when nothing was dropped.
func (f *filter) Summary(d time.Duration) {
	if f.dropped == 0 {
		return
	}
	fmt.Fprintf(f.w, "nixq: built %d, fetched %d, %s\n",
		f.built, f.fetched, d.Round(100*time.Millisecond))
}
