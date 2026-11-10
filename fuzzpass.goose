// The fuzz pass: the result of a goose-fuzz run as a test result. The
// package imports nothing from goose-fuzz. The caller runs fuzz::run
// and hands over the numbers and the text of the report.
namespace testkit;

import std;

const MAX_REPORT_BYTES: i64 = 4096;

// put_report appends the report with each byte outside printable ASCII
// as \xNN, except the line feed. It stops after MAX_REPORT_BYTES of
// the report and says so.
fn put_report(out: u8[>..]&, report: const u8[:]) {
    var n = report.len;
    if n > MAX_REPORT_BYTES { n = MAX_REPORT_BYTES; }
    for i in n {
        let b = report[i];
        if b == 10 || (b >= 32 && b < 127) {
            out.push(b);
        } else {
            out.push(92);
            out.push(120);
            let hi = b / 16;
            let lo = b % 16;
            if hi < 10 { out.push(48 + hi); } else { out.push(87 + hi); }
            if lo < 10 { out.push(48 + lo); } else { out.push(87 + lo); }
        }
    }
    if report.len > n {
        for b in "\n[report cut after 4096 bytes]" { out.push(b); }
    }
}

// fuzz_result records the result of one fuzz run in the running test.
// found is the value of fuzz::run, runs is Report.runs, and report is
// the text of fuzz::format_report. A run with no finding passes. A run
// with a finding fails and prints the report. A run of no inputs
// fails, because it proved nothing.
fn fuzz_result(t: T&, found: i64, runs: i64, report: const u8[:]) {
    if runs < 1 {
        fail(t, "the fuzz run tried no input");
        return;
    }
    if found != 0 {
        var msg: u8[>..] = [];
        for b in "the fuzz run found " { msg.push(b); }
        put_i64(msg, found);
        for b in " finding(s) in " { msg.push(b); }
        put_i64(msg, runs);
        for b in " run(s)\n" { msg.push(b); }
        put_report(msg, report);
        fail(t, msg[..]);
        return;
    }
    is_true(t, true, "fuzz run");
}
