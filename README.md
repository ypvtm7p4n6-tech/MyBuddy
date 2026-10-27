# MyBuddy

Een persoonlijke financiën-app voor **iPhone, iPad en Mac**, in de stijl van **Apple Muziek en Apple TV**: grote kleurvlakken met witte tekst, een carrousel bovenaan, planken met tegels, lijsten met een gekleurd pictogram en albumpagina's voor je spaarpotten, beleggingen en doelen. Het ontwerp gebruikt de standaardonderdelen van het systeem (tabbalk, werkbalk, zoekveld, menu's) en dus ook Liquid Glass op iOS 26 en macOS 26; de app zelf tekent geen glas.

## De drie tabs

| Tab | Wat je er doet |
|---|---|
| **Home** | Bovenaan een carrousel met drie grote kaarten: **Nog te verdelen** deze maand, je **Vermogen** (met een kleine grafiek en wat uit bank, spaarpotten en beleggingen bestaat) en je **Saldo vandaag** met de volgende betaling. De kleur van de achtergrond volgt de kaart die je ziet. Daaronder vijf planken met tegels: **Komende dagen**, **Spaarpotten**, **Beleggingen**, **Doelen** en **Hulpmiddelen**. Elke plank heeft rechts "Toon alles" en soms een "…"-menu (bijvoorbeeld "Kies potten…"). |
| **Bibliotheek** | De lijst van alle pagina's van de app in drie groepen: **Deze maand** (Maandoverzicht, Inkomen, Uitgaven, Verdelen, Bankrekening, Dag voor dag), **Sparen en beleggen** (Spaarpotten, Beleggingen) en **Plannen** (Doelen, Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck), met per rij het kerncijfer. Daaronder **Recent**: je laatste vijf handmatige boekingen. |
| **Zoeken** | Het zoekveld van het systeem. Zonder tekst tien bladertegels (**Blader**); met tekst de resultaten per groep (Pagina's, Spaarpotten, Beleggingen, Doelen, Inkomen en uitgaven, Instellingen). Er is geen zoekgeschiedenis. Op iPhone staat de zoektab los, rechts naast de andere twee. |

**Profielknop en Instellingen.** Instellingen is geen tab. Op iPhone en iPad staat rechtsboven op Home, Bibliotheek en Zoeken een **profielknop** (een cirkel met je initiaal); die opent Instellingen als **volle pagina** op de stapel van de tab, nooit als blad. Een stip op de knop meldt dat er bij de synchronisatie iets aandacht vraagt. Op de Mac staat Instellingen in het **Instellingen-venster** (Cmd+komma, App-menu). Je bereikt Instellingen dus in één tik vanaf elke tabwortel en in twee tikken vanaf elke diepte; ook Zoeken vindt ze.

**Sneltoetsen (Mac, iPad met toetsenbord).** Cmd+1 Home, Cmd+2 Bibliotheek, Cmd+3 Zoeken, Cmd+F zoekt, Cmd+komma opent Instellingen, Cmd+R ververst de koersen.

## De schermen

- **Maandoverzicht** ("Waar gaat je geld heen"): een grafiek per maand met de keuze Maand, Half jaar of Jaar, wat er nog te verdelen of over is, en de cijfers van de periode en per maand. Bereikbaar via de Bibliotheek.
- **Hulpmiddelen**: de vier rekenhulpen (Noodbuffer, Versnellers, Toekomstschatting, Aankoopcheck) met een regel uitleg. Bereikbaar via de plank Hulpmiddelen op Home en via Zoeken.
- **Inkomen, Uitgaven, Verdelen, Bankrekening, Dag voor dag**: de pagina's van de maand. Vanaf Home, de Bibliotheek en Zoeken openen ze op de huidige maand; binnen de pagina blader je met de maandbalk.
- **Spaarpot, belegging en doel zijn albumpagina's**: bovenaan een grote kop met een gekleurde tegel, de naam, het kerngetal, de voortgang en knoppen (bijvoorbeeld Storten, Opnemen, Bewerken), daaronder de lijst met boekingen, waarde-updates of onderdelen als "tracklijst", met swipe-acties en een contextmenu. Grafieken en rekenregels zijn ongewijzigd.
- **Instellingen**: Account (eerst en los), Rekenen, Koersen, Gegevens (back-up, import, export), Indeling en Over MyBuddy.

**Een pagina opent op de stapel waar je bent.** Een link wisselt niet van tab; een pagina mag op twee stapels staan, en nooit twee keer in hetzelfde pad. Tik je op de tab waar je al zit, dan ga je terug naar de wortel.

**Eigen indeling.** Op Home bepaal je zelf de volgorde van de vijf planken: houd een plankkop **lang ingedrukt**, of ga naar Instellingen, Indeling. Welke potten en beleggingen op Home staan kies je met "Kies potten…" en "Kies beleggingen…" in het menu van de plank. Een volgorde die je in een eerdere versie bewaarde laadt gewoon.

## Ontwerpprincipes

Eén taal voor het hele ontwerp: een gekleurd tegelverloop met witte tekst (acht tinten, gemeten op contrast: wit op een tegel haalt ruim 6 op 1, bij Verhoog contrast ruim 9 op 1), een zacht kleurverloop achter elke pagina in de tint van het onderwerp, grote afgeronde hoeken (hero 28, kaart 20, tegel 16, albumkop 24), horizontale planken die per tegel snappen, pillen als knoppen in de inhoud, en alleen systeemglas voor tabbalk, werkbalk en menu's. De kleur draagt nooit alleen de betekenis: titel, symbool, teken en woord staan er altijd bij. Alles schaalt mee met Dynamic Type (bij de grootste formaten staan hero en planken onder elkaar), respecteert Verlaag beweging, Verlaag transparantie en Verhoog contrast, en elke actie is ook zonder gebaar te bereiken (swipe-acties hebben altijd een menu of knop).

Alle bedragen worden afgerond op hele euro's getoond (koersen en uurloon met centen).

## Starten (Mac met Xcode 26)

1. Installeer XcodeGen: `brew install xcodegen`
2. In deze map: `xcodegen` (maakt `MyBuddy.xcodeproj`)
3. Open `MyBuddy.xcodeproj`. Kies bij *Signing & Capabilities* je eigen Team bij **beide** targets (MyBuddy en MyBuddyTests). Kies een iPhone, iPad of "My Mac" en druk op Run.

Bij het eerste openen staat Home leeg met twee knoppen: **Salaris instellen** en **Voorbeelddata laden**, zodat je alles direct kunt zien. De app vraagt iOS 18 of macOS 15; onderdelen van iOS 26 (Liquid Glass, krimpende tabbalk) staan achter een versiecontrole.

De rekenlogica testen zonder Xcode-project: `cd CoreTests && swift test` (ruim 1800 tests).

## Dag voor dag

Je geeft per inkomsten- of uitgavenregel een **dag van de maand** op, en per spaarpot of belegging een **overschrijfdag** (of één dag voor de hele maand). De app rekent het saldo van je bankrekening en van elke spaarpot **per dag**. Een verdeling voor een maand die nog komt wordt op die dag overgeschreven: tot die dag telt het niet mee in het potsaldo. Op de bankpagina zie je het saldo per gekozen dag, de komende 14 dagen, een dagsaldo-grafiek en een waarschuwing als je onder nul of onder je buffer komt.

## Spaarpotten met rente

Per pot stel je een **rentepercentage**, het **uitbetalingsmoment** (maandelijks, per kwartaal, half jaar of jaar) en de **dag** in. De app schrijft de rente automatisch bij op die dag (bij het opstarten en terwijl de app open staat). Elke uitbetaling heeft een vast id, dus er wordt nooit dubbel bijgeschreven, ook niet bij twee apparaten.

## Import en export

In Instellingen, Gegevens:
- **JSON-back-up** maken en terugzetten (ook om te verhuizen naar een ander apparaat).
- **CSV-export** voor Numbers of Excel.
- **Importeren uit Excel (.xlsx) of CSV**: de app herkent de onderdelen en deelt ze in als inkomen, vaste lasten, variabele lasten, spaarpot of belegging. Je ziet eerst een voorbeeldscherm waar je elke rij kunt aanpassen. Importeren voegt toe en vervangt niets.

## Inloggen en synchroniseren

Zonder instelling werkt de app met **lokale accounts** (alles blijft op dit apparaat). Met **Firebase** (gratis Spark-plan) log je in met e-mail en wachtwoord en synchroniseren je apparaten automatisch (iPhone, iPad, Mac). Er is **geen SDK of extra pakket** nodig; de app gebruikt de Firebase REST-API's. Stappen: zie [`firebase/README.md`](firebase/README.md). Kort: Authentication > Email/Password aanzetten, de regels uit `firebase/database.rules.json` plakken en je Web API-sleutel in `App/Config/FirebaseConfig.swift` zetten. De gegevens worden onderweg beveiligd (HTTPS) en door regels afgeschermd per gebruiker, maar zijn niet end-to-end versleuteld.

## Koersen en marktgegevens

Beleggingen met een **ticker** (bijv. `VWCE.DE`, `AAPL`, `BTC-EUR`) en een **aantal** krijgen automatisch een live koers in euro. Bron: Yahoo Finance, met Stooq en CoinGecko als reserve. Dit zijn onofficiële bronnen zonder garantie. In Instellingen test je de verbinding per bron. Inflatie en rente haalt de app bij de ECB op (instelbaar).

## Aankoopcheck

Vul in wat je wilt kopen, de soort en de prijs plus verzendkosten, en kies **eerst** hoeveel uur je ervoor wilt werken. Daarna toont de app wat het in werkuren kost. Gelijk of minder uren dan nodig: de prijs wordt rood met feedback. Meer uren dan nodig: groen, met feedback of het financieel kan. De app zoekt zelf geen goedkopere prijs (dat mag niet zomaar); ze opent zoekopdrachten bij Beslist, Google Shopping en Tweakers/Kieskeurig, en jij vult de beste prijs in.

## Wat de app niet doet

- Geen bankkoppeling: je saldo vul je zelf in en de app rekent verder.
- Geen financieel advies. Rendementen en rente zijn aannames die je zelf instelt.

## Verificatie

**Wat is gecontroleerd.** De rekenlogica (`App/Core`) wordt op Linux gecompileerd en getest (`cd CoreTests && swift test`, ruim 1800 tests, zonder wijziging van een rekenregel of opslagformaat in ontwerp 2). De hele app, ook de SwiftUI-laag, is gecontroleerd met een **nagebootste typecheck** (`/tmp/ctl-all/run-all.sh`, een Swift 6.0-frontend in Swift 5-modus tegen nagemaakte versies van SwiftUI, Charts en de platformframeworks, gegenereerd uit Apple's documentatie): 0 fouten voor iOS en macOS, Debug en Release, en 0 gebruiken van iOS 26-API's buiten een versiecontrole. Daarnaast draaien de scripts `docs/design/design-checks.sh --final` (ontwerpregels), `docs/design2/contract-check.sh final` (bestaat elk onderdeel van het ontwerpcontract met zijn handtekening), `docs/design2/keep-check.sh --final` (heeft elke rekenaanroep van de oude schermen nog een gebruiker) en `docs/design2/own-check.sh`.

**Wat niet is gecontroleerd.** Het nieuwe ontwerp (Home, Bibliotheek, Zoeken, de albumpagina's en de schil eromheen) is **door de bouwers niet in Xcode gecompileerd en niet op een toestel of in de simulator bekeken**. De nagebootste typecheck mist API's die Xcode wel kent en kan iets te mild zijn; de macOS-CI, de enige echte compiler in dit project, is bij het opleveren niet gestart. Het is dus niet vastgesteld dat de app bouwt, hoe de schermen er in werkelijkheid uitzien, of de planken en de carrousel op de juiste breedte snappen, en ook het gedrag van iOS 26 (zoektab, glas om de profielknop, krimpende tabbalk) is niet gezien. **Volgende stap:** laat de CI draaien (`.github/workflows/ci.yml` bouwt iOS en macOS, draait de tests en maakt met "Run workflow" screenshots via `scripts/ci-screenshots.sh`, die op de tak `ci-screenshots` komen) en loop daarna de lijst in `docs/design2/plan.md` par. 5.5 na: iPhone SE en Pro Max, iPad, Mac op drie breedtes, licht en donker, grootste tekst, Verhoog contrast, Verlaag transparantie en Verlaag beweging, VoiceOver, iOS 18 en 26.

Voor screenshots start je een debug-build met `-mybuddy-demo` (voorbeelddata) en bijvoorbeeld `-mybuddy-tab library`, `-mybuddy-open flow` of `-mybuddy-hero 1`; alle argumenten staan in `App/Debug/DebugLaunch.swift`.

Ontwerpkeuzes en de opbouw staan in [`system_architecture.md`](system_architecture.md), het ontwerpplan met alle besluiten in [`docs/design2/plan.md`](docs/design2/plan.md) en het contract van de blok-id's en bestemmingen in [`docs/v3-spec.md`](docs/v3-spec.md).
