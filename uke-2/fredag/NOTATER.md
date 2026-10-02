# Uke 2 fredag (økt 02.10): fra `git push` til en server på internett, notater

Dagens oppgave var å ta hele flyten ut på en VPS: SSH, nginx, TLS og en deploy-jobb som ruller ut uten at
jeg rører serveren. Appen i oppgaven var ClaimTheSquarePostgres fra kursrepoet. Hele dagen var frivillig.

## Valget: jeg fulgte gjennomgangen og satte ikke opp egen VPS

Jeg har ikke råd til å betale for en server, heller ikke noen kroner i timen. Jeg undersøkte gratisveiene
før timen:

| Alternativ | Hvorfor ikke i dag |
|---|---|
| Hetzner (oppgavens forslag) | Koster penger, faktureres per time |
| Oracle Cloud Always Free | Gratis VM med offentlig IP, men krever kredittkort ved registrering |
| AWS Free plan | Kreditt i 6 måneder, men krever kort, og kontoen stenges etter perioden |
| Azure for Students | Bare for nye Azure-kunder, og det er usikkert om fagskolen teller |
| GitHub Codespaces | Ingen offentlig IP, ingen port 80/443, ingen systemd. Holder for M1 til M3, ikke M4 |

Prosjektene mine kjører på Neon og Cloudflare. Der er det ingen server å drifte, og jeg vil ikke spre meg
på flere leverandører når det ikke trengs. Så jeg fulgte gjennomgangen i timen og skrev ned hva hvert steg
gjør, og hva som gjør den samme jobben hos meg.

## M1 til M3: allerede gjort med Varde denne uka

Kjeden fram til serveren kjører jeg allerede i Varde (`malinfossum/varde`):

- [x] **M1, porter:** `Format check`, `Build and test` og sårbarhetsrapport i `build-test.yml`. `docker` har `needs: [format, build-test]` (tirsdag)
- [x] **M2, GHCR:** `sha-<kort>` og `latest`, og en sha-tag pushes aldri to ganger (tirsdag og onsdag)
- [x] **M3, prod-sim:** `compose.prod.yml` kjører imaget CI bygde, ingenting bygges lokalt (onsdag)
- [x] **Rollback-drill:** 6188 ms og 5642 ms fra `.env`-endringen til `/health` viste den gamle taggen (torsdag)

## M4 og M5: hva serveren gjør, og hvem som gjør det hos meg

Tre ting er nye i dag: ett hopp (SSH), ett skap (hemmeligheter på serveren) og én inngang (nginx på 80/443).
Hos meg gjør Cloudflare og GitHub de samme jobbene:

| Steg på VPS-en | Hva det løser | Hos meg (Varde) |
|---|---|---|
| `deploy`-bruker, SSH-nøkkel, root stengt | Hvem kommer inn på maskinen | Ingen maskin. GitHub-kontoen og et Cloudflare-token som bare deploy-jobben har |
| `ufw` med 22, 80 og 443 | Hvilke porter er åpne | Ingen porter. Bare Cloudflares kant svarer |
| nginx som reverse proxy til `127.0.0.1:8080` | Én inngang, appen er ikke eksponert | Cloudflare Pages serverer de ferdige filene |
| DNS `A`-record, grå sky | Navnet peker på maskinen | `varde.pages.dev`, ingen egen DNS ennå |
| certbot og fornyings-timer | TLS, og at den ikke går ut i helga | TLS er automatisk på Pages |
| `.env` i `/opt/stack`, utenfor Git | Hemmelighetene bor på serveren | `production`-miljøet i GitHub: `NEON_CONNECTION_STRING` og Cloudflare-nøklene |
| Deploy-jobb: SSH, `pull`, `up -d`, helseport | Push til `main` ruller ut | `deploy-web.yml`: API-et starter mot Neon i runneren, eksporterer data, siden bygges og lastes opp med `wrangler` |

**Det jeg tar med meg:** en statisk side på Cloudflare er ikke «mindre DevOps». Den har den samme kjeden
(porter, et bygg, en utrulling og en vei tilbake), bare uten en maskin jeg må lappe. Prisen er at noen
andre eier inngangen. Varde fungerer slik fordi siden ikke trenger en server mens den kjører. En app med
innlogging eller skriving ville trengt en.

**Fella med vertsnavnet:** `ssh-keyscan` tar et vertsnavn, ikke `deploy@1.2.3.4`. Derfor står brukeren i en
egen secret. Vertsnavnet er en *variabel*, ikke en secret: det står allerede i sertifikatet og i DNS.

**Rekkefølgen i deploy-jobben:** `pull`, så `up -d`, så helseporten. Porten kjører *etter* at containeren
er byttet. Den oppdager en dårlig utrulling, men den stopper den ikke.

## M6: rollback hos meg

| | På VPS-en | Hos meg |
|---|---|---|
| Deployen tilbake | Actions, Run workflow med forrige sha-tag | Prod-sim: `IMAGE_TAG` i `.env`, `pull`, `up -d` (5,6 s). Nettsiden: Cloudflare Pages kan sette en tidligere deploy live igjen |
| Koden tilbake | `git revert`, ny pipeline | Samme: `git revert`, og `deploy-web.yml` bygger på nytt |

Scenario D er det viktigste: hvis `up -d` lykkes men appen krasjer, blir deploy-jobben rød *etter* at den
ødelagte versjonen er ute. Hos meg feiler en ødelagt Varde-build før opplastingen, og da ligger forrige
deploy fortsatt ute. Den ruller seg ikke ut halvveis.

## Den muntlige sjekken, svart for Varde

1. **Uke 1 mot uke 2:** ingenting av det som kjører, endret seg. Bare hvem som bygger imaget og hvor det kjører.
2. **Én container:** samme origin, så ingen CORS og ingen ekstra proxy-regel. Varde hadde to origins i
   Azure-tiden (frontend og API hver for seg), og derfor hadde API-et en CORS-policy i `Program.cs`.
   Den fjernet jeg 02.10 i Varde-PR #46, siden ingen nettleser kaller API-et lenger.
3. **Bevis for hva som kjører:** `podman inspect` på containeren (tag og digest) mot taggen fra den grønne
   kjøringen, og `version` i `/health`.
4. **`/health` mot en ekte rute:** `/health` sier at prosessen lever. En rute som spør databasen, sier at
   hele kjeden virker. Uten skjema er `/health` grønn og `/text-objects` rød. Derfor venter
   `deploy-web.yml` i Varde på `/api/municipalities`, ikke på `/health`.
5. **Rollback uten bygg:** taggen ligger i registryet, og imaget er uforanderlig. Derfor tar det sekunder.
6. **Hvem eier skjemaet:** i Varde eier appen det (EF-migrasjoner ved oppstart). Det er trygt bare fordi
   én runner migrerer om gangen: `deploy-web.yml` har en `concurrency`-gruppe. To instanser som starter
   samtidig, ville kappet om den samme migrasjonen.
7. **Knight Capital:** automatisert og verifiserbar utrulling. Hver versjon går gjennom en grønn pipeline,
   og rollback er en vanlig kommando med målt tid.

## Samme dag i Varde

Alle actions i Varde var på Node 20, som GitHub faser ut, og ingen workflow slo av telemetri. Begge deler
er fikset i Varde-PR #45, sammen med opprydding etter Azure-tiden.

## Gjenstår

- Peer-test av runbooken: droppet. Kurset er ferdig, og jeg rakk ikke å få en medstudent til å kjøre den.
- Hvis jeg en dag trenger en ekte server: Oracle Always Free er eneste gratis VM med offentlig IP, og den krever kort
