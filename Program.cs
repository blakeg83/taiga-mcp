using Microsoft.Extensions.Hosting;

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddTaigaServices(builder.Configuration);

await builder.Build().RunAsync();