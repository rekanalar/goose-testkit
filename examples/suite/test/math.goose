// A module of the sample suite. The command finds the test functions
// of this file and writes the calls to them.
namespace math;

import testkit;

fn test_sum(t: testkit::T&) {
    testkit::eq_i64(t, 2 + 3, 5);
}

fn test_product(t: testkit::T&) {
    testkit::eq_i64(t, 2 * 3, 6);
}
