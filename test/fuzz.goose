// The fuzz pass of the package: two targets run by goose-fuzz, and the
// result of each goes through testkit::fuzz_result.
//
//   goose build --debug test/fuzz.goose -o fuzz-pass
//   ./fuzz-pass            run both targets
//   ./fuzz-pass cov-path   print the path of the coverage compiler
//
// A coverage build finds far more than a blind one. Build with
// GOOSE_CC set to the path that cov-path prints, on a system whose C
// compiler has the coverage flag. The run writes its crashers and its
// corpus under TMPDIR, or under the current directory when TMPDIR is
// not set. A finding makes the program exit with code 1.
import std;
import os;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "rekanalar/goose-fuzz@v1.3.0";
import testkit from "..";

// The lexer takes any bytes. It must not abort, a fault must carry a
// line and a message, each name must be plain text, and a second scan
// of the same bytes must agree with the first.
fn lex_target(d: const u8[:]) {
    var names: u8[>..] = [];
    var why: u8[>..] = [];
    let line = testkit::lex_scan(d, names, why);
    var names2: u8[>..] = [];
    var why2: u8[>..] = [];
    let line2 = testkit::lex_scan(d, names2, why2);
    assert(line == line2 && names[..] == names2[..] && why[..] == why2[..]);
    if line != 0 {
        assert(line >= 1 && why.len > 0);
        return;
    }
    var len: i64 = 0;
    for b in names {
        if b == 10 {
            assert(len >= 1 && len <= 1024);
            len = 0;
        } else {
            assert(b >= 32 && b <= 126 && b != 92 && b != 34);
            len = len + 1;
        }
    }
    assert(len == 0);
}

// The matcher takes a pattern and a name, split at the first zero byte.
// It must not abort, a repeat must agree, an empty pattern must match,
// a name of letters, digits, '_' and '/' must match itself, and the shard must lie in range.
fn match_target(d: const u8[:]) {
    var cut = d.len;
    for i in d.len {
        if d[i] == 0 && cut == d.len { cut = i; }
    }
    let pat = d[0..cut];
    var name = d[0..0];
    if cut < d.len { name = d[cut + 1..d.len]; }
    // The filter refuses a pattern that the library cannot read, so a
    // pattern of that kind never reaches the matcher.
    var why: u8[>..] = [];
    if testkit::pattern_fault(pat, why) { return; }
    let a = testkit::matches(pat, name);
    assert(a == testkit::matches(pat, name));
    assert(testkit::matches("", name));
    var plain = true;
    for b in name { if !((b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 || b == 47) { plain = false; } }
    if plain { assert(testkit::matches(name, name)); }
    var n: i64 = 1;
    if d.len > 0 { n = (d[0] as i64) % 8 + 1; }
    let s = testkit::shard_of(name, n);
    assert(s >= 0 && s < n);
}

thread_fn lex_worker() { fuzz::call(lex_target); }
thread_fn match_worker() { fuzz::call(match_target); }

fn base_dir(out: u8[>..]&) {
    if !env("TMPDIR", out) { out.append("."); }
    out.append("/testkit-fuzz");
}

// seeds writes a few inputs near the call syntax. A run starts from them.
fn seeds(dir: const u8[:]) {
    make_dir(dir);
    var p: u8[>..] = [];
    p.append(dir);
    p.append("/s1");
    write_file(p[..], "testkit::run(t, \"a\") { tt => }\n");
    p.clear();
    p.append(dir);
    p.append("/s2");
    write_file(p[..], "// c\nlet s = \"x\";\ntestkit::begin(f(1, 2), \"b/c\");\n");
    p.clear();
    p.append(dir);
    p.append("/s3");
    write_file(p[..], "A/^B|c$\0A/B");
}

fn config(runs: i64, base: const u8[:]) -> fuzz::Config {
    var cfg = fuzz::config();
    cfg.runs = runs;
    cfg.max_len = 512;
    cfg.seed_dir.append(base);
    cfg.seed_dir.append("/seeds");
    cfg.crash_root.append(base);
    cfg.crash_root.append("/crashers");
    cfg.corpus_root.append(base);
    cfg.corpus_root.append("/corpus");
    cfg.dict.append("a=\"testkit::run(\"\nb=\"testkit::begin(\"\nc=\"\\\"\"\nd=\"//\"\ne=\"'\"\nf=\"/\"\ng=\"^\"\nh=\"|\"\n");
    return cfg;
}

fn main() {
    let argv = args();
    if argv.len > 1 && argv[1] == "cov-path" {
        var path: u8[>..] = [];
        if fuzz::coverage_path(path) { print(path); }
        return 0;
    }
    var base: u8[>..] = [];
    base_dir(base);
    make_dir(base[..]);
    var sd: u8[>..] = [];
    sd.append(base[..]);
    sd.append("/seeds");
    seeds(sd[..]);

    var t = testkit::new_t();
    testkit::run(t, "fuzz/lexer") { tt =>
        var rep = fuzz::Report { };
        let cfg = config(20000, base[..]);
        let found = fuzz::run("lexer", cfg, rep, lex_worker);
        var out: u8[>..] = [];
        fuzz::format_report(out, rep);
        testkit::fuzz_result(tt, found, rep.runs, out[..]);
    };
    testkit::run(t, "fuzz/matcher") { tt =>
        var rep = fuzz::Report { };
        let cfg = config(20000, base[..]);
        let found = fuzz::run("matcher", cfg, rep, match_worker);
        var out: u8[>..] = [];
        fuzz::format_report(out, rep);
        testkit::fuzz_result(tt, found, rep.runs, out[..]);
    };
    testkit::finish(t);
    return 0;
}
