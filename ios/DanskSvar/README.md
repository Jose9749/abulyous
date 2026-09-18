# DanskSvar — byg og installér

Appen findes som kildekode plus en projektbeskrivelse. Du genererer selv
Xcode-projektet og bygger den over på din iPhone.

## Det skal du bruge

- En Mac med **Xcode 15** eller nyere
- En **iPhone med iOS 17** eller nyere
- **XcodeGen** (`brew install xcodegen`) — laver `.xcodeproj` ud fra `project.yml`
- En **Anthropic API-nøgle** fra <https://console.anthropic.com> (kan tilføjes
  senere inde i appen)
- En Apple-ID. Et gratis ét er nok; se om signering længere nede.

## Byg

```bash
cd ios/DanskSvar
xcodegen generate          # laver DanskSvar.xcodeproj
open DanskSvar.xcodeproj
```

I Xcode:

1. Vælg **DanskSvar**-målet → fanen **Signing & Capabilities**.
2. Sæt **Team** til din egen Apple-konto. Xcode retter selv bundle-id'et, hvis
   `dk.privat.dansksvar` er taget.
3. Sæt **Background Modes** → **Audio, AirPlay, and Picture in Picture** til
   (den er allerede beskrevet i `project.yml`, men Xcode vil gerne se den i
   capabilities-listen).
4. Tilslut din iPhone, vælg den som destination, og tryk **Run** (⌘R).
5. Første gang: på telefonen under **Indstillinger → Generelt → VPN og
   enhedsadministration** skal du stole på dit udviklercertifikat.

Har du ikke lyst til at bruge XcodeGen, kan du oprette et almindeligt
iOS-app-projekt i Xcode, trække mappen `Sources` ind og kopiere nøglerne fra
`project.yml` over i målets Info-fane. `project.yml` er den korte vej.

### Signering

- **Gratis Apple-ID:** appen virker i **7 dage**, hvorefter du bygger den over
  igen med ⌘R. Ingen betaling.
- **Betalt udviklerprogram** (99 USD om året): appen virker i **et år** ad
  gangen.

Begge dele installerer kun på de telefoner, du selv bygger over på. Appen kan
ikke sendes videre til andre.

## Første gang du åbner appen

1. Sig ja til **mikrofon**, **talegenkendelse** og **notifikationer**.
2. Åbn **Indstillinger** i appen og indsæt din Anthropic-nøgle. Den lægges i
   telefonens nøglering.
3. Tryk **Start lytning**.

Vil du have svarene til at bryde igennem Fokus og lyse låseskærmen op, så lad
**Bryd igennem Fokus** være slået til. Er iOS' **Tidsfølsomme beskeder** slået fra
for appen under Indstillinger → DanskSvar → Beskeder, vises svaret stadig, men
uden at bryde igennem en Fokus-tilstand.

### Dansk talegenkendelse lokalt

Vil du have lyden til aldrig at forlade telefonen, skal dansk ligge lokalt:
**Indstillinger → Generelt → Tastatur → Diktering**, slå dansk til, og lad
telefonen hente sproget. Derefter kan du slå **Kun lokal talegenkendelse** til
inde i appen. Kan din iPhone ikke køre dansk lokalt, er kontakten grå.

## Sådan hænger koden sammen

| Fil | Ansvar |
|---|---|
| `Sources/Audio/AudioSessionController.swift` | Holder lydsessionen i live, også når skærmen er slukket. Fanger afbrydelser fra opkald og skift af lydvej. |
| `Sources/Audio/DanishSpeechCapture.swift` | Uafbrudt `da-DK`-genkendelse. Mikrofonen kører i ét stræk, mens selve genkendelsesopgaven fornys hvert 45. sekund, fordi iOS kapper en enkelt opgave efter cirka et minut. |
| `Sources/Core/DanishText.swift` | Dansk orddeling, fyldordsliste, let stammeafkortning og en sprogport, der kasserer det, der ikke er dansk. |
| `Sources/Core/TopicTracker.swift` | Den røde tråd. Holder en vægtet ordprofil af emnet, måler hver ny ytrings lighed med den, og erklærer emneskift efter to uforenelige ytringer i træk. |
| `Sources/Engine/ConversationEngine.swift` | Afgør **hvornår** der må svares. Seks betingelser skal være opfyldt — se nedenfor. |
| `Sources/Reply/DanishReplyPrompt.swift` | Den danske systemprompt og oplægget til modellen. |
| `Sources/Reply/ClaudeClient.swift` | HTTP-kaldet til Claude Messages API. |
| `Sources/Notifications/NotificationCoordinator.swift` | Lægger svaret på skærmen og fjerner det forrige. |
| `Sources/Storage/HistoryStore.swift` | Gemmer alle svar, der har været vist. |

### De seks betingelser for et svar

Motoren ser efter dem én gang i sekundet. Alle seks skal være opfyldt:

1. Karensperioden efter et emneskift er udløbet (som udgangspunkt 20 sekunder).
2. Der har været stille i mindst 6 sekunder — så appen ikke svarer midt i en sætning.
3. Emnet består af mindst 3 ytringer og 25 ord.
4. Sammenhængen i emnet er over kravet til rød tråd (16 %).
5. Der er gået mindst 90 sekunder siden sidste svar.
6. Er det samme emne som sidst, skal der være sagt mindst 45 nye ord om det.

Alle seks tal kan skrues på inde i appens indstillinger.

## Modellen

Svaret formuleres af **Claude Opus 5** (`claude-opus-5`) gennem
`POST /v1/messages`. Anthropic udgiver ingen officiel Swift-SDK, så kaldet er
skrevet som almindelig HTTP med `URLSession`.

Et par detaljer i kaldet, der er værd at kende:

- `output_config.effort` står på `low` som udgangspunkt. Det er den hurtigste
  indstilling, og det betyder noget her, fordi svaret skal være på skærmen, mens
  samtalen stadig handler om det, det handler om. Vil du have rigere formuleringer
  på bekostning af et par sekunder, så sæt **Grundighed** til `high` i
  indstillingerne.
- `max_tokens` er sat rundhåndet, fordi loftet dækker både modellens interne
  tænkning og selve svarteksten. Svarets faktiske længde styres af systemprompten,
  ikke af `max_tokens`.
- Serverside-fallback er slået til (`fallbacks: "default"`). Afviser Opus 5'
  sikkerhedsfiltre en forespørgsel, køres den automatisk videre på en anden model
  i samme kald i stedet for bare at falde på gulvet.
- Et afslag kommer som HTTP 200 med `stop_reason: "refusal"`, ikke som en
  HTTP-fejl. Klienten tjekker det, før den læser tekst ud af svaret.

Regningen afhænger af, hvor meget der bliver talt. Et svar koster typisk nogle få
øre; med et svar hvert andet minut i en times samtale er der tale om småpenge,
men det er dit forbrug, og det kan følges i Anthropics konsol.

## Hvad appen ikke kan

- **Den kan ikke høre, hvem der taler.** Der er ingen adskillelse af stemmer.
  Taler du selv, bliver dine ord en del af det samme emne som de andres.
- **Den kan ikke lytte uden mikrofon.** Se forbeholdet i hovedmappens README.
- **Den kan ikke skjule den orange prik.** Det er en OS-funktion.
- **Den overlever ikke, at iOS lukker den.** Baggrundslyd holder appen i live i
  meget lang tid, men får telefonen brug for hukommelsen, kan den lukke appen.
  Så skal du åbne den og trykke **Start lytning** igen.
- **Den kan ikke opdatere en notifikation, der allerede ligger.** iOS tillader
  det ikke uden en server. Appen fjerner derfor den gamle og lægger en ny —
  hvilket er præcis den opførsel, der er bedt om.
