using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;

var builder = Host.CreateApplicationBuilder(args);
builder.Configuration.AddEnvironmentVariables("TAIGA_");
builder.Services.AddTaigaServices(builder.Configuration);

await builder.Build().RunAsync();
