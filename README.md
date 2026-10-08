# MyBuddy

Een persoonlijke financiën-app voor **iPhone, iPad en Mac**, in de stijl van Apple's **Liquid Glass** met donker olijfgroen als kleur. Alles blijft op je eigen apparaat.

| Tab | Wat je er doet |
|---|---|
| **Home** | Bovenaan wat je nog kunt verdelen. Daaronder drie blokken: Overzicht (grafiek per maand), Spaarpotten (3 die je zelf kiest) en Beleggingen (groeigrafiek en tegels per beleggingssoort). |
| **Savings** | Kies maand, half jaar of jaar (terug en vooruit). Salaris (vast of uurloon × uren), overige inkomsten, uitgaven, geld verdelen over spaarpotten en beleggingen, spaarpotten met doel, en je bankrekening (saldo vul je zelf in). |
| **Beleggingen** | Portefeuille met live koersen, toekomstschatting (dagen, weken, maanden, jaren, drie scenario's, inflatie), doelen (pensioen, vakantie, parttime werken, eigen doel) en versnellers die uit jouw eigen cijfers komen. |

De tabbalk staat onderin. **Elk blok opent een eigen pagina**; die pagina's staan niet in de tabbalk en zijn alleen via hun blok te bereiken.

## Starten (Mac met Xcode 26)

1. Installeer XcodeGen: `brew install xcodegen`
2. In deze map: `xcodegen` (maakt `MyBuddy.xcodeproj`)
3. Open `MyBuddy.xcodeproj`, kies bij *Signing & Capabilities* je eigen Team, kies een iPhone, iPad of "My Mac" en druk op Run.

Bij het eerste openen kun je op Home **Voorbeelddata** laden om alles direct te zien.

De rekenlogica testen zonder Xcode-project: `cd CoreTests && swift test`.

## Koersen

Beleggingen met een **ticker** (bijv. `VWCE.DE`, `AAPL`, `BTC-EUR`) en een **aantal** krijgen automatisch een live koers, omgerekend naar euro. Zoeken kan op naam. De koersen komen van Yahoo Finance: gratis en zonder sleutel, maar onofficieel. Het kan dus ooit veranderen of tijdelijk niet werken. De bron zit achter het protocol `QuoteService` (`App/Core/Quotes.swift`) en is in één bestand te vervangen. Zonder ticker vul je de waarde zelf in.

Elke keer dat een koers binnenkomt, bewaart de app een meetpunt. Zo bouwt de groeigrafiek zich vanzelf op. Met "Historie aanvullen" haal je koersen van het afgelopen jaar binnen.

## Back-up en export

In Instellingen maak je een **JSON-back-up** van al je gegevens en importeer je die weer (ook om naar een ander apparaat te verhuizen). Uitgaven kun je daarnaast als **CSV** exporteren voor Numbers of Excel.

## Wat de app niet doet

- Geen bankkoppeling: je saldo vul je zelf in. De app rekent daarna het overschot van elke maand erbij.
- Geen sync tussen apparaten (gegevens staan in één JSON-bestand per apparaat). iCloud is een logische volgende stap.
- Geen financieel advies. Rendementen zijn aannames die je zelf instelt.

## Status van de verificatie

Deze code is geschreven in een omgeving **zonder Swift-compiler en zonder Xcode**. Het is dus nog niet gebouwd of gedraaid. Wel gedaan: syntaxcontrole van alle bestanden met een Swift-parser, verwachte testwaarden onafhankelijk narekenen in Python, en parser-tests voor de koersdata op voorbeeld-JSON. Verwacht bij de eerste build een paar compilerfouten; stuur ze door en ze zijn snel opgelost.

Ontwerpkeuzes staan in [`system_architecture.md`](system_architecture.md).
