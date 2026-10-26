using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using TaigaMCP.Hosting;
using TaigaMCP.Config;
using Microsoft.Extensions.Hosting;

var builder = Host.CreateApplicationBuilder(args);
var mcpOptions = new McpOptions();
builder.Configuration.GetSection(McpOptions.SectionName).Bind(mcpOptions);
mcpOptions.Normalize();

if (mcpOptions.IsHttp)
{
    var webBuilder = WebApplication.CreateBuilder(args);
    webBuilder.WebHost.UseUrls(mcpOptions.ListenerUrl);
    webBuilder.Services.AddTaigaServices(webBuilder.Configuration);
    webBuilder.Services.AddTaigaMcpServer().WithHttpTransport();

    var app = webBuilder.Build();
    app.MapMcp(mcpOptions.Path);
    await app.RunAsync();
}
else
{
    builder.Services.AddTaigaServices(builder.Configuration);
    builder.Services.AddTaigaMcpServer().WithStdioServerTransport();
    await builder.Build().RunAsync();
}
