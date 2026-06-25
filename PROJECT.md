# StockDock

App macOS per la menu bar che mostra in tempo reale le quotazioni di borsa e il P&L del portafoglio. Non richiede account né API key: i dati vengono direttamente da Yahoo Finance.

## Descrizione

StockDock è un'app leggera che vive nella menu bar di macOS. Con un click sull'icona si apre un popover con watchlist, portafogli e impostazioni. I prezzi si aggiornano in tempo reale via WebSocket (~1 update/sec per simbolo).

## Stack tecnologico

- **Linguaggio**: Swift 5.9
- **UI**: SwiftUI
- **Piattaforma**: macOS 14+ (Sonoma)
- **Build system**: Swift Package Manager (`Package.swift`)
- **Dati real-time**: Yahoo Finance WebSocket (`wss://streamer.finance.yahoo.com`) via protobuf
- **Dati fallback**: Yahoo Finance REST API (v7 batch quotes + v8 chart)
- **Dipendenze**: [apple/swift-protobuf](https://github.com/apple/swift-protobuf) (decodifica messaggi WSS)

## Struttura cartelle principali

```
StockDock/
├── Package.swift               # Configurazione SPM, target unico, macOS 14+
├── StockDock/
│   ├── StockDockApp.swift       # Entry point (@main), collega AppDelegate
│   ├── AppDelegate.swift       # NSStatusItem, popover, timer aggiornamento 5s
│   ├── Models/
│   │   ├── StockQuote.swift    # Modelli: StockQuote (con 52w range), Portfolio, Holding, SearchResult
│   │   ├── PriceAlert.swift    # PriceAlert, AlertCondition, AlertEvaluator (logica pura testabile)
│   │   └── PortfolioNotification.swift # PortfolioNotification(Mode) + PortfolioAlertEvaluator (logica pura testabile)
│   ├── Services/
│   │   ├── StockService.swift      # Fetch quotazioni e tassi di cambio da Yahoo Finance REST
│   │   ├── WebSocketService.swift  # Streaming real-time via WSS + protobuf + auto-reconnect
│   │   ├── NotificationManager.swift # Notifiche locali (UN) + inoltro webhook + AlertMonitor
│   │   ├── PortfolioMonitor.swift  # Valuta le notifiche per-portfolio e le fa scattare
│   │   ├── WebhookNotifier.swift   # POST a webhook Discord/Slack (auto-detect, https + host whitelist)
│   │   ├── yaticker.pb.swift       # Codice Swift generato da yaticker.proto
│   │   └── StorageService.swift    # Persistenza locale (JSON) + formatNumber/formatAmount (separatore migliaia locale-aware)
│   ├── Views/
│   │   ├── ContentView.swift   # Contenitore con tab (Watchlist / Portfolios / Settings)
│   │   ├── WatchlistView.swift # Lista ticker con prezzi, variazione giornaliera e 52w range bar
│   │   ├── RangeBar.swift      # Barra 52 settimane con marker di posizione
│   │   ├── PortfolioListView.swift # Portafogli con P&L per holding
│   │   ├── AddHoldingView.swift# Form aggiunta/modifica holding
│   │   ├── AlertEditView.swift # Sheet creazione price alert
│   │   ├── PortfolioNotificationsView.swift # Popover gestione notifiche per-portfolio
│   │   ├── SearchView.swift    # Ricerca ticker per simbolo o nome
│   │   └── SettingsView.swift  # Valuta, extended hours, menu bar, sezione Notifications (webhook + price alert + notifiche portfolio)
│   ├── Assets.xcassets
│   └── Resources/AppIcon.icns
└── screenshots/                # Screenshot per README
```

## Funzionalità chiave

- **Menu bar configurabile**: P&L assoluto, P&L %, P&L + %, valore totale portafoglio, miglior/peggior titolo watchlist, riepilogo portafoglio, **Ticker (scorre la watchlist)**, **Ticker + Portfolio (scorre watchlist + 1 slide riepilogo portafoglio)**, solo icona
- **Colori menu bar personalizzabili**: in Settings → "Menu Bar Colors", color picker per i colori di rialzo/ribasso (default = verde/rosso di sistema finché non si toccano) + toggle "Use system text color" che usa il colore testo di sistema (sempre leggibile su qualsiasi sfondo; la direzione resta data da `+/−` e `▲▼`). Persistiti come hex in `data.json`; helper `ColorHex.swift` (bridge hex↔`NSColor`/`Color`)
- **Percentuali a 2 decimali**: toggle in Settings (default off per tenere la barra compatta) che porta tutte le % da 1 a 2 decimali (menu bar, watchlist, portafogli)
- **Ticker: nome vs simbolo** (issue #8.2): toggle "Show name instead of symbol" (default off) nelle modalità Ticker → la barra mostra il nome leggibile (es. "S&P 500") invece del simbolo grezzo ("^GSPC"). Implementato in `AppDelegate.watchlistSlide(...)` con fallback al simbolo se il nome è vuoto; setting `tickerShowName` in `StorageService`
- **Ticker: ordinamento** (issue #8.1): picker "Ticker order" (As added / By type / Alphabetical) che decide l'ordine con cui le voci della watchlist scorrono **nella menu bar** (il popover ha già il suo sort per colonna). Helper puro `StorageService.tickerOrder(_:mode:types:)` — il raggruppamento "type" segue stocks → ETF → indici → futures (stabile entro gruppo, tipi sconosciuti in coda); setting `watchlistSort`
- **Niente valuta sugli indici** (issue #8.3): gli indici non hanno valuta, quindi il loro valore non viene prefissato dal simbolo valuta. Riconoscimento via `StorageService.isIndex(symbol:type:)` (tipo Yahoo `INDEX`, fallback `^`). Il tipo asset arriva dall'API (`quoteType` v7, `instrumentType` v8 chart, `SearchResult.type` in ricerca) ed è cachato/persistito in `symbolType: [symbol: String]` in `data.json` — risolto una volta perché stabile per simbolo, non ricalcolato ad ogni tick
- **Localizzazione (6 lingue)**: selettore in Settings → "Language" (English default) con Inglese, Tedesco, Francese, Spagnolo, Italiano, Portoghese. Stringhe in `Resources/<lang>.lproj/Localizable.strings`; override in-app del locale via `\.environment(\.locale, …)` reattivo su `ContentView` (NON via system locale). `release.sh` copia i `.lproj` in `Contents/Resources` (Bundle.main) così SwiftUI li risolve; `Package.swift` ha `defaultLocalization: "en"`. ⚠️ In `swift run` (dev) le risorse SPM finiscono in `Bundle.module`, quindi la traduzione si vede **solo** nell'app bundlata
- **Watchlist**: aggiunta titoli per simbolo, nome o ISIN con ricerca live; prezzi in valuta originale o convertiti; badge PRE/POST per extended hours; filtro locale per nome, simbolo o ISIN
- **Portafogli multipli**: prezzo medio di carico, data acquisto per tasso di cambio storico, P&L per holding e totale
- **Short & leva (issue #9)**: toggle **Settings → Advanced → "Enable short positions & leverage"** (default OFF, `advancedPositions` in `data.json`). Con ON, i form add/edit holding sbloccano la **quantità negativa** (posizione short) e un campo **leverage** per-holding. La matematica vive su `Holding`: `pnl`/`marketValue` × `effectiveLeverage`, `pnlPercent` inverte il segno per gli short (prezzo giù = guadagno) e la leva si cancella nel % di posizione (è exposure-relative); `costBasisLocal` è il cost basis con segno+leva, usato ovunque per i totali e per il % a livello portafoglio (`abs(costBasis)` così i panieri long/short non azzerano il %). Badge **SHORT** (arancio) e **Nx** leva (blu) sulla riga holding. `leverage: Double?` opzionale → i `data.json` pre-1.7.1 decodificano puliti come 1×. Coperto da `Tests/ShortLeverageTests.swift` (8 casi: long/short × profit/loss × leva)
- **Conversione valuta**: supporta EUR, USD, GBP, CHF, JPY, CAD, AUD; tassi di cambio live e storici
- **52-week range**: barra nella watchlist che mostra dove sta il prezzo tra minimo e massimo annuale; dati dalle stesse chiamate quote (v7 + fallback v8), preservati tra i tick WSS
- **Price alert (one-shot)**: 6 condizioni (prezzo sopra/sotto soglia, variazione % giornaliera su/giù, vicino a max/min 52w); creazione da menu contestuale watchlist, gestione in Settings (riarmo, elimina, badge "triggered"); notifica locale macOS via `UNUserNotificationCenter`; valutati ad ogni aggiornamento prezzo (tick WSS, REST, avvio, wake); scattano una volta poi si disattivano
- **Watchlist Display personalizzabile**: toggle in Settings per mostrare/nascondere nome società, range giornaliero, barra 52w e variazione assoluta in ogni riga; default tutti ON, persistiti in `data.json`
- **Notifiche Discord/Slack**: in Settings, toggle + URL webhook + "Send test"; tutte le notifiche (price alert e portfolio) vengono inoltrate al webhook oltre alla notifica macOS; auto-detect Discord (embed colorato verde/rosso) vs Slack (testo); solo https su host noti (SSRF-safe); funziona anche in dev
- **Notifiche per-portfolio**: tasto destro sull'header del portafoglio → "Notifications…"; 4 modalità (variazione giornaliera ≥ %, ≥ importo, riepilogo giornaliero, milestone di valore); default ±1% / ±250 / milestone ogni 10.000 / riepilogo dopo le 22:00; **anti-spam a high-water mark per-direzione** (`lastStepUp`/`lastStepDown`): scatta solo su nuovi estremi, mentre ritracciamenti, oscillazioni sulla soglia e attraversamenti dello zero restano silenziosi (reset giornaliero per gli step), milestone "primed" silenziosamente al primo giro e poi solo su nuovo massimo/minimo; in più un backstop in `NotificationManager.send` impedisce che lo *stesso* identifier riparta entro 120s (nessun tipo può spammare a tick rate); variazione del giorno = `change` per-azione × quantità × cambio nella valuta preferita; valutate ad ogni aggiornamento prezzo; stato e regole persistiti in `data.json` per id portafoglio. Le notifiche di variazione giornaliera e il riepilogo includono un **breakdown per-titolo** (simbolo · variazione % · valore, aggregato per simbolo, ordinato per impatto del giorno, cap 12 righe + "…and N more") così si capisce cosa ha mosso il portafoglio
- **Extended hours**: prezzi pre-market e after-hours con rispettivo P&L
- **Persistenza**: dati salvati in `~/Library/Application Support/StockDock/data.json` (watchlist, portafogli, isinMap, alert, notifiche portfolio, webhook, preferenze); nessun dato inviato a server esterni
- **Test**: target `StockDockTests` (`Tests/`) con unit test della logica pura — `AlertEvaluator` (tutte le condizioni + casi limite), `PortfolioAlertEvaluator` (crossingStep/milestone/summary), `fiftyTwoWeekPosition`, formattazione numeri, `TickerOrderingTests` (issue #8: `isIndex` + `tickerOrder`) e `ShortLeverageTests` (issue #9: P&L/marketValue/pnlPercent/costBasis su short + leva). Esegui con `swift test`
- **Export/Import portafogli**: export singolo o di tutti i portafogli in JSON via NSSavePanel; import via NSOpenPanel con dedup nomi e UUID rigenerati
- **Menu bar reattiva**: si aggiorna immediatamente ad ogni modifica di portafoglio, impostazioni o chiusura popover (oltre ai tick WebSocket e REST polling)
- **Save debounced**: le scritture su disco sono debounced a 100ms per non bloccare il main thread; save immediato alla chiusura dell'app; nessun save ridondante al caricamento iniziale
- **Reactive subscriptions**: un observer Combine su `$portfolios` + `$watchlist` (debounce 500ms) aggiorna automaticamente le subscription WebSocket e triggera `refreshAll` dopo qualsiasi mutazione

## Come buildare e avviare

### Da sorgente con Swift PM

```bash
git clone https://github.com/simonsruggi/StockDock.git
cd StockDock
swift build -c release
# Eseguibile: .build/release/StockDock
```

### Build come app bundle (Xcode)

```bash
xcodebuild -scheme StockDock -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath .build/xcode build
```

### Avvio rapido (sviluppo)

```bash
swift run
```

L'app non compare nel Dock (`.accessory` policy): l'icona appare nella menu bar in alto a destra.

## Architettura dati

- **WebSocket (primario)**: `WebSocketService` si connette a `wss://streamer.finance.yahoo.com/?version=2`, riceve tick in formato JSON-wrapped base64 protobuf. I tick vengono bufferizzati e flushati in batch 1 volta al secondo per evitare SwiftUI redraw eccessivi.
- **REST polling (secondario)**: ogni 5 min per exchange rates (correnti e storici). Usato anche come bootstrap iniziale e fallback se il WSS cade.
- **Cache eviction**: ad ogni refresh REST, vengono rimossi quotes, exchange rates e historical rates non più necessari.
- **Sleep/Wake**: il WSS si disconnette su system sleep e si riconnette al wake con refresh immediato.
- **P&L con FX corretto**: il P&L è calcolato come `marketValue × currentRate − costBasis × historicalRate`, considerando il tasso di cambio storico alla data di acquisto per il costo carico.
- **Auto-reconnect**: backoff esponenziale (2s, 4s, 8s... max 120s) in caso di disconnessione WSS.

## Note importanti

- **Nessuna API key richiesta**: Yahoo Finance non richiede autenticazione, ma usa un meccanismo cookie+crumb gestito automaticamente dal `StockService`
- **Fallback API**: se la v7 batch quote fallisce, viene usata la v8 chart API per ogni simbolo singolarmente
- **Protobuf**: lo schema `yaticker.proto` nella root genera `yaticker.pb.swift` via `protoc --swift_out`. Rigenerare se cambia lo schema: `protoc --swift_out=StockDock/Services/ yaticker.proto`
- **Requisiti**: Xcode 15+ e macOS 14 Sonoma o successivo
- **Firma/Entitlements**: `StockDock.entitlements` presente nella root per eventuali accessi di rete
- **Release / What's New**: `./release.sh <versione> <build>` builda, firma, notarizza, aggiorna `appcast.xml`, crea la GitHub release e aggiorna il cask Homebrew. Le note "What's New" mostrate da Sparkle vanno scritte in `release-notes/<versione>.html` (HTML), che lo script inietta nel `<description>` dell'appcast
