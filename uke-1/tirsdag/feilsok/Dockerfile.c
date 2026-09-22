# Task 4C: no explicit restore before publish
# Stage 1: SDK bygger og tester
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY . .
RUN dotnet publish LabApi.csproj -c Release -o /app/publish

# Stage 2: kun runtime og publish-output
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

RUN apt-get update && apt-get install -y libkrb5-3 wget && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/publish .

RUN useradd -m appuser
USER appuser

ENV ASPNETCORE_URLS=http://0.0.0.0:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "LabApi.dll"]
