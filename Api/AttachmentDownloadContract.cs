using Microsoft.Extensions.Options;
using TaigaMCP.Config;
using TaigaMCP.Models;

namespace TaigaMCP.Api;

/// <summary>Validated source and destination policy for an attachment download.</summary>
internal sealed record AttachmentDownloadPlan(
    Uri SourceUri,
    bool RequiresAuthentication,
    Uri? AuthenticationOrigin,
    string DestinationPath,
    long MaximumBytes);

internal static class AttachmentDownloadContract
{
    public static AttachmentDownloadPlan CreatePlan(
        WorkItemAttachmentDto attachment,
        string destination,
        IOptions<TaigaOptions> options)
    {
        ArgumentNullException.ThrowIfNull(attachment);
        ArgumentNullException.ThrowIfNull(options);
        InputValidation.Required(destination, nameof(destination));
        InputValidation.Positive(options.Value.MaxAttachmentBytes, nameof(TaigaOptions.MaxAttachmentBytes));

        var destinationPath = ValidateDestination(destination);
        var baseUri = GetBaseUri(options.Value.BaseUrl);
        var sourceUri = ResolveSourceUri(attachment, baseUri);

        return new AttachmentDownloadPlan(
            sourceUri,
            IsSameOrigin(sourceUri, baseUri),
            IsSameOrigin(sourceUri, baseUri) ? baseUri : null,
            destinationPath,
            options.Value.MaxAttachmentBytes);
    }

    private static string ValidateDestination(string destination)
    {
        if (!Path.IsPathFullyQualified(destination))
            throw new ArgumentException("destination must be an absolute local file path.", nameof(destination));

        string fullPath;
        try
        {
            fullPath = Path.GetFullPath(destination);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            throw new ArgumentException("destination must be a valid local file path.", nameof(destination), ex);
        }

        var fileName = Path.GetFileName(fullPath);
        var directory = Path.GetDirectoryName(fullPath);
        if (string.IsNullOrWhiteSpace(fileName) || string.IsNullOrWhiteSpace(directory))
            throw new ArgumentException("destination must identify a file in an existing directory.", nameof(destination));
        if (Directory.Exists(fullPath))
            throw new ArgumentException("destination must identify a file, not a directory.", nameof(destination));
        if (!Directory.Exists(directory))
            throw new ArgumentException("destination parent directory must already exist.", nameof(destination));
        if (File.Exists(fullPath))
            throw new ArgumentException("destination already exists; downloads never overwrite existing files.", nameof(destination));

        return fullPath;
    }

    private static Uri ResolveSourceUri(WorkItemAttachmentDto attachment, Uri baseUri)
    {
        var source = !string.IsNullOrWhiteSpace(attachment.Url)
            ? attachment.Url
            : attachment.AttachedFile;
        if (string.IsNullOrWhiteSpace(source))
            throw new TaigaRequestException("Taiga attachment has no usable download location.");

        if (!Uri.TryCreate(source, UriKind.Absolute, out var absolute))
        {
            if (!Uri.TryCreate(source, UriKind.Relative, out var relative) || relative.IsAbsoluteUri)
                throw new TaigaRequestException("Taiga attachment returned an invalid download location.");

            absolute = new Uri(baseUri, relative);
        }

        if (!IsHttpScheme(absolute) || string.IsNullOrEmpty(absolute.Host) || !string.IsNullOrEmpty(absolute.UserInfo))
            throw new TaigaRequestException("Taiga attachment returned an unsupported download URL.");

        return absolute;
    }

    private static Uri GetBaseUri(string? value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var baseUri) ||
            !IsHttpScheme(baseUri) ||
            string.IsNullOrEmpty(baseUri.Host))
            throw new ArgumentException("Taiga base URL must be an absolute HTTP/HTTPS URL.", nameof(value));

        return baseUri;
    }

    private static bool IsSameOrigin(Uri source, Uri baseUri)
        => string.Equals(source.Scheme, baseUri.Scheme, StringComparison.OrdinalIgnoreCase) &&
           string.Equals(source.Host, baseUri.Host, StringComparison.OrdinalIgnoreCase) &&
           source.Port == baseUri.Port;

    private static bool IsHttpScheme(Uri uri)
        => string.Equals(uri.Scheme, Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) ||
           string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase);
}
