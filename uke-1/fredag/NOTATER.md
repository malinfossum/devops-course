# Fredag 25.09 — notater (handoff kl. 15:00)

Prosjekt: **Varde** (`malinfossum/varde`). Filene ble skrevet torsdag på `feat/containerise` og
merget i PR #24; fredagen går til å kjøre dem, bevise hardening og få runbooken peer-testet.
Kjørt i Codespacet 25.09.

Oppsett i Codespacet:

```bash
gh repo clone malinfossum/varde /workspaces/varde
cd /workspaces/varde
cp .env.example .env          # sett et ekte passord
git check-ignore -v .env && git status --short   # .env skal ikke stå i lista
```

## Steg 3: Dockerfile og `.dockerignore`

Ligger i `api/` (samme mappe som `Varde.slnx`, så byggekonteksten matcher diskstrukturen).
`compose.yml` i rota bygger med `context: ./api`.

```bash
podman build -t varde ./api
podman images varde
podman build -f api/Dockerfile.naiv -t varde-naiv ./api
podman images | grep varde
podman run --rm -p 8080:8080 --name vardetest varde   # klager på databasen — det er meningen
```

**Observert:** `varde` 103 MB · `varde-naiv` 534 MB (content size; på disk 368 MB mot 1,8 GB) ·
feilmelding uten db: `System.InvalidOperationException: ConnectionStrings:VardeDb is not configured.`
Varde stopper før den prøver å koble til — i motsetning til labApi har den ingen
`localhost`-standard i `appsettings.json`, så feilen sier *hva* som mangler, ikke *hvor* den lette.

Valg jeg tok, og hvorfor de avviker fra malen:

1. **Ingen `dotnet test` i bygget.** Testene i Varde oppretter ekte `varde_test_<guid>`-databaser
   i en Postgres (`VARDE_TEST_PG`); en byggecontainer har ingen. Kvalitetsporten hører derfor
   hjemme i CI i uke 2, med en service-container. Malen forutsetter labApis in-memory-tester.
2. **`global.json` kopieres før restore.** Den pinner SDK-en (`10.0.300`, `latestFeature`);
   uten den i imaget bygger SDK-imaget med en annen versjon enn jeg gjør lokalt.
3. **`--no-restore` på publish**, siden restore allerede er et eget, cachet lag.
4. **`!.env.example` i `.gitignore`.** Repoet ignorerte `.env.*`, som også traff malen —
   kontrakten må være i Git, så den har nå et unntak.

## Steg 4: Compose-stacken

```bash
podman compose up -d --build
podman compose ps
curl --fail http://localhost:8080/health
curl "http://localhost:8080/api/resources?query=helse"   # eller et annet ekte endepunkt
podman compose logs api
```

**Observert:** `/health` → 200 (`{"status":"ok","version":"dev",…}`), søk → 200 · begge healthy:
**nei** først. `db` ble healthy, men `api` gikk fra `health: starting` til `unhealthy` etter drøyt ett
minutt, selv om `curl /health` ga 200 hele tiden.

Årsaken: healthchecken brukte `wget --spider`, som sender **HEAD**. `/health` er registrert med
`MapGet`, så HEAD gir 405, og wget melder «Remote file does not exist -- broken link!!!». Bevis:
`curl -I /health` → 405, `curl /health` → 200. Fiks: vanlig GET (`--output-document=/dev/null`) —
samme felle som kursets egen `labApi/compose.yml` kommenterer. Etter fiksen: begge healthy på 45 s.

I samme logg: `libgssapi_krb5.so.2: cannot open shared object file`. Dockerfilen installerte
`libkrb5-3`, men fila Npgsql laster ligger i `libgssapi-krb5-2`. Byttet pakke, feilmeldingen borte.
Begge fiksene: Varde PR #28.

Connection stringen heter `ConnectionStrings__VardeDb`, ikke `__DefaultConnection` — Varde
leser `GetConnectionString("VardeDb")`. Dobbel underscore fordi `:` ikke er lovlig i et
miljøvariabelnavn.

**Felle å se etter:** i container er `ASPNETCORE_ENVIRONMENT` = Production, og da kjører
`app.UseHttpsRedirection()`. Uten en https-port konfigurert er den en no-op med en warning i
loggen — men ser jeg 307 på `/health`, er det der feilen ligger.

## Steg 5: Hardening

```bash
podman compose exec api id                                      # ikke uid 0
podman inspect varde-api --format '{{.HostConfig.Memory}}'      # 536870912
podman compose kill api && sleep 5 && podman compose ps         # restart: unless-stopped
podman inspect varde-api --format '{{.RestartCount}}'           # ventet på db, ikke restartet
```

**Observert:** id → `uid=1655(appuser)` · minne → 536870912 (512 MiB) · etter kill → `Exited (137)`,
**ikke** startet igjen · RestartCount → 0.

`compose kill` går gjennom Docker og teller som en manuell stopp, og da gjelder ikke
`unless-stopped`. En ekte krasj — `kill -9` på prosessen utenfra, forbi Docker — ga
`RestartCount=1` og containeren oppe igjen. Restart-policyen virker; testen må simulere en krasj,
ikke en stopp.

Bonus `read_only: true` + `tmpfs: /tmp` + `no-new-privileges` + `cap_drop: ALL`: prøvd med en
override-fil (`compose -f compose.yml -f harden.yml`). **Brekker ingenting:** `api` healthy,
`/health` og søk 200, ingen skrivefeil i loggen. Ikke lagt inn i `compose.yml` ennå.

## Steg 6: Runbook og peer-test

Runbooken står i `README.md` under «Runbook — the API in containers»: `cp .env.example .env`
→ `podman compose up -d --build` → `curl /health`, pluss `down` mot `down -v`.

Peer-test: ___ (hvem, og hva de måtte spørre om — hvert spørsmål er en linje som mangler)

## Handoff-sjekklisten

1. [x] Repo på GitHub — `malinfossum/varde` (PR #24)
2. [x] Multi-stage Dockerfile for eget prosjekt (non-root, alle csproj + `.slnx` før restore)
3. [x] `podman compose up -d` starter `api` + `db` stabilt — etter healthcheck-fiksen i PR #28
4. [x] `/health` → 200 på 8080
5. [x] `.env` utenfor Git, `.env.example` i Git
6. [ ] Runbook testet av en annen
