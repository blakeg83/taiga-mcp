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
        Assert.Null(plan.ExpectedBytes);
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

    [Theory]
    [InlineData("media/901.bin")]
    [InlineData("attachments/901.bin")]
    [InlineData("/media/901.bin")]
    public void CreatePlan_RejectsStoragePathWhenUrlIsMissing(string source)
    {
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var error = Assert.Throws<TaigaRequestException>(() => AttachmentDownloadContract.CreatePlan(
            new WorkItemAttachmentDto { AttachedFile = source },
            destination,
            Options.Create(OptionsWithBaseUrl())));

        Assert.Contains("storage path", error.Message);
        Assert.DoesNotContain(source, error.Message);
    }

    [Fact]
    public void CreatePlan_AcceptsAbsoluteAttachedFileUrlWhenUrlIsMissing()
    {
        var destination = Path.Combine(Path.GetTempPath(), $"taiga-download-{Guid.NewGuid():N}.bin");
        var plan = AttachmentDownloadContract.CreatePlan(
            new WorkItemAttachmentDto { AttachedFile = "https://files.example/901?token=synthetic" },
            destination,
            Options.Create(OptionsWithBaseUrl()));

        Assert.Equal("?token=synthetic", plan.SourceUri.Query);
        Assert.False(plan.RequiresAuthentication);
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
