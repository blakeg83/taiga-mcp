using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

/// <summary>Handles Taiga authentication and token reuse.</summary>
public sealed class AuthClient
{
    private readonly TaigaConfig _cfg;
    private string? _token;

    public AuthClient(TaigaConfig cfg)
    {
        _cfg = cfg;
    }

    public async Task EnsureAuthAsync(HttpClient http)
    {
        if (!string.IsNullOrEmpty(_token))
        {
            http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _token);
            return;
        }

        var body = JsonSerializer.Serialize(new { type = "normal", username = _cfg.Username, password = _cfg.Password });
        var res = await http.PostAsync("auth", new StringContent(body, Encoding.UTF8, "application/json"));
        res.EnsureSuccessStatusCode();
        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        _token = doc.RootElement.GetProperty("auth_token").GetString()
                 ?? throw new InvalidOperationException("Taiga auth_token missing");
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _token);
    }
}
