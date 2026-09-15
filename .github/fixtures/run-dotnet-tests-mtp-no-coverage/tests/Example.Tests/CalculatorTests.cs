namespace Example.Tests;

/// <summary>
/// Proves run-dotnet-tests still runs tests on Microsoft.Testing.Platform when the
/// project does not reference the code coverage extension.
/// </summary>
public class CalculatorTests
{
  /// <summary>
  /// A passing test, so a zero-tests exit code cannot pass for success.
  /// </summary>
  [Fact]
  public void Add_ReturnsSum() => Assert.Equal(4, 2 + 2);
}
