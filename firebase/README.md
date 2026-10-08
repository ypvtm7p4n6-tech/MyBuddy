# MyBuddy met Firebase: inloggen en synchroniseren

Met deze stappen kun je in MyBuddy inloggen met e-mail en wachtwoord en je gegevens automatisch gelijk houden op je
iPhone, iPad en Mac. Je hebt alleen een gratis Firebase-project nodig (het Spark-plan). Een betaald
Apple Developer-account is niet nodig.

Alles wat je moet doen staat hieronder. Het kost ongeveer 10 minuten. Je hoeft niets te programmeren: je plakt één
sleutel in één bestand.

> Zolang je geen sleutel hebt ingevuld, werkt de app precies zoals voorheen, met accounts die alleen op je eigen
> apparaat bestaan. Je kunt dit dus rustig later doen.

## Wat staat waar

| Bestand | Wat het is |
|---|---|
| `firebase/database.rules.json` | De beveiligingsregels die je in de Firebase-console plakt (stap 3) |
| `App/Config/FirebaseConfig.swift` | Hier plak je je Web API-sleutel (stap 4) |

Je Firebase-project: `my-buddy-finance`. Je database:
`https://my-buddy-finance-default-rtdb.europe-west1.firebasedatabase.app` (regio europe-west1, in Europa).
Die gegevens staan al in `FirebaseConfig.swift`.

## Stap 1. Authentication aanzetten (inloggen met e-mail en wachtwoord)

1. Ga naar <https://console.firebase.google.com> en open je project **my-buddy-finance**.
2. Kies links **Build > Authentication** (in het Nederlands: **Authenticatie**).
3. Klik op **Get started** (**Aan de slag**) als je dat nog niet deed.
4. Open het tabblad **Sign-in method** (**Aanmeldingsmethode**).
5. Kies **Email/Password** (**E-mail/wachtwoord**), zet **Enable** (**Inschakelen**) aan en klik op **Save** (**Opslaan**).
   De tweede schakelaar, "Email link (passwordless sign-in)", laat je uit.

## Stap 2. Realtime Database controleren

1. Kies links **Build > Realtime Database**.
2. Staat er al een database met het adres `https://my-buddy-finance-default-rtdb.europe-west1.firebasedatabase.app`?
   Dan ben je klaar. Zo niet: klik op **Create Database**, kies de regio **europe-west1 (Belgium)** en start in
   **locked mode** (vergrendeld). De regels in stap 3 vervangen dat toch.

## Stap 3. De beveiligingsregels plakken

Dit is het belangrijkste stuk voor je veiligheid. Zonder deze regels kan niemand erbij (vergrendeld) of, als je ooit
"test mode" koos, kan iedereen erbij. Met deze regels kan **alleen jij, ingelogd, je eigen gegevens lezen en schrijven**.

1. Open `firebase/database.rules.json` in dit project en kopieer de hele inhoud.
2. Ga in de Firebase-console naar **Realtime Database** en open het tabblad **Rules** (**Regels**).
3. Selecteer alles in het veld, plak de inhoud en klik op **Publish** (**Publiceren**).

Wat de regels doen:

- Alles is standaard dicht (`".read": false`, `".write": false`).
- Alleen `users/{jouw-uid}` is open, en alleen als je bent ingelogd en je `uid` gelijk is aan dat pad
  (`auth.uid === $uid`). Een ander kan jouw pad dus niet lezen en jij niet het zijne.
- Onder `users/{uid}/finance` mag alleen het afgesproken formaat staan: `data` (tekst, kleiner dan 8 miljoen tekens),
  `modifiedAt` (getal), `schema` (getal) en eventueel `device` (tekst). Al het andere wordt geweigerd.

## Stap 4. Je Web API-sleutel in de app zetten

1. Klik in de Firebase-console op het **tandwiel** naast "Project Overview" en kies **Project settings**
   (**Projectinstellingen**).
2. Blijf op het tabblad **General** (**Algemeen**). Kopieer de **Web API Key** (**Web API-sleutel**), een lange tekst die
   begint met `AIza`.
3. Open in Xcode het bestand `App/Config/FirebaseConfig.swift` en plak de sleutel tussen de aanhalingstekens:

   ```swift
   static let apiKey = "AIza...jouw sleutel..."
   ```

4. Bouw de app opnieuw en start hem (Cmd+R). Je ziet nu een inlogscherm met **Inloggen**, **Account maken** en
   **Wachtwoord vergeten**.

Is de sleutel een geheim? Nee. Hij zegt alleen welk Firebase-project je app gebruikt, en staat in elke app die Firebase
gebruikt. Je gegevens worden beschermd door het inloggen en de regels uit stap 3, niet door deze sleutel.

## Stap 5 (niet verplicht). De sleutel beperken

Wil je dat de sleutel alleen voor jouw app werkt?

1. Ga naar <https://console.cloud.google.com/apis/credentials> en kies hetzelfde project.
2. Open de sleutel die **Browser key (auto created by Firebase)** heet.
3. Kies bij **Application restrictions** voor **iOS apps** en voeg de bundle-ID **`nl.mybuddy.app`** toe.
4. Kies bij **API restrictions** voor **Restrict key** en vink **Identity Toolkit API** en **Token Service API** aan.
5. Sla op. Het kan een paar minuten duren voor het werkt.

De app stuurt de bundle-ID bij elk verzoek mee (`X-Ios-Bundle-Identifier`), dus ook de Mac-versie blijft werken.
Krijg je later de melding "Deze API-sleutel is beperkt tot een andere app"? Controleer dan deze beperking.

## Zo test je het met twee apparaten

1. Start de app op je eerste apparaat (bijvoorbeeld de Mac), kies **Account maken** en vul een e-mailadres en
   wachtwoord in (minimaal 6 tekens).
2. Heb je al gegevens op dat apparaat? Dan vraagt de app: *"Je hebt lokale gegevens op dit apparaat. Uploaden naar je
   account?"* Kies **Uploaden**.
3. Open **Instellingen**. Onder **Synchroniseren** staat **Gesynchroniseerd** met het tijdstip.
4. Installeer de app op je tweede apparaat (iPhone of iPad), kies **Inloggen** en gebruik hetzelfde e-mailadres en
   wachtwoord. Je gegevens verschijnen.
5. Wijzig iets op het ene apparaat. Binnen een paar seconden staat het ook op het andere (de app wacht 1,5 seconde
   na je laatste wijziging en stuurt dan).
6. Zet het ene apparaat in vliegtuigmodus, wijzig daar iets, en zet vliegtuigmodus weer uit. De wijziging gaat dan
   alsnog mee: **Instellingen > Synchroniseren > Nu synchroniseren** doet het ook meteen.

**Als je op beide apparaten verschillende wijzigingen maakte** (bijvoorbeeld allebei offline) vraagt de app
*"Welke versie wil je houden?"*:

- **Bewaar deze versie**: de gegevens van dit apparaat gaan naar de cloud.
- **Neem cloud-versie over**: de gegevens uit de cloud vervangen die van dit apparaat.
- **Later**: kies je straks in Instellingen.

De versie die je niet kiest, raak je niet kwijt: de app bewaart hem eerst als back-up op dit apparaat. Je zet hem terug
via **Instellingen > Synchroniseren > Back-ups van conflicten > Terugzetten**.

Koersen tellen hierbij niet mee. Ververst een apparaat de koersen terwijl een ander apparaat iets echt wijzigt, dan
blijft de echte wijziging staan en haalt de app de koersen later gewoon opnieuw op. Verversen twee apparaten alleen
tegelijk de koersen, dan wint de nieuwste. Je krijgt de vraag dus alleen als je op beide apparaten echt iets anders
hebt aangepast.

## Wat de app wel en niet doet

- De app werkt altijd op het bestand op je eigen apparaat. De cloud is een aanvulling: zonder internet kun je gewoon
  verder en haalt de app het later in.
- Je wachtwoord wordt nergens bewaard. Alleen een inlogtoken (een soort sleutelkaart) staat in de Keychain van je
  apparaat, zodat je ingelogd blijft.
- "Wachtwoord vergeten" stuurt Firebase een e-mail met een link om een nieuw wachtwoord te kiezen.
- "Account verwijderen" wist eerst je gegevens in de cloud, dan je account, en daarna de bestanden op dit apparaat.
  Heb je dezelfde account ook op een ander apparaat open staan, dan zet dat apparaat de gegevens niet terug: het
  merkt dat het account weg is en logt uit. De gegevens op dat apparaat zelf blijven staan.
- Op de Mac heeft MyBuddy één venster. Een tweede venster zou dezelfde gegevens tegelijk aanpassen en synchroniseren.
- De synchronisatie werkt op iPhone, iPad en Mac.

## Veiligheid en privacy

- De verbinding is versleuteld (HTTPS), zowel bij het inloggen als bij het versturen van je gegevens.
- De toegangsregels (stap 3) zorgen dat alleen jij je eigen gegevens kunt lezen en schrijven.
- **De gegevens zijn niet end-to-end versleuteld.** Ze staan leesbaar in jouw Firebase-database. Wie toegang heeft tot
  je Firebase-project (jij, en Google als beheerder van de dienst) kan ze in de console zien. Voor een persoonlijke
  financiën-app van jezelf is dat meestal prima, maar zet er geen gegevens in die je met niemand wilt delen die bij je
  Firebase-project kan. Deel je Firebase-project dus niet met anderen.
- Een back-up van je gegevens (Instellingen > Back-up exporteren) blijft ook mogelijk.

## Wat het gratis plan (Spark) toestaat

Het Spark-plan kost niets en vraagt geen creditcard. Voor deze app is het ruim genoeg. Globaal (controleer de actuele
cijfers op <https://firebase.google.com/pricing>):

- Realtime Database: 1 GB opslag, 10 GB downloaden per maand en 100 gelijktijdige verbindingen. Je gegevens zijn
  een paar honderd kilobyte; de app waarschuwt als ze boven ongeveer 5 MB komen.
- Authentication met e-mail en wachtwoord: gratis.

Je kunt per ongeluk niet meer betalen dan 0 euro: Spark schakelt bij overschrijding van de limiet de dienst tijdelijk
uit in plaats van te factureren.

## Waarom er geen "Firebase SDK" nodig is

Voor Firebase bestaan officiële pakketten voor Swift (`firebase-ios-sdk`). MyBuddy gebruikt die bewust **niet**, maar
praat rechtstreeks met de officiële internetadressen (REST) van Firebase:

- Inloggen: `identitytoolkit.googleapis.com` (aanmaken, inloggen, wachtwoord vergeten, wijzigen, verwijderen) en
  `securetoken.googleapis.com` (inlogtoken vernieuwen).
- Gegevens: de Realtime Database op jouw `…firebasedatabase.app`-adres, met live updates via Server-Sent Events.

Voordelen:

- **Geen pakketten om te installeren.** Dus ook geen gedoe met Swift Package Manager.
- **Geen `GoogleService-Info.plist`** om te downloaden en toe te voegen. Alleen één sleutel.
- **Korte bouwtijd.** Het SDK is groot en kost minuten extra bij elke schone build.
- **Volledig testbaar.** De hele inlog- en synchronisatielogica draait in de automatische tests, zonder echt netwerk.
- Werkt op **iPhone, iPad en Mac** met dezelfde code.

### Liever het officiële SDK?

Dat kan ook. De stappen, in grote lijnen:

1. Registreer in de Firebase-console bij **Project settings > Your apps** een **iOS-app** met bundle-ID `nl.mybuddy.app`
   en download `GoogleService-Info.plist`. Sleep het bestand in Xcode in de map `App` (vink "Copy items if needed" aan).
2. Kies in Xcode **File > Add Package Dependencies…**, plak `https://github.com/firebase/firebase-ios-sdk` en kies
   **FirebaseAuth** en **FirebaseDatabase** voor het doel MyBuddy.
3. Roep bij het opstarten `FirebaseApp.configure()` aan (in `MyBuddyApp.init`).
4. Gegevens lezen en schrijven doe je dan zo:

   ```swift
   import FirebaseAuth
   import FirebaseDatabase

   let db = Database.database(url: "https://my-buddy-finance-default-rtdb.europe-west1.firebasedatabase.app")
   let uid = Auth.auth().currentUser!.uid
   let ref = db.reference(withPath: "users/\(uid)/finance")

   try await ref.setValue(["data": jsonTekst, "modifiedAt": millis, "device": naam, "schema": 1])
   let snapshot = try await ref.getData()
   ref.observe(.value) { snapshot in /* wijziging van een ander apparaat */ }
   ```

5. De regels uit stap 3 en het gegevensformaat blijven hetzelfde. Je moet dan zelf `Auth.auth()` in plaats van
   `CloudAccount` en `Database` in plaats van `FirebaseDatabaseClient` aansluiten.

Nadelen van het SDK voor deze app: een extra pakket van honderden megabytes bij het bouwen, een plist-bestand,
en minder controle over wanneer er precies wordt gesynchroniseerd en hoe conflicten worden afgehandeld.

## Als er iets misgaat

| Melding in de app | Wat te doen |
|---|---|
| "Inloggen met e-mail en wachtwoord staat nog uit" | Stap 1: zet **Email/Password** aan. |
| "Authentication is nog niet ingeschakeld in je Firebase-project" | Stap 1: klik in Authentication op **Get started**. |
| "De Firebase Web API-sleutel in FirebaseConfig.swift is ongeldig" | Stap 4: kopieer de sleutel opnieuw, zonder spaties. |
| "Deze API-sleutel is beperkt tot een andere app" | Stap 5: controleer de beperking (bundle-ID `nl.mybuddy.app`). |
| "Geen toegang tot je gegevens in de cloud" | Stap 3: plak de regels opnieuw en klik **Publish**. |
| "De database is niet gevonden" | Stap 2 en `databaseURL` in `FirebaseConfig.swift` controleren. |
| "Er bestaat al een account met dit e-mailadres" | Kies **Inloggen**, of **Wachtwoord vergeten**. |
| "Te veel pogingen" | Wacht een paar minuten en probeer het opnieuw. |
| "Je sessie is verlopen" | Log opnieuw in. Je gegevens op het apparaat blijven staan. |

Je account en gebruikers zie je in de console onder **Authentication > Users**. Je gegevens zie je onder
**Realtime Database > Data** bij `users/…/finance`. De tekst staat daar als één lange regel JSON; dat is dezelfde
tekst als in een back-upbestand van de app.
