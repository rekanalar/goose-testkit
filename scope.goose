// Scoped tests, subtests, fixtures and case tables.
//
// Each form is a generic function that calls its type parameter and
// takes one trailing block. The package stores no callback, because
// Goose cannot store one.
namespace testkit;

import std;

// put_i64 appends the decimal text of n.
fn put_i64(out: u8[>..]&, n: i64) {
    var v = n;
    if v < 0 {
        out.push('-');
        v = -v;
    }
    var digits: u8[>..] = [];
    if v == 0 { digits.push('0'); }
    while v > 0 {
        digits.push((48 + v % 10) as u8);
        v = v / 10;
    }
    var k = digits.len;
    while k > 0 {
        k = k - 1;
        out.push(digits[k]);
    }
}

// run runs one test: it begins the test, calls the block with the
// tracker, and ends the test. The caller cannot forget either call.
// It gives false when an unexpected failure exists.
fn run<F>(t: T&, name: const u8[:]) -> bool {
    if !matches(t.pat, name) { leave_out(t, name, false); return true; }
    if t.shard_n > 0 && shard_of(name, t.shard_n) != t.shard_i - 1 {
        leave_out(t, name, true);
        return true;
    }
    if t.count > 1 { return rerun(t, name, t.count) { tt => F(tt) }; }
    begin(t, name);
    F(t);
    return end(t);
}

// scope runs a subtest of the test that runs now, as t.Run does in
// Go. The name reads parent/child. A failed subtest fails the parent.
// A skipped subtest does not. A parent that skipped runs no subtest.
fn scope<F>(t: T&, name: const u8[:]) -> bool {
    if t.skipped { return true; }
    let p_cur = t.cur;
    let p_checks = t.checks;
    let p_fails = t.fails;
    let p_expected_fails = t.expected_fails;
    let p_expected = t.expected;
    var joined: u8[>..] = [];
    for b in t.names[t.cur.at..t.cur.at + t.cur.len] { joined.push(b); }
    joined.push('/');
    // Go turns each space of the name of a subtest into an underscore.
    for b in underscore(name) { joined.push(b); }
    if !matches(t.pat, joined[..]) { return true; }
    begin(t, joined[..]);
    F(t);
    let ok = end(t);
    t.cur = p_cur;
    t.checks = p_checks;
    t.fails = p_fails;
    t.expected_fails = p_expected_fails;
    t.expected = p_expected;
    t.skipped = false;
    if !ok {
        if t.expected { t.expected_fails = t.expected_fails + 1; }
        else { t.fails = t.fails + 1; }
    }
    return ok;
}

// cases runs one subtest for each row index 0..n, inside the test
// that runs now. The block takes the tracker and the row index. The
// name of a row reads name/i.
fn cases<F>(t: T&, name: const u8[:], n: i64) -> bool {
    var all = true;
    for i in n {
        var row: u8[>..] = [];
        for b in name { row.push(b); }
        row.push('/');
        put_i64(row, i);
        let ok = scope(t, row[..]) { tt => F(tt, i) };
        if !ok { all = false; }
    }
    return all;
}

// rerun runs a test up to n times and stops at the first attempt
// that does not fail. Only the last attempt counts in the totals and
// in the names. A test that passes after a retry prints a note. It
// gives false when every attempt failed. pytest-rerunfailures and
// gotestsum --rerun-fails do the same job. Go testing has no retry.
fn rerun<F>(t: T&, name: const u8[:], n: i64) -> bool {
    var attempt: i64 = 0;
    while attempt < n {
        attempt = attempt + 1;
        let pass0 = t.pass_tests;
        let fail0 = t.fail_tests;
        let skip0 = t.skip_tests;
        let xfail0 = t.xfail_tests;
        let checks0 = t.total_checks;
        let unlisted0 = t.unlisted;
        let names0 = t.names.len;
        begin(t, name);
        F(t);
        let ok = end(t);
        if ok {
            if attempt > 1 { print("NOTE ", name, ": passed on attempt ", attempt, " of ", n); }
            return true;
        }
        if attempt < n {
            t.pass_tests = pass0;
            t.fail_tests = fail0;
            t.skip_tests = skip0;
            t.xfail_tests = xfail0;
            t.total_checks = checks0;
            t.unlisted = unlisted0;
            t.names.resize(names0, 0);
            print("RETRY ", name, ": attempt ", attempt, " of ", n, " failed");
        }
    }
    return false;
}
