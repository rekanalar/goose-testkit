# goose-testkit

[![ci](https://github.com/rekanalar/goose-testkit/actions/workflows/ci.yml/badge.svg)](https://github.com/rekanalar/goose-testkit/actions/workflows/ci.yml)

Test helpers for Goose programs. A failed check reports what it got and what it wanted, and the test goes on. The suite counts the results, prints a summary, and exits non-zero when a test fails.

The model is the `testing` package of Go. A test is a plain function. The caller lists the tests by name, because Goose stores no function value.

## Install

```goose
import testkit from "rekanalar/goose-testkit@v0.1.0";
```

Put the import in `test/run.goose`. Your library does not need it.

## Example

```goose
import std;
import testkit from "rekanalar/goose-testkit@v0.1.0";

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
| `finish(t)` | Prints the counts and the names. Aborts when a test failed, so the exit code is not zero |

## Limits

- **The caller lists the tests.** pytest, Rust and Go find the tests for you. Goose cannot store a function, so a test that `main` does not call does not run. The summary names each test that ran.
- **No assert rewriting.** pytest rewrites `assert a == b` to show both sides. Goose has no such hook, so each check takes the two values as arguments.
- **No fixture machinery and no plugins.** A fixture is a function. Use `defer` for the teardown. Plugins would need runtime hooks that the language lacks.
- **No parallel runs.** One tracker runs one test at a time.
- **`finish` aborts to set the exit code.** Goose has no call that exits with a chosen code. A failed suite prints a runtime error line after the summary.
- **One tracker bounds its names.** It keeps 65536 bytes of test names. A test past that bound still runs and counts. The report counts the names it did not list.
- **`eq_f64` follows Go.** Go has no tolerance check in `testing`. A NaN on either side fails here, as the comparison `<=` does in Go.

## Security

- **The report bounds what it prints.** A window of a differing text holds at most 48 bytes. A byte below 32 or above 126 prints as `\xNN`. A hostile text cannot write a control sequence to the terminal.
- **The package reads no file, runs no command and opens no network.**
- **The name buffer has a bound.** A suite of many tests cannot grow the tracker without limit. Past 65536 bytes the tracker drops the name of each finished test.
- **Test names and messages print as given.** The caller owns them. Only the windows of `eq_text` and `eq_bytes` escape control bytes.

## License

MIT
