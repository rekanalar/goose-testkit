// The test suite of testkit itself. It drives the library and checks
// the counters, so a fault in the report cannot hide.
import std;
import testkit from "..";

fn names_of(list: const u8[:]) -> bool {
    return list.len > 0;
}

fn fixture_run(order: u8[>..]&) {
    var t = testkit::new_t();
    testkit::run(t, "fx") { tt =>
        with_db(tt, order) { t2, db =>
            testkit::eq_i64(t2, db, 7);
            order.push('b');
        }
    };
    assert(t.pass_tests == 1);
}

// with_db is a fixture: it sets up, runs the block, and tears down.
// A failed check or a skip returns from the block, so the teardown
// runs. Goose v2026.3 has no defer, so the fixture does not use one.
fn with_db<F>(t: testkit::T&, order: u8[>..]&) {
    order.push('s');
    let db: i64 = 7;
    F(t, db);
    order.push('d');
}

fn check_scopes() {
    // The rules of t.Run in Go 1.27: the name reads parent/child, a
    // failed subtest fails every ancestor, a skipped subtest leaves
    // the parent a pass.
    var t = testkit::new_t();
    testkit::run(t, "Parent") { tt =>
        testkit::scope(tt, "ok") { t2 => testkit::eq_i64(t2, 1, 1) };
        testkit::scope(tt, "bad") { t2 => testkit::eq_i64(t2, 1, 2) };
        testkit::scope(tt, "skipped") { t2 => testkit::skip(t2, "s") };
        testkit::scope(tt, "nest") { t2 =>
            testkit::scope(t2, "deep") { t3 => testkit::eq_i64(t3, 1, 2) };
        };
        testkit::fail(tt, "parent after");
    };
    // ok, skipped: pass and skip. bad, deep, nest and Parent fail.
    assert(t.pass_tests == 1 && t.skip_tests == 1 && t.fail_tests == 4);
    var want: u8[>..] = [];
    for s in ["Parent", "Parent/ok", "Parent/bad", "Parent/skipped", "Parent/nest", "Parent/nest/deep"] {
        for b in s { want.push(b); }
        want.push(10);
    }
    assert(t.names == want);

    // A parent that only has a skipped child passes.
    var t2 = testkit::new_t();
    testkit::run(t2, "OnlySkip") { tt =>
        testkit::scope(tt, "c") { t3 => testkit::skip(t3, "s") };
    };
    assert(t2.pass_tests == 1 && t2.skip_tests == 1 && t2.fail_tests == 0);

    // A parent that skipped runs no subtest, as Go ends the test.
    var t3 = testkit::new_t();
    testkit::run(t3, "SkipParent") { tt =>
        testkit::skip(tt, "p");
        testkit::scope(tt, "never") { t4 => testkit::fail(t4, "ran") };
    };
    assert(t3.fail_tests == 0 && t3.skip_tests == 1);

    // Go turns each space of the name of a subtest into an underscore.
    var t4 = testkit::new_t();
    testkit::run(t4, "P") { tt =>
        testkit::scope(tt, "a b") { t2 => testkit::eq_i64(t2, 1, 1) };
    };
    assert(t4.names == "P\nP/a_b\n");
}

fn check_cases() {
    var t = testkit::new_t();
    var seen: i64 = 0;
    testkit::run(t, "Table") { tt =>
        testkit::cases(tt, "row", 3) { t2, i =>
            seen = seen + i + 1;
            testkit::eq_i64(t2, i * 2, i + i);
        };
    };
    assert(seen == 6);
    assert(t.pass_tests == 4 && t.fail_tests == 0);
    var want: u8[>..] = [];
    for s in ["Table", "Table/row/0", "Table/row/1", "Table/row/2"] {
        for b in s { want.push(b); }
        want.push(10);
    }
    assert(t.names == want);
    // A failing row fails the table.
    var t2 = testkit::new_t();
    testkit::run(t2, "Bad") { tt =>
        testkit::cases(tt, "r", 2) { t3, i => testkit::eq_i64(t3, i, 1) };
    };
    assert(t2.fail_tests == 2);
}

fn check_fixture() {
    var order: u8[>..] = [];
    fixture_run(order);
    assert(order == "sbd");
    // The teardown runs after a failed check and after a skip.
    var o2: u8[>..] = [];
    var t = testkit::new_t();
    testkit::run(t, "failing") { tt =>
        with_db(tt, o2) { t2, db => testkit::eq_i64(t2, db, 8) };
    };
    testkit::run(t, "skipping") { tt =>
        with_db(tt, o2) { t2, db => testkit::skip(t2, "s") };
    };
    assert(o2 == "sdsd");
    assert(t.fail_tests == 1 && t.skip_tests == 1);
}

fn check_rerun() {
    // A flaky test passes on the third attempt: it counts once, as a pass.
    var t = testkit::new_t();
    var k: i64 = 0;
    assert(testkit::rerun(t, "flaky", 3) { tt =>
        k = k + 1;
        testkit::eq_i64(tt, k, 3);
    });
    assert(k == 3);
    assert(t.pass_tests == 1 && t.fail_tests == 0 && t.total_checks == 1);
    assert(t.names == "flaky\n");
    // A test that always fails counts once, as a failure.
    var t2 = testkit::new_t();
    var j: i64 = 0;
    assert(!testkit::rerun(t2, "dead", 2) { tt =>
        j = j + 1;
        testkit::fail(tt, "no");
    });
    assert(j == 2 && t2.fail_tests == 1 && t2.pass_tests == 0);
    assert(t2.names == "dead\n");
}

// The run pattern follows go test -run. Each row below was observed
// on a real Go suite: TestA with children B (grandchild D) and C.
fn check_matches() {
    assert(testkit::matches("", "A") && testkit::matches("", "Nope"));
    // A short pattern runs the subtree.
    assert(testkit::matches("A", "A/B/D") && testkit::matches("A", "A/C"));
    assert(!testkit::matches("A", "Nope"));
    // The parent runs and the other children do not.
    assert(testkit::matches("A/B", "A") && testkit::matches("A/B", "A/B/D"));
    assert(!testkit::matches("A/B", "A/C"));
    assert(testkit::matches("A/x", "A") && !testkit::matches("A/x", "A/B"));
    // A first part that misses runs nothing, not even the parent.
    assert(!testkit::matches("x/B", "A") && !testkit::matches("x/B", "A/B"));
    assert(!testkit::matches("nope2", "A"));
    // An empty first part matches anything.
    assert(testkit::matches("/B", "A") && testkit::matches("/B", "Nope"));
    assert(testkit::matches("/B", "A/B") && !testkit::matches("/B", "A/C"));
    // Text match, anchors and alternatives.
    assert(testkit::matches("lpha", "Alpha") && testkit::matches("lpha", "Zalpha"));
    assert(testkit::matches("Alpha/eta", "Alpha/XBeta"));
    assert(testkit::matches("Alpha/^Beta", "Alpha/Beta"));
    assert(!testkit::matches("Alpha/^Beta", "Alpha/XBeta"));
    assert(testkit::matches("Beta$", "XBeta") && !testkit::matches("Beta$", "BetaX"));
    assert(testkit::matches("^A$", "A") && !testkit::matches("^A$", "AB"));
    assert(testkit::matches("Alpha|Zalpha", "Zalpha") && !testkit::matches("Alpha|Beta", "Zeta"));
}

// Each part of the run pattern reads as a regular expression. These
// rows come from a real go test -run run on a Go suite with the tests
// TestAlpha, TestAlphaTwo and TestAlphaSub.
fn check_regex() {
    // A part matches anywhere in the name part.
    assert(testkit::matches("Alpha", "TestAlpha"));
    assert(testkit::matches("Alpha", "TestAlphaTwo"));
    assert(testkit::matches("Alpha", "TestAlphaSub"));
    // A part that ends with $ matches only a name part that ends with a
    // match.
    assert(testkit::matches("Alpha$", "TestAlpha"));
    assert(!testkit::matches("Alpha$", "TestAlphaTwo"));
    // A part that begins with ^ matches only a name part that begins
    // with a match.
    assert(!testkit::matches("^Alpha", "TestAlpha"));
    assert(testkit::matches("^Test", "TestAlpha"));
    assert(!testkit::matches("^Test", "MyTest"));
    // A dot reads as any byte and a class reads as a class.
    assert(testkit::matches("A.*a", "TestAlpha"));
    assert(testkit::matches("Test[A-Z]lpha", "TestAlpha"));
    assert(!testkit::matches("Test[^A-Z]lpha", "TestAlpha"));
    // A group holds its own slash and bar.
    assert(testkit::matches("A/(x|y)", "A/x") && testkit::matches("A/(x|y)", "A/y"));
    assert(!testkit::matches("A/(x|y)", "A/z"));
    // A space of a pattern part reads as an underscore, as in Go.
    assert(testkit::matches("Test Alpha", "Test_Alpha"));
}

// The shard hash is fixed: FNV-1a on 32 bits. The two shards of a
// pair hold every name once.
fn check_shard() {
    assert(testkit::shard_of("A", 4) == testkit::shard_of("A", 4));
    assert(testkit::shard_of("anything", 1) == 0);
    // Reference values: FNV-1a 32 of "a" is 0xe40c292c and of "" is 0x811c9dc5.
    assert(testkit::shard_of("a", 4294967295) == 0xe40c292c);
    assert(testkit::shard_of("", 4294967295) == 0x811c9dc5);
    var both = 0;
    for name in ["A", "A/B", "A/C", "Nope", "x", "y", "z"] {
        let in1 = testkit::shard_of(name, 2) == 0;
        let in2 = testkit::shard_of(name, 2) == 1;
        assert(in1 != in2);
        both = both + 1;
    }
    assert(both == 7);
}

// A run with a filter, a shard and a count.
fn check_filter() {
    var t = testkit::new_t();
    testkit::filter(t, "A/B", 0, 0, 1);
    var ran: i64 = 0;
    testkit::run(t, "A") { tt =>
        ran = ran + 1;
        testkit::scope(tt, "B") { t2 => ran = ran + 10; };
        testkit::scope(tt, "C") { t2 => ran = ran + 100; };
    };
    testkit::run(t, "Nope") { tt => ran = ran + 1000; };
    assert(ran == 11);
    // A and its subtest A/B pass. Nope is a skip. The list of names
    // holds A and A/B only.
    assert(t.filtered == 1 && t.skip_tests == 1 && t.pass_tests == 2);
    assert(t.names.len == 6);

    // Shard 1 of 2 and shard 2 of 2 run each test once between them.
    var runs: i64 = 0;
    for i in 2 {
        var s = testkit::new_t();
        testkit::filter(s, "", i + 1, 2, 1);
        for k in 6 {
            var nm: u8[>..] = [];
            nm.push((65 + k) as u8);
            testkit::run(s, nm[..]) { tt => runs = runs + 1; };
        }
        assert(s.sharded + s.pass_tests == 6);
    }
    assert(runs == 6);

    // A count of 3 retries a test that fails twice, then passes.
    var u = testkit::new_t();
    testkit::filter(u, "", 0, 0, 3);
    var attempts: i64 = 0;
    let ok = testkit::run(u, "flaky") { tt =>
        attempts = attempts + 1;
        testkit::is_true(tt, attempts >= 3, "third attempt");
    };
    assert(ok && attempts == 3 && u.pass_tests == 1 && u.fail_tests == 0);
}

// The result of a fuzz run. A clean run passes. A finding fails and
// prints the report. A run of no input fails. A hostile report prints
// escaped and cut.
fn check_fuzz_result() {
    var t = testkit::new_t();
    testkit::begin(t, "clean");
    testkit::fuzz_result(t, 0, 100, "seed: 1\nruns: 100\nfindings: 0\n");
    assert(testkit::end(t) && t.total_checks == 1);
    testkit::begin(t, "found");
    testkit::fuzz_result(t, 2, 100, "x");
    assert(!testkit::end(t) && t.fail_tests == 1);
    testkit::begin(t, "none");
    testkit::fuzz_result(t, 0, 0, "");
    assert(!testkit::end(t) && t.fail_tests == 2);
    // Under xfail a finding counts as an expected failure.
    testkit::begin(t, "xfail");
    testkit::xfail(t, "known");
    testkit::fuzz_result(t, 1, 5, "x");
    assert(testkit::end(t) && t.xfail_tests == 1);
    var out: u8[>..] = [];
    testkit::put_report(out, "a\x1b[31m\nb\x00");
    assert(out[..] == "a\\x1b[31m\nb\\x00");
    var big: u8[>..] = [];
    for k in 5000 { big.push('x'); }
    var cut: u8[>..] = [];
    testkit::put_report(cut, big[..]);
    assert(cut.len == 4096 + 30);
}

// found lexes one source text. It gives 0, or the line of the fault.
// The names and the fault message go to the two buffers.
fn found(src: const u8[:], names: u8[>..]&, why: u8[>..]&) -> i64 {
    names.clear();
    why.clear();
    return testkit::lex_scan(src, names, why);
}

// A message about a file name hides every byte outside printable ASCII.
fn check_put_safe() {
    var out: u8[>..] = [];
    testkit::lex_put_safe(out, "a\x1b[31mb\x00c\xffd e/f.goose");
    assert(out[..] == "a?[31mb?c?d e/f.goose");
}

// The lexer finds the call sites that name a test with a literal and
// ignores everything else.
fn check_lex() {
    var names: u8[>..] = [];
    var why: u8[>..] = [];
    // run and begin, with a nested paren, over lines.
    assert(found("testkit::run(t, \"a\") { tt => }", names, why) == 0 && names[..] == "a\n");
    assert(found("testkit::begin(t, \"b/c\");", names, why) == 0 && names[..] == "b/c\n");
    assert(found("testkit::run(f(1, (2)), \"n\")", names, why) == 0 && names[..] == "n\n");
    assert(found("testkit::run(\n  t,\n  \"far\"\n)", names, why) == 0 && names[..] == "far\n");
    assert(found("testkit::run(t, \"p\"); testkit::run(t, \"q\");", names, why) == 0 && names[..] == "p\nq\n");
    // A call in a comment, in a string, a name built at runtime, a
    // longer identifier and a call with one argument give nothing.
    assert(found("// testkit::run(t, \"x\")\n", names, why) == 0 && names.len == 0);
    assert(found("let s = \"testkit::run(t, \\\"x\\\")\";", names, why) == 0 && names.len == 0);
    assert(found("let q = '\"'; let r = 'x';", names, why) == 0 && names.len == 0);
    assert(found("testkit::run(t, name)", names, why) == 0 && names.len == 0);
    assert(found("xtestkit::run(t, \"x\")", names, why) == 0 && names.len == 0);
    assert(found("testkit::run(t)", names, why) == 0 && names.len == 0);
    // The faults name the line.
    assert(found("a\nb\nlet s = \"open\nc", names, why) == 3 && why[..] == "a string never ends");
    assert(found("\ntestkit::run(t", names, why) == 2 && why[..] == "a call never closes");
    assert(found("testkit::run(t, \"a\\nb\")", names, why) == 1
           && why[..] == "a test name holds a backslash; write the name in plain text");
    assert(found("testkit::run(t, \"\")", names, why) == 1 && why[..] == "a test name is empty");
    assert(found("testkit::run(t, \"\x01\")", names, why) == 1
           && why[..] == "a test name holds a byte outside printable ASCII");
    // A name of 1024 bytes passes. One of 1025 bytes faults.
    var big: u8[>..] = [];
    for b in "testkit::run(t, \"" { big.push(b); }
    for k in 1024 { big.push('x'); }
    for b in "\")" { big.push(b); }
    assert(found(big[..], names, why) == 0 && names.len == 1025);
    var big2: u8[>..] = [];
    for b in "testkit::run(t, \"" { big2.push(b); }
    for k in 1025 { big2.push('x'); }
    for b in "\")" { big2.push(b); }
    assert(found(big2[..], names, why) == 1 && why[..] == "a test name is longer than 1024 bytes");
}

// The benchmark times a block. It is not a test, and the run pattern
// leaves it out.
fn check_bench() {
    var t = testkit::new_t();
    var sum: i64 = 0;
    let per = testkit::bench(t, "add", 100) { i => sum = sum + i; };
    assert(sum == 4950);
    assert(per >= 0.0);
    // A benchmark does not count in the totals of the suite.
    assert(t.pass_tests == 0 && t.fail_tests == 0 && t.total_checks == 0);
    // The run pattern leaves a benchmark out.
    var t2 = testkit::new_t();
    testkit::filter(t2, "other", 0, 0, 1);
    var hits: i64 = 0;
    let per2 = testkit::bench(t2, "add", 10) { i => hits = hits + i; };
    assert(hits == 0 && per2 == 0.0);
}

// The lexer finds the namespace of a file and the test functions of a
// file.
fn check_funcs() {
    var ns: u8[>..] = [];
    testkit::lex_namespace("namespace math;\nfn test_a(t: testkit::T&) { }\n", ns);
    assert(ns[..] == "math");
    ns.clear();
    testkit::lex_namespace("import std;\nfn main() { }\n", ns);
    assert(ns.len == 0);
    var names: u8[>..] = [];
    var why: u8[>..] = [];
    assert(testkit::lex_funcs("fn test_a(t: testkit::T&) { }\nfn test_b(t: testkit::T&) { }\n", names, why) == 0);
    assert(names[..] == "test_a\ntest_b\n");
    // A function that is not a test gives nothing.
    names.clear();
    assert(testkit::lex_funcs("fn helper(t: i64) { }\nfn main() { }\n", names, why) == 0 && names.len == 0);
    // A test function with a wrong shape is a fault that names the line.
    names.clear();
    why.clear();
    assert(testkit::lex_funcs("fn test_a(t: i64) { }\n", names, why) == 1);
    assert(why[..] == "a test function takes one tracker: testkit::T&");
    names.clear();
    why.clear();
    assert(testkit::lex_funcs("fn test_a(t: testkit::T&, x: i64) { }\n", names, why) == 1);
    assert(why[..] == "a test function takes one tracker");
    names.clear();
    why.clear();
    assert(testkit::lex_funcs("fn test_a(t: testkit::T&) -> bool { }\n", names, why) == 1);
    assert(why[..] == "a test function returns nothing");
    // A test function inside a function is not a test.
    names.clear();
    assert(testkit::lex_funcs("fn outer() { fn test_a(t: testkit::T&) { } }\n", names, why) == 0 && names.len == 0);
}

fn main() {
    // A clean test: both checks run, the suite counts one pass.
    var t = testkit::new_t();
    testkit::begin(t, "clean");
    testkit::eq_i64(t, 1 + 1, 2);
    testkit::is_true(t, "abc" == "abc", "text equality");
    assert(testkit::end(t));
    assert(t.pass_tests == 1 && t.fail_tests == 0 && t.total_checks == 2);

    // A failing check reports and continues; the test fails once.
    testkit::begin(t, "bad");
    testkit::eq_i64(t, 1, 2);
    testkit::eq_i64(t, 3, 4);
    assert(!testkit::end(t));
    assert(t.fail_tests == 1 && t.total_checks == 4);

    // The tolerance of eq_f64: inside passes, outside fails, a NaN
    // fails.
    testkit::begin(t, "float");
    testkit::eq_f64(t, 0.1 + 0.2, 0.3, 1e-9);
    assert(testkit::end(t));
    testkit::begin(t, "float");
    testkit::eq_f64(t, 0.1 + 0.2, 0.3, 0.0);
    assert(!testkit::end(t));
    testkit::begin(t, "float");
    testkit::eq_f64(t, 0.0 / 0.0, 0.0, 1.0);
    assert(!testkit::end(t));

    // eq_text: equal passes; a difference reports the first byte.
    testkit::begin(t, "text");
    testkit::eq_text(t, "one\ntwo\n", "one\ntwo\n");
    assert(testkit::end(t));
    testkit::begin(t, "text");
    testkit::eq_text(t, "one\ntwo\n", "one\nTWO\n");
    assert(!testkit::end(t));
    // A length difference counts as a difference at the short end.
    testkit::begin(t, "text");
    testkit::eq_text(t, "ab", "abc");
    assert(!testkit::end(t));

    // eq_bytes holds the same report for raw bytes.
    testkit::begin(t, "bytes");
    testkit::eq_bytes(t, "ab", "ab");
    assert(testkit::end(t));
    testkit::begin(t, "bytes");
    testkit::eq_bytes(t, "a\x02", "a\x01");
    assert(!testkit::end(t));

    // skip ends the checks of the test.
    let before = t.total_checks;
    testkit::begin(t, "skip");
    testkit::skip(t, "not on this platform");
    testkit::eq_i64(t, 1, 2);
    assert(testkit::end(t));
    assert(t.skip_tests == 1 && t.total_checks == before);

    // A failure before a skip stays a failure, as in Go testing.
    let fails0 = t.fail_tests;
    testkit::begin(t, "failskip");
    testkit::fail(t, "early");
    testkit::skip(t, "late");
    assert(!testkit::end(t));
    assert(t.fail_tests == fails0 + 1);

    // xfail turns the failures of the test into expected ones.
    testkit::begin(t, "xfail");
    testkit::xfail(t, "bug 7");
    testkit::eq_i64(t, 1, 2);
    assert(testkit::end(t));
    assert(t.xfail_tests == 1 && t.fail_tests == 7);

    // A test marked xfail that passes counts as a pass, with a note.
    let passes = t.pass_tests;
    testkit::begin(t, "xfailpass");
    testkit::xfail(t, "bug 8");
    testkit::eq_i64(t, 1, 1);
    assert(testkit::end(t));
    assert(t.pass_tests == passes + 1);

    // The names of every test that ran sit in the tracker.
    var want: u8[>..] = [];
    for s in ["clean", "bad", "float", "float", "float", "text", "text", "text", "bytes", "bytes", "skip", "failskip", "xfail", "xfailpass"] {
        for b in s { want.push(b); }
        want.push(10);
    }
    assert(t.names == want);

    // The name buffer stays bounded: past the cap a test still runs
    // and counts, and the report counts the names it dropped.
    var big = testkit::new_t();
    for i in 5000 {
        testkit::begin(big, "a_test_name_of_some_length");
        testkit::eq_i64(big, i, i);
        testkit::end(big);
    }
    assert(big.pass_tests == 5000);
    assert(big.names.len <= 65536 + 64);
    assert(big.unlisted > 0);

    check_scopes();
    check_cases();
    check_fixture();
    check_rerun();
    check_matches();
    check_regex();
    check_shard();
    check_filter();
    check_lex();
    check_bench();
    check_funcs();
    check_fuzz_result();
    check_put_safe();
    print("all testkit tests pass");
}
