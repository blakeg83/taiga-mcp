using Microsoft.Extensions.Options;
using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

public sealed class AuthClient
{
    private readonly TaigaOptions _cfg;
    private string? _token;
    private string? _refresh;

    public AuthClient(IOptions<TaigaOptions> opts) => _cfg = opts.Value;

    public async Task EnsureAuthAsync(HttpClient http)
    {
        if (!string.IsNullOrEmpty(_token))
        {
            http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _token);
            return;
        }

        var body = JsonSerializer.Serialize(new { type = "normal", username = _cfg.Username, password = _cfg.Password });
        using var res = await http.PostAsync("auth", new StringContent(body, Encoding.UTF8, "application/json"));
        res.EnsureSuccessStatusCode();

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        _token = doc.RootElement.GetProperty("auth_token").GetString()
                 ?? throw new InvalidOperationException("Taiga auth_token missing");
        _refresh = doc.RootElement.TryGetProperty("refresh", out var r) ? r.GetString() : null;

        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", _token);
    }

    public async Task<HttpResponseMessage> SendAsync(HttpClient http, HttpRequestMessage req)
    {
        await EnsureAuthAsync(http);

        req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
        var res = await http.SendAsync(req);
        if (res.StatusCode != HttpStatusCode.Unauthorized) return res;

        // token expired -> try refresh then one retry
        res.Dispose();
        if (await TryRefreshAsync(http))
        {
            var retry = await CloneAsync(req);
            retry.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
            return await http.SendAsync(retry);
        }

        // fallback: full re-login then retry
        _token = null;
        await EnsureAuthAsync(http);
        var retry2 = await CloneAsync(req);
        retry2.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _token);
        return await http.SendAsync(retry2);
    }

    private async Task<bool> TryRefreshAsync(HttpClient http)
    {
        if (string.IsNullOrEmpty(_refresh)) return false;

        var payload = JsonSerializer.Serialize(new { refresh = _refresh });
        using var res = await http.PostAsync("auth/refresh", new StringContent(payload, Encoding.UTF8, "application/json"));
        if (!res.IsSuccessStatusCode) return false;

        using var doc = JsonDocument.Parse(await res.Content.ReadAsStringAsync());
        _token = doc.RootElement.GetProperty("auth_token").GetString();
        if (doc.RootElement.TryGetProperty("refresh", out var r)) _refresh = r.GetString();
        return !string.IsNullOrEmpty(_token);
    }

    private static async Task<HttpRequestMessage> CloneAsync(HttpRequestMessage req)
    {
        var clone = new HttpRequestMessage(req.Method, req.RequestUri);
        foreach (var h in req.Headers) clone.Headers.TryAddWithoutValidation(h.Key, h.Value);
        if (req.Content is not null)
        {
            var bytes = await req.Content.ReadAsByteArrayAsync();
            clone.Content = new ByteArrayContent(bytes);
            foreach (var h in req.Content.Headers) clone.Content.Headers.TryAddWithoutValidation(h.Key, h.Value);
        }
        return clone;
    }
}
