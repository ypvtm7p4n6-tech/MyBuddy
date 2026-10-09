# MyBuddy

Een persoonlijke financiën-app voor **iPhone, iPad en Mac**, in de stijl van Apple's **Liquid Glass** met donker olijfgroen als kleur.

| Tab | Wat je er doet |
|---|---|
| **Home** | Bovenaan wat je nog kunt verdelen deze maand. Daaronder drie even grote blokken: Overzicht (grafiek per maand), Spaarpotten (totaal gespaard en totaal doel, plus 3 potten die je zelf kiest) en Beleggingen (groeigrafiek en tegels). |
| **Savings** | Kies maand, half jaar of jaar. Salaris (vast of uurloon × uren, met salarisdag), extra inkomsten en uitgaven (vast of variabel, met eigen dag en eventueel uit een of meer spaarpotten betaald), geld verdelen over potten en beleggingen op een overschrijfdag, spaarpotten met doel en rente, je bankrekening in de app (saldo per dag), buffer-calculator, **Beleggingen** (live koersen) en **Doelen** (levensdoelen en spaardoel-calculator in één blok). |
| **Tools** | **Versnellers** (uit jouw eigen cijfers; toepassen past je gegevens echt aan en je kunt het herstellen), **Toekomstschatting** en de **Aankoopcheck**: kost iets je werkuren waard? |

De tabbalk staat onderin en neemt eigen ruimte in, zodat hij nooit blokken afdekt. **Elk blok opent een eigen pagina.** Houd een blok **lang ingedrukt** om de volgorde van de blokken op die pagina aan te passen.

Alle bedragen worden afgerond op hele euro's getoond (koersen en uurloon met centen).

## Starten (Mac met Xcode 26)

1. Installeer XcodeGen: `brew install xcodegen`
2. In deze map: `xcodegen` (maakt `MyBuddy.xcodeproj`)
3. Open `MyBuddy.xcodeproj`. Kies bij *Signing & Capabilities* je eigen Team bij **beide** targets (MyBuddy en MyBuddyTests). Kies een iPhone, iPad of "My Mac" en druk op Run.

Bij het eerste openen kun je op Home **Voorbeelddata** laden om alles direct te zien.

De rekenlogica testen zonder Xcode-project: `cd CoreTests && swift test` (ruim 1100 tests).

## Dag voor dag

Je geeft per inkomsten- of uitgavenregel een **dag van de maand** op, en per spaarpot of belegging een **overschrijfdag** (of één dag voor de hele maand). De app rekent het saldo van je bankrekening en van elke spaarpot **per dag**. Een verdeling voor een maand die nog komt wordt op die dag overgeschreven: tot die dag telt het niet mee in het potsaldo. Op de bankpagina zie je het saldo per gekozen dag, de komende 14 dagen, een dagsaldo-grafiek en een waarschuwing als je onder nul of onder je buffer komt.

## Spaarpotten met rente

Per pot stel je een **rentepercentage**, het **uitbetalingsmoment** (maandelijks, per kwartaal, half jaar of jaar) en de **dag** in. De app schrijft de rente automatisch bij op die dag (bij het opstarten en terwijl de app open staat). Elke uitbetaling heeft een vast id, dus er wordt nooit dubbel bijgeschreven, ook niet bij twee apparaten.

## Import en export

In Instellingen:
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

De rekenlogica (`App/Core`) wordt bij elke push op Linux gecompileerd en getest, en de app wordt voor iOS en macOS gebouwd (GitHub Actions). Screenshots maak je met de handmatige workflow-run ("Run workflow"); ze komen op de tak `ci-screenshots`.

Ontwerpkeuzes staan in [`system_architecture.md`](system_architecture.md), het contract van de nieuwste uitbreiding in [`docs/v3-spec.md`](docs/v3-spec.md).
