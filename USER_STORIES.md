# User Stories — StockDock

## US-01: Menu Bar Display
**Come** utente, **voglio** vedere un riepilogo del mio portafoglio nella menu bar di macOS **così da** controllare i miei investimenti con un colpo d'occhio.

- [x] La menu bar mostra il P&L nel formato scelto (assoluto, %, entrambi, valore totale, miglior/peggior titolo, solo icona)
- [x] I valori si aggiornano in tempo reale con i prezzi
- [x] Colorazione verde (positivo) / rosso (negativo)
- [x] 8 modalità display: P&L, P&L %, P&L + %, Total Value, Best Stock, Worst Stock, Best & Worst, Icon Only

## US-02: Watchlist
**Come** utente, **voglio** mantenere una watchlist di titoli **così da** monitorare i loro prezzi.

- [x] Ricerca titoli per simbolo, nome o ISIN
- [x] Aggiunta/rimozione titoli dalla watchlist
- [x] Prezzo corrente, variazione giornaliera %, prezzi extended hours
- [x] Filtro locale per simbolo, nome o ISIN
- [x] Auto-ordinamento per performance giornaliera (migliore in cima)
- [x] Badge PRE (arancione) / POST (viola) per extended hours

## US-03: Gestione Portafogli
**Come** utente, **voglio** creare e gestire più portafogli con holding **così da** tracciare le performance dei miei investimenti.

- [x] Creazione, rinomina, eliminazione portafogli
- [x] Aggiunta holding con simbolo, quantità, prezzo medio e data acquisto
- [x] Modifica holding esistenti (quantità, prezzo medio, data acquisto)
- [x] Eliminazione holding
- [x] Valore totale portafoglio, P&L e P&L %
- [x] Per ogni holding: controvalore, P&L e P&L %
- [x] Filtro portafogli per nome o simbolo

## US-04: Aggiunta rapida da Watchlist a Portfolio
**Come** utente, **voglio** aggiungere velocemente un titolo dalla watchlist a un portafoglio **così da** non dover riscrivere il simbolo.

- [x] Click destro su titolo watchlist → menu "Add to Portfolio" con lista portafogli
- [x] Form rapido per quantità, prezzo medio e data acquisto (precompila il prezzo corrente)

## US-05: Aggiornamenti in Tempo Reale
**Come** utente, **voglio** che i prezzi si aggiornino in tempo reale **così da** avere sempre dati aggiornati.

- [x] WebSocket Yahoo Finance (~1 tick/sec per simbolo)
- [x] Riconnessione automatica con backoff esponenziale (2s, 4s, 8s... max 120s)
- [x] Watchdog: nessun tick per 60s → riconnessione
- [x] Heartbeat ogni 15s per mantenere la connessione
- [x] REST polling ogni 5 min come fallback per exchange rates
- [x] Dopo cambio portafoglio/watchlist, subscription WebSocket aggiornate entro 500ms
- [x] Tick bufferizzati e flushati 1x/sec per evitare rendering eccessivo

## US-06: Conversione Valuta
**Come** utente, **voglio** vedere i valori del portafoglio nella mia valuta preferita **così da** avere importi comprensibili.

- [x] Scelta valuta portafoglio (EUR, USD, GBP, CHF, JPY, CAD, AUD)
- [x] Scelta valuta display prezzi (originale o convertita)
- [x] Costo carico calcolato con tasso di cambio storico alla data di acquisto
- [x] Valori correnti calcolati con tassi di cambio live
- [x] P&L = valore corrente (tasso attuale) − costo carico (tasso storico)

## US-07: Extended Hours
**Come** utente, **voglio** vedere i prezzi pre-market e after-hours **così da** conoscere l'ultimo prezzo disponibile.

- [x] Toggle per mostrare/nascondere prezzi extended hours
- [x] Badge Pre-market (arancione) e Post-market (viola)
- [x] Valori portafoglio usano prezzi extended hours quando abilitati

## US-08: Persistenza Dati
**Come** utente, **voglio** che i miei dati siano salvati localmente **così da** ritrovarli al riavvio dell'app.

- [x] Dati salvati come JSON in `~/Library/Application Support/StockDock/data.json`
- [x] Save debounced (100ms) per non bloccare il main thread
- [x] Save immediato alla chiusura dell'app
- [x] Nessun save ridondante durante il caricamento iniziale
- [x] Nessun dato inviato a server esterni

## US-09: Sleep/Wake
**Come** utente, **voglio** che l'app gestisca correttamente sleep e risveglio del Mac **così da** non sprecare risorse.

- [x] Sleep: disconnette WebSocket, ferma timer
- [x] Wake: riconnette, refresh completo quote e tassi di cambio

## US-10: Interfaccia Popover
**Come** utente, **voglio** accedere all'app con un click sull'icona nella menu bar **così da** avere tutto a portata di mano.

- [x] Click apre popover con tre tab: Watchlist, Portfolios, Settings
- [x] Click esterno chiude il popover
- [x] Alla chiusura del popover, subscription WebSocket e menu bar aggiornati
- [x] Nessuna icona nel Dock (`.accessory` policy)

## US-11: Impostazioni
**Come** utente, **voglio** personalizzare il comportamento dell'app **così da** adattarla alle mie esigenze.

- [x] Valuta prezzi stock (originale o convertita)
- [x] Valuta portafoglio
- [x] Toggle extended hours
- [x] Modalità display menu bar (8 opzioni)
