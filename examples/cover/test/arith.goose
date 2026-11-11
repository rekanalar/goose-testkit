namespace arith;

import std;
import testkit;

fn sum_to(n: i64) -> i64 {
    var s: i64 = 0;
    var i: i64 = 1;
    while i <= n { s = s + i; i = i + 1; }
    return s;
}

fn test_sum(t: testkit::T&) {
    testkit::eq_i64(t, sum_to(10), 55);
}

fn test_empty(t: testkit::T&) {
    testkit::eq_i64(t, sum_to(0), 0);
}
