# DanskSvar i browseren

`dansksvar.html` er webudgaven af appen. Den er udgivet som artefakt og kan
åbnes i Safari på iPhone.

Den deler algoritmer med den native app i [`../ios/DanskSvar`](../ios/DanskSvar):
samme danske fyldordsliste, samme stammeafkortning, samme emnesporing med
vægtet ordprofil og cosinus-lighed, og de samme seks betingelser for, hvornår
et svar må komme. Den danske systemprompt er også den samme.

## Hvad der er anderledes end den native app

| | Native app | Browser |
|---|---|---|
| Lytter med låst skærm | Ja | **Nej** — Safari standser siden |
| Svar på låseskærmen | Ja | **Nej** — websider har ikke adgang |
| Lytter i baggrunden | Ja | **Nej** — siden skal være fremme |
| Talegenkendelse | `SFSpeechRecognizer`, kan køre lokalt | `webkitSpeechRecognition`, altid via Apples servere |
| Dansk-genkendelse | `NLLanguageRecognizer` | Simplere optælling af danske funktionsord |
| Adgang til modellen | Egen API-nøgle i nøgleringen | Artefaktens `sample`-kapabilitet — ingen nøgle i browseren |
| Holder skærmen vågen | Ikke nødvendigt | `navigator.wakeLock` |

Webudgaven kræver **Safari** på iPhone. Chrome og Firefox på iOS får ikke
adgang til talegenkendelsen, selvom de kører på samme WebKit.
