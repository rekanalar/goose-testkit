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

fn test_scopes() {
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
}

fn test_cases() {
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

fn test_fixture() {
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

fn test_rerun() {
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

    test_scopes();
    test_cases();
    test_fixture();
    test_rerun();
    print("all testkit tests pass");
}
