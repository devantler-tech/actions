namespace SourceMapping.Tests;

/// <summary>
/// Verifies packages remain resolvable through caller-defined source mappings.
/// </summary>
public class DependencyTests
{
  /// <summary>
  /// Reads a value from the package restored exclusively from the mapped local source.
  /// </summary>
  [Fact]
  public void LocalMappedPackage_IsAvailable()
  {
    Assert.Equal("mapped-source", Fixture.Dependency.Marker.Value);
  }
}
