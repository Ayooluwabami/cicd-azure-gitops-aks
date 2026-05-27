# ── Stage 1: build ────────────────────────────────────────────────────────────
# --platform=$BUILDPLATFORM runs the SDK on the native build agent (amd64).
# This avoids QEMU-emulated arm64 execution which triggers a NullReferenceException
# in the CheckForDuplicateItems MSBuild task (SDK 8.0.421 + QEMU bug).
# The published output is framework-dependent IL (architecture-neutral) and
# runs on any platform via the aspnet runtime image below.
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY dotnet-app.csproj .
RUN dotnet restore

COPY Program.cs .
RUN dotnet publish -c Release -o /app/publish --no-restore

# ── Stage 2: hardened runtime ─────────────────────────────────────────────────
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime

# Create a dedicated non-root user.
# Reason: ASP.NET base image runs as root by default. A compromised
# ASP.NET process running as root can write anywhere on the container
# filesystem and is one container-escape away from node compromise.
RUN groupadd --gid 1001 appgroup \
    && useradd --uid 1001 --gid appgroup --no-create-home --shell /sbin/nologin appuser

WORKDIR /app

COPY --from=build --chown=appuser:appgroup /app/publish .

# Disable dotnet telemetry sent to Microsoft.
# Reason: reduces unexpected outbound network calls from the container.
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    DOTNET_RUNNING_IN_CONTAINER=true \
    ASPNETCORE_URLS=http://+:8080

USER appuser

EXPOSE 8080

ENTRYPOINT ["dotnet", "dotnet-app.dll"]
