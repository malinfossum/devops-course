# Uke 2 mandag (økt torsdag 24.09) — CI-fundamenter, notater

Oppgavene gjorde jeg i mitt eget prosjekt **Varde** (`malinfossum/varde`), ikke i kursrepoet. Varde har
allerede en `ci.yml` med to påkrevde sjekker (`api-tests`, `web-tests`), så kurs-pipelinen ble en egen fil
ved siden av: `.github/workflows/build-test.yml`, på branchen `ci/build-test`, PR #25.

## Oppgave 0 og 0.5

- `.github/` ligger i repo-rota, så workflowen trigges. `Varde.slnx` ligger derimot i `api/`, så alle
  `dotnet`-kommandoene må peke på `api/Varde.slnx`.
- Varde har testprosjekt fra før (`Varde.Tests`: 36 unit + 50 integrasjon), så **0b hoppet jeg over**.

## Oppgave 1a — grønn (etter to røde jeg ikke hadde planlagt)

| Kjøring | Hva skjedde | Hvorfor |
|---|---|---|
| 1 | Rød i «Restore»: `MSB1003` | `dotnet restore` i rota fant ingen prosjekt- eller løsningsfil. Løst med `api/Varde.slnx`. |
| 2 | Rød i «Test»: `Test host process crashed` | Integrasjonstestene trenger PostgreSQL, og runneren er naken. Den statiske konstruktøren som kobler til databasen kastet, og tok hele testverten med seg. |
| 3 | Grønn, 36/36 | `--filter "FullyQualifiedName~Varde.Tests.Unit"`: bare unit-testene kjører her. Integrasjonstestene kjører fortsatt i `ci.yml`, som starter en Postgres-service-container. |

Lærdom: «naken runner» betyr også ingen database. Enten gir jeg pipelinen en database, eller så lar jeg være
å kjøre testene som trenger den. Å hoppe stille over dem i testkoden gjør en rød feil om til grønn.

## Oppgave 1b — rød med vilje

Endret `[InlineData(7, 7)]` til `[InlineData(7, 8)]` i `PagingTests.cs`, pushet (`7878c53`), så rødt, angret
(`a190c5f`), grønt igjen. Hele syklusen: endre → push → tilbakemelding → fikse.

## Oppgave 2 — les Actions-UI-et

1. **Rødt steg:** «Test». Restore og bygg var grønne. Hadde feilen ligget i «Bygg», hadde koden ikke
   kompilert — da er det bygge-porten som ikke holdt, og ingen tester har kjørt i det hele tatt.
2. **Første feil i loggen:**
   ```
   Varde.Tests.Unit.PagingTests.NormalizePage_never_returns_less_than_one(input: 7, expected: 8) [FAIL]
   Expected: 8
   Actual:   7
   at ... PagingTests.cs:line 14
   Failed!  - Failed: 1, Passed: 35, Skipped: 0, Total: 36
   ```
3. **Tid per steg (grønn kjøring):** restore 12 s · bygg 12 s · test 3 s. Restore cacher jeg først:
   NuGet-pakkene endrer seg sjelden, så de kan gjenbrukes mellom kjøringer med en cache-nøkkel på
   `.csproj`-filene — samme idé som lag-cachen i Dockerfilen.
4. **Re-run jobs** er feil første grep fordi samme commit gir samme resultat: en ekte feil blir rød igjen,
   og en ustabil test som tilfeldigvis blir grønn skjuler problemet. Les loggen først; kjør på nytt bare
   når loggen viser en infrastrukturfeil, for eksempel et nettverkstimeout.
5. Én setning hver:
   - Grønt/rødt i UI-et er bedre sannhet enn «Jonas sa det var deployet» fordi det viser hva maskinen
     faktisk gjorde, med logg og commit-SHA, synlig for alle — ikke hva én person husker.
   - `docker`-jobben trenger `needs:` fordi jobber kjører parallelt på hver sin maskin; uten `needs:`
     starter den samtidig med format og build og kan pushe et image før testene er grønne.

## Huskelista

- [x] Repo-rota = prosjektet — workflowen blir faktisk trigget
- [x] Grønn pipeline: checkout → .NET 10 → restore → bygg → test
- [x] Én rød pipeline sett med vilje og obdusert (steget «Test», linje 14 i `PagingTests.cs`)
- [x] Testprosjekt: finnes fra før, med i løsningen, Dockerfilen kopierer `Varde.Tests.csproj`
- [x] `/health` fortsatt 200 på `main` — sjekket med API-et kjørt lokalt mot Postgres, ikke via compose
