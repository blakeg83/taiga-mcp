namespace TaigaMCP.Config;

/// <summary>Options for connecting to Taiga.</summary>
public class TaigaOptions
{
    public static bool IsValidBaseUrl(string? value)
        => Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
           (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps) &&
           !string.IsNullOrEmpty(uri.Host) && string.IsNullOrEmpty(uri.UserInfo) &&
           string.IsNullOrEmpty(uri.Query) && string.IsNullOrEmpty(uri.Fragment);

    public int MetadataTtlSeconds { get; set; } = 300;
    public long MaxAttachmentBytes { get; set; } = 10 * 1024 * 1024;
    public string BaseUrl { get; set; } = "https://api.taiga.io/api/v1/";
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
}
