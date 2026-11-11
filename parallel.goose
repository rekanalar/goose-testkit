// The parallel run: the totals of one test that a worker ran, and the
// calls that move them between the workers and the tracker of the
// caller. A worker runs one test of the suite in its own tracker, puts
// the part on a queue, and ends. The generated file holds the workers.
namespace testkit;

import std;

const MAX_WORKERS: i64 = 64;

// Part holds what one worker ran. It is flat, so it crosses a queue.
// The names stay the final field: a struct holds one growable array.
struct Part {
    pass_tests: i64,
    fail_tests: i64,
    skip_tests: i64,
    xfail_tests: i64,
    total_checks: i64,
    unlisted: i64,
    filtered: i64,
    sharded: i64,
    names: u8[>..],
}

// report puts the totals of a worker on the queue.
fn report(t: T&) {
    qput(Part { pass_tests: t.pass_tests, fail_tests: t.fail_tests,
                skip_tests: t.skip_tests, xfail_tests: t.xfail_tests,
                total_checks: t.total_checks, unlisted: t.unlisted,
                filtered: t.filtered, sharded: t.sharded, names: t.names[..] });
}

// absorb adds each part on the queue to the tracker of the caller.
fn absorb(t: T&) {
    var more = true;
    while more {
        let p, ok = qpoll<Part>();
        if !ok {
            more = false;
        } else {
            t.pass_tests = t.pass_tests + p.pass_tests;
            t.fail_tests = t.fail_tests + p.fail_tests;
            t.skip_tests = t.skip_tests + p.skip_tests;
            t.xfail_tests = t.xfail_tests + p.xfail_tests;
            t.total_checks = t.total_checks + p.total_checks;
            t.unlisted = t.unlisted + p.unlisted;
            t.filtered = t.filtered + p.filtered;
            t.sharded = t.sharded + p.sharded;
            for b in p.names { t.names.push(b); }
        }
    }
}

// crashed counts a worker that aborted as a failed test. The abort
// message of the worker goes to the report.
fn crashed(t: T&, name: const u8[:], why: const u8[:]) {
    t.fail_tests = t.fail_tests + 1;
    for b in name { t.names.push(b); }
    t.names.push(10);
    // The message comes from a test, so it prints escaped and cut.
    var shown: u8[>..] = [];
    put_report(shown, why);
    print("FAIL ", name, ": the test aborted: ", shown[..]);
}

// sort_names puts the names of the tests in byte order, so the report
// of a parallel run does not depend on which worker ended first.
fn sort_names(t: T&) {
    var starts: i64[>..] = [];
    var ends: i64[>..] = [];
    var at: i64 = 0;
    var p: i64 = 0;
    while p < t.names.len {
        if t.names[p] == 10 {
            starts.push(at);
            ends.push(p);
            at = p + 1;
        }
        p = p + 1;
    }
    var order: i64[>..] = [];
    for k in starts.len { order.push(k); }
    var x: i64 = 1;
    while x < order.len {
        let cur = order[x];
        var y = x;
        while y > 0 && name_after(t.names[starts[order[y - 1]]..ends[order[y - 1]]], t.names[starts[cur]..ends[cur]]) {
            order[y] = order[y - 1];
            y = y - 1;
        }
        order[y] = cur;
        x = x + 1;
    }
    var out: u8[>..] = [];
    for k in order.len {
        for b in t.names[starts[order[k]]..ends[order[k]]] { out.push(b); }
        out.push(10);
    }
    t.names.clear();
    for b in out { t.names.push(b); }
}

// name_after reports whether a sorts after b in byte order.
fn name_after(a: const u8[:], b: const u8[:]) -> bool {
    var k: i64 = 0;
    while k < a.len && k < b.len {
        if a[k] != b[k] { return a[k] > b[k]; }
        k = k + 1;
    }
    return a.len > b.len;
}
