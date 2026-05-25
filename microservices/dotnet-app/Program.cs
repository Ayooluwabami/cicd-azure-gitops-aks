var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "1.0.0";

app.MapGet("/", () => Results.Json(new
{
    service = "dotnet-app",
    status = "running",
    version
}));

app.MapGet("/health", () => Results.Json(new { status = "healthy" }));

app.MapGet("/api/data", () => Results.Json(new
{
    service = "dotnet-app",
    message = "Hello from the .NET microservice!",
    version
}));

app.Run();
