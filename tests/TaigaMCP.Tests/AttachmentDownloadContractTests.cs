using Microsoft.Extensions.Options;
using TaigaMCP.Api;
using TaigaMCP.Config;
using TaigaMCP.Models;
using Xunit;

namespace TaigaMCP.Tests;

public sealed class AttachmentDownloadContractTests
{
    [Fact]
    public void CreatePlan_UsesSameOriginUrlWithAuthentication()
    {
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var plan = AttachmentDownloadContract.CreatePlan(
            new WorkItemAttachmentDto { Url = "https://fake.taiga.test/media/901.bin" },
            destination,
            Options.Create(OptionsWithBaseUrl()));

        Assert.Equal(new Uri("https://fake.taiga.test/media/901.bin"), plan.SourceUri);
        Assert.True(plan.RequiresAuthentication);
        Assert.Equal(Path.GetFullPath(destination), plan.DestinationPath);
        Assert.Equal(10 * 1024 * 1024, plan.MaximumBytes);
    }

    [Fact]
    public void CreatePlan_DoesNotAuthenticateExternalSignedUrl()
    {
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var plan = AttachmentDownloadContract.CreatePlan(
            new WorkItemAttachmentDto { Url = "https://files.example/901?signature=synthetic" },
            destination,
            Options.Create(OptionsWithBaseUrl()));

        Assert.False(plan.RequiresAuthentication);
    }

    [Fact]
    public void CreatePlan_ResolvesAttachedFileWhenUrlIsMissing()
    {
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var plan = AttachmentDownloadContract.CreatePlan(
            new WorkItemAttachmentDto { AttachedFile = "media/901.bin" },
            destination,
            Options.Create(OptionsWithBaseUrl()));

        Assert.Equal("https://fake.taiga.test/api/v1/media/901.bin", plan.SourceUri.AbsoluteUri);
        Assert.True(plan.RequiresAuthentication);
    }

    [Fact]
    public void CreatePlan_RejectsRelativeDestination()
    {
        Assert.Throws<ArgumentException>(() => AttachmentDownloadContract.CreatePlan(
            new WorkItemAttachmentDto { Url = "https://files.example/901" },
            "relative.bin",
            Options.Create(OptionsWithBaseUrl())));
    }

    [Fact]
    public void CreatePlan_RejectsExistingDestination()
    {
        var target = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        File.WriteAllText(target, "preserve");
        try
        {
            var error = Assert.Throws<ArgumentException>(() => AttachmentDownloadContract.CreatePlan(
                new WorkItemAttachmentDto { Url = "https://files.example/901" },
                target,
                Options.Create(OptionsWithBaseUrl())));

            Assert.Contains("never overwrite", error.Message);
        }
        finally { File.Delete(target); }
    }

    [Fact]
    public void CreatePlan_RejectsUnsupportedSourceScheme()
    {
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");

        var error = Assert.Throws<TaigaRequestException>(() => AttachmentDownloadContract.CreatePlan(
            new WorkItemAttachmentDto { Url = "file:///secret.bin" },
            destination,
            Options.Create(OptionsWithBaseUrl())));

        Assert.Contains("unsupported download URL", error.Message);
    }

    private static TaigaOptions OptionsWithBaseUrl()
        => new() { BaseUrl = TaigaTestClient.BaseUrl };
}
