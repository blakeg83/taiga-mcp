namespace TaigaMCP.Config;

/// <summary>Configuration for selecting the MCP server transport.</summary>
public sealed class McpOptions
{
    public const string SectionName = "Mcp";
    public const string StdioTransport = "stdio";
    public const string HttpTransport = "http";

    public string Transport { get; set; } = StdioTransport;
    public string Address { get; set; } = "127.0.0.1";
    public int Port { get; set; } = 3001;
    public string Path { get; set; } = "/mcp";

    public bool IsHttp => string.Equals(Transport, HttpTransport, StringComparison.OrdinalIgnoreCase);

    public string ListenerUrl => $"http://{FormatAddress(Address)}:{Port}";

    public static bool IsSupportedTransport(string? value)
        => string.Equals(value?.Trim(), StdioTransport, StringComparison.OrdinalIgnoreCase) ||
           string.Equals(value?.Trim(), HttpTransport, StringComparison.OrdinalIgnoreCase);

    public static bool IsValidAddress(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return false;

        var address = value.Trim();
        if (address is "*" or "+") return true;
        if (address.Contains('/') ||
            address.Contains('?') ||
            address.Contains('#') ||
            address.Contains('@') ||
            address.Contains("://", StringComparison.Ordinal))
        {
            return false;
        }

        if (address.StartsWith("[", StringComparison.Ordinal) || address.EndsWith("]", StringComparison.Ordinal))
        {
            return address.Length > 2 &&
                address[0] == '[' &&
                address[^1] == ']' &&
                Uri.CheckHostName(address[1..^1]) == UriHostNameType.IPv6;
        }

        return Uri.CheckHostName(address) is UriHostNameType.Dns or UriHostNameType.IPv4 or UriHostNameType.IPv6;
    }

    public static bool IsValidPort(int value) => value is >= 1 and <= 65_535;

    public static bool IsValidPath(string? value)
        => !string.IsNullOrWhiteSpace(value) &&
           value.StartsWith("/", StringComparison.Ordinal) &&
           !value.Contains('?') &&
           !value.Contains('#') &&
           !value.Any(char.IsWhiteSpace);

    public void Normalize()
    {
        Transport = (Transport ?? string.Empty).Trim().ToLowerInvariant();
        Address = (Address ?? string.Empty).Trim();
        Path = (Path ?? string.Empty).Trim();
    }

    private static string FormatAddress(string address)
        => address.Contains(':') && !address.StartsWith("[", StringComparison.Ordinal)
            ? $"[{address}]"
            : address;
}
