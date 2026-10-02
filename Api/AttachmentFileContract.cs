using System.Collections.ObjectModel;
using System.Security;
using Microsoft.Extensions.Options;
using TaigaMCP.Config;

namespace TaigaMCP.Api;

/// <summary>Validated local file information used by the single-file attachment upload.</summary>
internal sealed record AttachmentFileSource(
    string FullPath,
    string FileName,
    long Length,
    string MediaType);

internal static class AttachmentFileContract
{
    private static readonly IReadOnlyDictionary<string, string> MediaTypes =
        new ReadOnlyDictionary<string, string>(new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            [".bmp"] = "image/bmp",
            [".csv"] = "text/csv",
            [".gif"] = "image/gif",
            [".htm"] = "text/html",
            [".html"] = "text/html",
            [".jpeg"] = "image/jpeg",
            [".jpg"] = "image/jpeg",
            [".json"] = "application/json",
            [".pdf"] = "application/pdf",
            [".png"] = "image/png",
            [".txt"] = "text/plain",
            [".webp"] = "image/webp",
            [".xml"] = "application/xml",
            [".zip"] = "application/zip"
        });

    public static AttachmentFileSource Validate(string file, IOptions<TaigaOptions> options)
    {
        InputValidation.Required(file, nameof(file));
        ArgumentNullException.ThrowIfNull(options);
        InputValidation.Positive(options.Value.MaxAttachmentBytes, nameof(TaigaOptions.MaxAttachmentBytes));

        string fullPath;
        try
        {
            fullPath = Path.GetFullPath(file);
        }
        catch (Exception ex) when (ex is ArgumentException or NotSupportedException or PathTooLongException)
        {
            throw new ArgumentException("file must be a valid local file path.", nameof(file), ex);
        }

        if (!Path.IsPathFullyQualified(fullPath))
            throw new ArgumentException("file must be an absolute local file path.", nameof(file));
        if (Directory.Exists(fullPath))
            throw new ArgumentException("file must identify a file, not a directory.", nameof(file));

        FileInfo info;
        try
        {
            info = new FileInfo(fullPath);
            info.Refresh();
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or SecurityException)
        {
            throw new ArgumentException("file could not be inspected.", nameof(file), ex);
        }

        if (!info.Exists)
            throw new ArgumentException("file does not exist or is not accessible.", nameof(file));
        if (info.Length > options.Value.MaxAttachmentBytes)
            throw new ArgumentException(
                $"file exceeds the configured maximum size of {options.Value.MaxAttachmentBytes} bytes.",
                nameof(file));

        var fileName = Path.GetFileName(fullPath);
        if (string.IsNullOrWhiteSpace(fileName))
            throw new ArgumentException("file must have a filename.", nameof(file));

        return new AttachmentFileSource(fullPath, fileName, info.Length, GetMediaType(fileName));
    }

    public static string GetMediaType(string fileName)
        => MediaTypes.TryGetValue(Path.GetExtension(fileName), out var mediaType)
            ? mediaType
            : "application/octet-stream";
}
