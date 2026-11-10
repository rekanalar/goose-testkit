// A small suite that shows the shape of a testkit run: the tests are
// plain functions, main lists them, finish prints the summary.
import std;
import testkit from "..";

fn add(a: i64, b: i64) -> i64 { return a + b; }

fn test_add(t: testkit::T&) {
    testkit::eq_i64(t, add(1, 2), 3);
    testkit::eq_i64(t, add(-1, 1), 0);
    testkit::eq_f64(t, add(1, 2) * 0.5, 1.5, 1e-12);
}

fn test_text(t: testkit::T&) {
    testkit::eq_text(t, "a b c", "a b c");
    testkit::is_true(t, "abc".len == 3, "length");
}

fn test_slow(t: testkit::T&) {
    testkit::skip(t, "too slow for every run");
}

fn main() {
    var t = testkit::new_t();
    testkit::begin(t, "test_add");
    test_add(t);
    testkit::end(t);
    testkit::begin(t, "test_text");
    test_text(t);
    testkit::end(t);
    testkit::begin(t, "test_slow");
    test_slow(t);
    testkit::end(t);
    testkit::finish(t);
}
