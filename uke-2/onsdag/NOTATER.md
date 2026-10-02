# Uke 2 onsdag (økt 30.09): deploy lokalt og rollback, notater

Samme prosjekt som hele uka: **Varde** (`malinfossum/varde`). Alt kjørte i Codespacet (Docker, `podman` er alias).
Endringene gikk via PR #35, fordi `main` er beskyttet og det bare er `main` som lager nye images.

## Oppgave 0: det som må på plass før deploy

### 0a. `/health` melder versjon

Den var allerede på plass fra uke 1: endpointet i `Program.cs` leser `config["APP_VERSION"] ?? "dev"`, og
`compose.yml` setter `APP_VERSION: dev`. Dev-stacken svarte:

```
{"status":"ok","version":"dev","time":"2026-09-30T16:21:22.0138865+00:00"}
```

**Men bygget feilet først** i Codespacet, mens CI bygde samme Dockerfile grønt:

```
error NETSDK1064: Package Microsoft.AspNetCore.OpenApi, version 10.0.10 was not found.
```

Årsak: Codespace-klonen hadde gamle `obj/`-mapper fra en `dotnet build` 25.09. `.dockerignore` sa `obj/`,
men et mønster uten `**/` treffer bare i rota av build-konteksten. `Varde.Api/obj` ble derfor med i
`COPY . .` og overskrev restore-laget. CI så det aldri, fordi en fersk checkout ikke har `obj/`.
Fiks: `**/bin/` og `**/obj/` (commit `37a588b`).

### 0b. `compose.prod.yml`

Kopiert fra labApi og gjort til min: `name: varde-prod`, `varde-api-prod`, `varde-db-prod`, volumet
`varde_prod_data`, `image: ${API_IMAGE}:${IMAGE_TAG:-latest}`. Én ting måtte endres utover tabellen:
connection stringen heter `ConnectionStrings__VardeDb` hos meg, ikke `__DefaultConnection`.
Kommentarblokka om `MIGRATE_ON_STARTUP` er med.

`.env` og `.env.example` fikk:

```env
API_IMAGE=ghcr.io/malinfossum/varde
IMAGE_TAG=latest
```

`podman compose -f compose.prod.yml config` kjørte rent og viste meg, ikke `REPLACE-ME`:

```
image: ghcr.io/malinfossum/varde:latest
APP_VERSION: latest
```

- [x] `/health` svarer med `version` (`dev` i dev)
- [x] Grønn pipeline (siste `main`, `a581a64`)
- [x] `compose.prod.yml` uten `build:`, med `image:`
- [x] `config` kjører rent

## Oppgave 1: første deploy, med bevis

Taggen fra tirsdag: **`sha-a581a64`**. Dev-stacken ned, `IMAGE_TAG=sha-a581a64` i `.env`, så `pull` og `up -d`.
Fra `pull` til begge containerne var healthy: **19 s** (tomt prod-volum, så migrering og seed var med).

```
varde-api-prod Up 6 seconds (healthy)
varde-db-prod Up 17 seconds (healthy)
{"status":"ok","version":"sha-a581a64","time":"2026-09-30T16:21:41.7507645+00:00"}
```

**Beviset, 18:21:41:**

```
ghcr.io/malinfossum/varde:sha-a581a64
```

`/api/categories` svarte 200, så data kom fra databasen også.

**Hva helseporten beviser om databasen:** Varde migrerer før `app.Run()`, så en API som svarer på `/health`
har kommet seg forbi migreringen, og databasen svarte da appen startet. Den beviser *ikke* at databasen
svarer nå: `/health` rører ikke databasen. Derfor sjekket jeg et endpoint som leser data i tillegg.

### Funn: en sha-tag er ikke låst

På tirsdag hadde imaget ID `19adcf518c4e`. I dag viste containeren `13b54d70d348`, med samme tag.
Pipeline-loggen forklarer det: jeg kjørte tirsdagens `main`-kjøring på nytt for å teste cachen, og forsøk 2
pushet `sha-a581a64` på nytt med en ny digest.

```
forsøk 1: "containerimage.digest": "sha256:19adcf518c4e
forsøk 2: "containerimage.digest": "sha256:13b54d70d348
```

Taggen navngir commiten, ikke bytene. Samme kode, men et nytt bygg er et nytt image. Det eneste som ikke
kan flytte seg er digesten (`ghcr.io/malinfossum/varde@sha256:...`).

**Fikset i samme PR:** docker-jobben sjekker nå registryet først og hopper over push hvis commiten allerede
har et image. Testet ved å kjøre image-jobben for `b8e13da` på nytt: «Build and push» ble `skipped`, loggen
sa `sha-b8e13da already exists, nothing is pushed`, og digesten sto fast på `ae03c96f84c4`.
Runbooken ber nå også om digesten i beviset: `inspect --format '{{.Config.Image}} {{.Image}}'`.

## Oppgave 2: ny versjon og rollback

### 2a. Ny versjon

Endringen: API-et logger én linje med versjonen når det starter. Den rører ikke `/health`, og kan sees i
`logs api`. PR #35 merget som `b8e13da`, alle porter grønne, image-jobben pushet **`sha-b8e13da`**
(digest `ae03c96f84c4`). `IMAGE_TAG=sha-b8e13da`, så `pull` og `up -d`:

```
{"status":"ok","version":"sha-b8e13da","time":"2026-09-30T16:35:18.1654983+00:00"}
18:35:18  ghcr.io/malinfossum/varde:sha-b8e13da sha256:ae03c96f84c4...
varde-api-prod  |       Varde API starting, version sha-b8e13da
```

Helseporten, `inspect` og loggen sier det samme: verden har endret seg.

### 2b. Rollback med tidtaker

`IMAGE_TAG=sha-a581a64`, `pull`, `up -d`. Tidtakeren startet før jeg endret `.env` og stoppet da `/health`
svarte med gammel sha. Første runde målte ingenting (Codespacet har ikke `bc`), så jeg tok en runde til
med millisekunder i bash:

```
sha-a581a64: /health answers after 5266 ms (pull 1186 ms) at 16:36:14 UTC
ghcr.io/malinfossum/varde:sha-a581a64 sha256:13b54d70d348...
```

**Rollback: 5,3 s**, der `pull` var 1,2 s fordi imaget lå lokalt. Containerens egen healthcheck ble
`healthy` først litt senere, fordi den bare sjekker hvert 30. sekund. Etter rollback kom ingen
«starting, version»-linje i loggen: den gamle koden kjører.

**Overlevde databasen?** Ja. 9 kategorier før og etter, og volumet har samme `CreatedAt` (16:21:24Z) hele
veien. Dataene bor i volumet, ikke i containeren. Containeren kan kastes og byttes, og det er derfor
rollback går i det hele tatt: vi bytter kode, ikke data. Det holdt her fordi begge versjonene har samme
migrasjoner. Hadde den nye versjonen endret skjemaet, ville den gamle koden møtt et nyere skjema.

**Uten den gamle taggen?** Jeg måtte ha lett i Actions-historikken eller pakkeversjonene, og gjettet på
hvilken som var den forrige. Og funnet over viser at taggen alene ikke var nok før fiksen: noter digesten også.

## Knight-spørsmålet

Jeg kan peke på `varde-api-prod` og si hvilken commit den kjører (`/health`), hvilket image (`inspect`)
og hvilke bytes (digesten). Tilbake tok 5 sekunder fordi jeg hadde skrevet ned hvor tilbake var.
Funnet i dag var at en tag som ser låst ut, kan flytte seg. Da hadde «hva kjører nå?» fått feil svar,
selv med alle kommandoene riktige.

## Huskelista

- [x] `compose.prod.yml` i repoet, `config`-kjørt ren
- [x] `/health` melder den taggen jeg deployet (`sha-a581a64`, så `sha-b8e13da`, så tilbake)
- [x] Begge taggene notert med klokkeslett: `sha-a581a64` 18:21:41, `sha-b8e13da` 18:35:18, rollback 18:36:14
- [x] Runbook med deploy og rollback i Varde sin README (ikke testet av en annen; peer-testen er droppet)
