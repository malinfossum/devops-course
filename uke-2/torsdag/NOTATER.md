# Uke 2 torsdag (økt 01.10): rollback og feilsøking, notater

Samme prosjekt som hele uka: **Varde** (`malinfossum/varde`). Alt kjørte i Codespacet (Docker, `podman` er alias).
Jeg kjørte kommandoene selv i terminalen. Poenget i dag var å se feilene med egne øyne.

## Startsjekk

`.env` sto fortsatt på `sha-a581a64` etter gårsdagens rollback. Jeg satte `IMAGE_TAG=sha-b8e13da` (siste
grønne `main`), så `pull` og `up -d`.

```
varde-api-prod  ghcr.io/malinfossum/varde:sha-b8e13da  Up 6 seconds (healthy)   0.0.0.0:8080->8080/tcp
varde-db-prod   docker.io/library/postgres:16          Up 4 minutes (healthy)   5432/tcp
image: ghcr.io/malinfossum/varde:sha-b8e13da
{"status":"ok","version":"sha-b8e13da","time":"2026-10-01T12:50:07.7336085+00:00"} exit=0
```

- [x] `api` + `db` oppe, `status` `ok`, `version` er en ekte SHA
- [x] Taggen kommer fra `image: ${API_IMAGE}:${IMAGE_TAG:-latest}` i `compose.prod.yml`, og verdiene fra `.env`
- [x] Siste push til `main` (`b8e13da`) ga grønn pipeline

## Oppgave 1: ci-broken.yml-jakten

### Steg 1: med øynene

Jeg leste `ci-broken.yml` mot `ci.yml` uten å se på kommentarblokka først. Fire feil:

| Linje | Feil | Konsekvens | Fiks |
|---|---|---|---|
| 55 | `file: infra/docker/Dockerfile` | Fila finnes ikke, Dockerfile ligger i rota. docker-jobben går rød | Fjern `file:` (eller `file: Dockerfile`) |
| 19–20 | `permissions:` har bare `contents: read` | Når stien er fikset, blir push `denied`. Lesing er ikke skriving | `packages: write` |
| 44 | `needs: build` | docker venter ikke på format-jobben. Et image kan pushes selv om formatet er feil | `needs: [format, build]` |
| 40 | `dotnet format LabApi.slnx` | Uten `--verify-no-changes` formaterer den bare, og sjekker ingenting | Legg til `--verify-no-changes` |

**Kommentarene stemmer ikke helt med koden.** Jobben som heter `test` kjører faktisk `dotnet format`, mens
testene ligger i `build`. Kommentar 4 sier «push: true på pull_request», men triggeren er `workflow_dispatch`.
Selve feilen er den samme: rettigheten til å skrive pakker mangler. Navnet på en jobb er ikke det jobben gjør.

**Hvilke to blir aldri røde?** `needs` som mangler en port (linje 44) og format uten verifisering (linje 40).
Begge gir grønn logg. De er farligst nettopp derfor: porten ser ut som den virker, men stopper ingenting.
De to andre feiler høyt, og den som feiler høyt, blir fikset.

### Steg 2–4: ikke kjørt

Miroret i timen var lærerens eget demo-repo. Der har jeg bare lesetilgang, og `ci-broken.yml` lå ikke på `main`.
Vi gikk gjennom feilene felles i timen i stedet. Selvsjekken i oppgaveteksten bekrefter rekkefølgen:
først «no such file or directory», så `denied` når stien er fikset.

## Oppgave 2: kontrollert feilinjeksjon

### B. Taggen som ikke finnes

`IMAGE_TAG=sha-does-not-exist`, så `pull`:

```
✗ api Error failed to resolve reference "ghcr.io/malinfossum/varde:sha-does-not-exist": ghcr.io/malinfossum/varde:sha-does-not-exist: not found
! db  Interrupted
Error response from daemon: failed to resolve reference "ghcr.io/malinfossum/varde:sha-does-not-exist": ghcr.io/malinfossum/varde:sha-does-not-exist: not found
```

Bæreordet er **`not found`**. GHCR var ærlig denne gangen, men oppgaveteksten advarer om at den kan si
`denied` om en tag som bare mangler. `db Interrupted` er ikke en egen feil: compose henter parallelt og
avbryter resten når én feiler.

Hva kjørte etterpå?

```
varde-api-prod  ghcr.io/malinfossum/varde:sha-b8e13da  Up 3 minutes (healthy)
{"status":"ok","version":"sha-b8e13da","time":"2026-10-01T12:53:14.8774758+00:00"} exit=0
```

Den gamle versjonen sto urørt. `pull` feilet før `up`, så ingen container ble byttet. Rekkefølgen
`pull && up -d` er altså en port i seg selv. Grønn tag tilbake, `pull` og `up -d` gikk rent.

### C. Health-gaten på feil adresse

```
$ curl --fail http://localhost:8081/health; echo " exit=$?"
curl: (7) Failed to connect to localhost port 8081 after 0 ms: Couldn't connect to server
 exit=7
$ curl --fail http://localhost:8080/healt; echo " exit=$?"
curl: (22) The requested URL returned error: 404
 exit=22
```

Exit 7 betyr at ingen lytter på døra. Exit 22 betyr at noen åpnet og svarte «finnes ikke». **Det er 22 som
beviser at tjenesten kjører.**

Til en kollega med rød health-gate i morgen tidlig: les exit-koden før du gjetter. 7: sjekk `ps` og
port-mappingen, for appen svarer ikke i det hele tatt. 22: appen lever, så sjekk URL-en og stien.

### D. Healthchecken til db fjernet

Linje 27–31 i `compose.prod.yml` kommentert ut med `sed`, sjekket med `git diff`, så `down -v` og `up -d`:

```
✗ Container varde-db-prod   Error
✓ Container varde-api-prod  Created
dependency failed to start: container varde-db-prod has no healthcheck configured
```

Jeg traff utfallet der compose nekter, ikke kappløpet. `api` ble `Created`, men aldri startet: `ps` viste
bare `db`, `logs api` var tom og `RestartCount` var 0, fordi den aldri hadde kjørt.
`condition: service_healthy` uten en healthcheck bak er et løfte ingen kan holde. Docker Compose sa fra
med en gang. Et verktøy som ikke gjør det, venter evig eller starter api i stillhet, og da kommer kappløpet.

Gjenopprettet med `git restore compose.prod.yml` (fra commiten, ikke fra hukommelsen). `git diff --stat`
var tom. Kald start med tomt volum:

```
✓ Container varde-db-prod   Healthy   10.8s
✓ Container varde-api-prod  Started   10.8s
varde-api-prod  Up 6 seconds (healthy)
varde-db-prod   Up 17 seconds (healthy)
0
{"status":"ok","version":"sha-b8e13da","time":"2026-10-01T12:58:23.9529113+00:00"} exit=0
```

Databasen brukte 10,8 s på å bli klar, og `api` ventet på den. `RestartCount` 0: det er rekkefølgen som
holder stacken oppe, ikke restart-policyen.

### A. Auth

Hoppet over. Pakken er public, så pull trenger ingen innlogging. Push-siden av samme feilklasse er
`packages: write` i oppgave 1: synlighet styrer lesing, scopes styrer skriving.

### Feiljournal

| Feiltekst (kort) | Hva jeg lærte |
|---|---|
| `failed to resolve reference ... not found` | `pull` feiler før noe byttes. Les taggen av en grønn kjøring, ikke fra minnet |
| `curl: (7) Couldn't connect to server` | Ingen lytter. Sjekk `ps` og porten |
| `curl: (22) The requested URL returned error: 404` | Appen lever. Sjekk URL-en og stien |
| `dependency failed to start: ... has no healthcheck configured` | Et vilkår uten sjekk bak feiler høyt eller venter i stillhet. Healthcheck og `depends_on` hører sammen |

## Fra timen

- Feilsøking øves bare på ting som er ødelagt. Læringen ligger i å finne og fikse feilen, ikke i at noe virker.
- Feilene i oppgaveteksten trenger ikke kjøres én for én. Det viktige er å legge merke til dem, så jeg
  kjenner dem igjen og unngår dem neste gang.
- AI er god på DevOps, men secrets og sikkerhet må jeg passe på hele tiden selv. Et eksempel fra i dag:
  `compose config` uten filter skriver ut databasepassordet i klartekst. Derfor bruker jeg `| grep image:`.
- DevSecOps-team er blitt vanlig, fordi sikkerhet ikke kan være et eget steg til slutt.
- I morgen: ClaimTheSquare-oppgaven og DNS. Det var DNS.

## Oppgave 3: rød test, ekte brudd og rollback på stoppeklokke

### Del 1: porten som holder

`main` i Varde er beskyttet, så den røde testen gikk via en PR (#37), ikke en push til `main`. Jeg endret
én forventet verdi i `PagingTests` fra `[InlineData(7, 7)]` til `[InlineData(7, 8)]`. Lokalt først:

```
Varde.Tests.Unit.PagingTests.NormalizePage_never_returns_less_than_one(input: 7, expected: 8) [FAIL]
Assert.Equal() Failure: Values differ
Expected: 8
Actual:   7
Failed!  - Failed:     1, Passed:    35, Skipped:     0, Total:    36
```

Samme linjer i CI (`Build and test`, exit code 1). `Format check` var grønn: en usann påstand kan godt være
pent formatert kode. PR-en fikk `BLOCKED`, og GHCR fikk ingen ny tag.

**Forbehold:** docker-jobben var grå, men på en PR er den *alltid* grå (`if: github.event_name == 'push'`).
Den grå jobben beviser derfor ingenting om `needs` her. Beviset er den røde sjekken som stopper merge,
og at ingen ny tag dukket opp. Reparert med `git revert` (`7bb1978`), grønt igjen, PR lukket uten merge.

**«Vi har tester» mot en rød test som stopper leveransen:** tester som bare kjøres, er en rapport. En test
som stopper merge og image, er en port. Forskjellen ligger i `needs` og i branch protection, ikke i testene.

### Del 2: bruddet testene ikke ser

Jeg døpte om `/health` til `/status` (engelsk rutenavn, ikke `/helse`). Alle 36 enhetstester var grønne
lokalt, og alle sjekker på PR #38 var grønne. Merget som `4e97289`, og imaget **`sha-4e97289`** landet i
GHCR. Pipelinen så ingenting, fordi testene sjekker logikk og ikke HTTP-flaten. Det er derfor health-gaten
finnes. Den levende siden ble ikke rørt: `deploy-web.yml` venter på `/api/municipalities`, ikke `/health`.

Reparert med `git revert -m 1` på merge-commiten (PR #39, `83f4d70`), og **`sha-83f4d70`** er den grønne
taggen dagen skal ende på.

### Del 3: rollback-drillen

Deploy `sha-4e97289`: `curl: (22) The requested URL returned error: 404`, exit 22. Tjenesten lever, men
døra den spør på finnes ikke lenger.

**Runde 1: 6188 ms** fra `.env`-endringen til `/health` svarte `sha-5156e25`, og `inspect` viste
`ghcr.io/malinfossum/varde:sha-5156e25`. Så tilbake til `sha-4e97289` (exit 22 igjen). **Runde 2: 5642 ms**, samme bevis.
Runde 2 var et halvt sekund raskere, og prosedyren var den samme. Dagen endte på `sha-83f4d70`: `/health` exit 0, og `git status -s` var tom, så `.env` er ikke i Git.

**To ulike «returer»:** `git revert` ruller *koden* bakover ved å gå framover: ny commit, nytt image
(`sha-83f4d70`). Rollbacken ruller *deployen* bakover: et gammelt image, ingen ombygging. Den første tar
en pipeline-kjøring. Den andre tar sekunder, fordi imaget allerede ligger i registryet.

## Oppgave 4: runbook

Rollback-delen ligger i Varde-README-en (PR #40, merget 01.10): påstand og bevis, tre steg tilbake,
tag-register, øvingstider og feiljournal med de ordrette feiltekstene fra i dag. Runbooken i Varde er
på engelsk, som resten av prosjektet.

## Ikke gjort

- Peer-test av runbooken: droppet. Kurset er ferdig.
