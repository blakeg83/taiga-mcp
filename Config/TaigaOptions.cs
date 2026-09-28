namespace TaigaMCP.Config;

/// <summary>Options for connecting to Taiga.</summary>
public class TaigaOptions
{
    public int MetadataTtlSeconds { get; set; } = 300;
    public string BaseUrl { get; set; } = "https://api.taiga.io/api/v1/";
    public string Username { get; set; } = "";
    public string Password { get; set; } = "";
}
