# Torsdag 24.09 — notater

Eget prosjekt for containeriseringen: **Varde** (`malinfossum/varde`), den tospråklige
tjenestekatalogen. Arbeidet ble gjort på branchen `feat/containerise` og er merget til `main` (PR #24).

## Steg 0: Kartlegging

| Spørsmål | Svar |
|---|---|
| Hva heter løsningen? | `Varde.slnx`, i `api/` i repoet (web-frontenden ligger i `web/`) |
| Hvilke `.csproj`? | `Varde.Api`, `Varde.Core`, `Varde.Data`, `Varde.Tests` — alle rett under `api/` |
| Hvilket er API-et? | `Varde.Api` (`Program.cs`, `launchSettings.json`) |
| DLL-navn? | `Varde.Api.dll` |
| Database i dag? | **PostgreSQL allerede** (`UseNpgsql`, Neon i prod) → steg 1 hoppes over, jf. oppgaveteksten |
| Port i dag? | 5005 lokalt (`launchSettings`); containeren lytter på 8080 via `ASPNETCORE_URLS` |
| Løsningsfil? | Ja, `.slnx` — må kopieres før `dotnet restore` |

Hvorfor Varde og ikke Hugin: Hugin er også onion (`Core`/`Infrastructure`/tynne verter), men
SQLite er vevd inn i den — WAL, busy-timeout, `.bak`-kopi før migrering, public modes
arbeidskopi, og CLI og API deler samme fil. Å bytte den til Postgres er en refaktorering på
flere timer, ikke en torsdagsøkt. Varde har allerede Postgres, ekte lagdeling og ingen
container fra før, så det er de faktiske DevOps-stegene som gjenstår.

## Steg 1: Bytt til PostgreSQL

Hoppet over — prosjektet bruker `Npgsql.EntityFrameworkCore.PostgreSQL` fra før, og
`Migrations/` er allerede Postgres-migrasjoner.

## Steg 2: `/health` og migrering ved oppstart

Begge deler i `api/Varde.Api/Program.cs`:

```csharp
app.MapGet("/health", (IConfiguration config) => Results.Ok(new
{
    status = "ok",
    version = config["APP_VERSION"] ?? "dev",
    time = DateTimeOffset.UtcNow
}));
```

Migreringen fantes fra før (`Database.Migrate()` ved oppstart), men kjørte alltid. Nå er den
bak `MIGRATE_ON_STARTUP`, slik at prod kan skru den av — flere replikaer som migrerer samtidig
ville kollidert.

**Verifisert:** `dotnet build Varde.Api/Varde.Api.csproj` → Build succeeded, 0 warnings, 0 errors.

**Bevis mot tom database (kjøres i Codespacet):**

```bash
cd /workspaces/varde          # gh repo clone malinfossum/varde (main)
podman run -d --name devdb -e POSTGRES_DB=devdb -e POSTGRES_USER=devuser \
  -e POSTGRES_PASSWORD=devpass -p 5432:5432 docker.io/library/postgres:16
cd api && ConnectionStrings__VardeDb="Host=localhost;Port=5432;Database=devdb;Username=devuser;Password=devpass" \
  dotnet run --project Varde.Api
# nytt terminalvindu:
curl --fail http://localhost:5005/health
podman exec -it devdb psql -U devuser -d devdb -c '\dt'
podman rm -f devdb
```

**Observert:** `/health` → 200 · tabeller uten `database update`: 0 før oppstart, 8 etter —
`Categories`, `CategoryTranslations`, `Municipalities`, `ResourceCategories`,
`ResourceMunicipalities`, `ResourceTranslations`, `Resources` og `__EFMigrationsHistory`.

## Dagens leveranse

- [x] Postgres i bruk (var der fra før)
- [x] `Migrations/` er Postgres-migrasjoner
- [x] `/health` finnes
- [x] Migrering ved oppstart, styrt av `MIGRATE_ON_STARTUP`
- [x] Committet: `2f2188c` på `feat/containerise`
