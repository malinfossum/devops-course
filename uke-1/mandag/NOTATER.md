# Mandag 21.09 — notater

Kjørt i Codespacet (`podman` = alias for `docker`).

## Oppgave 1: Hva skjedde egentlig?

**Observert:**

- `podman images` — `hello-world:latest`, ID `5e2309035332`, 25.9 kB disk / 9.49 kB content.
- `podman ps -a` — `b1379afa97bd`, navn `kind_gauss`, status `Exited (0)` — synlig kun med `-a`.
- `podman start -a kind_gauss` — samme hilsen som i oppgave 0, ingen ny nedlasting.

**Refleksjon:**

- Image vs container i listingene: `images` viser malen (én linje, 25.9 kB, skrivebeskyttet). `ps -a` viser instansen som ble laget fra malen — med egen ID, eget navn (`kind_gauss`) og egen status. Én mal kan gi mange instanser.
- Hvorfor ble ikke containeren fjernet automatisk? Fordi stopp og fjern er to forskjellige ting. Containeren beholder skrivelaget og loggene sine til jeg sier `rm` — det er derfor jeg kunne `start -a` den igjen. Vil jeg ha auto-opprydding må jeg be om det med `--rm`.
- `podman run` = `pull` + `create` + `start` — hent imaget hvis det mangler, lag en container av det, start den. Det stemte med det jeg så: `web2` hoppet over pull-steget fordi nginx allerede lå lokalt.

## Oppgave 2: Kjør en ekte webserver

**Observert:**

- `podman run -d --name web -p 8080:80 docker.io/library/nginx` — 5 lag lastet ned (mye mer enn hello-world), container `bdceeb445a82`, terminalen tilbake med én gang.
- `podman ps` — `web`, `Up`, `0.0.0.0:8080->80/tcp, [::]:8080->80/tcp` — synlig uten `-a` fordi den kjører.
- Nettleser via Ports-fanen (8080): `…-8080.app.github.dev` → «Welcome to nginx!».
- `podman logs -f web` — oppstart: entrypoint-scripts, `nginx/1.31.6`, `OS: Linux 6.8.0-1064-azure` (vertskjernen!), master + 2 workers. Reload: `GET / HTTP/1.1" 200`, deretter `304` (cache), pluss `404` på `/favicon.ico`.
- `podman exec -it web bash` → `cat /etc/os-release`: Debian GNU/Linux 13 (trixie), 13.7.
- `ps aux` finnes ikke i slim-imaget; `ls /proc` + `/proc/1/cmdline`: PID 1 = `nginx: master process nginx -g daemon off;`, workers 29/30, pluss shellet mitt (31/38/39).

**Refleksjon:**

- Hvorfor ser containeren ut som en Linux-boks? Her avviker jeg fra kurset: jeg har ingen `podman machine`. Codespace-VM-en er allerede Linux, og containeren låner kjernen dens — loggen sa `OS: Linux 6.8.0-1064-azure`, altså Azure sin kjerne, ikke nginx sin. Det som er «Debian 13» inne i containeren er bare filsystemet. Containeren er en prosess på verten med eget filsystem og egne navnerom, ikke en egen maskin.

## Oppgave 3: Isolasjon — to containere

**Observert:**

- `podman run -d --name web2 -p 8081:80 docker.io/library/nginx` — ingen nedlasting, bare ny ID `4b887eb628a4`.
- `podman ps` — to linjer: `web2` 8081 (Up 24 s) og `web` 8080 (Up 10 min), samme `IMAGE nginx`.
- `podman exec web bash -c '…index.html'` — ingen utdata (engangskommando, ikke `-it`).
- 8080 viser: «Server 1».
- 8081 viser: fortsatt «Welcome to nginx!».

**Refleksjon:**

- Samme image, to containere, null påvirkning — hvorfor? Imaget er skrivebeskyttede lag. Hver container får et tynt skrivelag oppå, og `echo … > index.html` traff bare `web` sitt lag. `web2` leste fortsatt fra imaget. Det er Knight-poenget: én mal, N like instanser, ingen kan smitte de andre.

## Oppgave 4: Livssyklusen

**Observert:**

- `podman stop web` / `podman rm web` — begge svarer bare `web`; stopp gikk raskt (nginx svarer på SIGTERM).
- Ny `web` (`dc593fb55fc7`) fra samme image → 8080 viser «Welcome to nginx!» igjen — «Server 1» er borte.
- Opprydding: `podman ps -a` etter `stop`/`rm web web2`: bare `kind_gauss` (hello-world, Exited) igjen.

**Refleksjon:**

- Hvor ble «Server 1» av, og hvorfor er det en feature? Den bodde i skrivelaget til den gamle `web`, og `rm` kastet laget. Ny `web` startet rent fra imaget. Feature fordi hver `run` gir en kjent tilstand — «det virket på min server» kan ikke skje når imaget *er* serveren. Data som skal overleve må i volumes (torsdag).

## Oppgave 5: Feilsøk live

**Scenario A — portkonflikt:**

- Feilmelding fra `app2`: `Bind for 0.0.0.0:8080 failed: port is already allocated`. Containeren ble likevel opprettet (status `Created`) — så `app2 -p 8082:80` feilet på navnekonflikt: `The container name "/app2" is already in use`. `rm` først, så nytt forsøk.
- Valgt løsning: frigjøre porten — `podman rm -f app1`, deretter `app2` på 8080.

**Scenario B — containeren dør umiddelbart:**

- `podman ps -a` etter `doedsdomt`: `Exited (0) 9 seconds ago`, COMMAND `/bin/sh` — shellet fikk ingen stdin og avsluttet med én gang.
- `sover` med `sleep 3600`: `Up` — hovedprosessen lever, så containeren lever. Ryddet med `rm -f doedsdomt sover app1 app2`.

**Refleksjon:**

- Hva bestemmer om en container lever? Hovedprosessen (PID 1). `doedsdomt` fikk `/bin/sh` uten stdin, shellet avsluttet, containeren døde med `Exited (0)` — ingen feil, bare ingen jobb. `sover` fikk `sleep 3600` og lever i en time. Lærdom fra scenario A: en `run` som feiler på port lager likevel containeren (`Created`), så navnet er opptatt til jeg `rm`-er den.

## Knight-spørsmålet

- Hvilket av dagens grep ville reddet Knight Capital? Oppgave 3: samme image gir bit for bit like servere, fordi konfigurasjonen følger imaget og ikke maskinen. Men det alene hadde ikke holdt — de trengte også en automatisert utrulling som traff alle åtte, og en sjekk som fanget den ene som ble hoppet over. Det er uke 2.

## Til tirsdag — tre gjetninger om labApi-imaget

1. Multi-stage: bygg og `publish` med SDK-imaget, kjør med det mye mindre `aspnet`-runtime-imaget. SDK-en skal ikke være med i det som deployes.
2. `.csproj` kopieres inn og `dotnet restore` kjøres *før* resten av koden, så NuGet-laget caches og bare kodeendringer trigger ny bygg.
3. Postgres skal *ikke* inn i imaget — den er en egen container. Connection string kommer som miljøvariabel (`.env` utenfor git), ikke hardkodet i imaget. `ASPNETCORE_URLS` må peke på 0.0.0.0:8080 så porten kan mappes ut.
