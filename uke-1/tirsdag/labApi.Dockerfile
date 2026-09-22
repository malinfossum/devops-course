# My own multi-stage Dockerfile for labApi (task 3), written before reading the fasit.
# Copy it into the labApi folder as Dockerfile after renaming the original to Dockerfile.fasit.

# Stage 1: build with the SDK
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Project file first so restore is cached until a package changes
COPY LabApi.csproj ./
RUN dotnet restore

# Source last, then publish only the API project
COPY . .
RUN dotnet publish LabApi.csproj -c Release -o /app/publish --no-restore

# Stage 2: runtime only, with nothing but the publish output
FROM mcr.microsoft.com/dotnet/aspnet:10.0
WORKDIR /app
COPY --from=build /app/publish .

# Do not run as root
RUN useradd -m appuser
USER appuser

# Listen on all interfaces inside the container so -p 8080:8080 reaches it
ENV ASPNETCORE_URLS=http://0.0.0.0:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "LabApi.dll"]
