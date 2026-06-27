namespace Failing.Tests;

// A single deliberately-failing test, mirroring go-test-fixture's TestDeliberatelyFails.
// run-dotnet-tests' gate (`dotnet test`) MUST exit non-zero on this, proving the .NET test
// gate still blocks a PR when a test fails. test-run-dotnet-tests-blocks points the gate's
// command at this fixture and asserts the block.
public class DeliberateFailureTests
{
  [Fact]
  public void Test_DeliberatelyFails() =>
    Assert.True(false, "This test fails on purpose to exercise the run-dotnet-tests gate's block path.");
}
