namespace Example.Tests;

/// <summary>
/// Proves run-dotnet-tests runs an xUnit v3 4.x project on Microsoft.Testing.Platform.
/// </summary>
public class CalculatorTests
{
  /// <summary>
  /// A passing test, so a zero-tests exit code cannot pass for success.
  /// </summary>
  [Fact]
  public void Add_ReturnsSum() => Assert.Equal(4, 2 + 2);
}
