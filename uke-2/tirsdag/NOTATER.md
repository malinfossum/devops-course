# Uke 2 tirsdag (økt 28.09 og 30.09): kvalitetsporter og image til GHCR, notater

Som på mandag jobbet jeg i **Varde** (`malinfossum/varde`), i kurs-pipelinen `.github/workflows/build-test.yml`.
`main` er beskyttet, så alt gikk via PR: portene biter på PR-en, og varen lages etter merge.

## Oppgave 0: mandagens gjeld

Siste kjøring på `main` var grønn og `git status` var ren. Men før format-porten kunne stå, måtte
`dotnet format` bli enig med seg selv på Linux:

- På Windows-klonen min var alt grønt. På runneren (Linux-utsjekk, LF) ga formatsjekken 9867 × `ENDOFLINE`,
  fordi `api/.editorconfig` krevde CRLF mens filene i git er LF.
- Fiks (PR #29): LF overalt (`end_of_line = lf` + `eol=lf` i `api/.gitattributes`), EF-migrasjonene merket
  som `generated_code`. Exit 0 både på en ren LF-klon og på Windows.

## Oppgave 1: format-porten (PR #30)

- Jobben `format` kjører `dotnet format api/Varde.slnx --verify-no-changes`. Feilen *«Both a MSBuild project
  file and solution file found»* fikk jeg aldri: rota mi har verken prosjekt eller solution, så jeg måtte
  navngi `api/Varde.slnx` fra start.
- **Porten biter:** ekstra innrykk i én linje ga rød kjøring (36403725909):
  ```
  CategoryService.cs(31,9): error WHITESPACE: Fix whitespace formatting. Delete 4 characters.
  ```
  Loggen peker på fil, linje og kolonne, ikke bare «det er stygt».
- Fikset med `dotnet format api/Varde.slnx` (uten `--verify`), `git diff` viste bare mellomrom. Grønn igjen.

Refleksjon: `--verify-no-changes` er sjekkeren, uten flagget er det fikseren. Fikseren retter filene og gir
exit 0, så en port uten flagget blir aldri rød.

## Oppgave 2: bygg og push image til GHCR (PR #33)

- `env:` øverst med `REGISTRY: ghcr.io` og `IMAGE_NAME: ${{ github.repository }}`.
- `docker`-jobben er fra fasiten, med tre endringer:
  - `needs: [format, build-test]`: jeg beholdt jobbnavnet mitt fra mandag i stedet for å døpe det om til `build`.
  - `context: ./api`: Dockerfilen ligger i `api/`, ikke i repo-rota.
  - `packages: write` står bare på docker-jobben. Fasiten har den øverst, men da får format og test også
    skriverett de ikke trenger.
- Build-jobben fikk også `dotnet list package --vulnerable --include-transitive`. Ingen funn. Den gir exit 0
  uansett, så den er en rapport i loggen, ikke en port.
- **På PR-en:** format og build-test grønne, docker `skipping`. PR-en kontrolleres, bare `main` produserer varer.
- **Etter merge** (kjøring 36716669653, commit `a581a64`): format og build-test først, så docker. Loggen
  navngir imaget to ganger:
  ```
  ghcr.io/malinfossum/varde:sha-a581a64
  ghcr.io/malinfossum/varde:latest
  ```
  **Sha-taggen til i morgen: `sha-a581a64`.**
- **Synlighet:** repoet er public, så pakken ble public av seg selv. Sjekket med anonym pull: begge taggene
  svarer 200, `sha-0000000` svarer 404.
- **Cache (steg 6):** `main` er beskyttet, så i stedet for en tom commit kjørte jeg samme kjøring på nytt.
  «Build and push» gikk fra **1 min 42 s** til **7 s**, med 13 `CACHED`-linjer i loggen.

## Oppgave 3: hent varen ned

I Codespacet (Docker, `podman` er alias):

```bash
docker pull ghcr.io/malinfossum/varde:sha-a581a64
docker pull ghcr.io/malinfossum/varde:latest
docker images --format "{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}"
```

```
ghcr.io/malinfossum/varde:latest       19adcf518c4e 368MB
ghcr.io/malinfossum/varde:sha-a581a64  19adcf518c4e 368MB
```

To navn, én image-ID. `latest` er bare et navn som peker på den nyeste, og det flytter seg ved neste push.
En tag som ikke finnes:

```
docker pull ghcr.io/malinfossum/varde:sha-0000000
... not found
```

Registryet vet hva som finnes der. Stacken kjørte jeg ikke, den er til i morgen.

## Knight-spørsmålet

`latest` svarer på «hva er nyest?», og det svaret endrer seg mens du spør. Knight Capital visste ikke hvilken
kode som kjørte på hvilken maskin. Med `latest` hadde de hatt samme blindsone: navnet sier ingenting om
hvilken commit som faktisk rullet ut. En sha-tag er festet til én commit og kan ikke flytte seg.

## Huskelista

- [x] `format`-porten er grønn, og jeg har sett den bite én gang
- [x] `docker`-jobben er grønn: `sha-a581a64` + `latest` ligger på lageret
- [x] Den fulle sha-taggen står i notatene
- [x] Pakken er public
- [x] Imaget er pullet og ligger i `docker images`
- [x] Prod-simen er ikke kjørt ennå
