using ModelContextProtocol;
using TaigaMCP.Api;

namespace TaigaMCP.Tools;

internal static class ToolErrors
{
    public static async Task<string> RunAsync(Func<Task<string>> action)
    {
        try { return await action(); }
        catch (ArgumentException ex) { throw new McpException(ex.Message); }
        catch (TaigaRequestException ex) { throw new McpException(ex.Message); }
    }
}
