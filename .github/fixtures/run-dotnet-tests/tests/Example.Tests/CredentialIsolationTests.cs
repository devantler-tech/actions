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
    string? configOverride = Environment.GetEnvironmentVariable("RUN_DOTNET_TESTS_CREDENTIAL_CONFIG");
    string[] configPaths;
    if (!string.IsNullOrWhiteSpace(configOverride))
    {
      configPaths = [configOverride];
    }
    else if (string.Equals(
      Environment.GetEnvironmentVariable("GITHUB_ACTIONS"),
      "true",
      StringComparison.OrdinalIgnoreCase))
    {
      configPaths = OperatingSystem.IsWindows()
        ? [
          Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "NuGet",
            "NuGet.Config"),
        ]
        : [
          Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".nuget",
            "NuGet",
            "NuGet.Config"),
          Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".config",
            "NuGet",
            "NuGet.Config"),
        ];
    }
    else
    {
      return;
    }

    Assert.Null(Environment.GetEnvironmentVariable("NuGetPackageSourceCredentials_github"));

    foreach (string configPath in configPaths.Where(File.Exists))
    {
      var config = XDocument.Load(configPath);
      var githubCredentials = config
        .Descendants("packageSourceCredentials")
        .Elements()
        .FirstOrDefault(element =>
          string.Equals(element.Name.LocalName, "github", StringComparison.OrdinalIgnoreCase));

      Assert.False(
        githubCredentials is not null,
        "GitHub Packages credentials must not be persisted where repository tests can read them.");
    }
  }
}
