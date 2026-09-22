# Stage 1: build with the SDK (compiler, MSBuild, NuGet)
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Project file first: the restore layer stays cached until dependencies change
COPY HelloContainer.csproj ./
RUN dotnet restore

# Task 2.4: uncomment, build twice, and watch which steps say CACHED
# RUN echo "kode endret"

# Source last: a code change only rebuilds from here down
COPY . .
RUN dotnet publish -c Release -o /app/publish --no-restore

# Stage 2: runtime only. Console app, so runtime:10.0 (aspnet:10.0 is for web apps)
FROM mcr.microsoft.com/dotnet/runtime:10.0
WORKDIR /app
COPY --from=build /app/publish .
ENTRYPOINT ["dotnet", "HelloContainer.dll"]
