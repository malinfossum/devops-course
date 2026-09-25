# Tirsdag 22.09 — notater

Kjørt i Codespacet (`podman` = alias for `docker`). Filene ligger i `uke-1/tirsdag/`:
`HelloContainer/` (oppgave 0–2), `labApi.Dockerfile` (min versjon, oppgave 3) og
`feilsok/Dockerfile.{a,b,c}` (oppgave 4). Tall merket `___` fylles inn fra terminalen.

## Oppsett

```bash
cd /workspaces/devops-course && git pull
rm -rf /workspaces/HelloContainer          # den jeg lagde med dotnet new — bruker repo-versjonen
cd uke-1/tirsdag/HelloContainer
```

labApi ligger i kursrepoet (privat). Codespace-tokenet når bare mitt eget repo, så jeg logger inn
med min egen bruker i denne terminalen og kloner:

```bash
unset GITHUB_TOKEN && gh auth login -h github.com -p https -w -s repo
gh repo clone GetAcademy/devops_mini_2026.3 /workspaces/course
```

## Oppgave 0: Første Dockerfile (HelloContainer)

```bash
podman build -t hello .
podman run --rm hello
podman run --rm hello
```

**Observert (kjørt 24.09):** `Hello from a container! Klokken er 09/24/2026 09:26:38`, så `… 09:26:39`.
Samme tekst, ett sekund mellom. Datoen står i amerikansk format: containeren har ingen norsk
kultur-innstilling, så .NET faller tilbake på invariant kultur.

**Refleksjon:** Klokken er ulik fordi programmet kjører på nytt hver gang; alt annet er likt fordi
imaget er en frossen, skrivebeskyttet mal — hver `run` lager en ny container fra nøyaktig de samme
lagene, så bare det som skjer i kjøretid kan variere.

Valg jeg tok: stage 2 bruker `runtime:10.0`, ikke `aspnet:10.0`, fordi dette er en console-app uten
web-stack. `--no-restore` på publish fordi restore allerede er gjort i sitt eget (cachede) lag.

## Oppgave 1: Naiv vs multi-stage

```bash
podman build -f Dockerfile.naiv -t hello-naiv .
podman build -t hello .
podman images hello
podman images hello-naiv
```

**Observert:**

| Image | Content size | Disk usage |
|---|---|---|
| `hello` | 83.2 MB | 300 MB |
| `hello-naiv` | 351 MB | 1.3 GB |

`docker images` viser to tall: *content size* er de komprimerte lagene (det som lastes ned og
pushes), *disk usage* er utpakket på disk. Det naive imaget er drøyt fire ganger så stort på begge.

**Refleksjon:** Det naive imaget har med (1) hele SDK-en — compiler, MSBuild, NuGet-klient — som
bare trengs for å bygge, (2) kildekoden (`Program.cs`, `.csproj`), (3) `obj/`-mellomprodukter og
NuGet-pakkecachen fra restore. Multi-stage-imaget har bare runtime + `publish/`-mappen.

## Oppgave 2: Layer caching

```bash
sed -i 's/Hello from a container!/Hei fra en container!/' Program.cs
podman build -t hello .                    # 2.1–2.2
dotnet add package Humanizer
podman build -t hello .                    # 2.3
sed -i 's/^# RUN echo "kode endret"/RUN echo "kode endret"/' Dockerfile
podman build -t hello .                    # 2.4, første gang
podman build -t hello .                    # 2.4, andre gang
```

**Observert:**

- 2.2: `CACHED` på WORKDIR, COPY csproj og RUN restore (FROM-linjene hentes fra de lokale imagene); bygget på nytt: COPY . ., publish og `COPY --from` i stage 2.
- 2.3: etter Humanizer bygges COPY csproj, restore, COPY . ., publish og `COPY --from` på nytt — alt fra COPY csproj og nedover, fordi `.csproj` endret seg. Bare WORKDIR var cachet.
- 2.4: første bygg — lagene over `echo` cachet, `echo` og alt under bygget på nytt. Andre bygg — alt cachet, også `echo`.

**Refleksjon, regelen i én setning:** Et lag gjenbrukes bare når instruksjonen og alle lagene over
den er uendret; endrer jeg noe, bygges det laget og alt under det på nytt. Derfor: det som sjelden
endres (csproj + restore) øverst, koden nederst.

## Oppgave 3: Containeriser labApi

```bash
cd /workspaces/course/labApi
mv Dockerfile Dockerfile.fasit
cp /workspaces/devops-course/uke-1/tirsdag/labApi.Dockerfile Dockerfile
cat .dockerignore
podman build -t labapi .
podman run -p 8080:8080 --name labtest labapi     # Ctrl+C når feilen har kommet
podman logs labtest
podman build -f Dockerfile.fasit -t labapi:fasit .
podman images labapi                               # ← skjermdump: oppgave-3.png
```

**3.3 `.dockerignore`:** finnes. Den dekker `bin/ obj/ publish/ logs/ .git/ .env .env.* *.env`,
IDE-mapper, `Dockerfile`, `compose*.yml` og `*.md`. Det jeg savnet: `tests/` — testene trengs ikke
i publish-imaget mitt, men fasiten kjører dem i bygget, så de må med der. Ellers komplett.

**3.4 Hva API-et klager over:** `Npgsql.NpgsqlException (0x80004005): Failed to connect to 127.0.0.1:5432`,
med `SocketException (111): Connection refused` under. Appen kjører `MigrateAsync()` ved oppstart, og `appsettings.json` peker på
`Host=localhost` — inne i containeren finnes ingen Postgres på localhost. Løses onsdag med Compose:
egen `db`-container og `ConnectionStrings__DefaultConnection` med `Host=db` som miljøvariabel.

**3.5 Min versjon mot fasiten:**

1. Fasiten kopierer `LabApi.slnx` og test-csproj før restore, og kjører `dotnet test` i bygget.
   Min har bare `LabApi.csproj` og hopper over testene.
2. Fasiten installerer `libkrb5-3` (Npgsql vil ha Kerberos-biblioteket) og `wget` (compose-healthchecken
   bruker den) i runtime-stage. Min gjør ikke det — ville feilet på healthcheck onsdag.
3. Fasiten navngir stage 2 (`AS runtime`) og lar publish restore implisitt; min bruker `--no-restore`.
   Ellers likt: sdk→aspnet, csproj først, non-root, 0.0.0.0:8080, `LabApi.dll`.

Hvorfor testene kjører inne i bygget: rød test = rødt bygg = ikke noe image. Det er kvalitetsporten
til CI-en finnes i uke 2 — et image som ikke består testene kan aldri deployes, uansett hvem som bygger.
Løsningsfilen må med før restore, ellers får testprosjektet ingen `project.assets.json` og
`dotnet test --no-restore` feiler (NETSDK1004).

**3.6 Størrelse:** min 99 MB · fasit 103 MB (content size; på disk 352 MB mot 368 MB). Fasiten er litt
større: krb5 + wget + apt-lag.

```bash
podman rm -f labtest
podman rmi labapi
mv Dockerfile.fasit Dockerfile
```

## Oppgave 4: Bryt ting med hensikt

```bash
cd /workspaces/course/labApi
F=/workspaces/devops-course/uke-1/tirsdag/feilsok
podman build -f $F/Dockerfile.a -t feil-a . && podman run --rm feil-a
podman run --rm --entrypoint ls feil-a -la /app
podman build -f $F/Dockerfile.b -t feil-b .
podman build -f $F/Dockerfile.c -t feil-c . && podman run --rm feil-c   # Ctrl+C
podman rmi feil-a feil-c
```

**A. Feil DLL-navn:** bygget går fint — feilen kommer først ved `run`: `The application 'Api.dll' does
not exist or is not a managed .dll or .exe.` `ls /app` viser `LabApi.dll`. Riktig navn uten å gjette: `--entrypoint ls` lister
`/app` i imaget. `--entrypoint` må til, ellers blir `ls -la /app` argumenter til `dotnet LabApi.dll`.

**B. COPY-feil:** bygget stopper i stage 2: `failed to calculate checksum of ref …: "/src/app/publish": not found`.
Stage 1 publiserer til `/app/publish` (`-o /app/publish`), ikke under `/src`. Svaret står i Dockerfilen.

**C. Uten restore:** fungerer — `dotnet publish` kjører implisitt restore. Vi eksplisiterer likevel:
med restore som eget lag rett etter `COPY *.csproj` er det cachet ved kodeendringer; den implisitte
restoren ligger etter `COPY . .` og kjører på nytt for hvert eneste tastetrykk.

## Knight-spørsmålet

I går: samme image overalt. I dag: hvordan det imaget lages — av en fil i Git som bygger identisk
hver gang, ikke av en tekniker som kopierer filer til sju av åtte servere.

## Til onsdag

labApi starter ikke uten Postgres. Hvem starter hvem: Compose starter `db` først, `api` venter på
`depends_on: condition: service_healthy`. API-et finner databasen på tjenestenavnet `db` i
compose-nettverket (DNS). Trenger databasen 5 sekunder: healthcheck (`pg_isready`) holder API-et
tilbake til den svarer — «startet» og «klar» er ikke det samme.
