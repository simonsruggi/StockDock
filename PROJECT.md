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

- **Menu bar configurabile**: P&L assoluto, P&L %, P&L + %, valore totale portafoglio, miglior/peggior titolo watchlist, solo icona
- **Watchlist**: aggiunta titoli per simbolo, nome o ISIN con ricerca live; prezzi in valuta originale o convertiti; badge PRE/POST per extended hours; filtro locale per nome, simbolo o ISIN
- **Portafogli multipli**: prezzo medio di carico, data acquisto per tasso di cambio storico, P&L per holding e totale
- **Conversione valuta**: supporta EUR, USD, GBP, CHF, JPY, CAD, AUD; tassi di cambio live e storici
- **52-week range**: barra nella watchlist che mostra dove sta il prezzo tra minimo e massimo annuale; dati dalle stesse chiamate quote (v7 + fallback v8), preservati tra i tick WSS
- **Price alert (one-shot)**: 6 condizioni (prezzo sopra/sotto soglia, variazione % giornaliera su/giù, vicino a max/min 52w); creazione da menu contestuale watchlist, gestione in Settings (riarmo, elimina, badge "triggered"); notifica locale macOS via `UNUserNotificationCenter`; valutati ad ogni aggiornamento prezzo (tick WSS, REST, avvio, wake); scattano una volta poi si disattivano
- **Watchlist Display personalizzabile**: toggle in Settings per mostrare/nascondere nome società, range giornaliero, barra 52w e variazione assoluta in ogni riga; default tutti ON, persistiti in `data.json`
- **Notifiche Discord/Slack**: in Settings, toggle + URL webhook + "Send test"; tutte le notifiche (price alert e portfolio) vengono inoltrate al webhook oltre alla notifica macOS; auto-detect Discord (embed colorato verde/rosso) vs Slack (testo); solo https su host noti (SSRF-safe); funziona anche in dev
- **Notifiche per-portfolio**: tasto destro sull'header del portafoglio → "Notifications…"; 4 modalità (variazione giornaliera ≥ %, ≥ importo, riepilogo giornaliero, milestone di valore); default ±1% / ±250 / milestone ogni 10.000 / riepilogo dopo le 22:00; **anti-spam a high-water mark per-direzione** (`lastStepUp`/`lastStepDown`): scatta solo su nuovi estremi, mentre ritracciamenti, oscillazioni sulla soglia e attraversamenti dello zero restano silenziosi (reset giornaliero per gli step), milestone "primed" silenziosamente al primo giro e poi solo su nuovo massimo/minimo; in più un backstop in `NotificationManager.send` impedisce che lo *stesso* identifier riparta entro 120s (nessun tipo può spammare a tick rate); variazione del giorno = `change` per-azione × quantità × cambio nella valuta preferita; valutate ad ogni aggiornamento prezzo; stato e regole persistiti in `data.json` per id portafoglio. Le notifiche di variazione giornaliera e il riepilogo includono un **breakdown per-titolo** (simbolo · variazione % · valore, aggregato per simbolo, ordinato per impatto del giorno, cap 12 righe + "…and N more") così si capisce cosa ha mosso il portafoglio
- **Extended hours**: prezzi pre-market e after-hours con rispettivo P&L
- **Persistenza**: dati salvati in `~/Library/Application Support/StockDock/data.json` (watchlist, portafogli, isinMap, alert, notifiche portfolio, webhook, preferenze); nessun dato inviato a server esterni
- **Test**: target `StockDockTests` (`Tests/`) con unit test della logica pura — `AlertEvaluator` (tutte le condizioni + casi limite), `PortfolioAlertEvaluator` (crossingStep/milestone/summary) e `fiftyTwoWeekPosition`. Esegui con `swift test`
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
