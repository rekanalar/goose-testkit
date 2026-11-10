// The test suite of testkit itself. It drives the library and checks
// the counters, so a fault in the report cannot hide.
import std;
import testkit from "..";

fn names_of(list: const u8[:]) -> bool {
    return list.len > 0;
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

    print("all testkit tests pass");
}
