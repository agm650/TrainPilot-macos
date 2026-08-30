# TrainPilot macOS — MVP

Client natif macOS pour `TrainPilot-server`.

## Cible

- macOS 12 Monterey minimum
- Swift / SwiftUI
- Universal Intel + Apple Silicon via le target macOS standard Xcode
- API TrainPilot HTTP + WebSocket
- Trousseau macOS pour le refresh token

## Fonctionnalités incluses

- configuration de l'URL du serveur ;
- login / refresh token / logout ;
- vérification de compatibilité API via `/api/v1/system/info` ;
- liste des locomotives ;
- acquisition et libération des control leases ;
- maintien des leases par heartbeat ;
- plusieurs leases simultanés avec un seul poste de conduite affiché ;
- bascule entre locomotives sous contrôle ;
- poste SNCF Classic responsive et plein écran ;
- grande roue de vitesse 0–100 % ;
- distinction vitesse demandée / vitesse confirmée ;
- inverseur AV / N / AR :
  - `N` envoie immédiatement 0 % ;
  - le dernier sens DCC reste mémorisé ;
  - AV ↔ AR est interdit tant que la vitesse demandée n'est pas à 0 % ;
- F0…Fn génériques selon les capabilities de la centrale ;
- track power ;
- emergency stop ;
- raccourcis clavier ;
- WebSocket avec snapshot, séquence, détection de trou et `client.snapshot_request` ;
- reconnexion WebSocket ;
- prise en charge des événements centrale / power / emergency / speed / functions / leases.

## Démarrage

1. Ouvrir `TrainPilot.xcodeproj`.
2. Sélectionner le target `TrainPilot`.
3. Dans **Signing & Capabilities**, choisir votre équipe de développement si Xcode le demande.
4. Exécuter l'application.
5. Dans l'écran de connexion, saisir l'adresse du serveur, par exemple :
   `http://192.168.0.60:8080`
6. Se connecter avec un utilisateur disposant du rôle `driver` ou supérieur.
7. Ouvrir **TrainPilot > Bibliothèque…**, prendre le contrôle d'une locomotive puis revenir au poste.

## Raccourcis

| Touche | Action |
|---|---|
| ↑ / ↓ | +/- 1 % |
| ⇧↑ / ⇧↓ | +/- 10 % |
| ← / → | AR / AV à 0 % |
| Espace | N / 0 % immédiat |
| F1…F12 | Fonctions F1…F12 |
| ⌘1…⌘9 | Changer de locomotive contrôlée |
| ⌘⌥E | Arrêt d'urgence |
| ⇧⌘L | Bibliothèque |

## HTTP local / ATS

Le `Info.plist` du MVP contient `NSAllowsArbitraryLoads = true` afin de permettre un serveur TrainPilot local en HTTP sur une IP privée.

Avant distribution :
- privilégier HTTPS/WSS ;
- retirer `NSAllowsArbitraryLoads` ;
- appliquer une politique ATS plus restrictive.

## Contrat WebSocket

Le client accepte un snapshot contenant au minimum :

```json
{
  "type": "system.snapshot",
  "sequence": 42,
  "payload": {
    "station": { "...": "capabilities" },
    "stationStatus": { "...": "status" }
  }
}
```

Le snapshot peut également contenir :
- `locomotives`
- `leases` ou `controlLeases`
- `blocks`
- `turnouts`
- `routes`

Les locomotives sont dans tous les cas chargées par HTTP.

Lorsqu'un trou de séquence est détecté :

```json
{
  "type": "client.snapshot_request",
  "lastSequence": 42
}
```

Le client ignore alors les événements suivants jusqu'au nouveau snapshot.

## Limites volontaires du MVP

- après relance, vitesse/direction/fonctions peuvent rester inconnues jusqu'à un nouvel événement ;
- pas encore de vitesse en km/h ;
- pas de définition sémantique des fonctions F0…Fn ;
- pas d'éditeur de cabine ;
- un seul poste visible à la fois ;
- pas encore de vue graphique du réseau ;
- pas d'icône d'application personnalisée.

## Fichiers importants

- `TrainPilot/App/AppModel.swift` : orchestration application / connexions / commandes
- `TrainPilot/Core/Networking/APIClient.swift` : REST + refresh token
- `TrainPilot/Core/Networking/EventClient.swift` : WebSocket + resynchronisation
- `TrainPilot/Driving/DrivingSession.swift` : état de conduite par locomotive
- `TrainPilot/Driving/DrivingSessionManager.swift` : plusieurs leases, une session active
- `TrainPilot/Cab/Components/ThrottleWheel.swift` : grande roue de vitesse
- `TrainPilot/Cab/Themes/SNCFClassicCabView.swift` : première cabine
