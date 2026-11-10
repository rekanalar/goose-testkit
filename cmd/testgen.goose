// testgen: finds the tests of a Goose suite and writes test/_gen.goose.
//
// Build: goose build cmd/testgen.goose -o testgen
// Run from the package root: testgen [-run pattern] [-shard i/n] [-count n]
//
// The command reads the .goose files of test/ and src/, lexes each as
// text, and collects the name of each testkit::run and testkit::begin
// call that names its test with a string literal. It writes the sorted
// names and the options of this run to test/_gen.goose, and nothing
// else. It runs no code.
import std;
import os;
import testkit from "..";

const MAX_FILES: i64 = 256;
const MAX_TESTS: i64 = 4096;
const MAX_RUN_BYTES: i64 = 1024;
const MAX_PATTERNS: i64 = 256;
const MAX_COUNT: i64 = 1000;
const OUT_PATH: const u8[:] = "test/_gen.goose";

// die prints a message and ends the program with exit code 1.
fn die(msg: const u8[:]) {
    write_stderr("testgen: ");
    write_stderr(msg);
    write_stderr("\n");
    abort("testgen failed");
}

fn put(out: u8[>..]&, s: const u8[:]) {
    for b in s { out.push(b); }
}

// parse_num reads a decimal number. It gives -1 for anything else.
fn parse_num(s: const u8[:]) -> i64 {
    if s.len == 0 || s.len > 9 { return -1; }
    var n: i64 = 0;
    for b in s {
        if b < 48 || b > 57 { return -1; }
        n = n * 10 + (b - 48);
    }
    return n;
}

// ends_with reports whether s ends with tail.
fn ends_with(s: const u8[:], tail: const u8[:]) -> bool {
    if s.len < tail.len { return false; }
    var k: i64 = 0;
    while k < tail.len {
        if s[s.len - tail.len + k] != tail[k] { return false; }
        k = k + 1;
    }
    return true;
}

// cmp orders two names bytewise.
fn cmp(a: const u8[:], b: const u8[:]) -> i64 {
    var k: i64 = 0;
    while k < a.len && k < b.len {
        if a[k] != b[k] { return (a[k] as i64) - b[k]; }
        k = k + 1;
    }
    return a.len - b.len;
}

// scan_dir lexes each .goose file of a directory, except the generated
// file, and appends the names to out. It gives the count of files.
fn scan_dir(dir: const u8[:], files: i64, out: u8[>..]&) -> i64 {
    var listing: u8[>..] = [];
    if !list_dir(dir, listing) { return files; }
    var count = files;
    var start: i64 = 0;
    var i: i64 = 0;
    while i < listing.len {
        if listing[i] == 10 {
            let name = listing[start..i];
            start = i + 1;
            if ends_with(name, ".goose") && name != "_gen.goose" {
                count = count + 1;
                if count > MAX_FILES { die("more than 256 source files"); }
                var path: u8[>..] = [];
                put(path, dir);
                path.push(47);
                put(path, name);
                var src: u8[>..] = [];
                if !read_file(path[..], src) { die("cannot read a source file"); }
                var why: u8[>..] = [];
                let line = testkit::lex_scan(src[..], out, why);
                if line != 0 {
                    var msg: u8[>..] = [];
                    testkit::lex_put_safe(msg, path[..]);
                    msg.push(58);
                    testkit::put_i64(msg, line);
                    put(msg, ": ");
                    put(msg, why[..]);
                    die(msg[..]);
                }
            }
        }
        i = i + 1;
    }
    return count;
}

// check_run rejects a run pattern that the generated file cannot hold
// as a plain string, or that is past a bound.
fn check_run(pat: const u8[:]) {
    if pat.len > MAX_RUN_BYTES { die("the -run pattern is longer than 1024 bytes"); }
    var parts: i64 = 1;
    for b in pat {
        if b == 124 { parts = parts + 1; }
        if b < 32 || b > 126 || b == 34 || b == 92 {
            die("the -run pattern holds a quote, a backslash or a byte outside printable ASCII");
        }
    }
    if parts > MAX_PATTERNS { die("more than 256 patterns in -run"); }
}

fn main() {
    var run: u8[>..] = [];
    var shard_i: i64 = 0;
    var shard_n: i64 = 0;
    var count: i64 = 1;
    let a = args();
    var i: i64 = 1;
    while i < a.len {
        if a[i] == "-run" && i + 1 < a.len {
            for b in a[i + 1] { run.push(b); }
            i = i + 2;
        } else if a[i] == "-count" && i + 1 < a.len {
            count = parse_num(a[i + 1]);
            if count < 1 || count > MAX_COUNT { die("-count takes a number from 1 to 1000"); }
            i = i + 2;
        } else if a[i] == "-shard" && i + 1 < a.len {
            let s = a[i + 1];
            var slash: i64 = -1;
            var k: i64 = 0;
            while k < s.len {
                if s[k] == 47 { slash = k; }
                k = k + 1;
            }
            if slash < 0 { die("-shard takes i/n"); }
            shard_i = parse_num(s[0..slash]);
            shard_n = parse_num(s[slash + 1..s.len]);
            if shard_i < 1 || shard_n < 1 || shard_i > shard_n { die("-shard takes i/n with 1 <= i <= n"); }
            i = i + 2;
        } else {
            die("usage: testgen [-run pattern] [-shard i/n] [-count n]");
        }
    }
    check_run(run[..]);

    var found: u8[>..] = [];
    var files = scan_dir("test", 0, found);
    files = scan_dir("src", files, found);
    if files == 0 { die("no .goose file in test/ or src/"); }

    // Cut the blob into names, then sort the names bytewise.
    var starts: i64[>..] = [];
    var ends: i64[>..] = [];
    var at: i64 = 0;
    var p: i64 = 0;
    while p < found.len {
        if found[p] == 10 {
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
        while y > 0 && cmp(found[starts[order[y - 1]]..ends[order[y - 1]]], found[starts[cur]..ends[cur]]) > 0 {
            order[y] = order[y - 1];
            y = y - 1;
        }
        order[y] = cur;
        x = x + 1;
    }

    var out: u8[>..] = [];
    put(out, "// Generated by testgen. Do not edit: run testgen again.\n");
    put(out, "namespace _gen;\n\n");
    put(out, "fn add(out: u8[>..]&, s: const u8[:]) {\n    for b in s { out.push(b); }\n    out.push(10);\n}\n\n");
    put(out, "// list appends the name of each test, each ended by a line feed.\n");
    put(out, "fn list(out: u8[>..]&) {\n");
    var unique: i64 = 0;
    var n: i64 = 0;
    while n < order.len {
        let name = found[starts[order[n]]..ends[order[n]]];
        var same: i64 = 1;
        while n + same < order.len && cmp(name, found[starts[order[n + same]]..ends[order[n + same]]]) == 0 {
            same = same + 1;
        }
        if same > 1 {
            var msg: u8[>..] = [];
            put(msg, "warning: the test name ");
            put(msg, name);
            put(msg, " has ");
            testkit::put_i64(msg, same);
            put(msg, " call sites");
            write_stderr("testgen: ");
            write_stderr(msg[..]);
            write_stderr("\n");
        }
        unique = unique + 1;
        if unique > MAX_TESTS { die("more than 4096 tests"); }
        put(out, "    add(out, \"");
        put(out, name);
        put(out, "\");\n");
        print("  ", name);
        n = n + same;
    }
    put(out, "}\n\nfn run() -> const u8[:] { return \"");
    put(out, run[..]);
    put(out, "\"; }\nfn shard_i() -> i64 { return ");
    testkit::put_i64(out, shard_i);
    put(out, "; }\nfn shard_n() -> i64 { return ");
    testkit::put_i64(out, shard_n);
    put(out, "; }\nfn count() -> i64 { return ");
    testkit::put_i64(out, count);
    put(out, "; }\n");
    if !write_file_atomic(OUT_PATH, out[..]) { die("cannot write test/_gen.goose; does test/ exist?"); }
    print("testgen: ", unique, " tests in ", files, " files, wrote ", OUT_PATH);
}
