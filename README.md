# DanskSvar

En iPhone-app, der lytter med på dansk tale i rummet, finder den røde tråd i det,
der bliver talt om, og lægger ét skriftligt svar på din låseskærm. Du siger ikke
noget, og du trykker ikke på noget.

Appen er skrevet til én telefon: din egen. Den bygges i Xcode og installeres
direkte på din iPhone. Den ligger ikke i App Store, og der er ingen server,
ingen konto og ingen anden bruger end dig.

Kildekoden ligger i [`ios/DanskSvar`](ios/DanskSvar). Byggevejledningen står i
[`ios/DanskSvar/README.md`](ios/DanskSvar/README.md).

## Sådan opfører den sig

- **Ingen notifikationer om, hvad andre siger.** Transskriptionen vises kun inde
  i appen, mens du har den åben. Den forlader aldrig appen som en notifikation.
- **Ét svar ad gangen.** Når et nyt svar kommer, fjernes det forrige fra
  låseskærmen og lægger sig i historikken inde i appen.
- **Svaret kommer af sig selv.** Der er ingen sendeknap og intet, du skal
  bekræfte.
- **Den venter, til der er noget at svare på.** Appen svarer først, når nok er
  sagt om det samme, når der er en tydelig rød tråd, og når der er en pause i
  talen. Skifter samtalen emne, går der et pusterum, før det nye svar kommer.
- **Dansk, der lyder dansk.** Svaret skrives af Claude på en dansk systemprompt,
  der beder om talt rigsdansk med rigtig sætningsrytme, danske sætningsadverbier
  og komplekse perioder, hvor emnet er komplekst — og uden oversættelsesdansk.

## Tre ting, du skal vide, før du går i gang

**1. Mikrofonen kan ikke undværes.** Du bad om, at det skulle foregå uden brug af
mikrofonen. Det kan ikke lade sig gøre: tale findes kun som lyd, og lyd kommer
kun ind gennem mikrofonen. Det, du *kan* slippe for — og slipper for her — er
selv at tale, at holde en knap nede og at trykke på send. Appen bruger mikrofonen
af sig selv i baggrunden; du rører den ikke.

iOS viser en **orange prik** øverst på skærmen, hele tiden mens mikrofonen er i
brug. Den kan ikke slås fra af en app, og det er med vilje fra Apples side. Alle
i rummet kan altså se, at telefonen lytter.

**2. Optagelse af andres samtaler.** I Danmark må du gerne optage en samtale, du
selv deltager i. At aflytte eller optage en samtale, du *ikke* deltager i, er
strafbart efter straffelovens § 263. Appen kan ikke høre forskel på, hvem der
taler — den skelner ikke mellem dig og de andre. Ansvaret for kun at bruge den i
samtaler, du selv er med i, ligger hos dig.

**3. Den kommer ikke i App Store.** En app, der lytter uafbrudt i baggrunden og
transskriberer omgivelserne, bliver afvist ved review. Det er uden betydning her,
fordi appen kun skal køre på din egen telefon, men den kan ikke deles videre ad
den vej.

## Privatliv

- Lyden gemmes aldrig. Der skrives ingen lydfil på noget tidspunkt.
- Transskriptionen ligger kun i hukommelsen og slettes, når appen lukkes.
- Kun selve svarene gemmes på telefonen — i historikken, som du selv kan rydde.
- Talegenkendelsen kan køre **helt lokalt** på telefonen, hvis dansk er hentet
  ned til diktering. Ellers går lyden gennem Apples talegenkendelse.
- Selve formuleringen laves af Claude. Det betyder, at et uddrag af samtalen
  sendes til Anthropics API. Vil du undgå det helt, kan du nøjes med appens
  lokale nødformulering — den er til gengæld meget enklere i sproget.

## Licens

Privat brug. Der følger ingen garanti med.
