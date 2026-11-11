// A suite that reports the coverage of its tests. The command writes
// the calls with the -cover flag, and the root file declares the fuzz
// package and the process package that it needs.
//
//   goose build -o testgen ../../cmd/testgen.goose
//   ./testgen -parallel 2 -cover
//   goose build --debug test/run.goose -o cover-run
//   GOOSE_CC=<path of cov-cc> goose build --debug test/run.goose -o cover-run
//
// A build without the coverage compiler runs the tests and reports
// that the coverage is off.
import std;
import process from "rekanalar/goose-process@v1.0.0";
import fuzz from "rekanalar/goose-fuzz@v1.3.0";
import testkit from "../../..";
import _gen;

fn main() {
    var t = testkit::new_t();
    testkit::filter(t, _gen::run(), _gen::shard_i(), _gen::shard_n(), _gen::count());
    _gen::run_all(t);
    testkit::finish(t);
}
