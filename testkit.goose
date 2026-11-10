// testkit - Test helpers for Goose programs: checks that report
// instead of abort, failure counts, case tables.
namespace testkit;

import std;
import scope;
import filter;
import lex;

// The most bytes of test names that one tracker keeps. A test past
// this bound still runs and counts. The report lists only the names
// that fit, and it counts the rest.
const MAX_NAME_BYTES: i64 = 65536;

// T holds the state of one test run. A test takes it as
// `t: testkit::T&` and hands it to every check. One tracker runs one
// suite; make one per program unless two suites run apart.
// Place holds a byte range in the name buffer.
struct Place {
    at: i64,
    len: i64,
}

struct T {
    // The name of the test that runs now.
    cur: Place,
    // The checks of the test that runs now.
    checks: i64,
    // The unexpected failures of the test that runs now.
    fails: i64,
    // The expected failures of the test that runs now, under xfail.
    expected_fails: i64,
    // The state of the test that runs now.
    skipped: bool,
    expected: bool,
    xfail_done: bool,
    // The totals over the suite.
    pass_tests: i64,
    fail_tests: i64,
    skip_tests: i64,
    xfail_tests: i64,
    total_checks: i64,
    // The tests whose names the tracker did not keep.
    unlisted: i64,
    // The options of this run, set by filter. An empty pattern and a
    // shard count of 0 select every test. The tests that the pattern
    // and the shard left out are counted as skips.
    pat: const u8[:],
    shard_i: i64,
    shard_n: i64,
    count: i64,
    filtered: i64,
    sharded: i64,
    // The bytes of every test name that ran, each ended by a line
    // feed. It stays the final field: a struct holds one growable
    // array, and it must come last.
    names: u8[>..],
}

// new_t gives an empty tracker.
fn new_t() -> T {
    return T { cur: Place { at: 0, len: 0 },
               checks: 0, fails: 0, expected_fails: 0, skipped: false, expected: false,
               xfail_done: false, pass_tests: 0, fail_tests: 0,
               skip_tests: 0, xfail_tests: 0, total_checks: 0, unlisted: 0, pat: "", shard_i: 0, shard_n: 0,
               count: 1, filtered: 0, sharded: 0, names: [] };
}

// begin starts a test. The name appears in the report.
fn begin(t: T&, name: const u8[:]) {
    t.cur.at = t.names.len;
    t.cur.len = name.len;
    for b in name { t.names.push(b); }
    t.names.push(10);
    t.checks = 0;
    t.fails = 0;
    t.expected_fails = 0;
    t.skipped = false;
    t.expected = false;
    t.xfail_done = false;
}

// end closes a test and sorts it into the totals. It gives the state
// of the test: true when it counts for the suite (a pass, an expected
// failure, a skip), false when an unexpected failure exists.
fn end(t: T&) -> bool {
    if t.expected {
        if t.expected_fails > 0 {
            t.xfail_tests = t.xfail_tests + 1;
        } else {
            t.pass_tests = t.pass_tests + 1;
            print("NOTE ", t.names[t.cur.at..t.cur.at + t.cur.len], ": passed, but xfail expects a failure");
        }
    }
    else if t.fails > 0 { t.fail_tests = t.fail_tests + 1; }
    else if t.skipped { t.skip_tests = t.skip_tests + 1; }
    else { t.pass_tests = t.pass_tests + 1; }
    t.total_checks = t.total_checks + t.checks;
    if t.names.len > MAX_NAME_BYTES {
        t.names.resize(t.cur.at, 0);
        t.unlisted = t.unlisted + 1;
    }
    let ok = t.fails == 0 || t.expected;
    t.checks = 0;
    t.fails = 0;
    t.expected_fails = 0;
    t.skipped = false;
    t.expected = false;
    return ok;
}

// fail reports a failure with a message and continues.
fn fail(t: T&, msg: const u8[:]) {
    if t.skipped { return; }
    t.checks = t.checks + 1;
    if t.expected { t.expected_fails = t.expected_fails + 1; return; }
    t.fails = t.fails + 1;
    print("FAIL ", t.names[t.cur.at..t.cur.at + t.cur.len], ": ", msg);
}

// skip marks the test skipped with a reason. The checks after it do
// not run, as t.Skip in Go ends the test. A failure before the skip
// stays a failure, as in Go.
fn skip(t: T&, reason: const u8[:]) {
    if t.skipped { return; }
    t.skipped = true;
    print("SKIP ", t.names[t.cur.at..t.cur.at + t.cur.len], ": ", reason);
}

// xfail marks the failures of the test as expected, with the bug that
// holds them. A test that passes anyway counts as a pass with a note.
fn xfail(t: T&, reason: const u8[:]) {
    if t.expected || t.skipped { return; }
    t.expected = true;
    t.xfail_done = true;
    print("XFAIL ", t.names[t.cur.at..t.cur.at + t.cur.len], ": ", reason);
}

// finish prints the summary and aborts when an unexpected failure
// exists, so the process exits non-zero for CI.
fn finish(t: T&) {
    print("testkit: ", t.pass_tests, " pass, ", t.fail_tests, " fail, ",
          t.skip_tests, " skip, ", t.xfail_tests, " xfail, ",
          t.total_checks, " checks");
    var i: i64 = 0;
    var start: i64 = 0;
    while i < t.names.len {
        if t.names[i] == 10 {
            print("  ran: ", t.names[start..i]);
            start = i + 1;
        }
        i = i + 1;
    }
    if t.unlisted > 0 { print("  and ", t.unlisted, " more test(s) not listed"); }
    if t.filtered > 0 || t.sharded > 0 {
        print("  left out: ", t.filtered, " by the run filter, ", t.sharded, " by the shard");
    }
    if t.fail_tests > 0 {
        abort("testkit: some tests failed; see the report above");
    }
}

import bytesdiff;

// eq_i64 checks two integers equal. On a mismatch it reports both.
fn eq_i64(t: T&, got: i64, want: i64) {
    if t.skipped { return; }
    t.checks = t.checks + 1;
    if got == want { return; }
    if t.expected { t.expected_fails = t.expected_fails + 1; return; }
    t.fails = t.fails + 1;
    print("FAIL ", t.names[t.cur.at..t.cur.at + t.cur.len], ": got ", got, ", want ", want);
}

// eq_f64 checks two floats equal within a tolerance. A NaN on either
// side fails, as Go's comparison does.
fn eq_f64(t: T&, got: f64, want: f64, tol: f64) {
    if t.skipped { return; }
    t.checks = t.checks + 1;
    let d = got - want;
    if d < 0.0 { if -d <= tol { return; } }
    else { if d <= tol { return; } }
    if t.expected { t.expected_fails = t.expected_fails + 1; return; }
    t.fails = t.fails + 1;
    print("FAIL ", t.names[t.cur.at..t.cur.at + t.cur.len], ": got ", got, ", want ", want, ", tol ", tol);
}

// is_true checks a condition, with a label for the report.
fn is_true(t: T&, cond: bool, label: const u8[:]) {
    if t.skipped { return; }
    t.checks = t.checks + 1;
    if cond { return; }
    if t.expected { t.expected_fails = t.expected_fails + 1; return; }
    t.fails = t.fails + 1;
    print("FAIL ", t.names[t.cur.at..t.cur.at + t.cur.len], ": ", label, " is false");
}

// eq_text checks two texts equal. On a mismatch it reports the first
// difference with a printable window on each side.
fn eq_text(t: T&, got: const u8[:], want: const u8[:]) {
    if t.skipped { return; }
    t.checks = t.checks + 1;
    if got == want { return; }
    if t.expected { t.expected_fails = t.expected_fails + 1; return; }
    t.fails = t.fails + 1;
    let name = t.names[t.cur.at..t.cur.at + t.cur.len];
    let at = bytesdiff::first_diff(got, want);
    var w1: u8[>..] = [];
    bytesdiff::show(w1, got, at);
    var w2: u8[>..] = [];
    bytesdiff::show(w2, want, at);
    print("FAIL ", name, ": texts differ at byte ", at);
    print("  got:  ", w1);
    print("  want: ", w2);
}

// eq_bytes checks two byte ranges equal, with the same report as
// eq_text.
fn eq_bytes(t: T&, got: const u8[:], want: const u8[:]) {
    eq_text(t, got, want);
}
