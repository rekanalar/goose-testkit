// The parallel helpers use queues, so this program needs goose build.
// It checks the totals that a worker puts on the queue, the order of
// the names and the count of an aborted worker.
import std;
import testkit from "..";

// A worker puts its totals on the queue and the caller adds them. The
// names come out in byte order, and an aborted worker counts as a
// failed test.
fn check_parallel() {
    var w1 = testkit::new_t();
    testkit::run(w1, "zeta") { tt => testkit::eq_i64(tt, 1, 1); };
    testkit::run(w1, "beta") { tt => testkit::eq_i64(tt, 1, 2); };
    testkit::report(w1);
    var w2 = testkit::new_t();
    testkit::run(w2, "alpha") { tt => testkit::skip(tt, "later"); };
    testkit::report(w2);
    var t = testkit::new_t();
    testkit::absorb(t);
    assert(t.pass_tests == 1 && t.fail_tests == 1 && t.skip_tests == 1);
    assert(t.total_checks == 2);
    testkit::sort_names(t);
    assert(t.names[..] == "alpha\nbeta\nzeta\n");
    // The queue holds nothing more.
    testkit::absorb(t);
    assert(t.pass_tests == 1);
    testkit::crashed(t, "gone", "assert failed");
    assert(t.fail_tests == 2);
    assert(t.names[..] == "alpha\nbeta\nzeta\ngone\n");
    // A control byte in the message prints escaped; the run goes on.
    testkit::crashed(t, "esc", "bad\x1b[31m");
    assert(t.fail_tests == 3);
}

fn main() {
    check_parallel();
    print("parallel tests pass");
}
