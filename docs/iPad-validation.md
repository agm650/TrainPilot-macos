# Validation manuelle iPad

Utiliser de préférence un iPad 11 pouces et un iPad 13 pouces sous iOS 26 ou 27,
en portrait puis en paysage. Le serveur peut utiliser une centrale simulée.

## Démarrage et navigation

- L'application affiche la connexion sans chevauchement ni troncature.
- Une erreur serveur est présentée sans fermeture de l'application.
- La barre latérale ouvre Bibliothèque, Layout, Conduite et Réglages.
- Aucune commande ni vue d'édition du layout n'est accessible.

## Bibliothèque

- Vérifier une bibliothèque vide, une locomotive et une liste longue.
- Rechercher par nom et adresse DCC.
- Vérifier la fiche en lecture seule avec un rôle `driver`.
- Avec un rôle `administrator`, créer, modifier et supprimer après confirmation.
- Importer une archive ZIP valide puis une archive invalide.
- Exporter l'archive et vérifier son nom ainsi que son ouverture par le serveur.
- Couper le réseau pendant une modification et vérifier l'erreur affichée.

## Conduite

- L'acquisition est toujours déclenchée explicitement.
- Une reprise d'une autre session du même utilisateur reste explicite.
- Tester AV, AR, 0 %, N, F0 et les autres fonctions disponibles.
- AV vers AR et AR vers AV sont impossibles au-dessus de 0 %.
- N commande immédiatement 0 % sans modifier le dernier sens DCC.
- Tester release, conflit d'acquisition et expiration du lease.
- Couper le réseau : les commandes deviennent indisponibles et la vitesse locale revient à 0.
- Reconnecter : aucune vitesse n'est renvoyée avant une action explicite.
- L'arrêt d'urgence reste visible et utilise l'état confirmé par le serveur.

## Layout opérationnel

- Vérifier le pan, le pincement de zoom et le recentrage à 100 %.
- Toucher un aiguillage puis commander une position.
- Vérifier les états pending, confirmé, inconnu et erreur.
- Confirmer l'absence d'ajout, suppression, déplacement, snap et sauvegarde.
