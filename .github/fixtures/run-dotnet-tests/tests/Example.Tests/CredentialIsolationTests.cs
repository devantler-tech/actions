using System.Xml.Linq;

namespace Example.Tests;

/// <summary>
/// Verifies the credential boundary of the run-dotnet-tests composite action.
/// </summary>
public class CredentialIsolationTests
{
  /// <summary>
  /// Ensures repository-controlled tests cannot read the GitHub Packages credential.
  /// </summary>
  [Fact]
  public void GitHubPackagesCredential_IsUnavailableToRepositoryTests()
  {
    string? configPath = Environment.GetEnvironmentVariable("RUN_DOTNET_TESTS_CREDENTIAL_CONFIG");
    if (string.IsNullOrWhiteSpace(configPath))
    {
      if (!string.Equals(
          Environment.GetEnvironmentVariable("GITHUB_ACTIONS"),
          "true",
          StringComparison.OrdinalIgnoreCase))
      {
        return;
      }

      configPath = OperatingSystem.IsWindows()
        ? Path.Combine(
          Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
          "NuGet",
          "NuGet.Config")
        : Path.Combine(
          Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
          ".nuget",
          "NuGet",
          "NuGet.Config");
    }

    Assert.Null(Environment.GetEnvironmentVariable("NuGetPackageSourceCredentials_github"));

    if (!File.Exists(configPath))
    {
      return;
    }

    var config = XDocument.Load(configPath);
    var githubCredentials = config
      .Descendants("packageSourceCredentials")
      .Elements()
      .FirstOrDefault(element =>
        string.Equals(element.Name.LocalName, "github", StringComparison.OrdinalIgnoreCase));

    Assert.Null(githubCredentials);
  }
}
