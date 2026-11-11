// The test filter: the -run patterns of Go, the shard of a suite, and
// the retry count. The generated file of the testgen command calls
// filter once at the start of main.
namespace testkit;

import std;
import regex;
import os;

// name_end gives the index of the next '/' at or after from, or the
// length of s when there is none. A name holds no pattern syntax, so
// every slash ends a part.
fn name_end(s: const u8[:], from: i64) -> i64 {
    var i = from;
    while i < s.len && s[i] != 47 { i = i + 1; }
    return i;
}

// pat_end gives the index of the next wanted byte of the pattern at the
// top level at or after from, or the length of the pattern when there
// is none. The wanted byte is a slash or a bar. A class or a group
// holds its own slashes and bars, and a backslash skips the next byte.
fn pat_end(s: const u8[:], from: i64, want: u8) -> i64 {
    var i = from;
    var cs: i64 = 0;
    var cp: i64 = 0;
    while i < s.len {
        let b = s[i];
        if b == 92 {
            i = i + 2;
        } else if b == 91 {
            cs = cs + 1;
            i = i + 1;
        } else if b == 93 {
            if cs > 0 { cs = cs - 1; }
            i = i + 1;
        } else if b == 40 {
            if cs == 0 { cp = cp + 1; }
            i = i + 1;
        } else if b == 41 {
            if cs == 0 && cp > 0 { cp = cp - 1; }
            i = i + 1;
        } else if b == want && cs == 0 && cp == 0 {
            return i;
        } else {
            i = i + 1;
        }
    }
    return s.len;
}

// underscore turns each space of s into an underscore, as Go does with
// the name of a subtest and with a part of a run pattern.
fn underscore(s: const u8[:]) -> u8[>..] {
    var out: u8[>..] = [];
    for b in s {
        if b == 32 { out.push(95); } else { out.push(b); }
    }
    return out;
}

// bad_pattern reports a run pattern that the regular expressions of the
// standard library refuse, and ends the program.
fn bad_pattern(pat: const u8[:], why: const u8[:]) {
    write_stderr("testkit: the run pattern holds a regular expression that the library refuses: ");
    write_stderr(pat);
    write_stderr(": ");
    write_stderr(why);
    write_stderr("\n");
    abort("testkit: the run pattern is not a valid regular expression");
}

// part_body gives the body of a pattern part: the part without a
// leading ^ and without a trailing $.
fn part_body(pat: const u8[:]) -> const u8[:] {
    var core = pat;
    if core.len > 0 && core[0] == 94 { core = core[1..core.len]; }
    if core.len > 0 && core[core.len - 1] == 36 { core = core[0..core.len - 1]; }
    return core;
}

// part_ok reports whether one pattern part matches one name part. The
// part reads as a regular expression, as Go reads it. A part matches
// when the expression matches anywhere in the name part. A leading ^
// anchors the start and a trailing $ anchors the end. An empty part
// matches anything.
fn part_ok(pat: const u8[:], s: const u8[:]) -> bool {
    let head = pat.len > 0 && pat[0] == 94;
    let tail = pat.len > 0 && pat[pat.len - 1] == 36;
    var body = underscore(part_body(pat));
    if body.len == 0 { return true; }
    var err: u8[>..] = [];
    let re = regex::compile(body[..], err);
    if err.len > 0 { bad_pattern(body[..], err[..]); }
    if head && tail { return regex::find_start(re, s, 0, s.len) == 0; }
    if head {
        let at, stop = regex::find(re, s);
        return at == 0;
    }
    if tail { return regex::find_start(re, s, 0, s.len) >= 0; }
    return regex::matches(re, s);
}

// alt_ok matches one pattern against a test name, part by part. A
// name with fewer parts than the pattern runs when its parts match:
// the parent of a matching subtest runs. A pattern with fewer parts
// than the name selects the whole subtree.
fn alt_ok(pat: const u8[:], name: const u8[:]) -> bool {
    var pa: i64 = 0;
    var na: i64 = 0;
    var ok = true;
    while ok {
        let pe = pat_end(pat, pa, 47);
        let ne = name_end(name, na);
        if !part_ok(pat[pa..pe], name[na..ne]) {
            ok = false;
        } else if pe >= pat.len || ne >= name.len {
            break;
        } else {
            pa = pe + 1;
            na = ne + 1;
        }
    }
    return ok;
}

// matches reports whether a name passes the -run pattern. Each part of
// the pattern reads as a regular expression, as Go reads it. A '|'
// separates alternative patterns. An empty pattern matches all.
fn matches(pat: const u8[:], name: const u8[:]) -> bool {
    if pat.len == 0 { return true; }
    var from: i64 = 0;
    var ok = false;
    while !ok {
        let to = pat_end(pat, from, 124);
        if alt_ok(pat[from..to], name) {
            ok = true;
        } else if to >= pat.len {
            break;
        } else {
            from = to + 1;
        }
    }
    return ok;
}

// pattern_fault reads every part of the pattern as a regular expression.
// It gives true when the standard library refuses a part, and then why
// holds the part and the reason.
fn pattern_fault(pat: const u8[:], why: u8[>..]&) -> bool {
    if pat.len == 0 { return false; }
    var from: i64 = 0;
    var more = true;
    var refused = false;
    while more && !refused {
        let to = pat_end(pat, from, 124);
        var pa: i64 = 0;
        var again = true;
        while again && !refused {
            let pe = pat_end(pat[from..to], pa, 47);
            var body = underscore(part_body(pat[from + pa..from + pe]));
            if body.len > 0 {
                var err: u8[>..] = [];
                let _ = regex::compile(body[..], err);
                if err.len > 0 {
                    for c in body { why.push(c); }
                    for c in ": " { why.push(c); }
                    for c in err { why.push(c); }
                    refused = true;
                }
            }
            if pe >= to - from { again = false; }
            else { pa = pe + 1; }
        }
        if to >= pat.len { more = false; }
        else { from = to + 1; }
    }
    return refused;
}

// check_pattern ends the program when the standard library refuses a
// part of the pattern. The filter calls it at the start of the run, so
// a bad pattern stops the run before the first test.
fn check_pattern(pat: const u8[:]) {
    var why: u8[>..] = [];
    if pattern_fault(pat, why) {
        write_stderr("testkit: the run pattern holds a regular expression that the library refuses: ");
        write_stderr(why[..]);
        write_stderr("\n");
        abort("testkit: the run pattern is not a valid regular expression");
    }
}

// shard_of gives the shard of a name, 0 to n - 1. It uses FNV-1a on
// 32 bits, so the same name lands in the same shard on every system.
fn shard_of(name: const u8[:], n: i64) -> i64 {
    var h: i64 = 2166136261;
    for b in name {
        h = ((h ^ b) * 16777619) & 4294967295;
    }
    return h % n;
}

// filter sets the options of this run. The run pattern follows Go:
// each part reads as a regular expression, ^ and $ anchor the ends of
// a part, | separates patterns, and a parent of a matching subtest
// runs. Shard i of n, counted from 1, runs the tests whose name hash
// mod n is i - 1. n of 0 turns the shard off. A count above 1 gives
// each test that many attempts.
fn filter(t: T&, run: const u8[:], shard_i: i64, shard_n: i64, count: i64) {
    check_pattern(run);
    t.pat = run;
    t.shard_i = shard_i;
    t.shard_n = shard_n;
    t.count = count;
}

// leave_out records a test that the filter or the shard left out. It
// counts as a skip, prints nothing, and does not run the block. The
// name stays out of the list of tests that ran.
fn leave_out(t: T&, name: const u8[:], by_shard: bool) {
    let names0 = t.names.len;
    let unlisted0 = t.unlisted;
    begin(t, name);
    t.skipped = true;
    if by_shard { t.sharded = t.sharded + 1; }
    else { t.filtered = t.filtered + 1; }
    end(t);
    t.names.resize(names0, 0);
    t.unlisted = unlisted0;
}
