# Onsdag 23.09 — notater

Kjørt i Codespacet (`podman` = alias for `docker`). Min compose-fil ligger i
`uke-1/onsdag/compose.yml`. Tallene er fylt inn fra terminalen 25.09. Kursrepoet fjernet
`labApi/.env.example` 24.09, så `.env` skrev jeg selv (`POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`,
pluss `PGADMIN_DEFAULT_*` for å stilne advarslene fra `tools`-profilen).

## Oppgave 0: Tirsdagens gjeld

```bash
cd /workspaces/course/labApi
podman rm -f labtest
cp .env.example .env                       # sett eget POSTGRES_PASSWORD i .env
git check-ignore -v .env                   # skal treffe .gitignore
mv compose.yml compose.fasit.yml
cp /workspaces/devops-course/uke-1/onsdag/compose.yml compose.yml
```

## Oppgave 1: Bare databasen

Oppgave 1 og 2 er samme fil hos meg; for å kjøre bare `db` først:

```bash
podman compose up -d db
podman compose ps
podman compose exec db psql -U labuser -d labapp
```

I psql: `\dt` (ingen tabeller ennå) · `SELECT version();` · `\q`

**Observert:** version() = `PostgreSQL 16.15 (Debian 16.15-1.pgdg13+2) on x86_64-pc-linux-gnu`

**Refleksjon:** En komplett PostgreSQL-server på under ett minutt, uten apt, uten `pg_hba.conf`,
uten tjeneste å konfigurere. Alt som var oppsett i `2.PostgreSQL-Setup` er nå tre env-variabler
og ett volume. Databasen er bare en container.

## Oppgave 2: API-et på

```bash
podman compose up -d
podman compose ps                          # begge healthy?
curl --fail http://localhost:8080/health
curl http://localhost:8080/api/products    # 10 seedede produkter
podman compose logs api                    # hvis noe feiler
```

**Observert:** `/health` → 200 · antall produkter 10

Felle jeg gikk i: var noe annet allerede bundet til 8080 (en annen stack), startet bare `db`, og
`api` sto som «not running» — da finnes heller ingen `Products`-tabell, siden det er API-et som migrerer.

Valg jeg tok: `build: .` (kortform) og ingen `container_name`, `restart` eller ressursgrenser —
det kommer torsdag. `db` har ingen `ports:` med vilje.

## Oppgave 3: Tre påstander

```bash
podman ps                                  # A: port-mapping bare på api
podman compose exec api getent hosts db    # B: DNS-svar for "db"
podman compose exec db psql -U labuser -d labapp -c \
  "INSERT INTO \"Products\" (\"Name\", \"Price\") VALUES ('Bevis på persistens', 1);"
podman compose down && podman compose up -d && sleep 20
podman compose exec db psql -U labuser -d labapp -c 'SELECT * FROM "Products";'   # C: raden er der
podman compose down -v && podman compose up -d && sleep 20
podman compose exec db psql -U labuser -d labapp -c 'SELECT * FROM "Products";'   # C: raden er borte
```

**Observert:**

- A: `podman ps` viser `0.0.0.0:8080->8080/tcp` på api, ingenting på db. (Ingen `psql` på verten.)
- B: `getent hosts db` → `172.18.0.2      db` (compose-nettverket).
- C: etter `down`/`up`: raden er der (1 treff) · etter `down -v`/`up`: raden er borte (0 treff).

**Refleksjon:** `down` fjerner containere og nettverk, men volumet `postgres_data` består —
dataene ligger i volumet, ikke i containeren. `down -v` sletter volumet også; det er full reset,
og det gjør jeg bare med vilje.

## Oppgave 4: Én kommando inn — «syklusen»

```bash
podman compose down
time (podman compose up -d && until curl -sf http://localhost:8080/health; do sleep 1; done)
```

**Observert:** `up -d` → `/health` 200 på 12,7 sekunder (fra `down`, imagene bygd fra før).

Kodeendring: nytt produkt i seed-lista i `Data/DbInitializer.cs`, så:

```bash
podman compose up -d --build
curl http://localhost:8080/api/products    # det nye produktet er med
```

**Syklusen:** endre kode → `podman compose up -d --build` → `curl /health`.

## Oppgave 5 (valgfritt): pgAdmin — se, ikke klikk

```bash
podman compose --profile tools up -d       # e-post + passord fra .env
# http://localhost:5050 via Ports-fanen; koble til host "db"
podman compose --profile tools down
```

**Refleksjon:** En rad endret i pgAdmin finnes bare i mitt volum — ikke i Git, ikke i noen
migrasjon. En partner som kloner repoet og kjører `up -d` ser den aldri. Skal en endring overleve,
går den via seed-kode eller migrasjon → Git → alle får den. Click-ops er nettopp det Knight gjorde.

## Knight-spørsmålet

Knight deployet til manuelt oppsatte servere ingen visste hvor like var. Her startes db og api fra
filer, med healthchecks og en definert tilstand for når api får starte. Ny maskin + repo + `.env`
= identisk miljø. Staging som speiler prod er `compose up -d` på en annen laptop.

## Rydd opp

```bash
mv compose.fasit.yml compose.yml           # labApi-fasiten tilbake
```

## Til torsdag

Stacken virker. Torsdag: 30 min teori om produksjonslik stack, så Postgres inn i mitt eget
onion-prosjekt (steg 0–2), fredag Dockerfile + compose + hardening + runbook (steg 3–6).
