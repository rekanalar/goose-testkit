// testgen: finds the tests of a Goose suite and writes test/_gen.goose.
//
// Build: goose build cmd/testgen.goose -o testgen
// Run from the package root: testgen [-run pattern] [-shard i/n] [-count n] [-parallel n] [-watch]
//
// The command reads the .goose files of test/ and src/, lexes each as
// text, and collects the name of each testkit::run and testkit::begin
// call that names its test with a string literal. It also finds the
// test functions of the suite directory: a top-level fn whose name
// starts with test_ and that takes one tracker. It writes the sorted
// names, the calls to the test functions and the options of this run to
// test/_gen.goose, and nothing else. It runs no code.
import std;
import os;
import testkit from "..";

const MAX_FILES: i64 = 256;
const MAX_TESTS: i64 = 4096;
const MAX_RUN_BYTES: i64 = 1024;
const MAX_PATTERNS: i64 = 256;
const MAX_COUNT: i64 = 1000;
const MAX_NS: i64 = 64;
const MAX_PATH: i64 = 256;
const OUT_PATH: const u8[:] = "test/_gen.goose";
const POLL_MS: i64 = 250;

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

// sort_lines sorts the lines of buf, each ended by a line feed, in the
// byte order of their bytes.
fn sort_lines(buf: u8[>..]&) {
    var starts: i64[>..] = [];
    var ends: i64[>..] = [];
    var at: i64 = 0;
    var p: i64 = 0;
    while p < buf.len {
        if buf[p] == 10 {
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
        while y > 0 && cmp(buf[starts[order[y - 1]]..ends[order[y - 1]]], buf[starts[cur]..ends[cur]]) > 0 {
            order[y] = order[y - 1];
            y = y - 1;
        }
        order[y] = cur;
        x = x + 1;
    }
    var out: u8[>..] = [];
    for k in order.len {
        for b in buf[starts[order[k]]..ends[order[k]]] { out.push(b); }
        out.push(10);
    }
    buf.clear();
    for b in out { buf.push(b); }
}

// hash_bytes gives the hash of the bytes, as the shard hash does. A
// change of the bytes gives another hash.
fn hash_bytes(b: const u8[:]) -> i64 {
    var h: i64 = 2166136261;
    for x in b {
        h = ((h ^ x) * 16777619) & 4294967295;
    }
    return h;
}

// fault prints the message of a fault in a source file. It names the
// file and the line.
fn fault(path: const u8[:], line: i64, why: const u8[:]) {
    var msg: u8[>..] = [];
    testkit::lex_put_safe(msg, path);
    msg.push(58);
    testkit::put_i64(msg, line);
    put(msg, ": ");
    put(msg, why);
    die(msg[..]);
}

// scan_dir lexes each .goose file of a directory, except the generated
// file. It appends the names of the call sites to found. When suite
// holds true, it also finds the test functions of the files. It appends
// each test function to decls, as a line of the namespace of the file,
// a tab and the name of the function. The namespace is empty for the
// root file of the suite. It gives the count of files.
fn scan_dir(dir: const u8[:], files: i64, found: u8[>..]&, decls: u8[>..]&, roots: i64&, suite: bool) -> i64 {
    var listing: u8[>..] = [];
    if !list_dir(dir, listing) { return files; }
    sort_lines(listing);
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
                let line = testkit::lex_scan(src[..], found, why);
                if line != 0 { fault(path[..], line, why[..]); }
                if suite {
                    var ns: u8[>..] = [];
                    testkit::lex_namespace(src[..], ns);
                    var names: u8[>..] = [];
                    let line2 = testkit::lex_funcs(src[..], names, why);
                    if line2 != 0 { fault(path[..], line2, why[..]); }
                    if ns.len == 0 {
                        roots = roots + 1;
                        if roots > 1 { die("the suite directory holds two files without a namespace"); }
                        put_decls(decls, "", names);
                    } else {
                        var stem = name[0..name.len - 6];
                        if ns != stem {
                            var msg: u8[>..] = [];
                            put(msg, "the namespace of ");
                            testkit::lex_put_safe(msg, path[..]);
                            put(msg, " is ");
                            put(msg, ns);
                            put(msg, " and the name of the file is ");
                            put(msg, stem);
                            die(msg[..]);
                        }
                        if names.len > 0 { put_decls(decls, ns, names); }
                    }
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
        if b < 32 || b > 126 || b == 34 {
            die("the -run pattern holds a quote or a byte outside printable ASCII");
        }
    }
    if parts > MAX_PATTERNS { die("more than 256 patterns in -run"); }
}

// put_run writes the run pattern as a string literal. A backslash
// becomes two, so the literal holds the pattern as the caller wrote it.
fn put_run(out: u8[>..]&, pat: const u8[:]) {
    for b in pat {
        if b == 92 { out.push(92); }
        out.push(b);
    }
}

// put_decls appends the test functions of a file to decls, as a line of
// the namespace, a tab and the name of the function.
fn put_decls(decls: u8[>..]&, ns: const u8[:], names: const u8[:]) {
    var start: i64 = 0;
    var i: i64 = 0;
    while i < names.len {
        if names[i] == 10 {
            put(decls, ns);
            decls.push(9);
            for b in names[start..i] { decls.push(b); }
            decls.push(10);
            start = i + 1;
        }
        i = i + 1;
    }
}

// decl_ns gives the namespace of a line of decls.
fn decl_ns(line: const u8[:]) -> const u8[:] {
    var i: i64 = 0;
    while i < line.len && line[i] != 9 { i = i + 1; }
    return line[0..i];
}

// decl_name gives the name of a line of decls.
fn decl_name(line: const u8[:]) -> const u8[:] {
    var i: i64 = 0;
    while i < line.len && line[i] != 9 { i = i + 1; }
    return line[i + 1..line.len];
}

// write_calls writes the call of each test function of decls.
fn write_calls(out: u8[>..]&, decls: const u8[:]) {
    var start: i64 = 0;
    var i: i64 = 0;
    while i < decls.len {
        if decls[i] == 10 {
            let line = decls[start..i];
            start = i + 1;
            put(out, "    testkit::run(t, \"");
            put(out, decl_name(line));
            put(out, "\") { tt => ");
            let ns = decl_ns(line);
            if ns.len > 0 { put(out, ns); }
            put(out, "::");
            put(out, decl_name(line));
            put(out, "(tt); };\n");
        }
        i = i + 1;
    }
}

// write_parallel writes the worker and the run of a parallel suite. The
// worker runs the test of one index in its own tracker. The run starts
// the workers in waves of n, waits for each, and adds their parts.
fn write_parallel(out: u8[>..]&, decls: const u8[:], workers: i64) {
    put(out, "thread_fn par_worker(idx: i64) {\n");
    put(out, "    var t = testkit::new_t();\n");
    put(out, "    testkit::filter(t, run(), shard_i(), shard_n(), count());\n");
    var start: i64 = 0;
    var i: i64 = 0;
    var k: i64 = 0;
    while i < decls.len {
        if decls[i] == 10 {
            let line = decls[start..i];
            start = i + 1;
            put(out, "    if idx == ");
            testkit::put_i64(out, k);
            put(out, " { testkit::run(t, \"");
            put(out, decl_name(line));
            put(out, "\") { tt => ");
            let ns = decl_ns(line);
            if ns.len > 0 { put(out, ns); }
            put(out, "::");
            put(out, decl_name(line));
            put(out, "(tt); }; }\n");
            k = k + 1;
        }
        i = i + 1;
    }
    put(out, "    testkit::report(t);\n}\n\n");
    put(out, "fn par_name(idx: i64) -> const u8[:] {\n");
    start = 0;
    i = 0;
    k = 0;
    while i < decls.len {
        if decls[i] == 10 {
            put(out, "    if idx == ");
            testkit::put_i64(out, k);
            put(out, " { return \"");
            put(out, decl_name(decls[start..i]));
            put(out, "\"; }\n");
            start = i + 1;
            k = k + 1;
        }
        i = i + 1;
    }
    put(out, "    return \"\";\n}\n\n");
    put(out, "// run_all runs every test of the suite in parallel workers.\n");
    put(out, "fn run_all(t: testkit::T&) {\n");
    put(out, "    let total: i64 = ");
    testkit::put_i64(out, k);
    put(out, ";\n    var done: i64 = 0;\n    while done < total {\n");
    put(out, "        var ids: i64[>..] = [];\n");
    put(out, "        while ids.len < ");
    testkit::put_i64(out, workers);
    put(out, " && done + ids.len < total {\n");
    put(out, "            ids.push(thread_spawn_contained(par_worker, done + ids.len));\n        }\n");
    put(out, "        var j: i64 = 0;\n        while j < ids.len {\n");
    put(out, "            var why: u8[>..] = [];\n");
    put(out, "            if !thread_wait(ids[j], why) { testkit::crashed(t, par_name(done + j), why[..]); }\n");
    put(out, "            j = j + 1;\n        }\n");
    put(out, "        testkit::absorb(t);\n        done = done + ids.len;\n    }\n");
    put(out, "    testkit::sort_names(t);\n}\n");
}

// generate finds the tests of the suite and writes the generated file.
// It gives the count of the tests it found.
fn generate(run: const u8[:], shard_i: i64, shard_n: i64, count: i64, workers: i64, quiet: bool) -> i64 {
    var found: u8[>..] = [];
    var decls: u8[>..] = [];
    var roots: i64 = 0;
    var files = scan_dir("test", 0, found, decls, roots, true);
    files = scan_dir("src", files, found, decls, roots, false);
    if files == 0 { die("no .goose file in test/ or src/"); }
    if roots == 0 { die("the suite directory holds no root file"); }

    // The names of the test functions join the names of the call sites.
    var names: u8[>..] = [];
    put(names, found[..]);
    var dstart: i64 = 0;
    var di: i64 = 0;
    while di < decls.len {
        if decls[di] == 10 {
            put(names, decl_name(decls[dstart..di]));
            names.push(10);
            dstart = di + 1;
        }
        di = di + 1;
    }
    sort_lines(names);

    var out: u8[>..] = [];
    put(out, "// Generated by testgen. Do not edit: run testgen again.\n");
    put(out, "namespace _gen;\n\n");
    put(out, "import testkit;\n");
    var last_ns: u8[>..] = [];
    dstart = 0;
    di = 0;
    while di < decls.len {
        if decls[di] == 10 {
            let ns = decl_ns(decls[dstart..di]);
            dstart = di + 1;
            // The lines of one module follow each other, so a new
            // namespace is one that differs from the last one.
            if ns.len > 0 && ns != last_ns {
                put(out, "import ");
                put(out, ns);
                put(out, ";\n");
            }
            last_ns = ns;
        }
        di = di + 1;
    }
    put(out, "\nfn add(out: u8[>..]&, s: const u8[:]) {\n    for b in s { out.push(b); }\n    out.push(10);\n}\n\n");
    put(out, "// list appends the name of each test, each ended by a line feed.\n");
    put(out, "fn list(out: u8[>..]&) {\n");
    var unique: i64 = 0;
    var pos: i64 = 0;
    while pos < names.len {
        var e = pos;
        while e < names.len && names[e] != 10 { e = e + 1; }
        let name = names[pos..e];
        // Count the places that hold this name.
        var places: i64 = 1;
        var p = e + 1;
        while p < names.len {
            var e2 = p;
            while e2 < names.len && names[e2] != 10 { e2 = e2 + 1; }
            if cmp(name, names[p..e2]) != 0 { break; }
            places = places + 1;
            p = e2 + 1;
        }
        if places > 1 {
            var msg: u8[>..] = [];
            put(msg, "warning: the test name ");
            put(msg, name);
            put(msg, " is in ");
            testkit::put_i64(msg, places);
            put(msg, " places");
            write_stderr("testgen: ");
            write_stderr(msg[..]);
            write_stderr("\n");
        }
        unique = unique + 1;
        if unique > MAX_TESTS { die("more than 4096 tests"); }
        put(out, "    add(out, \"");
        put(out, name);
        put(out, "\");\n");
        if !quiet { print("  ", name); }
        pos = p;
    }
    put(out, "}\n\nfn run() -> const u8[:] { return \"");
    put_run(out, run);
    put(out, "\"; }\nfn shard_i() -> i64 { return ");
    testkit::put_i64(out, shard_i);
    put(out, "; }\nfn shard_n() -> i64 { return ");
    testkit::put_i64(out, shard_n);
    put(out, "; }\nfn count() -> i64 { return ");
    testkit::put_i64(out, count);
    put(out, "; }\n\n");
    if workers > 0 {
        write_parallel(out, decls[..], workers);
    } else {
        put(out, "// run_all runs every test of the suite.\n");
        put(out, "fn run_all(t: testkit::T&) {\n");
        write_calls(out, decls[..]);
        put(out, "}\n");
    }
    if !write_file_atomic(OUT_PATH, out[..]) { die("cannot write test/_gen.goose; does test/ exist?"); }
    return unique;
}

// scan_sources reads the files of the two directories and appends a
// line for each of them to out: the path of the file, a tab and the
// hash of its bytes. The lines hold the paths in the byte order.
fn scan_sources(dir: const u8[:], out: u8[>..]&) {
    var listing: u8[>..] = [];
    if !list_dir(dir, listing) { return; }
    sort_lines(listing);
    var start: i64 = 0;
    var i: i64 = 0;
    while i < listing.len {
        if listing[i] == 10 {
            let name = listing[start..i];
            start = i + 1;
            if ends_with(name, ".goose") && name != "_gen.goose" {
                var path: u8[>..] = [];
                put(path, dir);
                path.push(47);
                put(path, name);
                var src: u8[>..] = [];
                if !read_file(path[..], src) { die("cannot read a source file"); }
                put(out, path);
                out.push(9);
                testkit::put_i64(out, hash_bytes(src[..]));
                out.push(10);
            }
        }
        i = i + 1;
    }
}

// line_end gives the index of the line feed that ends the line at at.
fn line_end(buf: const u8[:], at: i64) -> i64 {
    var i = at;
    while i < buf.len && buf[i] != 10 { i = i + 1; }
    return i;
}

// line_tab gives the index of the tab that ends the path of the line at
// at.
fn line_tab(buf: const u8[:], at: i64) -> i64 {
    var i = at;
    while i < buf.len && buf[i] != 9 { i = i + 1; }
    return i;
}

// any_change reports whether the sources changed. Each line of prev and
// cur holds the path of a file and its hash, separated by a tab. The
// paths of both hold the same order. It appends the path of each file
// that changed to out, each ended by a line feed.
fn any_change(prev: const u8[:], cur: const u8[:], out: u8[>..]&) -> bool {
    var any = false;
    var ps: i64 = 0;
    var cs: i64 = 0;
    while ps < prev.len || cs < cur.len {
        let pe = line_end(prev, ps);
        let ce = line_end(cur, cs);
        let pp = prev[ps..line_tab(prev, ps)];
        let cp = cur[cs..line_tab(cur, cs)];
        if pp == cp {
            if prev[line_tab(prev, ps) + 1..pe] != cur[line_tab(cur, cs) + 1..ce] {
                any = true;
                put(out, cp);
                out.push(10);
            }
        } else if cs >= cur.len || (ps < prev.len && cmp(pp, cp) < 0) {
            any = true;
            put(out, pp);
            out.push(10);
        } else {
            any = true;
            put(out, cp);
            out.push(10);
        }
        ps = pe + 1;
        cs = ce + 1;
    }
    return any;
}

fn main() {
    var run: u8[>..] = [];
    var shard_i: i64 = 0;
    var shard_n: i64 = 0;
    var count: i64 = 1;
    var watch = false;
    var workers: i64 = 0;
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
        } else if a[i] == "-parallel" && i + 1 < a.len {
            workers = parse_num(a[i + 1]);
            if workers < 1 || workers > testkit::MAX_WORKERS { die("-parallel takes a number from 1 to 64"); }
            i = i + 2;
        } else if a[i] == "-watch" {
            watch = true;
            i = i + 1;
        } else {
            die("usage: testgen [-run pattern] [-shard i/n] [-count n] [-parallel n] [-watch]");
        }
    }
    check_run(run[..]);

    let tests = generate(run[..], shard_i, shard_n, count, workers, false);
    print("testgen: ", tests, " tests, wrote ", OUT_PATH);
    if !watch { return; }

    var prev: u8[>..] = [];
    scan_sources("test", prev);
    scan_sources("src", prev);
    while true {
        sleep_ms(POLL_MS);
        var cur: u8[>..] = [];
        scan_sources("test", cur);
        scan_sources("src", cur);
        var changed: u8[>..] = [];
        if any_change(prev, cur, changed) {
            let n = generate(run[..], shard_i, shard_n, count, workers, true);
            var at: i64 = 0;
            var k: i64 = 0;
            while k < changed.len {
                if changed[k] == 10 {
                    print("testgen: ", changed[at..k], " changed, wrote ", OUT_PATH, " with ", n, " tests");
                    at = k + 1;
                }
                k = k + 1;
            }
        }
        prev = copy(cur);
    }
}
