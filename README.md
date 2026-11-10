# goose-testkit

[![ci](https://github.com/rekanalar/goose-testkit/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-testkit/actions/workflows/ci.yml)

Test helpers for Goose programs. A failed check reports what it got and what it wanted, and the test goes on. The suite counts the results, prints a summary, and exits non-zero when a test fails.

The model is the `testing` package of Go. A test is a plain function. The caller calls each test by name, because Goose stores no function value. The `testgen` command finds those names in the source. It adds the `-run` filter of Go, shards and a retry count.

## Install

```goose
import testkit from "rekanalar/goose-testkit@v0.4.0";
```

Put the import in `test/run.goose`. Your library does not need it.

## Example

```goose
import std;
import testkit from "rekanalar/goose-testkit@v0.4.0";

fn test_add(t: testkit::T&) {
    testkit::eq_i64(t, 1 + 2, 3);
    testkit::eq_text(t, "a b", "a b");
}

fn main() {
    var t = testkit::new_t();
    testkit::begin(t, "test_add");
    test_add(t);
    testkit::end(t);
    testkit::finish(t);
}
```

`finish` prints the summary and the name of each test that ran. Compare that list with the tests in your source, so a test that nobody calls shows itself.

## Scoped tests, fixtures and tables

Goose cannot store a function, but a generic function can call a block. So the scoped forms take a trailing block and call it once.

```goose
testkit::run(t, "test_rows") { tt =>
    with_db(tt) { t2, db => testkit::eq_i64(t2, db.rows, 3) };
};
testkit::run(t, "test_square") { tt =>
    testkit::cases(tt, "n", 4) { t2, i => testkit::eq_i64(t2, square(i), i * i) };
};
```

A fixture is a generic function that sets up, calls the block, and tears down. The example `examples/scoped.goose` shows one. The teardown runs after a failed check and after a skip, because a check returns. Goose v2026.3 has no `defer`, so a fixture does not use one.

## The testgen command

The command reads the Goose files of `test/` and `src/` as text. It finds each `testkit::run(` and `testkit::begin(` call that names its test with a string literal. It writes `test/_gen.goose`, which holds the sorted names and the options of this run.

```
goose build -o testgen cmd/testgen.goose
./testgen -run 'math' -shard 1/2 -count 2
```

The suite hands the options to the library at the start of `main`. The example `examples/suite` shows the whole flow.

```goose
import _gen;
testkit::filter(t, _gen::run(), _gen::shard_i(), _gen::shard_n(), _gen::count());
```

| Option | What it does |
|---|---|
| `-run pattern` | Runs the tests that match. The rules are those of `go test -run`, as the limits list shows |
| `-shard i/n` | Runs the tests whose name hash mod n equals i - 1. The hash is FNV-1a on 32 bits, so a name stays in its shard on every system |
| `-count n` | Gives each test up to n attempts, as `rerun` does |

A pattern splits on `/`. Each part matches a name part that holds it as text. A leading `^` anchors the start. A trailing `$` anchors the end. A `|` separates alternative patterns.

A short pattern runs the whole subtree: `-run math` runs `math/sum`. A long pattern runs the parent alone: `-run math/x` runs `math` and none of its subtests. A test that the filter or the shard leaves out counts as a skip. The summary counts it under `left out`, and the names list does not hold it.

A broken call site makes the command exit with code 1. The message names the file and the line. It warns on stderr when two call sites share one name. It writes `test/_gen.goose` and no other file.

## The fuzz pass

A fuzz target takes hostile bytes. Its result belongs in the suite report. The caller runs goose-fuzz and hands the numbers over:

```goose
var rep = fuzz::Report { };
let found = fuzz::run("lexer", cfg, rep, worker);
var out: u8[>..] = [];
fuzz::format_report(out, rep);
testkit::fuzz_result(t, found, rep.runs, out[..]);
```

A run with no finding passes. A run with a finding fails the test and prints the report. A run of no inputs fails, because it proved nothing. The package imports nothing from goose-fuzz, so only the fuzz program needs it.

## API

| Call | What it does |
|---|---|
| `new_t()` | Gives an empty tracker. One tracker holds one suite |
| `begin(t, name)` | Starts a test. The name appears in the report |
| `end(t)` | Closes the test and counts it. Gives false when it failed |
| `eq_i64(t, got, want)` | Checks two integers. A mismatch reports both |
| `eq_f64(t, got, want, tol)` | Checks two floats within a tolerance. A NaN fails |
| `eq_text(t, got, want)` | Checks two texts. A mismatch reports the first differing byte and a window of each side |
| `eq_bytes(t, got, want)` | Checks two byte ranges, with the report of `eq_text` |
| `is_true(t, cond, label)` | Checks a condition. The label names it in the report |
| `fail(t, msg)` | Reports a failure and goes on |
| `skip(t, reason)` | Ends the checks of the test. A failure before the skip stays a failure |
| `xfail(t, reason)` | Marks the failures of the test as expected. A test that passes anyway counts as a pass, with a note |
| `run(t, name) { tt => ... }` | Runs one test: begin, the block, end. Gives false when the test failed |
| `scope(t, name) { t2 => ... }` | Runs a subtest of the running test, as `t.Run` does in Go. The name reads `parent/child`. A failed subtest fails the parent. A skipped one does not |
| `cases(t, name, n) { t2, i => ... }` | Runs one subtest for each row index below n. The name of a row reads `name/i`. Call it inside a test |
| `rerun(t, name, n) { tt => ... }` | Runs a test up to n times and stops at the first attempt that does not fail. Only the last attempt counts |
| `filter(t, run, shard_i, shard_n, count)` | Sets the options of the run. The generated file holds the values. A shard count of 0 turns the shard off |
| `matches(pat, name)` | Tells whether a name passes a `-run` pattern, by the rules of Go |
| `shard_of(name, n)` | Gives the shard of a name, 0 to n - 1 |
| `fuzz_result(t, found, runs, report)` | Records the result of one fuzz run. A finding fails. A run of no input fails |
| `put_report(out, report)` | Appends a report with each byte outside printable ASCII as `\xNN`, cut at 4096 bytes |
| `finish(t)` | Prints the counts and the names. Aborts when a test failed, so the exit code is not zero |

## Limits

- **The caller still calls each test.** pytest, Rust and Go run every test they find. Goose cannot store a function, so a test that `main` does not call does not run. The command finds the names. It does not call them.
- **No assert rewriting.** pytest rewrites `assert a == b` to show both sides. Goose has no such hook, so each check takes the two values as arguments.
- **A fixture is a function, not an injected argument.** pytest finds a fixture by the name of a parameter. Here the test calls the fixture function and passes a block. There is no autouse and no fixture override.
- **A hard abort skips the teardown.** The teardown runs after a failed check and after a skip. A process abort, such as a failed `assert`, ends the program first.
- **No plugins.** A plugin would need a hook that Goose cannot store. The report is plain text, so a program can read it.
- **`cases` and `scope` need a running test.** Call them inside `run`. Outside a test, the parent name is the last test that ran, or empty.
- **`rerun` follows pytest-rerunfailures.** Go `testing` has no retry. A failed attempt prints its failure lines, then a `RETRY` line.
- **No parallel runs.** One tracker runs one test at a time.
- **A block takes one trailing position.** Goose allows one trailing block for each call. Nest the calls for a fixture inside a case.
- **`finish` aborts to set the exit code.** Goose has no call that exits with a chosen code. A failed suite prints a runtime error line after the summary.
- **One tracker bounds its names.** It keeps 65536 bytes of test names. A test past that bound still runs and counts. The report counts the names it did not list.
- **The lexer reads text, not a syntax tree.** A name built at runtime stays invisible. The command finds `run` and `begin` calls only. It does not find a subtest name. A call through an alias import is not found.
- **A pattern is a small part of a regex.** Go reads each part as a regular expression. Here a part is text with `^`, `$` and `|`. Go reads `.` as any byte and `*` as a repeat. Here each one is a plain byte.
- **A name holds printable ASCII and no backslash.** The command refuses any other name. So the generated file stays plain text.
- **`-count` is a retry count.** Go `-count n` runs each test n times. Here n is the attempt limit of `rerun`. A test stops at its first pass.
- **A shard splits the top-level tests.** A subtest runs with its parent.
- **A left-out test counts as a skip.** Go reports no test that `-run` leaves out. Here the totals add up to the number of calls.
- **The fuzz target is a `thread_fn` line the caller writes.** goose-fuzz builds its worker that way. The package cannot wrap it.
- **The adapter takes numbers and text, not a `Report`.** A `Report` type would force the dependency on every user.
- **Coverage needs the compiler of goose-fuzz.** A system without the coverage flag runs blind. A blind run finds far less. See the goose-fuzz README.
- **A fuzz run takes time.** The default of the pass here is 20000 inputs for each target, about 7 seconds. A suite that runs it at every commit grows slow.
- **One generated file for each suite.** There is no watch mode. Run the command again after you add a test.
- **The command has bounds.** It reads 256 files and finds 4096 tests. A name holds 1024 bytes. A run holds 256 patterns. A count stops at 1000.
- **`eq_f64` follows Go.** Go has no tolerance check in `testing`. A NaN on either side fails here, as the comparison `<=` does in Go.

## Security

- **The report bounds what it prints.** A window of a differing text holds at most 48 bytes. A byte below 32 or above 126 prints as `\xNN`. A hostile text cannot write a control sequence to the terminal.
- **The library reads no file, runs no command and opens no network.** Only the `testgen` command reads files.
- **The name buffer has a bound.** A suite of many tests cannot grow the tracker without limit. Past 65536 bytes the tracker drops the name of each finished test.
- **The command writes one file.** It writes `test/_gen.goose` through an atomic write, and no other path. It runs no code and starts no command.
- **The generated file holds plain text only.** A name holds printable ASCII with no quote and no backslash. The `-run` pattern follows the same rule. A source cannot break out of the string literal in the generated file.
- **The lexer bounds every string.** A string ends at the end of its line. A string that never ends is a fault with the file and the line. A name holds at most 1024 bytes.
- **A file name prints without control bytes.** A message about a file replaces each byte outside printable ASCII with `?`. A hostile file name cannot write a control sequence to the terminal.
- **The counts have bounds.** A suite of hostile sources cannot grow the list past 4096 tests or 256 files.
- **Risk that stays: the command reads each source file whole.** It has no size cap. A file of many gigabytes in `test/` or `src/` uses that much memory. Run the command only on a tree you trust. Review a new file in a pull request before CI runs the command.
- **Risk that stays: the command follows links.** A link inside `test/` or `src/` can point to any readable file. A link to a device such as `/dev/zero` never ends, and the read exhausts memory. The command prints no file content. It prints matching names, and the path and line of a fault. Keep links out of those directories.
- **The report of a fuzz run prints escaped and bounded.** It holds abort messages of a hostile target. Each byte outside printable ASCII prints as `\xNN`. The print stops at 4096 bytes.
- **Test names and messages print as given.** The caller owns them. Only the windows of `eq_text` and `eq_bytes` escape control bytes.

## License

MIT
