using System.Globalization;

namespace TaigaMCP.Api;

internal readonly record struct TaigaPageInfo(int? Total, int? NextPage, bool? HasMore);

internal static class TaigaPagination
{
    public static TaigaPageInfo Parse(
        IReadOnlyDictionary<string, string[]> headers,
        Uri requestUri)
    {
        var nextHeader = TryGetHeader(headers, "x-pagination-next", out var nextValue);
        var nextPage = nextHeader ? ParseNextPage(nextValue, requestUri) : null;
        var hasMore = nextHeader && nextPage is null
            ? null
            : nextPage.HasValue
                ? true
                : ParseHasMore(headers, hasContinuationHeader: nextHeader);
        return new TaigaPageInfo(
            ParseNonnegativeHeader(headers, "x-pagination-count"),
            nextPage,
            hasMore);
    }

    private static bool TryGetHeader(
        IReadOnlyDictionary<string, string[]> headers,
        string name,
        out string value)
    {
        if (headers.TryGetValue(name, out var values) && values.FirstOrDefault() is { } first)
        {
            value = first;
            return true;
        }

        value = string.Empty;
        return false;
    }

    private static int? ParseNonnegativeHeader(
        IReadOnlyDictionary<string, string[]> headers,
        string name)
        => TryGetHeader(headers, name, out var value) &&
           int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var number) &&
           number >= 0
            ? number
            : null;

    private static bool? ParseHasMore(
        IReadOnlyDictionary<string, string[]> headers,
        bool hasContinuationHeader)
    {
        if (hasContinuationHeader) return null;
        return TryGetHeader(headers, "x-paginated", out var value) &&
               bool.TryParse(value, out var paginated) &&
               !paginated
            ? false
            : null;
    }

    internal static bool TryParseNextPage(string value, Uri requestUri, out int? page)
    {
        value = value.Trim();
        if (value.Length == 0 || value.StartsWith('#'))
        {
            page = null;
            return false;
        }
        if (int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var directPage))
        {
            page = directPage > 0 ? directPage : null;
            return page.HasValue;
        }
        if (!Uri.TryCreate(value, UriKind.RelativeOrAbsolute, out var candidate))
        {
            page = null;
            return false;
        }

        Uri resolved;
        if (candidate.IsAbsoluteUri)
        {
            if (!string.Equals(candidate.Scheme, requestUri.Scheme, StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(candidate.Authority, requestUri.Authority, StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(candidate.AbsolutePath, requestUri.AbsolutePath, StringComparison.OrdinalIgnoreCase))
            {
                page = null;
                return false;
            }
            resolved = candidate;
        }
        else
        {
            resolved = new Uri(requestUri, candidate);
        }

        if (!string.Equals(resolved.Scheme, requestUri.Scheme, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(resolved.Authority, requestUri.Authority, StringComparison.OrdinalIgnoreCase) ||
            !string.Equals(resolved.AbsolutePath, requestUri.AbsolutePath, StringComparison.OrdinalIgnoreCase))
        {
            page = null;
            return false;
        }

        foreach (var part in resolved.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var pieces = part.Split('=', 2);
            if (!string.Equals(Uri.UnescapeDataString(pieces[0]), "page", StringComparison.OrdinalIgnoreCase) ||
                pieces.Length != 2)
                continue;
            var pageValue = Uri.UnescapeDataString(pieces[1]);
            if (int.TryParse(pageValue, NumberStyles.Integer, CultureInfo.InvariantCulture, out var parsedPage) && parsedPage > 0)
            {
                page = parsedPage;
                return true;
            }

            page = null;
            return false;
        }

        page = null;
        return false;
    }

    private static int? ParseNextPage(string value, Uri requestUri)
        => TryParseNextPage(value, requestUri, out var page) ? page : null;
}
